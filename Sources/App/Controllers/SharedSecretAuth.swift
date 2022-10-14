//
//  SharedSecretAuth.swift
//  
//
//  Created by Charles Wright on 9/20/22.
//

import Vapor
import Crypto

struct SharedSecretAuth {

    public static func token(secret: String, userId: String) throws -> String {
        let key = SymmetricKey(data: secret.data(using: .utf8)!)

        var hmac = HMAC<SHA512>(key: key)
        hmac.update(data: userId.data(using: .utf8)!)
        return Data(hmac.finalize()).hex
    }
    
    struct AuthDict: UiaAuthDict {
        var type = "com.devture.shared_secret_auth"
        var token: String
        var session: String
        var identifier: [String:String]
    }
}
