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
import Crypto

struct BSSpekeAuthChecker: AuthChecker {
    let LOGIN_OPRF = "m.login.bsspeke-ecc.oprf"
    let LOGIN_VERIFY = "m.login.bsspeke-ecc.verify"
    let ENROLL_OPRF = "m.enroll.bsspeke-ecc.oprf"
    let ENROLL_SAVE = "m.enroll.bsspeke-ecc.save"
    
    struct Config: Codable {
        var oprfSecret: String
        
        enum CodingKeys: String, CodingKey {
            case oprfSecret = "oprf_secret"
        }
    }
    
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
    
    struct EnrollRequest: Content {
        struct AuthDict: UiaAuthDict {
            var session: String
            var type: String
            var P: String
            var V: String
            var phfParams: PhfParams
            
            enum CodingKeys: String, CodingKey {
                case session
                case type
                case P
                case V
                case phfParams = "phf_params"
            }
        }
        var auth: AuthDict
    }
    
    struct VerifyRequest: Content {
        struct AuthDict: UiaAuthDict {
            var session: String
            var type: String
            var A: String
            var verifier: String
            
            enum CodingKeys: String, CodingKey {
                case session
                case type
                case A
                case verifier
            }
        }
        var auth: AuthDict
    }
    
    var app: Application
    let serverId: String
    let oprfKey: [UInt8]
    let config: Config
    
    init(app: Application, serverId: String, config: Config) {
        self.app = app
        self.serverId = serverId
        
        self.config = config
        // The OPRF secret isn't necessarily a valid key.  Hash it with SHA256 to get a key of the proper form.
        self.oprfKey = Array(SHA256.hash(data: config.oprfSecret.data(using: .utf8)!))
    }
    
    
    func getSupportedAuthTypes() -> [String] {
        return [LOGIN_OPRF, LOGIN_VERIFY, ENROLL_OPRF, ENROLL_SAVE]
    }
    
    func getParams(req: Request, sessionId: String, authType: String, userId: String?) async throws -> [String : AnyCodable]? {
        
        switch authType {
        case ENROLL_OPRF:
            // Client is just starting the protocol
            // For now these params are universal and hard-coded
            // In the future we would need a database lookup to find the particular params for the given user
            return [
                "curve" : AnyCodable("curve25519"),
                "hash_function" : AnyCodable("blake2b"), // FIXME Make this actually configurable
                "phf_params" : AnyCodable(PhfParams(name: "argon2i", iterations: 3, blocks: 100000)),
            ]
        case LOGIN_OPRF:
            guard let userId = userId else {
                // If the user wants to log in, we need to know who they claim to be
                throw MatrixError(status: .badRequest, errcode: .missingParam, error: "Missing parameter: user id")
            }
            let maybeRecord = try await BSSpekeUser.query(on: req.db)
                .filter(\.$id == userId)
                .first()
            guard let rec = maybeRecord else {
                // User doesn't seem to be enrolled with us.
                // If they ever actually try to authenticate with us, then we will throw an exception
                // But for now, we simply return no params
                req.logger.warning("BS-SPEKE: User \(userId) doesn't seem to be enrolled for \(LOGIN_OPRF)")
                return nil
            }
            return [
                "curve": AnyCodable(rec.curve),
                "hash_function": AnyCodable("blake2b"), // FIXME Make this actually configurable
                "phf_params": AnyCodable(PhfParams(name: rec.phf.name, iterations: rec.phf.iterations, blocks: rec.phf.blocks))
            ]
        case LOGIN_VERIFY:
            // Client should have already completed the ..._OPRF stage
            // In fact, this is our sort-of roundabout way of returning the results from that stage
            guard let userId = userId else {
                req.logger.debug("BS-SPEKE: Not returning params for \(LOGIN_VERIFY) until we get a username")
                return nil
            }
            guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
                throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't parse UIA request")
            }
            let auth = uiaRequest.auth
            let sessionId = auth.session
            let session = req.uia.connectSession(sessionId: sessionId)
            guard let blindSalt = await session.getData(for: authType+".blind_salt") as? String,
                  let B = await session.getData(for: authType+".B") as? String
            else {
                //throw MatrixError(status: .forbidden, errcode: .forbidden, error: "Auth stage for OPRF must be completed before completing BS-SPEKE auth")
                // Don't throw an error -- Maybe we just haven't gotten to the OPRF yet.
                // Or maybe we're advertising BS-SPEKE to everyone, but this user just isn't enrolled.
                req.logger.warning("BS-SPEKE: User \(userId) doesn't seem to be ready for \(LOGIN_VERIFY)")
                return nil
            }
            return [
                "blind_salt": AnyCodable(blindSalt),
                "B": AnyCodable(B)
            ]
        case ENROLL_SAVE:
            // Client should have already completed the ..._OPRF stage
            // In fact, this is our sort-of roundabout way of returning the results from that stage
            guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
                throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't parse UIA request")
            }
            let auth = uiaRequest.auth
            let sessionId = auth.session
            let session = req.uia.connectSession(sessionId: sessionId)
            guard let blindSalt = await session.getData(for: authType+".blind_salt") as? String
            else {
                //throw MatrixError(status: .forbidden, errcode: .forbidden, error: "Auth stage for OPRF must be completed before completing BS-SPEKE auth")
                // Don't throw an error -- Maybe we just haven't gotten to the OPRF yet
                return nil
            }
            return [
                "blind_salt": AnyCodable(blindSalt)
            ]
        default:
            throw MatrixError(status: .badRequest, errcode: .invalidParam, error: "Invalid BS-SPEKE auth stage \(authType)")
        }
    }
    
    private func _b64decode(_ str: String) throws -> [UInt8] {
        guard let data = Data(base64Encoded: str) else {
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Failed to decode base64 string")
        }
        let array = [UInt8](data)
        return array
    }
    
    private func computeB(req: Request, nextStage: String) async throws {
        guard let oprfRequest = try? req.content.decode(OprfRequest.self) else {
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Failed to decode BS-SPEKE OPRF request")
        }
        let auth = oprfRequest.auth
        let sessionId = auth.session
        let session = req.uia.connectSession(sessionId: sessionId)
        
        guard let bss = await session.getData(for: nextStage+".state") as? BlindSaltSpeke.ServerSession
        else {
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Couldn't find BS-SPEKE session state")
        }
        
        guard let userId = await session.getData(for: "user_id") as? String else {
            throw MatrixError(status: .internalServerError, errcode: .forbidden, error: "Could not determine user id")
        }
        
        guard let dbRecord = try await BSSpekeUser.query(on: req.db)
            .filter(\.$id == userId)
            .filter(\.$curve == auth.curve)
            .first()
        else {
            throw MatrixError(status: .forbidden, errcode: .forbidden, error: "User is not enrolled for BS-SPEKE auth")
        }
        
        let P = try _b64decode(dbRecord.P)
        let V = try _b64decode(dbRecord.V)
        
        let B = bss.generateB(basePoint: P)
        
        // Save B and V in our UIA session
        await session.setData(for: nextStage+".B", value: B.base64)
        await session.setData(for: nextStage+".V", value: V.base64)
    }
    
    private func doOPRF(req: Request, nextStage: String) async throws {
        guard let oprfRequest = try? req.content.decode(OprfRequest.self) else {
            req.logger.error("BS-SPEKE: Failed to decode OPRF request")
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Failed to decode BS-SPEKE OPRF request")
        }
        let auth = oprfRequest.auth
        let sessionId = auth.session
        let session = req.uia.connectSession(sessionId: sessionId)
        
        let blind = try _b64decode(auth.blind)
        
        guard let userId = await session.getData(for: "user_id") as? String else {
            throw MatrixError(status: .internalServerError, errcode: .forbidden, error: "Could not determine user id")
        }
        
        var bss = BlindSaltSpeke.ServerSession(serverId: self.serverId, clientId: userId, salt: self.oprfKey)
        let blindSalt = try bss.blindSalt(blind: blind)
        
        // Save the blind salt for return to the user
        await session.setData(for: nextStage+".blind_salt", value: blindSalt.base64)
        // Save our BS-SPEKE session for use in the next stage
        await session.setData(for: nextStage+".state", value: bss)
        // Save the curve name so we don't have to query the DB again
        await session.setData(for: nextStage+".curve", value: auth.curve)
    }
    
    private func verify(req: Request) async throws -> Bool {
        guard let verifyRequest = try? req.content.decode(VerifyRequest.self) else {
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't decode request for \(LOGIN_VERIFY)")
        }
        let auth = verifyRequest.auth
        let sessionId = auth.session
        let session = req.uia.connectSession(sessionId: sessionId)
        
        /* // Apparently this isn't actually needed here...
        guard let userId = await session.getData(for: "m.user.id") as? String
        else {
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Couldn't find user id for BS-SPEKE verification")
        }
        */
        
        guard let bss = await session.getData(for: LOGIN_VERIFY+".state") as? BlindSaltSpeke.ServerSession,
              let Vstring = await session.getData(for: LOGIN_VERIFY+".V") as? String
        else {
            throw MatrixError(status: .forbidden, errcode: .forbidden, error: "Must complete OPRF stage before attempting BS-SPEKE verification")
        }
                
        let A = try _b64decode(auth.A)
        req.logger.debug("\tA\t\(Data(A).hex)")

        let V = try _b64decode(Vstring)
        req.logger.debug("\tV\t\(Data(V).hex)")
        let verifier = try _b64decode(auth.verifier)
        req.logger.debug("cv\t\t\(Data(verifier).hex)")
        
        bss.deriveSharedKey(A: A, V: V)
        
        return bss.verifyClient(verifier: verifier)
    }
    
    private func enrollExtractParams(req: Request) async throws {
        guard let enrollRequest = try? req.content.decode(EnrollRequest.self)
        else {
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't decode request for auth type \(ENROLL_SAVE)")
        }
        let auth = enrollRequest.auth
        let sessionId = auth.session
        let session = req.uia.connectSession(sessionId: sessionId)
        
        /*
        guard let userId = await session.getData(for: "m.user.id") as? String
        else {
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Couldn't find user id for BS-SPEKE enrollment")
        }
        guard let curve = await session.getData(for: ENROLL_SAVE+".curve") as? String
        else {
            throw MatrixError(status: .forbidden, errcode: .forbidden, error: "Must complete OPRF stage before attempting BS-SPEKE enrollment")
        }
        */

        // Store all the stuff from the request into our UIA session
        // Then, if the whole UIA process succeeds, we will save these into the database later in onEnroll()
        await session.setData(for: ENROLL_SAVE+".P", value: auth.P)
        await session.setData(for: ENROLL_SAVE+".V", value: auth.V)
        //await session.setData(for: ENROLL_SAVE+".phf.name", value: auth.phfParams.name)
        //await session.setData(for: ENROLL_SAVE+".phf.blocks", value: auth.phfParams.blocks)
        //await session.setData(for: ENROLL_SAVE+".phf.iterations", value: auth.phfParams.iterations)
        await session.setData(for: ENROLL_SAVE+".phf_params", value: auth.phfParams)
    }
    
    func check(req: Request, authType: String) async throws -> Bool {
        switch authType {
        case ENROLL_OPRF:
            try await doOPRF(req: req, nextStage: ENROLL_SAVE)
            return true
        case ENROLL_SAVE:
            try await enrollExtractParams(req: req)
            return true
        case LOGIN_OPRF:
            try await doOPRF(req: req, nextStage: LOGIN_VERIFY)
            try await computeB(req: req, nextStage: LOGIN_VERIFY)
            return true
        case LOGIN_VERIFY:
            return try await verify(req: req)
        default:
            throw MatrixError(status: .badRequest, errcode: .invalidParam, error: "Bad auth type: \(authType) is not BS-SPEKE")
        }
    }
    
    func onLoggedIn(req: Request, userId: String) async throws {
        // Do nothing
    }
    
    func onEnrolled(req: Request, authType: String, userId: String) async throws {
        guard authType == ENROLL_SAVE else {
            req.logger.debug("BS-SPEKE: onEnroll() for non-\(ENROLL_SAVE) -- doing nothing")
            return
        }
        guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Can't enroll on a non-UIA request")
        }
        let auth = uiaRequest.auth
        let session = req.uia.connectSession(sessionId: auth.session)
        
        // OK the user just enrolled for some auth method.  Was it us?
        guard let curve = await session.getData(for: ENROLL_SAVE+".curve") as? String,
              let P = await session.getData(for: ENROLL_SAVE+".P") as? String,
              let V = await session.getData(for: ENROLL_SAVE+".V") as? String,
              let phfParams = await session.getData(for: ENROLL_SAVE+".phf_params") as? PhfParams
        else {
            //throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Could not retrieve BS-SPEKE data from UIA session")
            req.logger.debug("BS-SPEKE: The new user didn't enroll with us.  Nothing to do.")
            return
        }
        req.logger.debug("BS-SPEKE: Finalizing enrollment for user [\(userId)]")
        let dbRecord = BSSpekeUser(id: userId, curve: curve, P: P, V: V, phf: phfParams)
        try await dbRecord.create(on: req.db)
    }
    
    func isUserEnrolled(userId: String, authType: String) async throws -> Bool {
        switch authType {
        case ENROLL_OPRF, ENROLL_SAVE:
            // Everyone is always eligible to enroll
            return true
        case LOGIN_OPRF, LOGIN_VERIFY:
            // Only users who have a public key set up can log in
            let dbRecord = try await BSSpekeUser.query(on: app.db)
                .filter(\.$id == userId)
                .first()
            
            return dbRecord != nil
        default:
            // Any other auth type must be an error
            return false
        }
    }
    
    func isRequired(for userId: String, making request: Request, authType: String) async throws -> Bool {
        return true
    }
    
    func onUnenrolled(req: Request, userId: String) async throws {
        try await BSSpekeUser.query(on: req.db)
                             .filter(\.$id == userId)
                             .delete()
    }
    
    
}
