//
//  AuthController.swift
//  
//
//  Created by Charles Wright on 3/24/22.
//

import Vapor
import Yams
import AnyCodable


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
    var passthruHandler: PassthruHandler
    
    // For remembering when a given client last completed UIA with us
    // This way, we can avoid bothering them again when they just authed for another request
    var cache: ShardedActorDictionary<MatrixUser,Date>
    
    // MARK: Config
    struct Config: Codable {
        var apple: AppleStoreKitV2SubscriptionChecker.Config?
        var bsspeke: BSSpekeAuthChecker.Config
        var email: EmailConfig
        var terms: TermsAuthChecker.Config?
        
        var registration: RegistrationConfig
        struct RegistrationConfig: Codable {
            var sharedSecret: String
            
            enum CodingKeys: String, CodingKey {
                case sharedSecret = "shared_secret"
            }
        }
        
        var routes: [UiaRoute]
        var defaultFlows: [UiaFlow]
        var passthruEndpoints: [Endpoint]?
        
        struct UiaRoute: Codable {
            var path: String
            var method: HTTPMethod
            var flows: [UiaFlow]?
        }
        
        enum CodingKeys: String, CodingKey {
            case apple
            case bsspeke
            case email
            case terms
            case registration
            case routes
            case defaultFlows = "default_flows"
            case passthruEndpoints = "passthru_endpoints"
        }
    }
    
    // MARK: init
    init(app: Application, config: Config, matrixConfig: MatrixConfig) throws {
        self.app = app
        self.config = config
        
        self.domain = matrixConfig.domain
        self.homeserver = matrixConfig.homeserver
        
        self.cache = .init()
        
        // Set up our map from endpoints to UIA flows
        self.defaultFlows = config.defaultFlows
        self.flows = [:]
        for route in config.routes {
            let endpoint = Endpoint(route.method, route.path)
            self.flows[endpoint] = route.flows ?? defaultFlows
        }
        
        // Set up our UIA checker modules
        let usernameChecker = try UsernameEnrollAuthChecker(app: app)
        var authCheckerModules: [AuthChecker] = [
            DummyAuthChecker(),
            usernameChecker,
            PasswordAuthChecker(app: app),
            TokenRegistrationAuthChecker(),
            EmailAuthChecker(app: app, config: config.email),
            FooAuthChecker(),
            BSSpekeAuthChecker(app: app, serverId: matrixConfig.domain, config: config.bsspeke),

        ]
        
        if let termsConfig = config.terms {
            authCheckerModules.append(TermsAuthChecker(app: app, config: termsConfig))
        }
        
        if let appleConfig = config.apple {
            authCheckerModules.append(AppleStoreKitV2SubscriptionChecker(config: appleConfig))
        }
        
        self.checkers = [:]
        for module in authCheckerModules {
            for authType in module.getSupportedAuthTypes() {
                self.checkers[authType] = module
            }
        }
        
        // Set up our endpoint handlers, that take over after UIA is complete
        self.defaultProxyHandler = ProxyHandler(app: self.app)
        let loginHandler = LoginHandler(app: self.app,
                                        flows: self.flows[.init(.POST, "/login")] ?? self.defaultFlows)
        let accountAuthHandler = AccountAuthHandler(flows: self.flows[.init(.POST, "/account/auth")] ?? self.defaultFlows)
        let endpointHandlerModules: [EndpointHandler] = [
            loginHandler,
            RegistrationHandler(app: self.app),
            AccountDeactivateHandler(checkers: authCheckerModules, proxy: defaultProxyHandler),
            Account3PidHandler(),
            AccountPasswordHandler(),
            accountAuthHandler,
        ]
        self.handlers = [:]
        for module in endpointHandlerModules {
            for endpoint in module.endpoints {
                self.handlers[endpoint] = module
            }
        }
        self.passthruHandler = PassthruHandler(app: app, endpoints: self.config.passthruEndpoints ?? [])

    }
    
    // MARK: handle
    private func handle(req: Request, for endpoint: Endpoint, with handler: EndpointHandler) async throws -> Response {
        let policyFlows = flows[endpoint] ?? defaultFlows
        
        try await handleUIA(req: req, flows: policyFlows)
        
        let response = try await handler.handle(req: req)
        
        req.logger.debug("UIA Controller: Back from endpoint handler")
        req.logger.debug("UIA Controller: Got response = \(response.description)")

        // First order of business: Did the response succeed?  If not, then we have nothing else to do.
        guard response.status == .ok else {
            return response
        }
        
        // Did we just start a new session?
        // If so, add it to our UIA cache so the user won't have to re-auth immediately for things like cross-signing
        struct NewSessionResponse: Content {
            var userId: String
            var accessToken: String
            
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case accessToken = "access_token"
            }
        }
        if let nsr = try? response.content.decode(NewSessionResponse.self) {
            let user = MatrixUser(userId: nsr.userId, accessToken: nsr.accessToken)
            let now = Date()
            await self.cache.set(user, now)
        }
        
        
        // Now run any callbacks, as necessary
        // We need to check for a couple of special conditions here:
        // 1. Did we just enroll for something or register a new user?
        // 2. Did we just log someone in?
                        
        switch endpoint {
        case .init(.POST, "/register"),
             .init(.POST, "/account/auth"),
             .init(.POST, "/account/password"),
             .init(.POST, "/account/3pid/add"):
            req.logger.debug("UIA Controller: Running post-enrollment callbacks")

            // Find all of the checkers that we just used
            // Call .onEnrolled() for each of them
            guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
                req.logger.error("UIA Controller: Couldn't decode UIA request")
                throw Abort(.internalServerError)
            }
            let auth = uiaRequest.auth
            let session = req.uia.connectSession(sessionId: auth.session)
            guard let userId = try await getUserId(req: req) else {
                let msg = "UIA Controller: Couldn't find a user id for this request"
                req.logger.error("\(msg)")
                throw MatrixError(status: .internalServerError, errcode: .unknown, error: msg)
            }
            
            let completed = await session.getCompleted()
            //req.logger.debug("UIA Controller: Found completed stages: \(completed)")
            for stage in completed {
                guard let module = checkers[stage] else {
                    req.logger.error("UIA Controller: Couldn't find checker for [\(stage)]")
                    throw Abort(.internalServerError)
                }
                //req.logger.debug("UIA Controller: Calling .onEnrolled() for \(stage)")
                try await module.onEnrolled(req: req, authType: stage, userId: userId)
                //req.logger.debug("UIA Controller: Back from .onEnrolled() for \(stage)")
            }
            req.logger.debug("UIA Controller: Done with onEnrolled()")
            
        case .init(.POST, "/login"):
            req.logger.debug("UIA Controller: Running post-login callbacks")

            // Find all of the checkers that we just used
            // Call .onLoggedIn() for each of them
            guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
                req.logger.error("UIA Controller: Couldn't decode UIA request")
                throw Abort(.internalServerError)
            }
            let auth = uiaRequest.auth
            let session = req.uia.connectSession(sessionId: auth.session)
            guard let userId = try await getUserId(req: req) else {
                req.logger.error("UIA Controller: Couldn't find a user id for the request")
                throw Abort(.internalServerError)
            }
            let completed = await session.getCompleted()
            req.logger.debug("UIA Controller: Found completed stages: \(completed)")
            for stage in completed {
                req.logger.debug("UIA Controller: Calling .onLoggedIn() for \(stage)")
                guard let module = checkers[stage] else {
                    req.logger.error("UIA Controller: Couldn't find checker for [\(stage)]")
                    throw Abort(.internalServerError)
                }
                try await module.onLoggedIn(req: req, userId: userId)
                req.logger.debug("UIA Controller: Back from .onLoggedIn() for \(stage)")
            }
            req.logger.debug("UIA Controller: Done with onLoggedIn()")

            
        default:
            req.logger.debug("UIA Controller: No special post-processing for \(endpoint)")
            break
        }
        
        // Finally, after all that, now we can return the response that we received way up above
        return response
    }
    
    // MARK: boot
    func boot(routes: RoutesBuilder) throws {
        
        let matrixCSAPI = routes.grouped("_matrix", "client", ":version")
                                .grouped(MatrixUserAuthenticator(homeserver: self.homeserver))
        
        for (endpoint,handler) in handlers {
            matrixCSAPI.on(endpoint.method, endpoint.pathComponents) { (req) -> Response in
                let path = endpoint.pathComponents.map { $0.description }.joined()
                req.logger.debug("Handling request for \(endpoint.method) \(path) with \(handler.self)")
                return try await handle(req: req, for: endpoint, with: handler)
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
        
        if let passthruEndpoints = self.config.passthruEndpoints {
            for endpoint in passthruEndpoints {
                matrixCSAPI.on(endpoint.method, endpoint.pathComponents) { (req) -> Response in
                    try await passthruHandler.handle(req: req)
                }
            }
        }

    }
    
    // MARK: _getNewSessionID
    private func _getNewSessionID() -> String {
        let length = 12
        return String( (0 ..< length).map { _ in "0123456789".randomElement()! } )
    }
    
    // MARK: canonicalizeUserId
    private func canonicalizeUserId(_ username: String) -> String {
        let firstPart = username.starts(with: "@") ? username : "@" + username
        let userId = firstPart.contains(":") ? firstPart : firstPart + ":" + domain
        return userId
    }
    
    // MARK: getUserId
    public func getUserId(req: Request) async throws -> String? {
        // First look for a logged-in Matrix user with a Bearer token.
        // Our MatrixUserAuthenticator will have found the user_id for these users.
        if let authUser = req.auth.get(MatrixUser.self) {
            req.logger.debug("getUserId: Found user [\(authUser.userId)] in the Bearer token")
            return authUser.userId
        }
        
        // Maybe the user is trying to log in, and they sent the user id in the request
        if let loginRequest = try? req.content.decode(LoginRequestBody.self) {
            if loginRequest.identifier.type == "m.id.user" {
                req.logger.debug("getUserId: Found user [\(loginRequest.identifier.user)] in the /login request")
                return loginRequest.identifier.user
            } else {
                req.logger.error("getUserId: Login request has no m.id.user")
                return nil
            }
            // FIXME: Add support for looking up user id from a 3pid like an email address
        }
        
        // Maybe it's a new user trying to register
        if req.url.path.hasSuffix("/register") {
            // Now we are storing the username in the UIA session
            guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
                req.logger.warning("Couldn't parse /register request as UIA...  Not a UIA request???")
                return nil
            }
            let auth = uiaRequest.auth
            let session = req.uia.connectSession(sessionId: auth.session)
            guard let username = await session.getData(for: "username") as? String else {
                req.logger.warning("Couldn't get username for /register UIA request")
                return nil
            }
            return canonicalizeUserId(username)
        }

        // Every attempt to find a user id has failed
        // Guess we don't know who the heck this is after all...
        req.logger.debug("getUserId: No user id in request")
        return nil
    }
    
    // MARK: _getRequiredFlows
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
    
    // MARK: handleUIA

    // FIXME Find a better way to cache the list of actually required & useful flows inside the UIA session
    func handleUIA(req: Request, flows: [UiaFlow]) async throws {
                        
        // FIXME: Add an early check -- Has this user, with this access token, recently authenticated with us?
        //        It should be a very quick thing, like 30 seconds
        //        But if so, don't bother them again so soon.  Just return success.
        // NOTE: Don't return too early -- If the flows contain an "enroll" stage, we NEED to run UIA regardless of whether we've recently authed or not
        
        // First check -- Is this a "normal" UIA request for a logged-in user, and not a login or registration etc?
        if let user = req.auth.get(MatrixUser.self) {
            // Second check -- Has the user recently completed UIA with us?
            if let lastAuthedTimestamp = await self.cache.get(user) {
                let now = Date()
                // Third check -- Was the previous UIA success in the very recent past?
                let delay = lastAuthedTimestamp.distance(to: now)
                if delay < 30.0 {
                    // Ok, now we have successfully verified that the client is cool with us
                    // One last check -- Make sure they are not trying to enroll for something -- If so, we can't skip UIA, that would screw them up.
                    var enrolling = false
                    flowLoop: for flow in flows {
                        for stage in flow.stages {
                            if stage.contains(".enroll.") {
                                enrolling = true
                                break flowLoop
                            }
                        }
                    }
                    if !enrolling {
                        // Yay, we met *all* of the conditions to skip UIA for this request
                        // We're out of here!  Let the caller know that UIA is done.
                        // However -- DON'T update the cache.  This DOES NOT reset the timeout for the next time we will require auth.
                        req.logger.info("Skipping UIA for user [\(user.userId)] with access token [\(user.accessToken)] requesting \(req.url.path)")
                        return
                    }
                } else {
                    req.logger.debug("Can't automatically allow this request; \(delay) is too long since last UIA.")
                }
            }
        }
        
        // Try to find the user id for this request, which may be encoded in different places depending on the type of request
        let userId = try await getUserId(req: req)
                
        // Does this request already have a session associated with it?
        guard let uiaRequest = try? req.content.decode(UiaRequest.self)
        else {
            // No existing UIA structure -- Usually we will return a HTTP 401 with an initial UIA JSON response
            // *** One exception to this rule: If the required flows are empty, return success
            //     And to determine whether the required flows are empty, we need to look at each stage in each flow
            
            let requiredFlows = try await _getRequiredFlows(flows: flows, for: userId, making: req)

            // If there are no flows required for this request, we're done
            if requiredFlows.isEmpty {
                req.logger.debug("No required flows.  Skipping UIA.")
                return
            }
            // If we do have some flows, check to see if we have any flows with no remaining required stages
            for flow in requiredFlows {
                if flow.stages.isEmpty {
                    // Yay we're actually done.
                    // Somehow this entire flow is satisfied.  For example, maybe we've already completed it in the recent past.
                    // Anyway, return success to indicate that we're done with UIA.
                    req.logger.debug("Flow is satisfied.  Done with UIA.")
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
        
        // We have the user_id that we extracted above.  Store it in the request's UIA session where all of the checkers can find it.
        if let u = userId {
            req.logger.debug("UIA Controller: Request is from user_id [\(u)]")
            await session.setData(for: "user_id", value: u)
        } else {
            req.logger.debug("UIA Controller: No user id")
        }
        
        guard let requiredFlows = await session.getData(for: "required_flows") as? [UiaFlow]
        else {
            req.logger.error("UIA Controller: Couldn't find required flows for UIA session")
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
            req.logger.error("UIA Controller: Invalid auth type \(authType)")
            throw MatrixError(status: .forbidden, errcode: .invalidParam, error: "Invalid auth type \(authType)")
        }
        
        /*
        // For multi-stage authentication methods like BS-SPEKE, we *must* allow the user to complete the first stage multiple times
        // When the 2nd stage fails, e.g. the user mis-typed their password, the user has to go back and do both stages.
        // If we have already marked the first stage as unavailable, they can't do that.
        let alreadyCompleted = await session.getCompleted()
        if alreadyCompleted.contains(authType) {
            req.logger.error("UIA Controller: Authentication stage \(authType) has already been completed")
            throw MatrixError(status: .forbidden, errcode: .invalidParam, error: "Authentication stage \(authType) has already been completed")
        }
        */
        
        guard let checker = self.checkers[authType]
        else {
            // Uh oh, we screwed up and we don't have a checker for an auth type that we advertised.  Doh!
            // FIXME Create an actual Matrix response and return it
            //throw Abort(.internalServerError)
            req.logger.error("UIA Controller: No checker found for requested auth type: \(authType)")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "No checker found for auth type \(authType)")
        }
        
        
        // We don't want the optional try here, because it "consumes" the thrown exception instead of sending the Matrix error response back to the client.
        // Instead we want the regular try, which will let the checker generate a MatrixError for our Middlware to send.
        let success = try await checker.check(req: req, authType: authType)
        // In the case that the checker did not throw an error but actually returned a bool, then we have to check the true/false response code and handle it appropriately.
        if success {
        //if let success = try? await checker.check(req: req, authType: authType),
        //   success == true
        //{
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
                    
                    // Save the current timestamp in our cache, in case the same client needs to hit another UIA endpoint in the next few seconds
                    if let user = req.auth.get(MatrixUser.self) {
                        let now = Date()
                        await self.cache.set(user, now)
                    }
                    
                    return
                }
            }
            
            // We're still here, so we must not be done yet
            // Therefore we have more UIA stages left to go
            // Get their parameters for the UIA response
            var newParams: [String: [String: AnyCodable]] = [:]
            for flow in requiredFlows {
                for stage in flow.stages {
                    //req.logger.debug("UIA controller: Getting params for stage [\(stage)]")
                    if nil == newParams[stage] {
                        newParams[stage] = try? await checkers[stage]?.getParams(req: req, sessionId: sessionId, authType: stage, userId: userId)
                    }
                }
            }
            
            throw UiaIncomplete(flows: requiredFlows, completed: completed, params: newParams, session: sessionId)
            
        } else {
            throw MatrixError(status: .forbidden, errcode: .forbidden, error: "Authentication failed for type \(authType)")
        }
        
        
    }
}
