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
    
    let FROM_ADDRESS = "Circles <circles-noreply@futo.org>"
    
    let POSTMARK_TOKEN = "FIXME"
    
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
    
    init(app: Application) {
        self.app = app
    }
    
    
    func getSupportedAuthTypes() -> [String] {
        [ENROLL_REQUEST_TOKEN, ENROLL_SUBMIT_TOKEN,
         LOGIN_REQUEST_TOKEN, LOGIN_SUBMIT_TOKEN]
    }
    
    func getParams(req: Request, authType: String, userId maybeUserId: String?) async throws -> [String : AnyCodable]? {
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

        if authType == LOGIN_REQUEST_TOKEN {
            // Ok we're trying to log in some user.  Who is it?
            let session = req.uia.connectSession(sessionId: auth.session)
            guard let userId = session.getData(for: "m.user.id") else {
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
                throw Abort(.badRequest)
            }
        }
        
        // Generate a random 6-digit code
        let code = String( (0..<6).map { _ in "0123456789".randomElement()! } )
        // Send an email to the given address containing the code
        let postmarkResponse = try await Postmark.sendEmail(from: FROM_ADDRESS,
                                     to: userEmail,
                                     subject: "\(code) is your Circles verification code",
                                     html: "<html><body>Your verification code for Circles is: <b>\(code)</b>.</body></html>",
                                     text: "Your verification code for Circles is: \(code)",
                                     client: req.client,
                                     token: POSTMARK_TOKEN)
        
        if postmarkResponse.errorCode != 0 {
            // Sending the email through Postmark has failed
            throw Abort(.internalServerError)
        }
        
        // Save the code that we sent, so we can check it later
        let session = req.uia.connectSession(sessionId: auth.session)
        session.setData(for: authType+".token", value: code)
        if ENROLL_REQUEST_TOKEN == authType {
            // We're enrolling the user here, so this is a new email address for us
            // Save the address in the UIA session for now
            // If the user succeeds in enrolling, we'll save it into the DB in onEnrolled()
            session.setData(for: authType+".email", value: userEmail)
        }

        
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
        
        switch authType {
        case ENROLL_SUBMIT_TOKEN:
            guard let savedCode = session.getData(for: ENROLL_REQUEST_TOKEN+".token"),
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
            guard let savedCode = session.getData(for: LOGIN_REQUEST_TOKEN+".token"),
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
    
    func onEnrolled(req: Request, userId: String) async throws {
        // FIXME Save the user's email address in the database
        guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
            throw Abort(.badRequest)
        }
        
        let auth = uiaRequest.auth
        let session = req.uia.connectSession(sessionId: auth.session)
        
        if let userEmail = session.getData(for: ENROLL_REQUEST_TOKEN+".email") {
            let emailRecord = UserEmailAddress(userId: userId, email: userEmail)
            try await emailRecord.save(on: req.db)
        }
    }
    
    func isUserEnrolled(userId: String, authType: String) async throws -> Bool {
        // FIXME Lookup whether the user in the database
        if let _ = try await UserEmailAddress.query(on: app.db)
                                             .filter(\.$userId == userId)
                                             .first()
        {
            return true
        } else {
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
