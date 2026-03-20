//
//  OFLoginWithIdTokenParams.swift
//  OpenfortSwift
//
//  Created by Pavlo Hurkovskyi on 2025-07-25.
//

public struct OFLoginWithIdTokenParams: OFCodableSendable {
    public let provider: String
    public let token: String

    public init(provider: String, token: String) {
        self.provider = provider
        self.token = token
    }
}
