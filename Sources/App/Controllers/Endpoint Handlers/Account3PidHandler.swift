//
//  Account3PidHandler.swift
//  
//
//  Created by Charles Wright on 9/16/22.
//

import Vapor
import Fluent

struct Account3PidHandler: EndpointHandler {
    var endpoints: [Endpoint] = [
        .init(.GET, "/account/3pid"),
        .init(.POST, "/account/3pid/add"),
        .init(.POST, "/account/3pid/delete"),
    ]
    
    func handle(req: Request) async throws -> Response {
        guard let command = req.url.path.pathComponents.last?.description else {
            throw MatrixError(status: .badRequest, errcode: .unrecognized, error: "Invalid request")
        }
        switch (req.method, command) {
        case (.GET, "3pid"):
            return try await handleGet(req: req)
        case (.POST, "add"):
            return try await handleAdd(req: req)
        case (.POST, "delete"):
            return try await handleDelete(req: req)
        default:
            throw MatrixError(status: .badRequest, errcode: .unrecognized, error: "Invalid request")
        }
    }
    
    func handleGet(req: Request) async throws -> Response {
        guard let user = req.auth.get(MatrixUser.self) else {
            throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "This endpoint requires authentication")
        }
                
        let records = try await UserEmailAddress.query(on: req.db)
                                                .filter(\.$userId == user.userId)
                                                .all()
        
        struct GetResponseBody: Content {
            struct Threepid: Codable {
                var addedAt: UInt
                var address: String
                var medium: String
                var validatedAt: UInt
            }
            var threepids: [Threepid]
            
            init(_ emailRecords: [UserEmailAddress]) {
                self.threepids = emailRecords.map { rec in
                    Threepid(addedAt: UInt(rec.lastUpdated!.timeIntervalSince1970),
                             address: rec.email,
                             medium: "email",
                             validatedAt: UInt(rec.lastUpdated!.timeIntervalSince1970))
                }
            }
        }
        
        let responseBody = GetResponseBody(records)
        return try await responseBody.encodeResponse(for: req)
    }
    
    func handleAdd(req: Request) async throws -> Response {
        guard let user = req.auth.get(MatrixUser.self) else {
            throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "This endpoint requires authentication")
        }
        
        let userId = user.userId
        
        guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't parse UIA request")
        }
        let auth = uiaRequest.auth
        let session = req.uia.connectSession(sessionId: auth.session)
        
        guard let validatedEmailAddress = await session.getData(for: EmailAuthChecker.ENROLL_REQUEST_TOKEN+".email") as? String else {
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Could not find an email address")
        }
        
        let completed = await session.getCompleted()
        guard completed.contains(EmailAuthChecker.ENROLL_SUBMIT_TOKEN) else {
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Email address was never validated")
        }
        
        req.logger.debug("Adding 3pid [\(validatedEmailAddress)] for user [\(userId)]")
        
        // Ok cool, if we got this far, then it looks like the client did enroll for a 3pid.
        // Unlike the legacy Matrix API, we don't really care what the actual request looks like here.  We don't do identity server stuff.  Instead, the UIA session is all that matters to us.
        // And at this point we're good, so return success.
        // (It's up to the UiaController to run the post-enrollment callbacks for us once this completes)
        let emptyDict = [String:String]()
        return try await emptyDict.encodeResponse(for: req)
    }
    
    // https://spec.matrix.org/v1.3/client-server-api/#post_matrixclientv3account3piddelete
    func handleDelete(req: Request) async throws -> Response {
        guard let user = req.auth.get(MatrixUser.self) else {
            throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "This endpoint requires authentication")
        }
        
        let userId = user.userId
        
        struct DeleteRequestBody: Content {
            var address: String
            var medium: String
        }
        guard let requestBody = try? req.content.decode(DeleteRequestBody.self) else {
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Could not parse request")
        }
        
        guard requestBody.medium == "email" else {
            throw MatrixError(status: .badRequest, errcode: .invalidParam, error: "Only email 3pids are supported at this time")
        }

        try await UserEmailAddress.query(on: req.db)
            .filter(\.$userId == userId)
            .filter(\.$email == requestBody.address)
            .delete()
        
        // This is weird, but it's the spec...  We don't do identity servers, so our response is always "no support" because we have nothing to unbind from.
        var responseBody = ["id_server_unbind_result": "no-support"]
        
        return try await responseBody.encodeResponse(for: req)
    }
    
}
