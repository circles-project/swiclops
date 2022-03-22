//
//  PasswordAuthChecker.swift
//  
//
//  Created by Charles Wright on 3/22/22.
//

import Fluent
import Vapor

struct PasswordAuthChecker: AuthChecker {
    
    let AUTH_TYPE_LOGIN: String = "m.login.password"
    let AUTH_TYPE_ENROLL: String = "m.enroll.password"
    
    func getSupportedAuthTypes() -> [String] {
        [AUTH_TYPE_LOGIN, AUTH_TYPE_ENROLL]
    }
    
    func getParams(req: Request, authType: String, userId: String?) async throws -> [String : Any]? {
        switch authType  {
        case AUTH_TYPE_LOGIN:
            return nil
        case AUTH_TYPE_ENROLL:
            return ["min_length": 8]
        default:
            throw Abort(.badRequest)
        }
        
    }
    
    func check(req: Request, authType: String) async throws -> Bool {
        switch authType {
        case AUTH_TYPE_LOGIN:
            let result = try await self._checkLogin(req: req)
            return result
        case AUTH_TYPE_ENROLL:
            let result = try await self._checkEnroll(req: req)
            return result
        default:
            throw Abort(.badRequest)
        }
    }
    
    func _checkLogin(req: Request) async throws -> Bool {
        // Validate that the user is enrolled with us
        // Extract the username and password from the request
        // Hash the password
        // Compare with the stored password hash
        // If it matches, return true
        // Otherwise return false
        return false
    }
    
    func _checkEnroll(req: Request) async throws -> Bool {
        // Extract the username and password from the request
        // Check that the password satisfies our policy
        // If not, return false
        // Otherwise,
        //   Hash the password
        //   Save the hash in our session state
        return true
    }
    
    func onLoggedIn(req: Request, userId: String) async throws {
        // Do nothing
    }
    
    func onEnrolled(req: Request, userId: String) async throws {
        // Verify that this request is for us
        // Extract the new password from the request
        // Hash the new password
        // Save the new hash in the database
    }
    
    func isEnrolled(userId: String, authType: String) async -> Bool {
        // Query the database for any records with the given userId
        // If we found any valid records, return true
        // Otherwise return false
        return false
    }
    
    func onUnenrolled(req: Request, userId: String) async throws {
        // Verify that this request is for us
        // Verify that the given user is enrolled with us
        // Remove the user's entry from our database
    }
    
    
}
