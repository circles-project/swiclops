//
//  AuthChecker.swift
//  
//
//  Created by Charles Wright on 3/22/22.
//

import Fluent
import Vapor

protocol AuthChecker {
    
    func getSupportedAuthTypes() -> [String]
    
    func getParams(req: Request, authType: String, userId: String?) async throws -> [String:Any]?
    
    func check(req: Request, authType: String) async throws -> Bool
    
    func onLoggedIn(req: Request, userId: String) async throws -> Void

    func onEnrolled(req: Request, userId: String) async throws -> Void
    
    func isEnrolled(userId: String, authType: String) async -> Bool
    
    func onUnenrolled(req: Request, userId: String) async throws -> Void
}
