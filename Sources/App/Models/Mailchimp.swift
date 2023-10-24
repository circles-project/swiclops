//
//  Mailchimp.swift
//
//
//  Created by Charles Wright on 10/4/23.
//

import Vapor

struct Mailchimp {
    
    struct Config: Codable {
        var server: URL
        var apiKey: String
        var listId: String
        
        enum CodingKeys: String, CodingKey {
            case server
            case apiKey = "api_key"
            case listId = "list_id"
        }
    }
    
    static func subscribe(email: String,
                          to listId: String,
                          for req: Request,
                          server: URL,
                          apiKey: String,
                          tags: [String] = []
    ) async throws {
        req.logger.debug("Subscribing user \(email) to Mailchimp list \(listId)")
        
        let url = URI(scheme: server.scheme, host: server.host, port: server.port, path: "/lists/\(listId)/members")
        let headers = HTTPHeaders([
            ("Authorization", "Bearer: \(apiKey)"),
            ("Content-Type", "application/json"),
            ("Accept", "application/json"),
        ])
        
        struct RequestBody: Content {
            var emailAddress: String
            var status: Status
            enum Status: String, Codable {
                case subscribed
                case unsubscribed
                case cleaned
                case pending
                case transactional
            }
            var emailType: EmailType
            enum EmailType: String, Codable {
                case html
                case text
            }
            var mergeFields: [String: String] = [:]
            var interests: [String: String] = [:]
            var language: String?
            var vip: Bool
            var location: Location
            struct Location: Codable {
                var latitude: Double
                var longitude: Double
            }
            var marketingPermissions: [MarketingPermission] = []
            struct MarketingPermission: Codable {
                var id: String
                var enabled: Bool
                enum CodingKeys: String, CodingKey {
                    case id = "marketing_permission_id"
                    case enabled
                }
            }
            var ipSignup: String = ""
            var timestampSignup: String = ""
            var ipOpt: String = ""
            var timestampOpt: String = ""
            var tags: [String] = []
            
            enum CodingKeys: String, CodingKey {
                case emailAddress = "email_address"
                case status
                case emailType = "email_type"
                case mergeFields = "merge_fields"
                case interests
                case language
                case vip
                case location
                case marketingPermissions = "marketing_permissions"
                case ipSignup = "ip_signup"
                case timestampSignup = "timestamp_signup"
                case ipOpt = "ip_opt"
                case timestampOpt = "timestamp_opt"
                case tags
            }
        }
        
        let body = RequestBody(emailAddress: email,
                               status: .subscribed,
                               emailType: .html,
                               vip: false,
                               location: RequestBody.Location(latitude: 0,
                                                              longitude: 0),
                               tags: tags)
        
        let response = try await req.client.post(url, headers: headers, content: body)
        
        guard response.status == .ok
        else {
            req.logger.error("Mailchimp request rejected with status \(response.status)")
            throw Abort(.internalServerError)
        }
    }
}
