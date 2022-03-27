//
//  Postmark.swift
//  
//
//  Created by Charles Wright on 3/26/22.
//

import Vapor

struct Postmark {
    // https://postmarkapp.com/developer/api/email-api
    
    static func sendEmail(from: String,
                          to: String,
                          subject: String,
                          html: String,
                          text: String,
                          client: Client,
                          token: String
    )
    async throws -> SingleEmailResponse {
        let headers = HTTPHeaders([
            ("Content-Type", "application/json"),
            ("Accept", "application/json"),
            ("X-Postmark-Server-Token", token)
        ])
        let emailRequest = SingleEmailRequest(
            from: from,
            to: to,
            subject: subject,
            htmlBody: html,
            textBody: text
        )
        
        let response = try await client.post("https://api.postmarkapp.com/email", headers: headers) { req in
            try req.content.encode(emailRequest)
        }

        let emailResponse = try response.content.decode(SingleEmailResponse.self)
        return emailResponse
    }

    struct SingleEmailRequest: Content {
        // Submit to /email endpoint
    
        var from: String
        var to: String // For multiple recipients, use a comma-separated list inside the string
        var cc: String? // For multiple recipients, use a comma-separated list inside the string
        var bcc: String? // For multiple recipients, use a comma-separated list inside the string
        var subject: String?
        var tag: String?
        
        var htmlBody: String
        var textBody: String
        
        var replyTo: String?
        
        var headers: [Header]?
        
        struct Header: Content {
            var name: String
            var value: String
            
            enum CodingKeys: String, CodingKey {
                case name = "Name"
                case value = "Value"
            }
        }
        
        var trackOpens: Bool?
        var trackLinks: String?
        
        var metadata: [String:String]?
        
        var attachments: [Attachment]?
        
        struct Attachment: Content {
            var name: String
            var content: String
            var contentType: String
            
            enum CodingKeys: String, CodingKey {
                case name = "Name"
                case content = "Content"
                case contentType = "ContentType"
            }
        }
        
        var messageStream: String?
        
        enum CodingKeys: String, CodingKey {
            case from = "From"
            case to = "To"
            case cc = "Cc"
            case bcc = "Bcc"
            case subject = "Subject"
            case tag = "Tag"
            case htmlBody = "HtmlBody"
            case textBody = "TextBody"
            case replyTo = "ReplyTo"
            case headers = "Headers"
            case trackOpens = "TrackOpens"
            case trackLinks = "TrackLinks"
            case metadata = "Metadata"
            case attachments = "Attachments"
            case messageStream = "MessageStream"
        }
            
    }
    
    struct SingleEmailResponse: Content {
        var to: String
        var submittedAt: Date
        var messageId: String
        var errorCode: Int
        var message: String
        
        enum CodingKeys: String, CodingKey {
            case to = "To"
            case submittedAt = "SubmittedAt"
            case messageId = "MessageID"
            case errorCode = "ErrorCode"
            case message = "Message"
        }
    }

}
