import Foundation

/// Dependency-free EVM polling helpers built on `URLSession` JSON-RPC.
///
/// These complement ``OFERC20`` for flows that submit a transaction (or user operation) and then
/// need to block until it is mined. Both helpers poll on a fixed interval until the receipt appears
/// or the `timeout` elapses; a missing receipt is not an error, it just means "not yet mined".
public enum OFEVM {

    /// Polls `eth_getTransactionReceipt` until the receipt is available or `timeout` elapses.
    ///
    /// A pending transaction returns a `null` receipt, so this loops until the node returns a
    /// non-null receipt object. Use for ordinary EOA / contract transactions whose hash you already
    /// have (e.g. the hash returned by ``OpenfortEIP1193Web3Provider/request(method:params:)`` for
    /// `eth_sendTransaction`).
    ///
    /// - Parameters:
    ///   - txHash: Transaction hash to wait on (`0x`-prefixed).
    ///   - rpcURL: JSON-RPC endpoint for the transaction's chain.
    ///   - timeout: Maximum seconds to wait before giving up (default `60`).
    /// - Returns: `true` once the receipt is found; `false` if `timeout` elapses first.
    /// - Throws: ``OFERC20Error`` on an RPC-level error.
    public static func waitForReceipt(
        txHash: String,
        rpcURL: URL,
        timeout: TimeInterval = 60
    ) async throws -> Bool {
        try await poll(timeout: timeout) {
            if case let .object(receipt) = try await rpcCall(
                method: "eth_getTransactionReceipt", params: [txHash], rpcURL: rpcURL, bearer: nil
            ), !receipt.isEmpty {
                return true
            }
            return nil
        }
    }

    /// Polls Openfort's bundler `eth_getUserOperationReceipt` until the receipt is available.
    ///
    /// ERC-4337 user operations settle through a bundler, not the public chain RPC, so this queries
    /// Openfort's bundler endpoint `https://api.openfort.io/rpc/<chainId>` with the publishable key
    /// as a bearer token. A pending userOp returns `null`; this loops until a receipt object appears.
    ///
    /// - Parameters:
    ///   - userOpHash: User operation hash to wait on (`0x`-prefixed).
    ///   - chainId: Chain id, appended to the bundler URL path.
    ///   - publishableKey: Openfort publishable key, sent as `Authorization: Bearer <key>`.
    ///   - timeout: Maximum seconds to wait before giving up (default `60`).
    /// - Returns: `true` once the receipt is found; `false` if `timeout` elapses first.
    /// - Throws: ``OFERC20Error`` on an RPC-level error or an invalid bundler URL.
    public static func waitForUserOperationReceipt(
        userOpHash: String,
        chainId: Int,
        publishableKey: String,
        timeout: TimeInterval = 60
    ) async throws -> Bool {
        guard let rpcURL = URL(string: "https://api.openfort.io/rpc/\(chainId)") else {
            throw OFERC20Error.decodingFailed("Could not build Openfort bundler URL for chain \(chainId).")
        }
        return try await poll(timeout: timeout) {
            if case let .object(receipt) = try await rpcCall(
                method: "eth_getUserOperationReceipt", params: [userOpHash],
                rpcURL: rpcURL, bearer: publishableKey
            ), !receipt.isEmpty {
                return true
            }
            return nil
        }
    }

    // MARK: - Polling

    /// Runs `probe` every 1.5s until it returns a non-nil value or `timeout` elapses (then `false`).
    private static func poll(
        timeout: TimeInterval,
        probe: () async throws -> Bool?
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let found = try await probe() { return found }
            try await Task.sleep(nanoseconds: 1_500_000_000)
        }
        return false
    }

    // MARK: - JSON-RPC

    private enum RPCResult {
        case object([String: Any])
        case null
        case other
    }

    /// Single JSON-RPC POST, optionally bearer-authenticated. A `null` result maps to `.null`
    /// (a not-yet-mined receipt) rather than an error.
    private static func rpcCall(
        method: String,
        params: [Any],
        rpcURL: URL,
        bearer: String?
    ) async throws -> RPCResult {
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": method, "params": params]
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, _) = try await URLSession.shared.data(for: request)
        guard let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw OFERC20Error.decodingFailed("RPC response was not a JSON object.")
        }
        if let error = object["error"] as? [String: Any] {
            throw OFERC20Error.rpcError((error["message"] as? String) ?? "Unknown RPC error")
        }
        switch object["result"] {
        case let receipt as [String: Any]: return .object(receipt)
        case is NSNull, nil: return .null
        default: return .other
        }
    }
}
