//
//  TermsAuthChecker.swift
//  
//
//  Created by Charles Wright on 3/24/22.
//

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
    
    public struct Params: Content {
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
    }
    
    
    func getSupportedAuthTypes() -> [String] {
        [AUTH_TYPE_TERMS]
    }
    
    func getParams(req: Request, authType: String, userId: String?) async throws -> [String : AnyCodable]? {
        let privacyPolicy = Params.Policy(version: "1.0",
                                          en: .init(name: "Privacy Policy",
                                                    url: URL(string: "https://www.example.com/privacy/en/1.0.html")!
                                                   )
        )
        let params = Params(policies: ["privacy": privacyPolicy])
        return ["policies": AnyCodable(params.policies)] // FIXME this is horrible
    }
    
    func check(req: Request, authType: String) async throws -> Bool {
        guard let uiaRequest = try? req.content.decode(TermsUiaRequest.self),
              uiaRequest.auth.type == AUTH_TYPE_TERMS
        else {
            throw Abort(.badRequest)
        }
        
        // FIXME Also mark in the database that this user has accepted the terms
        //       Actually we can't do that right now -- We might not know the username
        //       But we can store this info in the UIA session, and then we can
        //       update the DB in the onLoggedIn / onEnrolled callback
        
        return true
    }
    
    func onLoggedIn(req: Request, userId: String) async throws {
        // FIXME Update the database with the fact that this user has accepted these terms
        // Use the AcceptedTerms model type for this
    }
    
    func onEnrolled(req: Request, userId: String) async throws {
        // FIXME Update the database with the fact that this user has accepted these terms
        // Use the AcceptedTerms model type for this
    }
    
    func isEnrolled(userId: String, authType: String) async -> Bool {
        return true
    }
    
    func onUnenrolled(req: Request, userId: String) async throws {
        // Can't unenroll from terms of service
        throw Abort(.badRequest)
    }
    
    
}
