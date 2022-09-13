//
//  RegistrationHandler.swift
//  
//
//  Created by Charles Wright on 9/12/22.
//

import Vapor
import CryptoKit

struct BasicRegisterRequestBody: Content {
    var deviceId: String?
    var inhibitLogin: Bool?
    var initialDeviceDisplayName: String?
    var password: String?
    var refreshToken: String?
    var username: String
}

struct SharedSecretRegisterRequestBody: Content {
    var deviceId: String?
    var inhibitLogin: Bool?
    var initialDeviceDisplayName: String?
    var mac: String
    var nonce: String
    var refreshToken: String?
    var username: String
    var password: String
    
    init(_ basicRequest: BasicRegisterRequestBody, nonce: String, sharedSecret: String) {
        self.deviceId = basicRequest.deviceId
        self.inhibitLogin = basicRequest.inhibitLogin
        self.initialDeviceDisplayName = basicRequest.initialDeviceDisplayName
        self.refreshToken = basicRequest.refreshToken
        
        self.username = basicRequest.username
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

struct RegistrationHandler: EndpointHandler {
    let app: Application
    let homeserver: URL
    var endpoints: [Endpoint]
    var sharedSecret: String
    
    init(app: Application, homeserver: URL, sharedSecret: String) {
        self.app = app
        self.homeserver = homeserver
        self.endpoints = [
            .init(.POST, "/register"),
        ]
        self.sharedSecret = sharedSecret
    }
    
    func handle(req: Request) async throws -> Response {
    
        
        guard let clientRequest = try? req.content.decode(BasicRegisterRequestBody.self)
        else {
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't parse /register request")
        }
        
        // We don't really handle /register requests all by ourselves
        // We handle all the authentication parts, but the "real" homeserver is the one who actually creates the account
        // We need to craft a /register request of the proper form, so that the homeserver can know that it came from us
        // -- Here we're using the shared secret approach from Synapse https://matrix-org.github.io/synapse/latest/admin_api/register_api.html
        // And then we proxy it to the real homeserver
        
        // First get a fresh nonce from the homeserver
        let nonceURI = URI(scheme: homeserver.scheme, host: homeserver.host, path: "/_synapse/admin/v1/register")
        let nonceResponse = try await req.client.get(nonceURI)
        struct NonceResponseBody: Content {
            var nonce: String
        }
        guard let nonceResponseBody = try? nonceResponse.content.decode(NonceResponseBody.self) else {
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Failed to get nonce")
        }
        let nonce = nonceResponseBody.nonce
        
        // Build the shared-secret request from the normal request and the crypto material
        let proxyRequestBody = SharedSecretRegisterRequestBody(clientRequest, nonce: nonce, sharedSecret: self.sharedSecret)
        
        // We have to use the special admin API, not the normal client-server endpoint
        let homeserverURI = URI(scheme: homeserver.scheme, host: homeserver.host, path: "/_synapse/admin/v1/register")

        let proxyResponse = try await req.client.post(homeserverURI, headers: req.headers, content: proxyRequestBody)
        let responseBody = Response.Body(buffer: proxyResponse.body ?? .init())
        return Response(status: proxyResponse.status, headers: proxyResponse.headers, body: responseBody)
    }
    
}
