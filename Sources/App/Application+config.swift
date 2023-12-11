//
//  Application+config.swift
//
//
//  Created by Charles Wright on 10/23/23.
//

import Vapor

struct ApplicationConfigKey: StorageKey {
    typealias Value = AppConfig
}

extension Application {
    var config: AppConfig? {
        get {
            self.storage[ApplicationConfigKey.self]
        }
        set {
            self.storage[ApplicationConfigKey.self] = newValue
        }
    }
}
