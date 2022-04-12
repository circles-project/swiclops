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
    
    @ID(key: "uuid")
    var id: UUID?
    
    @Field(key: "user_id")
    var userId: String?
    
    @Field(key: "curve")
    var curve: String
  
    @Field(key: "p")
    var P: String
    
    @Field(key: "v")
    var V: String

    /*
    final class PHF: Fields {
        @Field(key: "name")
        var name: String
        
        @Field(key: "iterations")
        var iterations: UInt
        
        @Field(key: "blocks")
        var blocks: UInt
        
        init() {
            self.name = "argon2i"
            self.blocks = 100000
            self.iterations = 3
        }
        
        init(name: String, blocks: UInt, iterations: UInt) {
            self.name = name
            self.blocks = blocks
            self.iterations = iterations
        }
    }
    */
    
    @Field(key: "phf")
    var phf: PHF
    
    init() {
    }
    
    init(id: UUID? = nil, userId: String, curve: String?, P: String, V: String, phf: PHF) {
        self.id = id
        self.userId = userId
        self.curve = curve ?? "curve25519"
        self.P = P
        self.V = V
        self.phf = phf
    }
}

