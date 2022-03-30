//
//  AuthController.swift
//  
//
//  Created by Charles Wright on 3/24/22.
//

import Vapor
import Yams
import AnyCodable

extension HTTPMethod: Codable {
    
}

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
    
    func boot(routes: RoutesBuilder) throws {
        for route in self.config.routes {
            let pathComponents = route.path.split(separator: "/").map { PathComponent(stringLiteral: String($0)) }
            routes.on(route.method, pathComponents, use: { (req) -> Response in
                let matrixResponse = try await handleUIA(req: req)
                return try await matrixResponse.encodeResponse(for: req)
            })
        }
    }
    
    private func _getNewSessionID() -> String {
        let length = 12
        return String( (0 ..< length).map { _ in "0123456789".randomElement()! } )
    }
    
    // FIXME Add a callback so that we can handle UIA and then do something else
    //       Like, sometimes we want to proxy the "real" request (sans UIA) to the homeserver
    //       But other times, we need to handle the request ourselves in another handler
    func handleUIA(req: Request) async throws -> MatrixResponse {

        // First let's make sure that this is one of our configured routes,
        // and let's get its configuration
        guard let route = self.config.routes.first(where: {
            $0.path == req.url.path && $0.method == req.method
        }) else {
            // We're not even supposed to be here
            throw Abort(.internalServerError)
        }

        let flows = route.flows
        
        // Does this request already have a session associated with it?
        guard let uiaRequest = try? req.content.decode(UiaRequest.self)
        else {
            // No existing UIA structure -- Return a HTTP 401 with an initial UIA JSON response
            let sessionId = _getNewSessionID()
            let session = req.uia.connectSession(sessionId: sessionId)
            var params: [String: [String: AnyCodable]] = [:]
            for flow in flows {
                for stage in flow.stages {
                    if nil != params[stage] {
                        params[stage] = await try? checkers[stage]?.getParams(req: req, authType: stage, userId: nil)  // FIXME userId should not be nil when the user is logged in and doing something that requires auth
                    }
                }
            }
            // FIXME somehow we need to set the UIA session's list of completed flows to []
            
            let responseBody = MatrixUiaResponse.Body(flows: flows, params: params, session: sessionId)
            
            return MatrixUiaResponse(status: .unauthorized, body: responseBody)
        }
        
        let auth = uiaRequest.auth
        let sessionId = auth.session
        // FIXME somehow we need to get (and later update) the UIA session's list of completed flows
        
        let authType = auth.type
        // Is this one of the auth types that are required here?
        let allStages = flows.reduce( Set<String>()) { (curr,next) in
            curr.union(Set(next.stages))
        }
        guard allStages.contains(authType) else {
            // FIXME Create and return a proper Matrix response
            //throw Abort(.forbidden)
            return MatrixErrorResponse(status: .forbidden, errorcode: .forbidden, error: "Invalid auth type") //.encodeResponse(for: req)
        }
        
        guard let checker = self.checkers[authType]
        else {
            // Uh oh, we screwed up and we don't have a checker for an auth type that we advertised.  Doh!
            // FIXME Create an actual Matrix response and return it
            throw Abort(.internalServerError)
        }
        
        let success = try await checker.check(req: req, authType: authType)
        if success {
            // FIXME Actually do something with this request
            //       Either handle the endpoint ourselves, or proxy it to the real homeserver
            return MatrixOkResponse()
        } else {
            // FIXME Create and return a real Matrix UIA response here
            return MatrixErrorResponse(status: .forbidden,
                                       errorcode: .forbidden,
                                       error: "Authentication failed"
            )//.encodeResponse(for: req)
        }
        
        
    }
}
