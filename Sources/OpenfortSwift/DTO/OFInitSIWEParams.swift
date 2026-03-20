//
//  OFInitSIWEParams.swift
//  OpenfortSwift
//
//  Created by Pavlo Hurkovskyi on 2025-07-25.
//

public struct OFInitSIWEParams: OFCodableSendable {
    public let address: String

    public init(address: String) {
        self.address = address
    }
}
