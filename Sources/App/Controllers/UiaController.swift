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
    var homeserver: URL
    var domain: String
    var checkers: [String: AuthChecker]
    var handlers: [Endpoint: EndpointHandler]    // Handlers for the client-server API
    var flows: [Endpoint: [UiaFlow]]
    var defaultFlows: [UiaFlow]
    var defaultProxyHandler: EndpointHandler
    
    struct Config: Codable {
        var backendAuth: BackendAuthConfig
        //var domain: String
        //var homeserver: URL
        var registration: RegistrationHandler.Config
        var bsspeke: BSSpekeAuthChecker.Config
        //var bsspekeOprfSecret: String
        var email: EmailConfig
        var routes: [UiaRoute]
        var defaultFlows: [UiaFlow]
        
        struct UiaRoute: Codable {
            var path: String
            var method: HTTPMethod
            var flows: [UiaFlow]
        }
        
        enum CodingKeys: String, CodingKey {
            case backendAuth = "backend_auth"
            //case bsspekeOprfSecret = "bsspeke_oprf_secret"
            case bsspeke
            //case domain
            case email
            //case homeserver
            case registration
            case routes
            case defaultFlows = "default_flows"
        }
    }
    
    init(app: Application, config: Config, matrixConfig: MatrixConfig) {
        self.app = app
        self.config = config
        
        self.domain = matrixConfig.domain
        self.homeserver = matrixConfig.homeserver
        
        // Set up our map from endpoints to UIA flows
        self.flows = [:]
        for route in config.routes {
            let endpoint = Endpoint(route.method, route.path)
            self.flows[endpoint] = route.flows
        }
        self.defaultFlows = config.defaultFlows
        
        
        // Set up our UIA checker modules
        let authCheckerModules: [AuthChecker] = [
            DummyAuthChecker(),
            PasswordAuthChecker(app: app),
            TermsAuthChecker(app: app),
            TokenRegistrationAuthChecker(),
            EmailAuthChecker(app: app, config: config.email),
            FooAuthChecker(),
            BSSpekeAuthChecker(app: app, serverId: matrixConfig.domain, config: config.bsspeke),

        ]
        self.checkers = [:]
        for module in authCheckerModules {
            for authType in module.getSupportedAuthTypes() {
                self.checkers[authType] = module
            }
        }
        
        // Set up our endpoint handlers, that take over after UIA is complete
        self.defaultProxyHandler = ProxyHandler(app: self.app, homeserver: matrixConfig.homeserver, authConfig: config.backendAuth)
        let loginHandler = LoginHandler(app: self.app,
                                        homeserver: matrixConfig.homeserver,
                                        flows: self.flows[.init(.POST, "/login")] ?? self.defaultFlows,
                                        authConfig: config.backendAuth)
        let endpointHandlerModules: [EndpointHandler] = [
            loginHandler,
            RegistrationHandler(app: self.app, homeserver: matrixConfig.homeserver, config: self.config.registration),
            AccountDeactivateHandler(app: self.app, proxy: self.defaultProxyHandler),
            Account3PidHandler(),
            AccountPasswordHandler(),
        ]
        self.handlers = [:]
        for module in endpointHandlerModules {
            for endpoint in module.endpoints {
                self.handlers[endpoint] = module
            }
        }

    }
    
    func boot(routes: RoutesBuilder) throws {
        
        let matrixCSAPI = routes.grouped("_matrix", "client", ":version")
        
        for (endpoint,handler) in handlers {

            matrixCSAPI.on(endpoint.method, endpoint.pathComponents) { (req) -> Response in
                let policyFlows = flows[endpoint] ?? defaultFlows
                
                try await handleUIA(req: req, flows: policyFlows)
                
                let response = try await handler.handle(req: req)
                
                req.logger.debug("UIA Controller: Back from endpoint handler")
                req.logger.debug("UIA Controller: Got response = \(response.description)")

                // First order of business: Did the response succeed?  If not, we have nothing else to do.
                guard response.status == .ok else {
                    return response
                }
                
                // We need to check for a couple of special conditions here:
                // 1. Did we just register a new user?
                // 2. Did we just log someone in?
                                
                switch endpoint {
                case .init(.POST, "/register"):
                    req.logger.debug("UIA Controller: Running post-register callbacks")

                    // Find all of the checkers that we just used
                    // Call .onEnrolled() for each of them
                    guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
                        req.logger.error("UIA Controller: Couldn't decode UIA request")
                        throw Abort(.internalServerError)
                    }
                    let auth = uiaRequest.auth
                    let session = req.uia.connectSession(sessionId: auth.session)
                    guard let userId = await session.getData(for: "user_id") as? String else {
                        req.logger.error("UIA Controller: Couldn't find a user_id in the UIA session")
                        throw Abort(.internalServerError)
                    }
                    
                    let completed = await session.getCompleted()
                    req.logger.debug("UIA Controller: Found completed stages: \(completed)")
                    for stage in completed {
                        req.logger.debug("UIA Controller: Calling .onEnrolled() for \(stage)")
                        guard let module = checkers[stage] else {
                            req.logger.error("UIA Controller: Couldn't find checker for [\(stage)]")
                            throw Abort(.internalServerError)
                        }
                        try await module.onEnrolled(req: req, userId: userId)
                    }
                    
                case .init(.POST, "/login"):
                    req.logger.debug("UIA Controller: Running post-login callbacks")
                    
                    /*
                      // FIXME: Move this stuff into LoginHandler
                    // Now supposing we have a valid /login response, we should be able to extract the user_id from it
                    struct MinimalLoginResponse: Content {
                        var userId: String
                        
                        enum CodingKeys: String, CodingKey {
                            case userId = "user_id"
                        }
                    }
                    guard let backendResponse = try? response.content.decode(MinimalLoginResponse.self)
                    else {
                        req.logger.error("UIA Controller: Homeserver /login returned 200 OK but we can't find a user_id")
                        throw Abort(.internalServerError)
                    }
                    let userId = backendResponse.userId
                    req.logger.debug("UIA Controller: The user logged in as [\(userId)]")
                    */

                    // Find all of the checkers that we just used
                    // Call .onLoggedIn() for each of them
                    guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
                        req.logger.error("UIA Controller: Couldn't decode UIA request")
                        throw Abort(.internalServerError)
                    }
                    let auth = uiaRequest.auth
                    let session = req.uia.connectSession(sessionId: auth.session)
                    guard let userId = await session.getData(for: "user_id") as? String else {
                        req.logger.error("UIA Controller: Couldn't find a user_id in the UIA session")
                        throw Abort(.internalServerError)
                    }
                    let completed = await session.getCompleted()
                    req.logger.debug("UIA Controller: Found completed stages: \(completed)")
                    for stage in completed {
                        req.logger.debug("UIA Controller: Calling .onEnrolled() for \(stage)")
                        guard let module = checkers[stage] else {
                            req.logger.error("UIA Controller: Couldn't find checker for [\(stage)]")
                            throw Abort(.internalServerError)
                        }
                        try await module.onLoggedIn(req: req, userId: userId)
                    }
                    
                default:
                    req.logger.debug("UIA Controller: No special processing for this endpoint")
                    break
                }
                
                return response
            }
        }
        
        for (endpoint, policyFlows) in flows {
            // Are we already handling this endpoint ourselves above?
            if handlers[endpoint] == nil {
                // If not, then clearly we (via the config) still wanted to enforce UIA for this endpoint.
                // So we do the UIA, and then we proxy the request on to the real homeserver who can handle it.
                matrixCSAPI.on(endpoint.method, endpoint.pathComponents) { (req) -> Response in
                    try await handleUIA(req: req, flows: policyFlows)
                    
                    return try await defaultProxyHandler.handle(req: req)
                }
            }
        }

    }
    
    private func _getNewSessionID() -> String {
        let length = 12
        return String( (0 ..< length).map { _ in "0123456789".randomElement()! } )
    }
    
    private func _getUserId(req: Request) async throws -> String? {
        if let bearerHeader = req.headers.bearerAuthorization {
            // FIXME: Move the bearer auth into a Vapor middleware https://docs.vapor.codes/4.0/authentication/#bearer
            let token = bearerHeader.token
            // Lookup the userId based on the bearer token
            // We can hit https://HOMESERVER/_matrix/client/VERSION/whoami to get the username from the access_token
            // We should probably also cache the access token locally, so we don't constantly batter that endpoint
            let uri = URI(scheme: self.homeserver.scheme,
                          host: self.homeserver.host,
                          path: "_matrix/client/v3/account/whoami")
            let hsResponse = try await req.client.get(uri, headers: req.headers)
            if hsResponse.status == .ok {
                // The homeserver knows who we are
                // Decode the response to extract the user id
                guard let whoami = try? hsResponse.content.decode(WhoamiResponseBody.self) else {
                    throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Failed to look up user id from access token")
                }
                return whoami.userId
            } else {
                // Homeserver didn't give us a user id -- guess we're not anybody
                return nil
            }
        } else {
            // Maybe the user is trying to log in, and they sent the user id in the request
            if let loginRequest = try? req.content.decode(LoginRequestBody.self) {
                if loginRequest.identifier.type == "m.id.user" {
                    return loginRequest.identifier.user
                } else {
                    return nil
                }
                // FIXME: Add support for looking up user id from a 3pid like an email address
            }
        }
        // Every attempt to find a user id has failed
        // Guess we don't know who the heck this is after all...
        return nil
    }
    
    private func _getRequiredFlows(flows: [UiaFlow], for user: String?, making request: Request) async throws -> [UiaFlow] {
        
        guard let userId = user else {
            // IF we don't know who you are, then everything is always required
            return flows
        }
        
        // FIXME This is where we should figure out the set of flows that we should advertise for this user and this endpoint
        //       1. The user may not be enrolled for every possible auth type
        //          - e.g. suppose we offer both BS-SPEKE and OPAQUE password login
        //            In that case, we should only advertise the ones where the user is already enrolled.
        //            Otherwise, the client may not know which protocol to use.  I mean, I guess it could try both.  But ugh what a mess.
        //       2. Some stages may not be required for all users at all times
        //          - e.g. for the Terms of Service, maybe the user has already accepted the latest terms
        //            In that case, we shouldn't bother them again
        let allFlows = flows
        var enrolledFlows: [UiaFlow] = []
        for flow in allFlows {
            // Is the user enrolled for all the stages in this flow?
            var userIsEnrolled = true
            for stage in flow.stages {
                guard let checker = checkers[stage] else {
                    throw MatrixError(status: .internalServerError, errcode: .unknown, error: "No checker for auth type \(stage)")
                }
                let enrolledForStage = try await checker.isUserEnrolled(userId: userId, authType: stage)
                if !enrolledForStage {
                    userIsEnrolled = false
                    break
                }
            }
            // If so, then add the required stages to
            if userIsEnrolled {
                enrolledFlows.append(flow)
            }
        }
        // Sanity check: Did we just rule out all of our allowable flows for this user?
        if enrolledFlows.isEmpty {
            throw MatrixError(status: .forbidden, errcode: .forbidden, error: "No authentication flows")
        }
        
        // Now we should do a second pass to remove any stages that are not required for this user
        var requiredFlows = [UiaFlow]()
        for flow in enrolledFlows {
            var requiredStages = [String]()
            for stage in flow.stages {
                guard let checker = checkers[stage] else {
                    throw MatrixError(status: .internalServerError, errcode: .unknown, error: "No checker for auth type \(stage)")
                }
                if try await checker.isRequired(for: userId, making: request, authType: stage) {
                    requiredStages.append(stage)
                }
            }
            requiredFlows.append( UiaFlow(stages: requiredStages) )
        }
        
        return requiredFlows
    }

    // FIXME Find a better way to cache the list of actually required & useful flows inside the UIA session
    func handleUIA(req: Request, flows: [UiaFlow]) async throws {
                
        let userId = try await _getUserId(req: req)
                
        // Does this request already have a session associated with it?
        guard let uiaRequest = try? req.content.decode(UiaRequest.self)
        else {
            // No existing UIA structure -- Usually we will return a HTTP 401 with an initial UIA JSON response
            // *** One exception to this rule: If the required flows are empty, return success
            //     And to determine whether the required flows are empty, we need to look at each stage in each flow
            
            let requiredFlows = try await _getRequiredFlows(flows: flows, for: userId, making: req)

            // Check to see if we have any flows with no remaining required stages
            for flow in requiredFlows {
                if flow.stages.isEmpty {
                    // Yay we're actually done.
                    // Somehow this entire flow is satisfied.  For example, maybe we've already completed it in the recent past.
                    // Anyway, return success to indicate that we're done with UIA.
                    return
                }
            }
            
            // Ok if our flows are non-empty, then the client really does have some work to do
            // Set up for UIA and let the client know what is required
            
            req.logger.debug("Request has no UIA session")
            let sessionId = _getNewSessionID()
            let session = req.uia.connectSession(sessionId: sessionId)
            
            // Save the set of required flows in the UIA session state -- We definitely don't want to calculate it again for every request in the session
            await session.setData(for: "required_flows", value: requiredFlows)
            
            var params: [String: [String: AnyCodable]] = [:]
            for flow in requiredFlows {
                for stage in flow.stages {
                    if nil == params[stage] {
                        params[stage] = try? await checkers[stage]?.getParams(req: req, sessionId: sessionId, authType: stage, userId: userId)
                    }
                }
            }
            
            req.logger.debug("Throwing UiaIncomplete error")
            throw UiaIncomplete(flows: requiredFlows, params: params, session: sessionId)
        }
        
        let auth = uiaRequest.auth
        let sessionId = auth.session
        let session = req.uia.connectSession(sessionId: sessionId)
        
        guard let requiredFlows = try await session.getData(for: "required_flows") as? [UiaFlow]
        else {
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Couldn't find required flows for UIA session")
        }

        let authType = auth.type
        req.logger.debug("Request is for auth type [\(authType)]")
        // Is this one of the auth types that are required here?
        let allStages = requiredFlows.reduce( Set<String>() ) { (curr,next) in
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
        
        
        //let success = try await checker.check(req: req, authType: authType)
        //if success {
        if let success = try? await checker.check(req: req, authType: authType),
        success == true {
            // Ok cool, we cleared one stage
            // * Mark the stage as complete
            req.logger.debug("UIA controller: Marking stage \(authType) as complete")
            await session.markStageComplete(stage: authType)
            // * Was this the final stage that we needed?
            // * Or are there still more to be completed?
            let completed = await session.getCompleted()
            req.logger.debug("UIA controller: Got completed = \(completed)")
            let completedStages: Set<String> = .init(completed)
            //req.logger.debug("UIA controller: Completed stages = \(completedStages)")
            for flow in requiredFlows {
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
            for flow in requiredFlows {
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
