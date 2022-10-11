//
//  MatrixUserAuthenticator.swift
//  
//
//  Created by Charles Wright on 9/29/22.
//

import Vapor

struct MatrixUser: Authenticatable, Hashable {
    var userId: String
    var accessToken: String
}

struct MatrixUserAuthenticator: AsyncBearerAuthenticator {
    var homeserver: URL
    var cache: ShardedActorDictionary<String,String>
    
    init(homeserver: URL) {
        self.homeserver = homeserver
        self.cache = .init()
    }
    
    func authenticate(
        bearer: BearerAuthorization,
        for request: Request
    ) async throws {
        
        if let cachedUserId = await self.cache.get(bearer.token) {
            request.auth.login(MatrixUser(userId: cachedUserId, accessToken: bearer.token))
            return
        }
        
        let uri = URI(scheme: self.homeserver.scheme,
                      host: self.homeserver.host,
                      path: "/_matrix/client/v3/account/whoami")
        let hsResponse = try await request.client.get(uri, headers: request.headers)
        if hsResponse.status == .ok {
            // The homeserver knows who we are
            // Decode the response to extract the user id
            if let whoami = try? hsResponse.content.decode(WhoamiResponseBody.self) {
                // Mark the request as belonging to the user
                request.auth.login(MatrixUser(userId: whoami.userId, accessToken: bearer.token))
                // And add this bearer token / user id combo to our cache
                await self.cache.set(bearer.token, whoami.userId)
            }
        }
   }
}
