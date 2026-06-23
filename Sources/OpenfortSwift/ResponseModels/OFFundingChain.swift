//
//  OFFundingChain.swift
//  OpenfortSwift
//
//  Source chains + currencies the funding rail can route from — a live
//  passthrough of the provider's supported routes, for building a source picker.
//

import Foundation

/// A source currency available on a chain.
public struct OFFundingCurrency: OFCodableSendable {
    public let symbol: String
    /// Contract address, or the zero address for the chain's native asset.
    public let address: String
    public let decimals: Int
    public let logo: String?
    /// `true` for the chain's native currency (ETH, SOL, POL, …).
    public let native: Bool
}

/// A source chain the rail can route from, with its routable currencies.
public struct OFFundingChain: OFCodableSendable {
    /// CAIP-2 chain id, e.g. `"eip155:8453"`.
    public let id: String
    public let name: String
    public let logo: String?
    public let vmType: String
    public let currencies: [OFFundingCurrency]
}
