//
//  OFPayLinkParams.swift
//  OpenfortSwift
//
//  Parameters for a session-bound Coinbase "Transfer funds" pay-link.
//

import Foundation

/// Parameters for a Coinbase pay-link. Session-bound: the destination chain and
/// address come from the session, so the link can't be redirected — the client
/// only chooses the amount.
public struct OFPayLinkParams: OFCodableSendable {
    /// Funding session (starts with `fnd_`) whose wallet receives the funds.
    public let sessionId: String
    /// The session's client secret. Optional when the session was created on this
    /// SDK instance (remembered); required for sessions created elsewhere.
    public let clientSecret: String?
    /// Amount to deliver, in the asset's human units (Coinbase enforces a minimum).
    public let amount: String
    /// Destination asset ticker; defaults to `"USDC"` server-side.
    public let asset: String?

    public init(sessionId: String, amount: String, clientSecret: String? = nil, asset: String? = nil) {
        self.sessionId = sessionId
        self.amount = amount
        self.clientSecret = clientSecret
        self.asset = asset
    }
}
