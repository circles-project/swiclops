//
//  EmailConfig.swift
//  
//
//  Created by Charles Wright on 9/20/22.
//

import Vapor
import Fluent

struct EmailConfig: Codable {
    var postmark: Postmark.Config
    var mailchimp: Mailchimp.Config?
}
