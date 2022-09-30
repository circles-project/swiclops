//
//  EmailAuthChecker.swift
//  
//
//  Created by Charles Wright on 3/26/22.
//

import Fluent
import Vapor
import AnyCodable


struct EmailAuthChecker: AuthChecker {
    
    let ENROLL_REQUEST_TOKEN = "m.enroll.email.request_token"
    let ENROLL_SUBMIT_TOKEN = "m.enroll.email.submit_token"
    let LOGIN_REQUEST_TOKEN = "m.login.email.request_token"
    let LOGIN_SUBMIT_TOKEN = "m.login.email.submit_token"
    
    let FROM_ADDRESS = "circuli@circu.li"
    
    let postmarkToken: String
    
    let app: Application
    
    struct RequestTokenUiaRequest: Content {
        struct AuthDict: UiaAuthDict {
            var type: String
            var session: String
            var email: String
        }
        var auth: AuthDict
    }
    
    struct SubmitTokenUiaRequest: Content {
        struct AuthDict: UiaAuthDict {
            var type: String
            var session: String
            var token: String
        }
        var auth: AuthDict
    }
    
    // FIXME: Add an email sender helper here
    //        Then we can support sending email through different services
    init(app: Application, config: EmailConfig) {
        self.app = app
        self.postmarkToken = config.postmarkToken
    }
    
    
    func getSupportedAuthTypes() -> [String] {
        [ENROLL_REQUEST_TOKEN, ENROLL_SUBMIT_TOKEN,
         LOGIN_REQUEST_TOKEN, LOGIN_SUBMIT_TOKEN]
    }
    
    func getParams(req: Request, sessionId: String, authType: String, userId maybeUserId: String?) async throws -> [String : AnyCodable]? {
        if LOGIN_REQUEST_TOKEN == authType {
            // The user is already registered, so we know what their valid email address(es) are
            // If they have more than one address, they need to tell us which one to use
            
            guard let userId = maybeUserId else {
                // If we're trying to log in, we'd better know who the user is
                throw Abort(.internalServerError)
            }
            
            let emailAddressRecords = try await UserEmailAddress.query(on: req.db).filter(\.$userId == userId).all()
            var emailAddresses: [String] = []
            for record in emailAddressRecords {
                let email = record.email
                emailAddresses.append(email)
            }
            
            return ["addresses": AnyCodable(emailAddresses)]
            
        } else {
            return nil
        }
    }
    
    func _handleRequestToken(req: Request, authType: String) async throws -> Bool {
        guard let uiaRequest = try? req.content.decode(RequestTokenUiaRequest.self)
        else {
            throw Abort(.badRequest)
        }
        
        let auth = uiaRequest.auth
        let userEmail = auth.email
        
        req.logger.debug("User requesting a token for email [\(userEmail)]")

        if authType == LOGIN_REQUEST_TOKEN {
            // Ok we're trying to log in some user.  Who is it?
            let session = req.uia.connectSession(sessionId: auth.session)
            guard let userId = await session.getData(for: "m.user.id") as? String else {
                // The top-level handler should have
                throw Abort(.internalServerError)
            }
            
            // Verify that the user is enrolled already with the given address
            guard let _ = try await UserEmailAddress.query(on: req.db)
                                           .filter(\.$email == userEmail)
                                           .filter(\.$userId == userId)
                                           .first()
            else {
                // User is not enrolled with this address
                throw Abort(.badRequest)
            }
        } else {
            guard authType == ENROLL_REQUEST_TOKEN else {
                throw MatrixError(status: .badRequest, errcode: .invalidParam, error: "Bad auth type [\(authType)]")
            }
        }
        
        // Generate a random 6-digit code
        let code = String( (0..<6).map { _ in "0123456789".randomElement()! } )
        // Send an email to the given address containing the code
        let postmarkResponse = try await Postmark.sendEmail(
                                     from: FROM_ADDRESS,
                                     to: userEmail,
                                     subject: "\(code) is your Circuli verification code",
                                     html: "<html><body>Your verification code for Circuli is: <b>\(code)</b>.</body></html>",
                                     text: "Your verification code for Circuli is: \(code)",
                                     for: req,
                                     token: postmarkToken)
        
        if postmarkResponse.errorCode != 0 {
            // Sending the email through Postmark has failed
            req.logger.warning("Postmark returned error code \(postmarkResponse.errorCode)")
            throw Abort(.internalServerError)
        }
        req.logger.debug("Postmark email was successful")
        
        // Save the code that we sent, so we can check it later
        let session = req.uia.connectSession(sessionId: auth.session)
        await session.setData(for: authType+".token", value: code)
        if ENROLL_REQUEST_TOKEN == authType {
            // We're enrolling the user here, so this is a new email address for us
            // Save the address in the UIA session for now
            // If the user succeeds in enrolling, we'll save it into the DB in onEnrolled()
            await session.setData(for: authType+".email", value: userEmail)
        }

        req.logger.debug("Sent email with token \(code)")
        
        // So far so good.  Allow the user to progress to the next stage in the auth flow.
        return true
    }
    
    func _handleSubmitToken(req: Request, authType: String) async throws -> Bool {
        guard let uiaRequest = try? req.content.decode(SubmitTokenUiaRequest.self) else {
            throw Abort(.badRequest)
        }
        let auth = uiaRequest.auth
        let code = auth.token
        
        let session = req.uia.connectSession(sessionId: auth.session)
        
        req.logger.debug("User submitted email token [\(code)] for session [\(auth.session)]")
        
        switch authType {
        case ENROLL_SUBMIT_TOKEN:
            guard let savedCode = await session.getData(for: ENROLL_REQUEST_TOKEN+".token") as? String,
                  savedCode == code
            else {
                // Hmmm either
                //   1) We don't seem to have saved a token/code for this session
                // Or
                //   2) We have a token, but it doesn't match what the user provided
                // Do not pass Go, Do not collect $200
                throw Abort(.forbidden)
            }
        case LOGIN_SUBMIT_TOKEN:
            guard let savedCode = await session.getData(for: LOGIN_REQUEST_TOKEN+".token") as? String,
                  savedCode == code
            else {
                // Hmmm either
                //   1) We don't seem to have saved a token/code for this session
                // Or
                //   2) We have a token, but it doesn't match what the user provided
                // Do not pass Go, Do not collect $200
                throw Abort(.forbidden)
            }
        default:
            // Should never be here
            throw Abort(.badRequest)
        }
        
        // If we made it this far, then we found a matching token
        // Allow the user to progress to the next stage in the flow
        return true
    }
    
    func check(req: Request, authType: String) async throws -> Bool {
        switch authType {
        case ENROLL_REQUEST_TOKEN:
            return try await _handleRequestToken(req: req, authType: authType)
        case ENROLL_SUBMIT_TOKEN:
            return try await _handleSubmitToken(req: req, authType: authType)
        case LOGIN_REQUEST_TOKEN:
            return try await _handleRequestToken(req: req, authType: authType)
        case LOGIN_SUBMIT_TOKEN:
            return try await _handleSubmitToken(req: req, authType: authType)
        default:
            throw Abort(.badRequest)
        }
    }
    
    func onLoggedIn(req: Request, userId: String) async throws {
        // Do nothing
    }
    
    func onEnrolled(req: Request, authType: String, userId: String) async throws {
        guard authType == ENROLL_SUBMIT_TOKEN else {
            req.logger.debug("m.enroll.email: onEnroll() but authType is not \(ENROLL_SUBMIT_TOKEN) -- doing nothing")
            return
        }
        req.logger.debug("m.enroll.email: onEnroll()")
        
        // FIXME Save the user's email address in the database
        guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
            throw Abort(.badRequest)
        }
        
        let auth = uiaRequest.auth
        let session = req.uia.connectSession(sessionId: auth.session)
        
        // Did the user enroll a new email with us?
        if let userEmail = await session.getData(for: ENROLL_REQUEST_TOKEN+".email") as? String {
            // If so, save their email to the database
            req.logger.debug("m.enroll.email: Finalizing enrollment for user [\(userId)] with email [\(userEmail)]")
            let emailRecord = UserEmailAddress(userId: userId, email: userEmail)
            try await emailRecord.save(on: req.db)
            req.logger.debug("m.enroll.email: User email saved to the database")
        } else {
            req.logger.error("m.enroll.email: Couldn't enroll user \(userId) because there is no email address in the session")
            throw Abort(.internalServerError)
        }
    }
    
    func isUserEnrolled(userId: String, authType: String) async throws -> Bool {
        switch authType {
            
        case ENROLL_REQUEST_TOKEN, ENROLL_SUBMIT_TOKEN:
            // Everyone is always eligible to do an enrollment
            return true
            
        case LOGIN_REQUEST_TOKEN, LOGIN_SUBMIT_TOKEN:
            // Lookup whether the user is in the database
            if let _ = try await UserEmailAddress.query(on: app.db)
                                                 .filter(\.$userId == userId)
                                                 .first()
            {
                return true
            } else {
                return false
            }
            
        default:
            // Any other authType must be a mistake
            return false
        }
    }
    
    func isRequired(for userId: String, making request: Request, authType: String) async throws -> Bool {
        // No way out of doing the email verification
        return true
    }
    
    func onUnenrolled(req: Request, userId: String) async throws {
        // FIXME Remove the entry from the database
        throw Abort(.notImplemented)
    }
    
    
}
