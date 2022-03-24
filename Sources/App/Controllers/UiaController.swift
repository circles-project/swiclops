//
//  AuthController.swift
//  
//
//  Created by Charles Wright on 3/24/22.
//

import Vapor
import Yams

struct UiaController {
    var app: Application
    var config: Config
    var checkers: [AuthChecker]
    
    struct Config: Codable {
        var homeserver: URL
        var routes: [UiaRoute]
        
        struct UiaRoute: Codable {
            
            enum Method: String, Codable {
                case head = "HEAD"
                case get = "GET"
                case put = "PUT"
                case post = "POST"
                case delete = "DELETE"
                case update = "UPDATE"
            }
            
            var path: String
            var method: Method
            var flows: [UiaFlow]
        }
    }
    
    // FIXME Add a callback so that we can handle UIA and then do something else
    //       Like, sometimes we want to proxy the "real" request (sans UIA) to the homeserver
    //       But other times, we need to handle the request ourselves in another handler
    func handle(req: Request) async throws -> AsyncResponseEncodable {

        // First let's make sure that this is one of our configured routes,
        // and let's get its configuration
        guard let route = self.config.routes.first(where: {
            $0.path == req.url.path && $0.method.rawValue == req.method.rawValue
        }) else {
            // We're not even supposed to be here
            throw Abort(.internalServerError)
        }

        let flows = route.flows
        
        return HTTPStatus.ok
    }
}
