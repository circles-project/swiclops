//
//  RegistrationHandler.swift
//  
//
//  Created by Charles Wright on 9/12/22.
//

import Vapor
import Crypto

struct BasicRegisterRequestBody: Content {
    var deviceId: String?
    var inhibitLogin: Bool?
    var initialDeviceDisplayName: String?
    var password: String?
    var refreshToken: Bool?
    // Moving the username out of the endpoint request and into a new UIA stage "m.enroll.username"
    // The idea is that now we can check / validate the username before making the user do all the rest of the UIA
    //var username: String
    
    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case inhibitLogin = "inhibit_login"
        case initialDeviceDisplayName = "initial_device_display_name"
        case password
        case refreshToken = "refresh_token"
    }
}

struct SynapseAdminPutUserRequestBody: Content {
    var password: String?
    var logout_devices: Bool?
    var displayname: String?
    var avatar_url: String?
    var threepids: [ThreePid]?
    struct ThreePid: Codable {
        var medium: Medium
        enum Medium: String, Codable {
            case email
            case msisdn
        }
        var address: String
    }
    var externalIds: [ExternalId]?
    struct ExternalId: Codable {
        var auth_provider: String
        var external_id: String
    }
    var admin: Bool?
    var deactivated: Bool?
    var locked: Bool?
    var user_type: String?
    
    init(email: String? = nil) {
        if let emailAddress = email {
            self.threepids = [ThreePid(medium: .email, address: emailAddress)]
        }
    }
}

struct SharedSecretRegisterRequestBody: Content {
    var deviceId: String?
    var inhibitLogin: Bool?
    var initialDeviceDisplayName: String?
    var mac: String
    var nonce: String
    var refreshToken: Bool?
    var username: String
    var password: String
    
    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case inhibitLogin = "inhibit_login"
        case initialDeviceDisplayName = "initial_device_display_name"
        case mac
        case nonce
        case refreshToken = "refresh_token"
        case username
        case password
    }
    
    init(_ basicRequest: BasicRegisterRequestBody, username: String, nonce: String, sharedSecret: String) {
        self.deviceId = basicRequest.deviceId
        self.inhibitLogin = basicRequest.inhibitLogin
        self.initialDeviceDisplayName = basicRequest.initialDeviceDisplayName
        self.refreshToken = basicRequest.refreshToken
        
        self.username = username
        // Ok this is dumb, but Synapse requires a password here
        // So fine, we'll generate 128 random bits and throw them away when we're done
        self.password = String(format: "%llx%llx", UInt64.random(), UInt64.random())
        
        self.nonce = nonce
        
        let key = SymmetricKey(data: sharedSecret.data(using: .utf8)!)
        
        var hmac = HMAC<Insecure.SHA1>(key: key)
        hmac.update(data: nonce.data(using: .utf8)!)
        hmac.update(data: Data(repeating: 0, count: 1))
        hmac.update(data: self.username.data(using: .utf8)!)
        hmac.update(data: Data(repeating: 0, count: 1))
        hmac.update(data: self.password.data(using: .utf8)!)
        hmac.update(data: Data(repeating: 0, count: 1))
        hmac.update(data: "notadmin".data(using: .utf8)!)

        self.mac = Data(hmac.finalize()).hex
    }
}

struct RegisterResponseBody: Content {
    var accessToken: String?
    var deviceId: String?
    var expiresInMs: Int?
    var homeServer: String?
    var refreshToken: String?
    var userId: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case deviceId = "device_id"
        case expiresInMs = "expires_in_ms"
        case homeServer = "home_server"
        case refreshToken = "refresh_token"
        case userId = "user_id"
    }
}

struct RegistrationHandler: EndpointHandler {
    let app: Application
    var endpoints: [Endpoint]
    
    
    init(app: Application) {
        self.app = app
        self.endpoints = [
            .init(.POST, "/register"),
        ]
    }
    
    
    func handle(req: Request) async throws -> Response {
        req.logger.debug("RegistrationHandler: Handling request")
        
        struct RegisterQueryParams: Content {
            enum Kind: String, Codable {
                case user
                case guest
            }
            var kind: Kind
        }
        if let params = try? req.query.decode(RegisterQueryParams.self) {
            guard params.kind == .user else {
                req.logger.error("Guest registration not suppported")
                throw MatrixError(status: .badRequest, errcode: .invalidParam, error: "Guest registration not supported")
            }
        }
        
        guard let clientRequest = try? req.content.decode(BasicRegisterRequestBody.self),
              let uiaRequest = try? req.content.decode(UiaRequest.self)
        else {
            req.logger.error("Couldn't parse /register request")
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't parse /register request")
        }
        let auth = uiaRequest.auth
        let session = req.uia.connectSession(sessionId: auth.session)
        guard let username = await session.getData(for: "username") as? String else {
            req.logger.error("Couldn't find username")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Couldn't find username")
        }
        req.logger.debug("RegistrationHandler: username = [\(username)")
        
        
        // We don't really handle /register requests all by ourselves
        // We handle all the authentication parts, but the "real" homeserver is the one who actually creates the account
        // Now that the UIA is done, we need to craft a /register request of the proper form, so that the homeserver can know that it came from us
        // And then we proxy it to the real homeserver
        
        guard let admin = req.application.admin
        else {
            req.logger.error("Could not get admin backend")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Could not get admin backend")
        }
        
        guard let config = req.application.config
        else {
            req.logger.error("Could not get application config")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Could not get configuration")
        }
        
        let homeserver = config.matrix.homeserver

        // -- Here we're using the shared secret approach from the Synapse admin API v1 https://matrix-org.github.io/synapse/latest/admin_api/register_api.html
        
        // First get a fresh nonce from the homeserver
        let nonceURI = URI(scheme: homeserver.scheme, host: homeserver.host, port: homeserver.port, path: "/_synapse/admin/v1/register")
        let nonceResponse = try await req.client.get(nonceURI)
        struct NonceResponseBody: Content {
            var nonce: String
        }
        guard let nonceResponseBody = try? nonceResponse.content.decode(NonceResponseBody.self) else {
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Failed to get nonce")
        }
        let nonce = nonceResponseBody.nonce
        req.logger.debug("RegistrationHandler: Got nonce = [\(nonce)]")
        

                        
        // Build the shared-secret request from the normal request and the crypto material
        let proxyRequestBody = SharedSecretRegisterRequestBody(clientRequest, username: username, nonce: nonce, sharedSecret: admin.sharedSecret)
            
        // We have to use the special admin API, not the normal client-server endpoint
        let homeserverURI = URI(scheme: homeserver.scheme, host: homeserver.host, port: homeserver.port, path: "/_synapse/admin/v1/register")

        let proxyResponse = try await req.client.post(homeserverURI, headers: req.headers, content: proxyRequestBody)
        req.logger.debug("RegistrationHandler: Got admin API response with status \(proxyResponse.status.code) \(proxyResponse.status.reasonPhrase)")

        // If the response was successful, then the user was just registered on the homeserver
        if proxyResponse.status == .ok {
            // We need to find out the user_id for all of our post-enroll callbacks
            struct MinimalRegisterResponse: Content {
                var userId: String
                
                enum CodingKeys: String, CodingKey {
                    case userId = "user_id"
                }
            }
            guard let minimalResponse = try? proxyResponse.content.decode(MinimalRegisterResponse.self)
            else {
                req.logger.error("RegistrationHandler: Admin API returned 200 OK but we can't find a user_id")
                
                // Ok WTF is going on here???
                // Update: It turns out that the nginx-proxy was adding gzip compression, which the Vapor client can't handle by default 🤦‍♂️😱👎
                //         The fix was simple: Connect directly to Synapse instead of going through Nginx.
                //         Alternatively, we also enabled decompression for the client in configure()
                req.logger.error("RegistrationHandler: Proxy response was \(proxyResponse.description)")
                
                throw Abort(.internalServerError)
            }
            let userId = minimalResponse.userId
            req.logger.debug("RegistrationHandler: The new user's id is [\(userId)]")
            
            // Now we need to save the user id in the UIA session; This is also for the post-enroll processing
            guard let uiaResponse = try? req.content.decode(UiaRequest.self) else {
                req.logger.error("RegistrationHandler: Couldn't decode UIA request")
                throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't decode UIA request")
            }
            let auth = uiaResponse.auth
            let session = req.uia.connectSession(sessionId: auth.session)
            await session.setData(for: "user_id", value: userId)
            
            
            // If the user validated an email address, we should also add it as a 3pid
            //   * To do this, we send a PUT to /_synapse/admin/v2/users/<user_id>
            //     https://matrix-org.github.io/synapse/latest/admin_api/user_admin_api.html#create-or-modify-account
            //     - Alternatively, we could just make a single call to the admin API v2 endpoint instead of making the request above
            //     - But then we would have to handle all the other junk that /register normally does.. initial device id, etc.
            //   * Then we can send the user email notifications about important things that happen on the server (downtime, new messages, etc)
            // HOWEVER to do this requires that we have admin user credentials on the homeserver
            if let creds = admin.creds,
               let email = await session.getData(for: EmailAuthChecker.ENROLL_SUBMIT_TOKEN+".email") as? String
            {
                req.logger.debug("Calling Synapse admin API v2 to add email address")
                
                let uri = URI(scheme: homeserver.scheme, host: homeserver.host, port: homeserver.port, path: "/_synapse/admin/v2/users/\(userId)")
                
                let requestBody = SynapseAdminPutUserRequestBody(email: email)
                
                let headers = HTTPHeaders([
                    ("Authorization", "Bearer: \(creds.accessToken)")
                ])

                let userAdminResponse = try await req.client.put(uri, headers: headers, content: requestBody)
                
                if userAdminResponse.status.code == 201 {
                    req.logger.debug("Added email address \(email) for user \(userId)")
                } else {
                    req.logger.error("Failed to add email address - got HTTP \(userAdminResponse.status.code) \(userAdminResponse.status.reasonPhrase)")
                }
                
            } else {
                req.logger.debug("Not adding an email adddress for this user")
            }
            
        }
        
        let response = try await proxyResponse.encodeResponse(for: req)
        req.logger.debug("RegistrationHandler: Converted ProxyResponse to a normal Vapor Response.  Returning now...")
        
        return response
    }
    
}
