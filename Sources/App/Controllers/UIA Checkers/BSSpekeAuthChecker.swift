//
//  BSSpekeAuthChecker.swift
//  
//
//  Created by Charles Wright on 4/5/22.
//

import Vapor
import AnyCodable
import BlindSaltSpeke

struct BSSpekeAuthChecker: AuthChecker {
    let LOGIN_OPRF = "m.login.bsspeke-ecc.oprf"
    let LOGIN_VERIFY = "m.login.bsspeke-ecc.verify"
    let ENROLL_OPRF = "m.enroll.bsspeke-ecc.oprf"
    let ENROLL_SAVE = "m.enroll.bsspeke-ecc.enroll"
    
    struct PhfParams: Codable {
        var name: String
        var iterations: UInt
        var blocks: UInt
    }
    
    struct BSSpekeParams: Codable {
        var curve: String
        var hashFunction: String
        var phfParams: PhfParams
    }
    
    func getSupportedAuthTypes() -> [String] {
        return [LOGIN_OPRF, LOGIN_VERIFY, ENROLL_OPRF, ENROLL_SAVE]
    }
    
    func getParams(req: Request, sessionId: String, authType: String, userId: String?) async throws -> [String : AnyCodable]? {
        switch authType {
        case ENROLL_OPRF, LOGIN_OPRF:
            return [
                "curve" : "curve25519",
                "hash_function" : "blake2b",
                "phf_params" : PhfParams(name: "argon2i", iterations: 3, blocks: 100000)
            ]
        case ENROLL_SAVE:
            return ["blind_salt": "12345", "B": "abcdef0123456789"]
        case LOGIN_VERIFY:
            return ["blind_salt": "12345", "B": "abcdef0123456789"]
        default:
            throw MatrixError(status: .badRequest, errcode: .invalidParam, error: "Invalid BS-SPEKE auth stage \(authType)")
        }
    }
    
    func check(req: Request, authType: String) async throws -> Bool {
        var bss = BlindSaltSpeke.ServerSession(serverId: "example.com", clientId: "@bob:example.com", salt: .init(repeating: 0xff, count: 32))
        throw Abort(.notImplemented)
    }
    
    func onLoggedIn(req: Request, userId: String) async throws {
        // Do nothing
    }
    
    func onEnrolled(req: Request, userId: String) async throws {
        throw Abort(.notImplemented)
    }
    
    func isUserEnrolled(userId: String, authType: String) async throws -> Bool {
        throw Abort(.notImplemented)
    }
    
    func isRequired(for userId: String, making request: Request, authType: String) async throws -> Bool {
        return true
    }
    
    func onUnenrolled(req: Request, userId: String) async throws {
        throw Abort(.notImplemented)
    }
    
    
}
