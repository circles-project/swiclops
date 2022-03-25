//
//  DummyAuthChecker.swift
//  
//
//  Created by Charles Wright on 3/24/22.
//

import Vapor
import AnyCodable

struct DummyAuthChecker: AuthChecker {
    let AUTH_TYPE_DUMMY = "m.login.dummy"
    
    func getSupportedAuthTypes() -> [String] {
        [AUTH_TYPE_DUMMY]
    }
    
    func getParams(req: Request, authType: String, userId: String?) async throws -> [String : AnyCodable]? {
        return nil
    }
    
    func check(req: Request, authType: String) async throws -> Bool {
        guard AUTH_TYPE_DUMMY == authType,
              let uiaRequest = try? req.content.decode(UiaRequest.self)
        else {
            throw Abort(.badRequest)
        }
        
        guard uiaRequest.auth.type == AUTH_TYPE_DUMMY else {
            throw Abort(.forbidden)
        }
        
        return true
    }
    
    func onLoggedIn(req: Request, userId: String) async throws {
        // Do nothing
    }
    
    func onEnrolled(req: Request, userId: String) async throws {
        // Do nothing
    }
    
    func isUserEnrolled(userId: String, authType: String) async -> Bool {
        // Everyone can do Dummy auth.  It's auth for dummies!
        return true
    }
    
    func isRequired(for userId: String, making request: Request, authType: String) async throws -> Bool {
        // If Dummy is enabled by the config, definitely include it in the advertised flow
        return true
    }
    
    func onUnenrolled(req: Request, userId: String) async throws {
        // Can't unenroll from dummy auth, dummy.  :-)
        throw Abort(.badRequest)
    }
    
    
}
