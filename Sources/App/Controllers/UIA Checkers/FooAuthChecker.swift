//
//  FooAuthChecker.swift
//  
//
//  Created by Charles Wright on 4/4/22.
//

import Vapor
import Fluent
import AnyCodable

struct FooAuthChecker: AuthChecker {
    let AUTH_TYPE_FOO = "m.login.foo"
    
    struct FooUiaRequest: Content {
        struct AuthDict: UiaAuthDict {
            var session: String
            var type: String
            var foo: String
        }
        var auth: AuthDict
    }
    
    func getSupportedAuthTypes() -> [String] {
        [AUTH_TYPE_FOO]
    }
    
    func getParams(req: Request, sessionId: String, authType: String, userId: String?) async throws -> [String : AnyCodable]? {
        req.logger.debug("Foo: Getting params")
        let number = Int.random(in: 0 ..< (1<<16))
        let foo = "\(number)"
        
        // FIXME Save foo in the UIA session
        let session = req.uia.connectSession(sessionId: sessionId)
        session.setData(for: AUTH_TYPE_FOO+".foo", value: foo)
        
        req.logger.debug("Foo: Saved foo = \(foo)")

        return ["foo": AnyCodable(foo)]
    }
    
    func check(req: Request, authType: String) async throws -> Bool {
        guard let fooUiaRequest = try? req.content.decode(FooUiaRequest.self) else {
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't decode request for \(AUTH_TYPE_FOO)")
        }
        let auth = fooUiaRequest.auth
        let sessionId = auth.session
        let session = req.uia.connectSession(sessionId: sessionId)
        let savedFoo = session.getData(for: AUTH_TYPE_FOO+".foo")
        let newFoo = auth.foo
        guard newFoo == savedFoo else {
            throw MatrixError(status: .forbidden, errcode: .forbidden, error: "Access denied: foo does not match")
        }
        return true
    }
    
    func onLoggedIn(req: Request, userId: String) async throws {
        // Do nothing
    }
    
    func onEnrolled(req: Request, userId: String) async throws {
        // Do nothing
    }
    
    func isUserEnrolled(userId: String, authType: String) async throws -> Bool {
        // Everyone is always enrolled for foo
        return true
    }
    
    func isRequired(for userId: String, making request: Request, authType: String) async throws -> Bool {
        // There is no escaping the foo
        return true
    }
    
    func onUnenrolled(req: Request, userId: String) async throws {
        // Do nothing
    }
    
    
}
