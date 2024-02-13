//
//  MatrixConfig.swift
//
//
//  Created by Michael Hollister on 2/13/24.
//

import Vapor

protocol AuthFlow: Content {}

struct LegacyAuthFlow: AuthFlow {
    var type: String
}
