//
//  UIA.swift
//  
//
//  Created by Charles Wright on 3/24/22.
//

import Vapor
import AnyCodable

protocol UiaAuthDict: Content {
    var type: String { get }
    var session: String { get }
}

struct UiaRequest: Content {
    struct AuthDict: UiaAuthDict {
        var type: String
        var session: String
    }
    var auth: AuthDict
}

struct UiaFlow: Content {
    var stages: [String]
}

/*
struct UiaResponse: Content {
    var flows: [UiaFlow]
    
    var completed: [String]?
    
    var params: [String: [String: AnyCodable]]
    
    var session: String
}
*/

struct MatrixUiaResponse: MatrixResponse {
    var status: HTTPStatus
    var body: Body
    
    struct Body: Content {
        var flows: [UiaFlow]
        
        var completed: [String]?
        
        var params: [String: [String: AnyCodable]]
        
        var session: String
    }
    
    func encodeResponse(for request: Request) async throws -> Response {
        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(body)
        return Response(status: status, body: .init(data: bodyData))
    }
}
