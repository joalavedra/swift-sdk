//
//  OFFundingSession.swift
//  OpenfortSwift
//
//  Cross-chain funding (deposit) session models, mirroring the openfort-js
//  `funding` namespace. A session is one deposit attempt against a destination:
//  create it, set a single payment method (a source the user commits to sending
//  from), then poll until it reaches a terminal status.
//

import Foundation

/// Where the funded crypto should land: a CAIP-2 chain + token contract (or the
/// zero address for native) + the destination wallet that receives the bridged funds.
public struct OFFundingTarget: OFCodableSendable {
    /// CAIP-2 chain id, e.g. `"eip155:8453"` for Base.
    public let chain: String
    /// Token contract address, or the zero address for the chain's native asset.
    public let currency: String
    /// Destination wallet that receives the bridged funds.
    public let address: String

    public init(chain: String, currency: String, address: String) {
        self.chain = chain
        self.currency = currency
        self.address = address
    }
}

/// The source route the user commits to sending from.
public struct OFFundingSource: OFCodableSendable {
    /// CAIP-2 chain id the user sends from, e.g. `"eip155:137"`.
    public let chain: String
    /// Token contract the user sends, or the zero address for native.
    public let currency: String
    /// Amount in the source token's smallest unit (wei, lamports, base units).
    public let amount: String

    public init(chain: String, currency: String, amount: String) {
        self.chain = chain
        self.currency = currency
        self.amount = amount
    }
}

/// Funding session lifecycle.
public enum OFFundingSessionStatus: String, OFCodableSendable, Equatable {
    case requiresPaymentMethod = "requires_payment_method"
    case waitingPayment = "waiting_payment"
    case processing
    case succeeded
    case bounced
    case expired

    /// `true` once the session has settled (`succeeded`) or failed (`bounced` /
    /// `expired`) and will not change again — the signal to stop polling.
    public var isTerminal: Bool {
        self == .succeeded || self == .bounced || self == .expired
    }
}

/// One fee component of a resolved payment method.
public struct OFFundingFee: OFCodableSendable {
    /// Fee kind, e.g. `"gas"`, `"relayerGas"`, `"relayerService"`, `"app"`.
    public let kind: String
    public let amount: String
    public let currency: String
}

/// A prefilled deeplink into a source wallet app (e.g. Trust Wallet, MetaMask).
public struct OFFundingWalletDeeplink: OFCodableSendable {
    public let app: String
    public let label: String
    public let url: String
}

/// Withdrawal guidance for a `cex` payment method.
public struct OFFundingCexGuidance: OFCodableSendable {
    /// Exchange id, e.g. `"binance"` | `"coinbase"`.
    public let exchange: String
    /// Network name as the exchange labels it, e.g. `"Base"`, `"Polygon"`.
    public let network: String
    /// Minimum withdrawal in source base units, if the exchange enforces one.
    public let minWithdrawal: String?
    /// `true` when the network requires a destination tag / memo.
    public let requiresMemo: Bool
}

/// A resolved payment method — what a custom UI renders and an agent reads.
public struct OFFundingPaymentMethod: OFCodableSendable {
    /// `"evm"`, `"solana"`, or `"cex"`.
    public let type: String
    public let source: OFFundingSource
    /// Address the user (or their CEX/wallet) sends to.
    public let receiverAddress: String
    /// BIP-21 / EIP-681 / Solana Pay URI for QR.
    public let addressUri: String
    /// Prefilled deeplinks for source wallet apps, when available.
    public let deeplinks: [OFFundingWalletDeeplink]
    /// Guidance for the `"cex"` type; `nil` otherwise.
    public let cex: OFFundingCexGuidance?
    public let fees: [OFFundingFee]
    /// Minimum to send for this route (source base units), or `nil`.
    public let minAmount: String?
}

/// A single deposit attempt.
public struct OFFundingSession: OFCodableSendable {
    public let id: String
    public let object: String
    public let status: OFFundingSessionStatus
    public let clientSecret: String
    public let target: OFFundingTarget
    public let amountUnits: String?
    public let metadata: [String: String]?
    public let externalId: String?
    public let strict: Bool
    public let paymentMethod: OFFundingPaymentMethod?
    public let createdAt: Int
    public let expiresAt: Int
}
