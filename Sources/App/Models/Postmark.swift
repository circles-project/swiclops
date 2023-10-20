//
//  Postmark.swift
//  
//
//  Created by Charles Wright on 3/26/22.
//

import Vapor

struct Postmark {
    // https://postmarkapp.com/developer/api/email-api
    
    struct Config: Codable {
        var token: String
    }
    
    static func sendEmail(from: String,
                          to: String,
                          subject: String,
                          html: String,
                          text: String,
                          for req: Request,
                          token: String,
                          messageStream: String? = nil
    ) async throws -> SingleEmailResponseBody
    {
        let headers = HTTPHeaders([
            ("Content-Type", "application/json"),
            ("Accept", "application/json"),
            ("X-Postmark-Server-Token", token)
        ])
        let requestBody = SingleEmailRequestBody(
            from: from,
            to: to,
            subject: subject,
            htmlBody: html,
            textBody: text,
            messageStream: messageStream
        )
        
        req.logger.debug("Sending Postmark request")
        let response = try await req.client.post("https://api.postmarkapp.com/email", headers: headers) { clientReq in
            try clientReq.content.encode(requestBody)
        }
        req.logger.debug("Got Postmark response with status \(response.status.code): \(response.status)")

        guard let responseBody = try? response.content.decode(SingleEmailResponseBody.self) else {
            req.logger.error("Failed to decode Postmark response")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Failed to decode email provider response")
        }
        return responseBody
    }

    struct SingleEmailRequestBody: Content {
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
    
    struct SingleEmailResponseBody: Content {
        var to: String
        var submittedAt: String // FIXME: This should really be a Date but it's ISO8601 with fractional seconds, so blegh https://useyourloaf.com/blog/swift-codable-with-custom-dates/
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
