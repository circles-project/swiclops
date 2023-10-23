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



// FIXME Now we need a new MatrixErrorMiddleware to convert these thrown errors into valid Matrix HTTP responses
struct MatrixError: AbortError {

    enum ErrorCode: String, Codable {
        // See https://spec.matrix.org/v1.2/client-server-api/#standard-error-response
        case forbidden = "M_FORBIDDEN"
        case unknownToken = "M_UNKNOWN_TOKEN"
        case missingToken = "M_MISSING_TOKEN"
        case badJson = "M_BAD_JSON"
        case notJson = "M_NOT_JSON"
        case notFound = "M_NOT_FOUND"
        case limitExceeded = "M_LIMIT_EXCEEDED"
        case unknown = "M_UNKNOWN"
        case unrecognized = "M_UNRECOGNIZED"
        case unauthorized = "M_UNAUTHORIZED"
        case userDeactivated = "M_USER_DEACTIVATED"
        case userInUse = "M_USER_IN_USE"
        case invalidUsername = "M_INVALID_USERNAME"
        case roomInUse = "M_ROOM_IN_USE"
        case invalidRoomState = "M_INVALID_ROOM_STATE"
        case threepidInUse = "M_THREEPID_IN_USE"
        case threepidNotFound = "M_THREEPID_NOT_FOUND"
        case threepidAuthFailed = "M_THREEPID_AUTH_FAILED"
        case threepidDenied = "M_THREEPID_DENIED"
        case serverNotTrusted = "M_SERVER_NOT_TRUSTED"
        case unsupportedRoomVersion = "M_UNSUPPORTED_ROOM_VERSION"
        case incompatibleRoomVersion = "M_INCOMPATIBLE_ROOM_VERSION"
        case badState = "M_BAD_STATE"
        case guestAccessForbidden = "M_GUEST_ACCESS_FORBIDDEN"
        case captchaNeeded = "M_CAPTCHA_NEEDED"
        case captchaInvalid = "M_CAPTCHA_INVALID"
        case missingParam = "M_MISSING_PARAM"
        case invalidParam = "M_INVALID_PARAM"
        case tooLarge = "M_TOO_LARGE"
        case exclusive = "M_EXCLUSIVE"
        case resourceLimitExceeded = "M_RESOURCE_LIMIT_EXCEEDED"
        case cannotLeaveServerNoticeRoom = "M_CANNOT_LEAVE_SERVER_NOTICE_ROOM"
        case expiredAccount = "ORG_MATRIX_EXPIRED_ACCOUNT" // https://matrix-org.github.io/synapse/latest/modules/account_validity_callbacks.html
    }
    
    struct Body: Content {
        var errcode: ErrorCode
        var error: String
    }
    
    var status: HTTPResponseStatus
    var body: Body
    
    init(status: HTTPStatus, errcode: ErrorCode, error: String) {
        self.status = status
        self.body = Body(errcode: errcode, error: error)
    }
    
    func basicEncodeResponse(for request: Request) -> Response {
        let encoder = JSONEncoder()
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        let bodyData = try! encoder.encode(body)
        let response = Response(status: status, headers: headers, body: .init(data: bodyData))
        return response
    }
    
    func encodeResponse(for request: Request) async throws -> Response {
        let response = basicEncodeResponse(for: request)
        return response
    }
    
    func encodeResponse(for request: Request) -> EventLoopFuture<Response> {
        let response = basicEncodeResponse(for: request)
        return request.eventLoop.makeSucceededFuture(response)
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
