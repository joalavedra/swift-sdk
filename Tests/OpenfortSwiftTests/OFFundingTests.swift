import Foundation
import Testing
@testable import OpenfortSwift

private func jsonDict(_ value: some Encodable) throws -> [String: Any]? {
    let data = try JSONEncoder().encode(value)
    return try JSONSerialization.jsonObject(with: data) as? [String: Any]
}

// MARK: - OFFundingPaymentMethodInput encoding

@Test func paymentMethodInputEvmEncodesTypeAndSource() throws {
    let pm = OFFundingPaymentMethodInput.evm(
        source: .init(chain: "eip155:137", currency: "0xUSDC", amount: "10000000")
    )
    let dict = try #require(try jsonDict(pm))
    #expect(dict["type"] as? String == "evm")
    #expect(dict["cex"] == nil)
    let source = try #require(dict["source"] as? [String: Any])
    #expect(source["chain"] as? String == "eip155:137")
    #expect(source["amount"] as? String == "10000000")
}

@Test func paymentMethodInputSolanaEncodesType() throws {
    let pm = OFFundingPaymentMethodInput.solana(
        source: .init(chain: "solana:5eykt", currency: "EPjF", amount: "1")
    )
    let dict = try #require(try jsonDict(pm))
    #expect(dict["type"] as? String == "solana")
    #expect(dict["cex"] == nil)
}

@Test func paymentMethodInputCexEncodesExchange() throws {
    let pm = OFFundingPaymentMethodInput.cex(
        cex: "binance",
        source: .init(chain: "eip155:137", currency: "0xUSDC", amount: "5000000")
    )
    let dict = try #require(try jsonDict(pm))
    #expect(dict["type"] as? String == "cex")
    #expect(dict["cex"] as? String == "binance")
    #expect(dict["source"] != nil)
}

// MARK: - OFFundingSessionStatus

@Test func statusDecodesSnakeCaseRawValues() {
    #expect(OFFundingSessionStatus(rawValue: "requires_payment_method") == .requiresPaymentMethod)
    #expect(OFFundingSessionStatus(rawValue: "waiting_payment") == .waitingPayment)
    #expect(OFFundingSessionStatus(rawValue: "succeeded") == .succeeded)
}

@Test func statusTerminalFlag() {
    #expect(OFFundingSessionStatus.succeeded.isTerminal)
    #expect(OFFundingSessionStatus.bounced.isTerminal)
    #expect(OFFundingSessionStatus.expired.isTerminal)
    #expect(!OFFundingSessionStatus.requiresPaymentMethod.isTerminal)
    #expect(!OFFundingSessionStatus.waitingPayment.isTerminal)
    #expect(!OFFundingSessionStatus.processing.isTerminal)
}

// MARK: - OFFundingSession decoding (matches the /v2/funding API shape)

@Test func sessionDecodesFromApiPayload() throws {
    let json = """
    {
      "id": "fnd_123",
      "object": "funding_session",
      "status": "waiting_payment",
      "clientSecret": "cs_abc",
      "target": { "chain": "eip155:8453", "currency": "0xUSDCbase", "address": "0xdest" },
      "amountUnits": null,
      "metadata": { "k": "v" },
      "externalId": null,
      "strict": false,
      "createdAt": 1700000000,
      "expiresAt": 1700086400,
      "paymentMethod": {
        "type": "evm",
        "source": { "chain": "eip155:137", "currency": "0xUSDCpoly", "amount": "10000000" },
        "receiverAddress": "0xreceiver",
        "addressUri": "ethereum:0xreceiver",
        "deeplinks": [ { "app": "metamask", "label": "Open on MetaMask", "url": "https://x" } ],
        "cex": null,
        "fees": [ { "kind": "relayerService", "amount": "20000", "currency": "0xUSDCpoly" } ],
        "minAmount": "100000"
      }
    }
    """
    let session = try JSONDecoder().decode(OFFundingSession.self, from: Data(json.utf8))
    #expect(session.id == "fnd_123")
    #expect(session.status == .waitingPayment)
    #expect(session.target.chain == "eip155:8453")
    #expect(session.metadata?["k"] == "v")
    #expect(session.amountUnits == nil)
    #expect(session.strict == false)

    let pm = try #require(session.paymentMethod)
    #expect(pm.type == "evm")
    #expect(pm.receiverAddress == "0xreceiver")
    #expect(pm.deeplinks.first?.app == "metamask")
    #expect(pm.cex == nil)
    #expect(pm.fees.first?.kind == "relayerService")
    #expect(pm.minAmount == "100000")
}

@Test func sessionDecodesCexGuidance() throws {
    let json = """
    {
      "id": "fnd_cex",
      "object": "funding_session",
      "status": "waiting_payment",
      "clientSecret": "cs_x",
      "target": { "chain": "eip155:8453", "currency": "0xUSDC", "address": "0xdest" },
      "amountUnits": null, "metadata": null, "externalId": null, "strict": true,
      "createdAt": 1, "expiresAt": 2,
      "paymentMethod": {
        "type": "cex",
        "source": { "chain": "eip155:137", "currency": "0xUSDC", "amount": "5000000" },
        "receiverAddress": "0xr", "addressUri": "ethereum:0xr",
        "deeplinks": [],
        "cex": { "exchange": "binance", "network": "Polygon", "minWithdrawal": "1000000", "requiresMemo": false },
        "fees": [], "minAmount": null
      }
    }
    """
    let session = try JSONDecoder().decode(OFFundingSession.self, from: Data(json.utf8))
    let cex = try #require(session.paymentMethod?.cex)
    #expect(cex.exchange == "binance")
    #expect(cex.network == "Polygon")
    #expect(cex.minWithdrawal == "1000000")
    #expect(cex.requiresMemo == false)
    #expect(session.paymentMethod?.deeplinks.isEmpty == true)
}
