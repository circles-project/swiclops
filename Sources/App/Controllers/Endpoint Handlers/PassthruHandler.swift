//
//  PassthruHandler.swift
//  
//
//  Created by Charles Wright on 7/13/23.
//

import Vapor

/*
 PassthruHandler - Like the ProxyHandler, but without UIA
 */
struct PassthruHandler: EndpointHandler {
    var app: Application
    var homeserver: URL
    var endpoints: [Endpoint]
    
    private var allocator: ByteBufferAllocator
    
    init(app: Application, homeserver: URL, endpoints: [Endpoint]) {
        self.app = app
        self.homeserver = homeserver
        self.endpoints = endpoints
        
        self.allocator = .init()
    }
    
    func handle(req: Request) async throws -> Response {
        req.logger.debug("Passthru: Handling request for \(req.url.path)")
        
        let clientReq = ClientRequest(method: req.method,
                                      url: req.url,
                                      headers: req.headers,
                                      body: req.body.data,
                                      byteBufferAllocator: self.allocator)
        let clientResponse = try await req.client.send(clientReq)
        req.logger.debug("Passthru: Got server response with status \(clientResponse.status)")
        
        let responseBody: Response.Body = clientResponse.body == nil ? .empty : .init(buffer: clientResponse.body!, byteBufferAllocator: self.allocator)
        
        let response = Response(status: clientResponse.status,
                                version: req.version,
                                headers: clientResponse.headers,
                                body: responseBody)
        
        req.logger.debug("Passthru: Sending response with status \(response.status) and \(response.body.data?.count ?? 0) bytes of body")
        return response
    }
    
    
}
