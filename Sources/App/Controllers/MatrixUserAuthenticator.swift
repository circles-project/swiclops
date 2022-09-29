//
//  MatrixUserAuthenticator.swift
//  
//
//  Created by Charles Wright on 9/29/22.
//

import Vapor

struct MatrixUser: Authenticatable {
    var userId: String
}

struct MatrixUserAuthenticator: AsyncBearerAuthenticator {
    var homeserver: URL
    
    init(homeserver: URL) {
        self.homeserver = homeserver
    }
    
    func authenticate(
        bearer: BearerAuthorization,
        for request: Request
    ) async throws {
        
        let uri = URI(scheme: self.homeserver.scheme,
                      host: self.homeserver.host,
                      path: "/_matrix/client/v3/account/whoami")
        let hsResponse = try await request.client.get(uri, headers: request.headers)
        if hsResponse.status == .ok {
            // The homeserver knows who we are
            // Decode the response to extract the user id
            if let whoami = try? hsResponse.content.decode(WhoamiResponseBody.self) {
                request.auth.login(MatrixUser(userId: whoami.userId))
            }
        }
   }
}
