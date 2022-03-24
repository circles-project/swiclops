//
//  PasswordLoginUiaRequest.swift
//  
//
//  Created by Charles Wright on 3/22/22.
//

import Vapor


struct PasswordLoginAuthDict: UiaAuthDict {
    var type: String
    var session: String

    // FIXME This should actually be flexible to handle different things
    //       See https://spec.matrix.org/v1.2/client-server-api/#identifier-types
    struct mIdUser: Content {
        var type: String
        var user: String
    }
    
    var identifier: mIdUser
    var password: String
}

struct PasswordLoginUiaRequest: Content {
    var auth: PasswordLoginAuthDict
}

struct PasswordEnrollAuthDict: UiaAuthDict {
    var type: String
    var session: String
    
    var newPassword: String
}

struct PasswordEnrollUiaRequest: Content {
    var auth: PasswordEnrollAuthDict
}
