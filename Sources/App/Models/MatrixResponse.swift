//
//  MatrixResponse.swift
//  
//
//  Created by Charles Wright on 3/29/22.
//

import Vapor


protocol MatrixResponse: AsyncResponseEncodable {
    var status: HTTPStatus { get }
    
    func encodeResponse(for request: Request) async throws -> Response
}

struct MatrixErrorResponse: MatrixResponse {
    var status: HTTPStatus
    var body: Body
    
    struct Body: Content {
        var errcode: ErrorCode
        var error: String
        
        init(errcode: ErrorCode, error: String) {
            self.errcode = errcode
            self.error = error
        }
    }
    
    enum ErrorCode: String, Codable {
        case forbidden = "M_FORBIDDEN"
        case unknownToken = "M_UNKNOWN_TOKEN"
        case missingToken = "M_MISSING_TOKEN"
        case badJson = "M_BAD_JSON"
        case notJson = "M_NOT_JSON"
        case notFound = "M_NOT_FOUND"
        case limitExceeded = "M_LIMIT_EXCEEDED"
        case unknown = "M_UNKNOWN"
    }
    
    init(status: HTTPStatus, errorcode: ErrorCode, error: String) {
        self.status = status
        self.body = Body(errcode: errorcode, error: error)
    }
    
    func encodeResponse(for request: Request) async throws -> Response {
        let encoder = JSONEncoder()
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        let bodyData = try encoder.encode(body)
        return Response(status: status, headers: headers, body: .init(data: bodyData))
    }
    
}

struct MatrixOkResponse: MatrixResponse {
    let status: HTTPStatus = .ok
    
    func encodeResponse(for request: Request) async throws -> Response {
        let encoder = JSONEncoder()
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        let body: [String:String] = [:]
        let bodyData = try encoder.encode(body)
        return Response(status: status, headers: headers, body: .init(data: bodyData))
    }
}
