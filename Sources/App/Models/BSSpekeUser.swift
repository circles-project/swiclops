//
//  BSSpekeUser.swift
//  
//
//  Created by Charles Wright on 4/11/22.
//

import Vapor
import Fluent

final class BSSpekeUser: Model {
    static var schema = "bsspeke_users"
    typealias PHF = BSSpekeAuthChecker.PhfParams
    
    @ID(custom: "user_id", generatedBy: .user)
    var id: String?

    @Field(key: "curve")
    var curve: String
  
    @Field(key: "p")
    var P: String
    
    @Field(key: "v")
    var V: String
    
    @Field(key: "phf")
    var phf: PHF
    
    init() {
    }
    
    init(id: String? = nil, curve: String?, P: String, V: String, phf: PHF) {
        self.id = id
        self.curve = curve ?? "curve25519"
        self.P = P
        self.V = V
        self.phf = phf
    }
}


