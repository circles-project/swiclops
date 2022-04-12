//
//  AuthController.swift
//  
//
//  Created by Charles Wright on 3/24/22.
//

import Vapor
import Yams
import AnyCodable

extension HTTPMethod: Codable { }

struct UiaController: RouteCollection {

    
    var app: Application
    var config: Config
    var checkers: [String: AuthChecker]
    
    struct Config: Codable {
        var homeserver: URL
        var routes: [UiaRoute]
        
        struct UiaRoute: Codable {
            var path: String
            var method: HTTPMethod
            var flows: [UiaFlow]
        }
    }
    
    init(app: Application, config: Config) {
        self.app = app
        self.config = config
        
        let authCheckerModules: [AuthChecker] = [
            DummyAuthChecker(),
            PasswordAuthChecker(app: app),
            TermsAuthChecker(app: app),
            TokenRegistrationAuthChecker(),
            EmailAuthChecker(app: app),
            FooAuthChecker(),
            BSSpekeAuthChecker(app: app, serverId: "circu.li", oprfKey: .init(repeating: 0xff, count: 32)),
        ]
        
        self.checkers = [:]
        
        for module in authCheckerModules {
            for authType in module.getSupportedAuthTypes() {
                self.checkers[authType] = module
            }
        }

    }
    
    func boot(routes: RoutesBuilder) throws {
        for route in self.config.routes {
            let pathComponents = route.path.split(separator: "/").map { PathComponent(stringLiteral: String($0))
            }
            routes.on(route.method, pathComponents, use: { (req) -> Response in
                
                req.logger.debug("Top-level handler got a request for \(route.path)")
                
                if let bodyString = req.body.string {
                    req.logger.debug("Request body is: \(bodyString)")
                } else {
                    req.logger.debug("Failed to decode request content")
                }
                
                try await handleUIA(req: req, flows: route.flows)
                // Now figure out what to do
                // * Is the route one of our own that we should handle internally?
                // * Or is it one that we should proxy to the homeserver?
                
                //throw Abort(.notImplemented)
                return Response(status: .ok)
            })
        }
    }
    
    private func _getNewSessionID() -> String {
        let length = 12
        return String( (0 ..< length).map { _ in "0123456789".randomElement()! } )
    }
    
    private func _getUserId(req: Request) async throws -> String? {
        guard let bearerHeader = req.headers.bearerAuthorization else {
            return nil
        }
        let token = bearerHeader.token
        // FIXME Lookup the userId based on the bearer token
        //       We can hit https://HOMESERVER/_matrix/client/VERSION/whoami to get the username from the access_token
        //       We should probably also cache the access token locally, so we don't constantly batter that endpoint
        // FIXME For now we fake it :)
        return "@alice:example.org"
    }
    
    // FIXME Add a callback so that we can handle UIA and then do something else
    //       Like, sometimes we want to proxy the "real" request (sans UIA) to the homeserver
    //       But other times, we need to handle the request ourselves in another handler
    func handleUIA(req: Request, flows: [UiaFlow]) async throws {
        
        let userId = try await _getUserId(req: req)
        
        // Does this request already have a session associated with it?
        guard let uiaRequest = try? req.content.decode(UiaRequest.self)
        else {
            // No existing UIA structure -- Return a HTTP 401 with an initial UIA JSON response
            req.logger.debug("Request has no UIA session")
            let sessionId = _getNewSessionID()
            let session = req.uia.connectSession(sessionId: sessionId)
            var params: [String: [String: AnyCodable]] = [:]
            for flow in flows {
                for stage in flow.stages {
                    if nil == params[stage] {
                        params[stage] = try? await checkers[stage]?.getParams(req: req, sessionId: sessionId, authType: stage, userId: userId)
                    }
                }
            }
            // FIXME somehow we need to set the UIA session's list of completed flows to []
            
            req.logger.debug("Throwing UiaIncomplete error")
            throw UiaIncomplete(flows: flows, params: params, session: sessionId)
        }
        
        let auth = uiaRequest.auth
        let sessionId = auth.session
        let session = req.uia.connectSession(sessionId: sessionId)

        let authType = auth.type
        // Is this one of the auth types that are required here?
        let allStages = flows.reduce( Set<String>() ) { (curr,next) in
            curr.union(Set(next.stages))
        }
        guard allStages.contains(authType) else {
            // FIXME Create and return a proper Matrix response
            //throw Abort(.forbidden)
            //return MatrixErrorResponse(status: .forbidden, errorcode: .forbidden, error: "Invalid auth type") //.encodeResponse(for: req)
            throw MatrixError(status: .forbidden, errcode: .invalidParam, error: "Invalid auth type \(authType)")
        }
        
        let alreadyCompleted = await session.getCompleted()
        if alreadyCompleted.contains(authType) {
            throw MatrixError(status: .forbidden, errcode: .invalidParam, error: "Authentication stage \(authType) has already been completed")
        }
        
        guard let checker = self.checkers[authType]
        else {
            // Uh oh, we screwed up and we don't have a checker for an auth type that we advertised.  Doh!
            // FIXME Create an actual Matrix response and return it
            //throw Abort(.internalServerError)
            req.logger.error("No checker found for requested auth type: \(authType)")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "No checker found for auth type \(authType)")
        }
        
        
        let success = try await checker.check(req: req, authType: authType)
        if success {
            // Ok cool, we cleared one stage
            // * Mark the stage as complete
            req.logger.debug("UIA controller: Marking stage \(authType) as complete")
            await session.markStageComplete(stage: authType)
            // * Was this the final stage that we needed?
            // * Or are there still more to be completed?
            let completed = await session.getCompleted()
            req.logger.debug("UIA controller: Got completed = \(completed)")
            let completedStages: Set<String> = .init(completed)
            req.logger.debug("UIA controller: Completed stages = \(completedStages)")
            for flow in flows {
                let flowStages: Set<String> = .init(flow.stages)
                if completedStages.isSuperset(of: flowStages) {
                    // Yay we're done with UIA
                    // Let's get out of here -- Let the main handler do whatever it needs to do with the "real" request
                    req.logger.debug("UIA controller: Yay we're done with UIA.  Completed flow = \(flow.stages)")
                    return
                }
            }
            
            // We're still here, so we must not be done yet
            // Therefore we have more UIA stages left to go
            // Get their parameters for the UIA response
            var newParams: [String: [String: AnyCodable]] = [:]
            for flow in flows {
                for stage in flow.stages {
                    if nil != newParams[stage] {
                        newParams[stage] = try? await checkers[stage]?.getParams(req: req, sessionId: sessionId, authType: stage, userId: userId)
                    }
                }
            }
            
            throw UiaIncomplete(flows: flows, completed: completed, params: newParams, session: sessionId)
            
        } else {
            throw MatrixError(status: .forbidden, errcode: .forbidden, error: "Authentication failed for type \(authType)")
        }
        
        
    }
}
