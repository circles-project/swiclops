//
//  BsspekeUser.swift
//  
//
//  Created by Charles Wright on 4/11/22.
//

import Vapor
import Fluent

final class BsspekeUser: Model {
    
    static var schema = "bsspeke_users"
    
    @ID(custom: "user_id", generatedBy: .user)
    var id: String?
    
    @Field(key: "curve")
    var curve: String
    
    @Field(key: "v")
    var V: String
    
    @Field(key: "p")
    var P: String
    
    final class PhfParams: Fields {
        @Field(key: "name")
        var name: String
        
        @Field(key: "iterations")
        var iterations: UInt
        
        @Field(key: "blocks")
        var blocks: UInt
    }
    
    @Field(key: "phf_params")
    var phfParams: PhfParams
}
