//
//  AuthChecker.swift
//  
//
//  Created by Charles Wright on 3/22/22.
//

import Fluent
import Vapor
import AnyCodable

protocol AuthChecker {
    
    func getSupportedAuthTypes() -> [String]
    
    func getParams(req: Request, sessionId: String, authType: String, userId: String?) async throws -> [String:AnyCodable]?
    
    func check(req: Request, authType: String) async throws -> Bool
    
    func onSuccess(req: Request, authType: String, userId: String) async throws -> Void

    func onLoggedIn(req: Request, authType: String, userId: String) async throws -> Void

    func onEnrolled(req: Request, authType: String, userId: String) async throws -> Void
    
    func isUserEnrolled(userId: String, authType: String) async throws -> Bool
    
    func isRequired(for userId: String, making request: Request, authType: String) async throws -> Bool
    
    func onUnenrolled(req: Request, userId: String) async throws -> Void
}
