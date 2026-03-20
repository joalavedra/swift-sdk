//
//  OFInitOAuthParams.swift
//  OpenfortSwift
//
//  Created by Pavlo Hurkovskyi on 2025-07-25.
//

public struct OFInitOAuthParams: OFCodableSendable {
    public let provider: String
    public let options: [String: AnyCodable]?
    public init(provider: String, options: [String: AnyCodable]? = nil) {
        self.provider = provider
        self.options = options
    }
}
