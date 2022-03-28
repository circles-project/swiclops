//
//  TermsAuthChecker.swift
//  
//
//  Created by Charles Wright on 3/24/22.
//

import Fluent
import Vapor
import AnyCodable

public struct TermsUiaAuthDict: UiaAuthDict {
    var type: String
    var session: String
}

public struct TermsUiaRequest: Content {
    var auth: TermsUiaAuthDict
}


struct TermsAuthChecker: AuthChecker {
    let AUTH_TYPE_TERMS = "m.login.terms"
    
    struct Policy: Codable {
        struct LocalizedPolicy: Codable {
            var name: String
            var url: URL
        }
        
        var version: String
        // FIXME this is the awfulest f**king kludge I think I've ever written
        // But the Matrix JSON struct here is pretty insane
        // Rather than make a proper dictionary, they throw the version in the
        // same object with the other keys of what should be a natural dict.
        // Parsing this properly is going to be something of a shitshow.
        // But for now, we do it the quick & dirty way...
        var en: LocalizedPolicy?
    }
    
    var policies: [String:Policy]
    var app: Application
    
    init(application: Application) {
        let privacy = Policy(version: "1.0",
                             en: .init(name: "Privacy Policy",
                                       url: URL(string: "https://www.example.com/privacy/en/1.0.html")!
                                       )
                             )
        self.policies = [ "privacy": privacy ]
        self.app = application
    }
    
    func getSupportedAuthTypes() -> [String] {
        [AUTH_TYPE_TERMS]
    }
    
    func getParams(req: Request, authType: String, userId: String?) async throws -> [String : AnyCodable]? {
        return ["policies": AnyCodable(self.policies)]
    }
    
    func check(req: Request, authType: String) async throws -> Bool {
        guard let uiaRequest = try? req.content.decode(TermsUiaRequest.self),
              uiaRequest.auth.type == AUTH_TYPE_TERMS
        else {
            throw Abort(.badRequest)
        }
        
        return true
    }
    
    func _updateDatabase(for req: Request, userId: String) async throws {
        guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
            throw Abort(.badRequest)
        }
        //let sessionId = uiaRequest.auth.session
        //let session = req.uia.connectSession(sessionId: sessionId)
        
        var dbRecords: [AcceptedTerms] = []
        for (name,policy) in self.policies {
            let version = policy.version
            dbRecords.append(AcceptedTerms(policy: name, userId: userId, version: version))
        }
        try await dbRecords.create(on: req.db)

    }
    
    func onLoggedIn(req: Request, userId: String) async throws {
        // Update the database with the fact that this user has accepted these terms
        // Use the AcceptedTerms model type for this
        try await self._updateDatabase(for: req, userId: userId)
    }
    
    func onEnrolled(req: Request, userId: String) async throws {
        // Update the database with the fact that this user has accepted these terms
        // Use the AcceptedTerms model type for this
        try await self._updateDatabase(for: req, userId: userId)
    }
    
    func isUserEnrolled(userId: String, authType: String) async -> Bool {
        return true
    }
    
    func isRequired(for userId: String, making request: Request, authType: String) async throws -> Bool {
        // Terms auth is one of the few that may not always be required
        // Query the database to see whether the user has already accepted the current terms
        
        for (name,policy) in self.policies {
            let version = policy.version
                        
            let alreadyAccepted = try await AcceptedTerms.query(on: request.db)
                                   .filter(\.$userId == userId)
                                   .filter(\.$policy == name)
                                   .filter(\.$version >= version)
                                   .first()

            
            guard alreadyAccepted != nil else {
                // User is required to accept current terms
                return true
            }
        }

        // User is currently up-to-date and doesn't need to accept anything new
        return false
    }
    
    func onUnenrolled(req: Request, userId: String) async throws {
        // Can't unenroll from terms of service
        throw Abort(.badRequest)
    }
    
    
}
