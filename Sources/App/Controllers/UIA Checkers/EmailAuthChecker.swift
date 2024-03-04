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
    
    static let ENROLL_REQUEST_TOKEN = "m.enroll.email.request_token"
    static let ENROLL_SUBMIT_TOKEN = "m.enroll.email.submit_token"
    static let LOGIN_REQUEST_TOKEN = "m.login.email.request_token"
    static let LOGIN_SUBMIT_TOKEN = "m.login.email.submit_token"
    
    let FROM_ADDRESS = "circles-noreply@futo.org"
    
    let config: EmailConfig
    
    let app: Application
    
    struct RequestTokenUiaRequest: Content {
        struct AuthDict: UiaAuthDict {
            var type: String
            var session: String
            var email: String
            var subscribeToList: Bool?
            
            enum CodingKeys: String, CodingKey {
                case type
                case session
                case email
                case subscribeToList = "subscribe_to_list"
            }
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
        self.config = config
    }
    
    
    func getSupportedAuthTypes() -> [String] {
        [
            EmailAuthChecker.ENROLL_REQUEST_TOKEN,
            EmailAuthChecker.ENROLL_SUBMIT_TOKEN,
            EmailAuthChecker.LOGIN_REQUEST_TOKEN,
            EmailAuthChecker.LOGIN_SUBMIT_TOKEN
        ]
    }

    private func censorString(_ string: String) -> String? {
        if string.count < 1 {
            return nil
        } else if string.count == 1 {
            return "*"
        } else if string.count == 2 {
            return "**"
        } else if let first = string.first, 
                  let last = string.last
        {
            let stars = Array(repeating: Character("*"), count: string.count-2)
            return "\(first)\(stars)\(last)"
        } else {
            // wtf?
            return nil
        }
    }

    private func censorEmailAddress(_ email: String) -> String? {
        let toks = email.split(separator: "@")
        guard toks.count == 2,
            let userPart = toks.first,
            let domainPart = toks.last
        else { return nil }

        guard let censoredUserPart = censorString(String(userPart))
        else { return nil }

        let subdomains = domainPart.split(separator: ".")
        guard subdomains.count > 1
        else { return nil }

        guard let tld = subdomains.last
        else { return nil }

        let domainString = subdomains.dropLast(1).joined(separator: ".")
        guard let censoredDomainString = censorString(domainString)
        else { return nil }

        return censoredUserPart + "@" + censoredDomainString + "." + String(tld)
    }
    
    func getParams(req: Request,
                   sessionId: String,
                   authType: String,
                   userId maybeUserId: String?
    ) async throws -> [String : AnyCodable]? {

        switch authType {
        case EmailAuthChecker.LOGIN_REQUEST_TOKEN:
            // The user is already registered, so we know what their valid email address(es) are
            // If they have more than one address, they need to tell us which one to use
            
            guard let userId = maybeUserId else {
                // If we're trying to log in, we'd better know who the user is
                req.logger.warning("Can't get email login params without a user id")
                return ["addresses": [:]]
            }
            
            let emailAddressRecords = try await UserEmailAddress
                                                    .query(on: req.db)
                                                    .filter(\.$userId == userId)
                                                    .all()
            //let emailAddresses = emailAddressRecords.compactMap { censorEmailAddress($0.email) }
            let emailAddresses = emailAddressRecords.compactMap { $0.email }
            
            return ["addresses": AnyCodable(emailAddresses)]
            
        case EmailAuthChecker.ENROLL_REQUEST_TOKEN:
            if let _ = app.config?.uia.email.mailchimp {
                // We have a mailing list.  Offer it to the user.
                return ["offer_list_subscription": true]
            } else {
                return nil
            }

        default:
            return nil
        }
    }
    
    func _handleRequestToken(req: Request, authType: String) async throws -> Bool {
        guard let uiaRequest = try? req.content.decode(RequestTokenUiaRequest.self)
        else {
            req.logger.error("Email UIA: Failed to parse UIA request")
            throw Abort(.badRequest)
        }
        
        let auth = uiaRequest.auth
        let userEmail = auth.email
        
        req.logger.debug("User requesting a token for email [\(userEmail)]")

        if authType == EmailAuthChecker.LOGIN_REQUEST_TOKEN {
            // Ok we're trying to log in some user.  Who is it?
            let session = req.uia.connectSession(sessionId: auth.session)
            guard let userId = await session.getData(for: "user_id") as? String else {
                // The top-level handler should have set the user id if we have one
                req.logger.error("Email UIA: Failed to get user id")
                throw Abort(.internalServerError)
            }
            
            // Verify that the user is enrolled already with the given address
            guard let _ = try await UserEmailAddress.query(on: req.db)
                                           .filter(\.$email == userEmail)
                                           .filter(\.$userId == userId)
                                           .first()
            else {
                // User is not enrolled with this address
                req.logger.error("Email UIA: User \(userId) is not enrolled with email address \(userEmail)")
                throw Abort(.badRequest)
            }
        } else {
            guard authType == EmailAuthChecker.ENROLL_REQUEST_TOKEN else {
                throw MatrixError(status: .badRequest, errcode: .invalidParam, error: "Bad auth type [\(authType)]")
            }
        }
        
        // Generate a random 6-digit code
        let code = String( (0..<6).map { _ in "0123456789".randomElement()! } )
        // Send an email to the given address containing the code
        let postmarkResponse = try await Postmark.sendEmail(
                                     from: FROM_ADDRESS,
                                     to: userEmail,
                                     subject: "\(code) is your Circles verification code",
                                     html: "<html><body>Your verification code for Circles is: <b>\(code)</b>.</body></html>",
                                     text: "Your verification code for Circles is: \(code)",
                                     for: req,
                                     token: config.postmark.token)
        
        if postmarkResponse.errorCode != 0 {
            // Sending the email through Postmark has failed
            req.logger.warning("Postmark returned error code \(postmarkResponse.errorCode)")
            throw Abort(.internalServerError)
        }
        req.logger.debug("Postmark email was successful")
        
        // Save the code that we sent, so we can check it later
        let session = req.uia.connectSession(sessionId: auth.session)
        await session.setData(for: authType+".token", value: code)
        if EmailAuthChecker.ENROLL_REQUEST_TOKEN == authType {
            // We're enrolling the user here, so this is a new email address for us
            // Save the address in the UIA session for now
            // If the user succeeds in enrolling, we'll save it into the DB in onEnrolled()
            await session.setData(for: authType+".email", value: userEmail)
        }
        
        // Remember whether the user wants to be subscribed to our mailing list
        let subscribeUserToList = auth.subscribeToList ?? false
        await session.setData(for: authType+".subscribe", value: subscribeUserToList)

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
        case EmailAuthChecker.ENROLL_SUBMIT_TOKEN:
            guard let savedCode = await session.getData(for: EmailAuthChecker.ENROLL_REQUEST_TOKEN+".token") as? String,
                  savedCode == code
            else {
                // Hmmm either
                //   1) We don't seem to have saved a token/code for this session
                // Or
                //   2) We have a token, but it doesn't match what the user provided
                // Do not pass Go, Do not collect $200
                throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "No matching token")
            }
            // Now that the user has validated their ownership of this email address,
            // we need to save it in the UIA session for use in onEnrolled()
            guard let email = await session.getData(for: EmailAuthChecker.ENROLL_REQUEST_TOKEN+".email") as? String
            else {
                throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Could not find email address for the given token")
            }
            await session.setData(for: EmailAuthChecker.ENROLL_SUBMIT_TOKEN+".email", value: email)
        case EmailAuthChecker.LOGIN_SUBMIT_TOKEN:
            guard let savedCode = await session.getData(for: EmailAuthChecker.LOGIN_REQUEST_TOKEN+".token") as? String,
                  savedCode == code
            else {
                // Hmmm either
                //   1) We don't seem to have saved a token/code for this session
                // Or
                //   2) We have a token, but it doesn't match what the user provided
                // Do not pass Go, Do not collect $200
                throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "No matching token")
            }
        default:
            // Should never be here
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Invalid auth stage for submit_token")
        }
        
        // If we made it this far, then we found a matching token
        // Allow the user to progress to the next stage in the flow
        return true
    }
    
    func check(req: Request, authType: String) async throws -> Bool {
        switch authType {
        case EmailAuthChecker.ENROLL_REQUEST_TOKEN:
            return try await _handleRequestToken(req: req, authType: authType)
        case EmailAuthChecker.ENROLL_SUBMIT_TOKEN:
            return try await _handleSubmitToken(req: req, authType: authType)
        case EmailAuthChecker.LOGIN_REQUEST_TOKEN:
            return try await _handleRequestToken(req: req, authType: authType)
        case EmailAuthChecker.LOGIN_SUBMIT_TOKEN:
            return try await _handleSubmitToken(req: req, authType: authType)
        default:
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Auth type [\(authType)] is not supported by the email auth checker")
        }
    }
    
    func onLoggedIn(req: Request, authType: String, userId: String) async throws {
        // Do nothing
    }
    
    func onEnrolled(req: Request, authType: String, userId: String) async throws {
        guard authType == EmailAuthChecker.ENROLL_SUBMIT_TOKEN else {
            req.logger.debug("m.enroll.email: onEnroll() but authType is not \(EmailAuthChecker.ENROLL_SUBMIT_TOKEN) -- doing nothing")
            return
        }
        req.logger.debug("m.enroll.email: onEnroll()")
        
        // FIXME Save the user's email address in the database
        guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't parse UIA request")
        }
        
        let auth = uiaRequest.auth
        let session = req.uia.connectSession(sessionId: auth.session)
        
        // Did the user enroll a new email with us?
        if let userEmail = await session.getData(for: EmailAuthChecker.ENROLL_SUBMIT_TOKEN+".email") as? String {
            // If so, save their email to the database
            req.logger.debug("m.enroll.email: Finalizing enrollment for user [\(userId)] with email [\(userEmail)]")
            let emailRecord = UserEmailAddress(userId: userId, email: userEmail)
            try await emailRecord.save(on: req.db)
            req.logger.debug("m.enroll.email: User email saved to the database")
            
            // Did the user want to be subscribed to our mailing list?
            if let subscribeUserToList = await session.getData(for: EmailAuthChecker.ENROLL_REQUEST_TOKEN+".subscribe") as? Bool,
               subscribeUserToList == true,
               let mailchimp = config.mailchimp
            {
                req.logger.debug("m.enroll.email: Subscribing user to our mailing list")
                try await Mailchimp.subscribe(email: userEmail, to: mailchimp.listId, for: req, server: mailchimp.server, apiKey: mailchimp.apiKey)
            }
        } else {
            let msg = "m.enroll.email: Couldn't enroll user \(userId) because there is no email address in the session"
            req.logger.error("\(msg)")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: msg)
        }
    }
    
    func isUserEnrolled(userId: String, authType: String) async throws -> Bool {
        switch authType {
            
        case EmailAuthChecker.ENROLL_REQUEST_TOKEN, EmailAuthChecker.ENROLL_SUBMIT_TOKEN:
            // Everyone is always eligible to do an enrollment
            return true
            
        case EmailAuthChecker.LOGIN_REQUEST_TOKEN, EmailAuthChecker.LOGIN_SUBMIT_TOKEN:
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
        // Remove the entry from the database
        try await UserEmailAddress.query(on: req.db)
            .filter(\.$userId == userId)
            .delete()
    }
    
    
}
