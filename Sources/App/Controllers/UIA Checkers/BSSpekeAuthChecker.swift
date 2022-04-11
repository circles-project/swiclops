//
//  BSSpekeAuthChecker.swift
//  
//
//  Created by Charles Wright on 4/5/22.
//

import Vapor
import Fluent
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
    
    /*
    struct BSSpekeParams: Codable {
        var curve: String
        var hashFunction: String
        var phfParams: PhfParams
    }
    */
    
    struct OprfRequest: Content {
        struct AuthDict: UiaAuthDict {
            var session: String
            var type: String
            var curve: String
            var blind: String
        }
        var auth: AuthDict
    }
    
    let app: Application
    let serverId: String
    let oprfKey: [UInt8]
    
    init(app: Application, serverId: String, oprfKey: [UInt8]) {
        self.app = app
        self.serverId = serverId
        self.oprfKey = oprfKey
    }
    
    
    func getSupportedAuthTypes() -> [String] {
        return [LOGIN_OPRF, LOGIN_VERIFY, ENROLL_OPRF, ENROLL_SAVE]
    }
    
    func getParams(req: Request, sessionId: String, authType: String, userId: String?) async throws -> [String : AnyCodable]? {
        
        switch authType {
        case ENROLL_OPRF, LOGIN_OPRF:
            // Client is just starting the protocol
            // For now these params are universal and hard-coded
            // In the future we would need a database lookup to find the particular params for the given user
            return [
                "curve" : AnyCodable("curve25519"),
                "hash_function" : AnyCodable("blake2b"),
                "phf_params" : AnyCodable(PhfParams(name: "argon2i", iterations: 3, blocks: 100000)),
            ]
        case ENROLL_SAVE, LOGIN_VERIFY:
            // Client should have already completed the ENROLL_OPRF stage
            // In fact, this is our sort-of roundabout way of returning the results from that stage
            guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
                throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't parse UIA request")
            }
            let auth = uiaRequest.auth
            let sessionId = uiaRequest.auth.session
            let session = req.uia.connectSession(sessionId: sessionId)
            guard let blindSalt = await session.getData(for: ENROLL_OPRF+".blind_salt") as? String,
                  let B = await session.getData(for: ENROLL_OPRF+".B") as? String
            else {
                throw MatrixError(status: .forbidden, errcode: .forbidden, error: "Auth stage for OPRF must be completed before completing BS-SPEKE auth")
            }
            return ["blind_salt": AnyCodable(blindSalt), "B": AnyCodable(B)]
        default:
            throw MatrixError(status: .badRequest, errcode: .invalidParam, error: "Invalid BS-SPEKE auth stage \(authType)")
        }
        
        throw Abort(.notImplemented)
    }
    
    private func doLoginOPRF(req: Request, authType: String) async throws {
        guard let oprfRequest = try? req.content.decode(OprfRequest.self) else {
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Failed to decode BS-SPEKE OPRF request")
        }
        let auth = oprfRequest.auth
        let sessionId = auth.session
        let session = req.uia.connectSession(sessionId: sessionId)
        
        let blindStr = auth.blind
        guard let blindData = Data(base64Encoded: blindStr) else {
            throw MatrixError(status: .badRequest, errcode: .invalidParam, error: "Bad parameter: blind")
        }
        let blind = [UInt8](blindData)
        
        guard let userId = await session.getData(for: "m.user.id") as? String else {
            throw MatrixError(status: .internalServerError, errcode: .forbidden, error: "Could not determine user id")
        }
        
        var bss = BlindSaltSpeke.ServerSession(serverId: self.serverId, clientId: userId, salt: self.oprfKey)
        let blindSalt = try bss.blindSalt(blind: blind)
        
        guard let dbRecord = try await BsspekeUser.query(on: req.db)
            .filter(\.$id == userId)
            .filter(\.$curve == auth.curve)
            .first()
        else {
            throw MatrixError(status: .forbidden, errcode: .forbidden, error: "User is not enrolled for BS-SPEKE auth")
        }
        
        let Pstring = dbRecord.P
        let Vstring = dbRecord.V
        
        guard let Pdata = Data(base64Encoded: Pstring) else {
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Failed to decode user's base point on the curve")
        }
        let P = [UInt8](Pdata)
        
        let B = bss.generateB(basePoint: P)
        
        // Save blindSalt and B in our UIA session
        await session.setData(for: LOGIN_VERIFY+".blind_salt", value: blindSalt.base64)
        await session.setData(for: LOGIN_VERIFY+".B", value: B.base64)
        // Save our BS-SPEKE session object as well
        await session.setData(for: LOGIN_VERIFY+".state", value: bss)
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
