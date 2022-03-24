//
//  Application+MatrixUIA.swift
//  
//
//  Created by Charles Wright on 3/23/22.
//

import Vapor

extension Application {
    
    struct MatrixUIAKey: StorageKey {
        typealias Value = MatrixUIA
    }
    
    public var uia: MatrixUIA {
        get {
            if !self.storage.contains(MatrixUIAKey.self) {
                self.storage[MatrixUIAKey.self] = MatrixUIA(app: self)
            }
            return self.storage[MatrixUIAKey.self]!
        }
        set(newValue) {
            self.storage[MatrixUIAKey.self] = newValue
        }
    }
    
    public struct MatrixUIA {
        public typealias UiaSessionStore = ConcurrentDictionary<String,UiaSessionData>
        let app: Application
        
        var sessions: UiaSessionStore
        
        init(app: Application) {
            self.app = app
            self.sessions = UiaSessionStore(n: 32)
        }
        
        /*
         // cvw: I really don't understand WTF this stuff is doing.  Just store the sessions in the object itself!
         
        // This is so we can store stuff in the application's storage
        // We define our own key here, so you have to have access to this declaration
        // in order to access our stuff.
        struct SessionsKey: StorageKey {
            typealias Value = UiaSessionStore
        }
        
        public var sessions: UiaSessionStore {
            // Our stuff should be stored in the application
            // If not, we have a problem
            guard let sessions = self.application.storage[SessionsKey.self] else {
                fatalError("Matrix UIA not configured. Configure with app.uia.initialize()")
            }
            return sessions
        }
        
        func initialize() {
            self.application.storage[SessionsKey.self] = .init(n: 32)
        }
        */
    }
}
