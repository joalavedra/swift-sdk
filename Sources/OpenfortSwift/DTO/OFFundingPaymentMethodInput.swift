//
//  OFFundingPaymentMethodInput.swift
//  OpenfortSwift
//
//  The source route the user commits to when funding a session.
//

import Foundation

/// The source route a user commits to for a funding session.
///
/// `evm` / `solana` are self-custody transfers (they get wallet deeplinks); `cex`
/// is a guided withdrawal from a centralized exchange — same deposit address, plus
/// withdrawal guidance (network, minimum, memo) and no wallet deeplinks.
///
/// Encodes to the shape the openfort-js funding namespace expects, e.g.
/// `{ "type": "evm", "source": { ... } }` or `{ "type": "cex", "cex": "binance", "source": { ... } }`.
public enum OFFundingPaymentMethodInput: Encodable, Sendable {
    case evm(source: OFFundingSource)
    case solana(source: OFFundingSource)
    case cex(cex: String, source: OFFundingSource)

    private enum CodingKeys: String, CodingKey {
        case type, source, cex
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .evm(source):
            try container.encode("evm", forKey: .type)
            try container.encode(source, forKey: .source)
        case let .solana(source):
            try container.encode("solana", forKey: .type)
            try container.encode(source, forKey: .source)
        case let .cex(cex, source):
            try container.encode("cex", forKey: .type)
            try container.encode(cex, forKey: .cex)
            try container.encode(source, forKey: .source)
        }
    }
}
