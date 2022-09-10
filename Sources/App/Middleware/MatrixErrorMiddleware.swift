//
//  MatrixErrorMiddleware.swift
//  * Based on Vapor's ErrorMiddleware
//
//  Created by Charles Wright on 3/30/22.
//

import Vapor

public final class MatrixErrorMiddleware: Middleware {
    // Look at https://github.com/vapor/vapor/blob/main/Sources/Vapor/Middleware/ErrorMiddleware.swift for reference
    
    public func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
        return next.respond(to: request).flatMapErrorThrowing { error in
            //request.logger.debug("Middleware says Hi")

            switch error {
                                
            case let matrixError as MatrixError:
                request.logger.debug("Middleware caught a MatrixError")
                return matrixError.basicEncodeResponse(for: request)
                
            case let incomplete as UiaIncomplete:
                request.logger.debug("Middleware got a UIA incomplete error")
                return incomplete.encodeResponse(for: request)
                
            case let abort as AbortError:
                request.logger.debug("Middleware got a Vapor AbortError")
                // Copied from Vapor's ErrorMiddleware.swift
                // this is an abort error, we should use its status, reason, and headers
                let reason = abort.reason
                let status = abort.status
                let headers = abort.headers
                return Response(status: status, headers: headers, body: .init(string: reason))
                
            default:
                return Response(status: .internalServerError)
            }
        }
    }
}
