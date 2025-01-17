//
//  AdminApiController.swift
//  
//
//  Created by Charles Wright on 9/16/22.
//

import Vapor
import Fluent

struct AdminApiController: RouteCollection {
    
    var app: Application
    var handlers: [Endpoint: EndpointHandler] // Handlers for the admin API

    
    init(app: Application, matrixConfig: MatrixConfig) {
        self.app = app
        
        let endpointHandlerModules: [EndpointHandler] = [
            TokenAdminHandler(app: self.app)
        ]
        
        self.handlers = [:]
        for module in endpointHandlerModules {
            for endpoint in module.endpoints {
                self.handlers[endpoint] = module
            }
        }
    }
    
    func boot(routes: RoutesBuilder) throws {
        let synapseAdminAPI = routes.grouped("_synapse", "admin", ":version")
        
        for (endpoint,handler) in handlers {
            synapseAdminAPI.on(endpoint.method, endpoint.pathComponents) { (req) -> Response in
                return try await handler.handle(req: req)
            }
        }
    }
    
    
}
