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
    
    func getParams(req: Request, sessionId: String, authType: String, userId: String?) async throws -> [String : AnyCodable]? {
        return nil
    }
    
    func check(req: Request, authType: String) async throws -> Bool {
        req.logger.debug("Dummy auth checker checking request of type \(authType)")
        guard AUTH_TYPE_DUMMY == authType,
              let uiaRequest = try? req.content.decode(UiaRequest.self)
        else {
            req.logger.error("DummyAuth: Wrong auth type: \(authType)")
            throw MatrixError(status: .badRequest, errcode: .invalidParam, error: "Invalid auth type: \(authType)")
        }
        
        guard uiaRequest.auth.type == AUTH_TYPE_DUMMY else {
            req.logger.error("DummyAuth: Bad auth type: \(authType) -- Doesn't match `authType` function parameter")
            throw MatrixError(status: .badRequest, errcode: .invalidParam, error: "Invalid auth type: \(authType)")
        }
        
        req.logger.debug("Dummy auth checker: Returning true")
        return true
    }
    
    func onLoggedIn(req: Request, userId: String) async throws {
        // Do nothing
    }
    
    func onEnrolled(req: Request, authType: String, userId: String) async throws {
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
