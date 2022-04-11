//
//  Request+MatrixUIA.swift
//  
//
//  Created by Charles Wright on 3/24/22.
//

import Vapor
import AnyCodable

extension Request {
    
    struct MatrixUIAKey: StorageKey {
        typealias Value = MatrixUIA
    }
    
    var uia: MatrixUIA {
        get {
            if !self.storage.contains(MatrixUIAKey.self) {
                self.storage[MatrixUIAKey.self] = MatrixUIA(req: self)
            }
            return self.storage[MatrixUIAKey.self]!
        }
        set(newValue) {
            self.storage[MatrixUIAKey.self] = newValue
        }
    }
    
    struct MatrixUIA {
        private var req: Request
        
        init(req: Request) {
            self.req = req
            self.session = nil
        }
        
        public func connectSession(sessionId: String) -> Session {
            if let existingSession = self.session {
                return existingSession
            }
            //self.session = .init(req: self.req, sessionId: sessionId)
            let newSession = Session(req: self.req, sessionId: sessionId)
            self.req.storage[Key.self] = newSession
            return newSession
        }
        
        struct Key: StorageKey {
            typealias Value = MatrixUIA.Session
        }
        
        var session: Session? {
            get {
                self.req.storage[Key.self]
            }
            set(newValue) {
                self.req.storage[Key.self] = newValue
            }
        }
        
        struct Session {
            private var req: Request
            private var sessionId: String
            
            init(req: Request, sessionId: String) {
                self.req = req
                self.sessionId = sessionId
            }
            
            public func getData(for key: String) async -> Any? {
                let app = self.req.application
                guard let sessionData = await app.uia.sessions.get(self.sessionId) else {
                    return nil
                }
                return sessionData[key]
            }
            
            public func setData(for key: String, value: Any) async {
                let app = self.req.application
                if let _ = await app.uia.sessions.get(self.sessionId) {
                    // Do nothing
                } else {
                    await app.uia.sessions.set(self.sessionId, UiaSessionData())
                }
                var s = await app.uia.sessions.get(self.sessionId)!
                s[key] = value
                
            }
            
            public func markStageComplete(stage: String) async {
                let app = self.req.application
                if let _ = await app.uia.sessions.get(self.sessionId) {
                    // Do nothing
                } else {
                    await app.uia.sessions.set(self.sessionId, UiaSessionData())
                }
                var s = await app.uia.sessions.get(self.sessionId)!
                s.completed.append(stage)
            }
            
            public func getCompleted() async -> [String] {
                let app = self.req.application
                return await app.uia.sessions.get(self.sessionId)?.completed ?? []
            }
        }
    }
}
