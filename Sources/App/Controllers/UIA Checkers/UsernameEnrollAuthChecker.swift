//
//  UsernameEnrollAuthChecker.swift
//  
//
//  Created by Charles Wright on 10/5/22.
//

import Vapor
import Fluent

import AnyCodable

struct UsernameEnrollAuthChecker: AuthChecker {
    let AUTH_TYPE_ENROLL_USERNAME = "m.enroll.username"
    
    let app: Application
    var badWords: Set<String>
    
    init(app: Application) throws {

        
        self.app = app

        let results = try? BadWord.query(on: app.db).all().wait()
        
        if let badWordList = results {
            self.badWords = Set(badWordList.compactMap {
                guard let word = $0.id else {
                    return nil
                }
                return word.lowercased().replacingOccurrences(of: " ", with: "")
            })
        } else {
            self.badWords = []
        }
        app.logger.debug("UsernameEnrollAuthChecker: Loaded \(self.badWords.count) bad words")
    }
    
    func getSupportedAuthTypes() -> [String] {
        [AUTH_TYPE_ENROLL_USERNAME]
    }
    
    func getParams(req: Request, sessionId: String, authType: String, userId: String?) async throws -> [String : AnyCodable]? {
        [:]
    }
    
    
    private func checkForBadWords(req: Request, username: String) throws {
        // Is the username a known bad word?
        if badWords.contains(username) {
            req.logger.debug("Username is a known bad word")
            throw MatrixError(status: .forbidden, errcode: .invalidUsername, error: "Username is not available")
        }
        
        // Is the username a leetspeak version of a known bad word?
        let unl33t = username
            .replacingOccurrences(of: "0", with: "o")
            .replacingOccurrences(of: "1", with: "i")
            .replacingOccurrences(of: "2", with: "z")
            .replacingOccurrences(of: "3", with: "r")
            .replacingOccurrences(of: "4", with: "a")
            .replacingOccurrences(of: "5", with: "s")
            .replacingOccurrences(of: "6", with: "b")
            .replacingOccurrences(of: "7", with: "t")
            .replacingOccurrences(of: "8", with: "ate")
            .replacingOccurrences(of: "9", with: "g")
        if badWords.contains(unl33t) {
            req.logger.debug("Username is a bad word in leetspeak")
            throw MatrixError(status: .forbidden, errcode: .invalidUsername, error: "Username is not available")
        }
        
        // Did they use punctuation to hide a bad word?
        let usernameWithoutPunks = username
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        if badWords.contains(usernameWithoutPunks) {
            req.logger.debug("Username is a bad word with punctuation")
            throw MatrixError(status: .forbidden, errcode: .invalidUsername, error: "Username is not available")
        }
        
        // Did they use punctuation AND leetspeak?
        let unl33tWithoutPunks = unl33t
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        if badWords.contains(unl33tWithoutPunks) {
            req.logger.debug("Username is a bad word in leetspeak with punctuation")
            throw MatrixError(status: .forbidden, errcode: .invalidUsername, error: "Username is not available")
        }
        
        // Does the username contain a bad word as an obvious subcomponent?
        // e.g. cuss_insult_swear or cuss-insult-swear or cuss.insult.swear
        let dashTokens = username.split(separator: "-")
        let underscoreTokens = username.split(separator: "_")
        let dotTokens = username.split(separator: ".")
        for tokenList in [dashTokens, underscoreTokens, dotTokens] {
            for token in tokenList {
                if badWords.contains(String(token)) {
                    req.logger.debug("Username contains a known bad word")
                    throw MatrixError(status: .forbidden, errcode: .invalidUsername, error: "Username is not available")
                }
            }
        }
    }
    
    func check(req: Request, authType: String) async throws -> Bool {
        struct UsernameEnrollUiaRequest: Content {
            struct UsernameAuthDict: UiaAuthDict {
                var type: String
                var session: String
                var username: String
            }
            var auth: UsernameAuthDict
        }
        
        guard let usernameRequest = try? req.content.decode(UsernameEnrollUiaRequest.self) else {
            let msg = "Couldn't parse \(AUTH_TYPE_ENROLL_USERNAME) request"
            req.logger.error("\(msg)") // The need for this dance is moronic.  Thanks SwiftLog.
            throw MatrixError(status: .badRequest, errcode: .badJson, error: msg)
        }
        let sessionId = usernameRequest.auth.session
        let username = usernameRequest.auth.username.lowercased()
        
        // Now we run our sanity checks on the requested username
        
        // Is it too short, or too long?
        guard username.count > 0,
              username.count < 256
        else {
            let msg = "Username must be at least 1 character and no more than 255 characters"
            req.logger.debug("\(msg)")
            throw MatrixError(status: .forbidden, errcode: .invalidUsername, error: msg)
        }
        
        // Does it look like it's trying to be misleading or possibly impersonate another user?
        // e.g. _bob or bob_ or bob. or .bob
        guard let first = username.first,
              let last = username.last,
              first.isPunctuation == false,
              last.isPunctuation == false
        else {
            let msg = "Username may not start or end with punctuation"
            req.logger.debug("\(msg)")
            throw MatrixError(status: .forbidden, errcode: .invalidUsername, error: msg)
        }
        
        // Is the requested username a valid Matrix username according to the spec?
        // Dangit, the new Regex is only available in Swift 5.7+
        //let regex = try Regex("([A-z]|[a-z]|[0-9]|[-_\.])+")
        // Doing it the old fashioned way -- Thank you Paul Hudson https://www.hackingwithswift.com/articles/108/how-to-use-regular-expressions-in-swift
        let range = NSRange(location: 0, length: username.utf16.count)
        let regex = try! NSRegularExpression(pattern: "([A-z]|[a-z]|[0-9]|[-_\\.])+")
        if regex.rangeOfFirstMatch(in: username, range: range).length != range.length {
            let msg = "Username must consist of ONLY alphanumeric characters and dot, dash, and underscore"
            req.logger.debug("\(msg)")
            throw MatrixError(status: .badRequest, errcode: .invalidUsername, error: msg)
        }
        
        // Does the requested username contain any obvious bad words?
        if badWords.count > 0 {
            try checkForBadWords(req: req, username: username)
        }
        
        // Is the username already taken?
        let existingUsername = try await Username.find(username, on: req.db)
        if let record = existingUsername {
            if record.status == .pending {
                // cvw: FIXME: Let's loosen this up a bit
                // * Allow a user with the same subscription identifier or the same email address to pick up where they left off and complete registration with the same username
                if record.reason == sessionId {
                    // There is already a pending registration but it's us
                    req.logger.debug("User is already pending but it's for this UIA session so it's OK")
                    return true
                }
                // OK there is (was?) a pending registration for some other session.  Is it an old one or is it current?
                let now = Date()
                // Here "current" means within the past n minutes
                let timeoutMinutes = 10.0
                if record.created!.distance(to: now) < timeoutMinutes * 60.0 {
                    req.logger.debug("Username is already pending for someone else")
                    throw MatrixError(status: .forbidden, errcode: .invalidUsername, error: "Username is pending.  Try again in \(timeoutMinutes) minutes.")
                }
            } else {
                // Otherwise the existence of this non-pending record in the database shows that the username is unavailable
                req.logger.debug("Username has already been claimed")
                throw MatrixError(status: .forbidden, errcode: .invalidUsername, error: "Username is not available")
            }
        }
        
        let pending = Username(username, status: .pending, reason: sessionId)
        try await pending.save(on: req.db)
        
        let session = req.uia.connectSession(sessionId: sessionId)
        await session.setData(for: "username", value: username)
        
        return true
    }
    
    func onLoggedIn(req: Request, userId: String) async throws {
        // Do nothing -- Should never happen anyway
    }
    
    func onEnrolled(req: Request, authType: String, userId: String) async throws {
        // First extract the basic username from the fully-qualified Matrix user id
        let localpart = userId.split(separator: ":").first!
        let username = localpart.trimmingCharacters(in: .init(charactersIn: "@"))
        
        guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
            let msg = "Could not parse UIA request"
            req.logger.error("\(msg)")
            throw MatrixError(status: .badRequest, errcode: .badJson, error: msg)
        }
        let auth = uiaRequest.auth
        let sessionId = auth.session

        // Then save this username in the database in a currently-enrolled state
        // Doh, doing this naively results in a race condition
        //let record = Username(username, status: .enrolled)
        //try await record.save(on: req.db)
        // Doing this properly requires that we make sure it really was *this* UIA session that had reserved the username (and that the username is still pending, and hasn't been grabbed by someone else...  Like maybe our user started signing up and then walked away for an hour before completing the last steps.  That's not gonna cut it buddy; somebody else is free to take that username after 20 minutes.  So we need to check for that.
        try await Username.query(on: req.db)
                          .set(\.$status, to: .enrolled)
                          .filter(\.$id == username)
                          .filter(\.$status == .pending)
                          .filter(\.$reason == sessionId)
                          .update()
            
    }
    
    func isUserEnrolled(userId: String, authType: String) async throws -> Bool {
        // If you have a user id, then yes you have a username
        return true
    }
    
    func isRequired(for userId: String, making request: Request, authType: String) async throws -> Bool {
        // If you already have a user id, then you have no need to enroll for a new one
        return false
    }
    
    func onUnenrolled(req: Request, userId: String) async throws {
        // Do nothing
    }
    
    
}
