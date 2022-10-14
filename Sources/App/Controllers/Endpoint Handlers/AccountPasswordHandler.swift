//
//  AccountPasswordHandler.swift
//  
//
//  Created by Charles Wright on 9/16/22.
//

import Vapor
import Fluent

struct AccountPasswordHandler: EndpointHandler {
    var endpoints: [Endpoint] = [
        .init(.POST, "/account/password")
    ]
    
    func handle(req: Request) async throws -> Response {
        guard let user = req.auth.get(MatrixUser.self) else {
            throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "This endpoint requires authentication")
        }
        
        let userId = user.userId
        
        guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't parse UIA request")
        }
        let auth = uiaRequest.auth
        let session = req.uia.connectSession(sessionId: auth.session)
        
        guard let digest = await session.getData(for: PasswordAuthChecker.AUTH_TYPE_ENROLL+".digest") as? String else {
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Could not find a new password hash to save")
        }
        
        let completed = await session.getCompleted()
        guard completed.contains(PasswordAuthChecker.AUTH_TYPE_ENROLL) else {
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Password enroll stage was not completed")
        }
        
        req.logger.debug("Adding password hash [\(digest)] for user [\(userId)]")
        
        // Ok cool, if we got this far, then it looks like the client did enroll for a new password.
        // Unlike the legacy Matrix API, we don't really care what the actual request looks like here.  We don't do identity server stuff.  Instead, the UIA session is all that matters to us.
        // And at this point we're good, so return success.
        // (It's up to the UiaController to run the post-enrollment callbacks for us once this completes)
        let emptyDict = [String:String]()
        return try await emptyDict.encodeResponse(for: req)
    }
    
}
