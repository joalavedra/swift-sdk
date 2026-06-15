import Foundation

/// Dependency-free ERC-20 conveniences: pure calldata builders plus `eth_call` reads over a
/// plain JSON-RPC endpoint. Lets apps fetch balances and build `transfer` calldata without
/// hand-rolling ABI encoding or wiring up a Web3 library.
///
/// Calldata builders are pure and synchronous. The read helpers (`balance`, `decimals`,
/// `formattedBalance`) perform a single `eth_call` via `URLSession` against the supplied RPC URL.
///
/// - Note: Raw balances are returned as `0x`-prefixed hex (lossless for the full uint256 range).
///   `formattedBalance` converts via `Decimal`, which holds 38 significant digits — exact for any
///   realistic token balance, but a value with more than 38 significant digits is rounded.
public enum OFERC20 {

    /// Builds `transfer(address,uint256)` calldata (selector `0xa9059cbb`).
    /// - Parameters:
    ///   - to: Recipient address (`0x`-prefixed, 20 bytes).
    ///   - amount: Token amount in base units as a `0x`-prefixed or bare hex string.
    /// - Returns: `0x`-prefixed calldata.
    public static func transfer(to: String, amount: String) -> String {
        "0xa9059cbb" + pad32(to) + pad32(amount)
    }

    /// Builds `balanceOf(address)` calldata (selector `0x70a08231`).
    /// - Parameter owner: Address to query (`0x`-prefixed, 20 bytes).
    /// - Returns: `0x`-prefixed calldata.
    public static func balanceOf(owner: String) -> String {
        "0x70a08231" + pad32(owner)
    }

    /// Builds `decimals()` calldata (selector `0x313ce567`).
    /// - Returns: `0x`-prefixed calldata.
    public static func decimals() -> String {
        "0x313ce567"
    }

    /// Encodes a token `amount` into its base-unit hex representation (amount × 10^decimals),
    /// suitable as the `amount` argument to `transfer`.
    /// - Parameters:
    ///   - amount: Human-readable amount (e.g. `1.5`).
    ///   - decimals: Token decimals (e.g. `6` for USDC, `18` for most ERC-20s).
    /// - Returns: `0x`-prefixed hex of the integer base-unit value.
    public static func baseUnits(_ amount: Decimal, decimals: Int) -> String {
        var scaled = amount * pow(Decimal(10), max(0, decimals))
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .down)
        return decimalToHex(rounded)
    }

    /// Reads the raw `balanceOf` for `owner` on `token` via `eth_call`.
    /// - Returns: Raw balance in base units as a `0x`-prefixed hex string (lossless).
    public static func balance(token: String, owner: String, rpcURL: URL) async throws -> String {
        try await ethCall(to: token, data: balanceOf(owner: owner), rpcURL: rpcURL)
    }

    /// Reads a token's `decimals()` via `eth_call`.
    public static func decimals(token: String, rpcURL: URL) async throws -> Int {
        let hex = try await ethCall(to: token, data: decimals(), rpcURL: rpcURL)
        guard let value = UInt64(strip0x(hex), radix: 16) else {
            throw OFERC20Error.decodingFailed("decimals() returned non-numeric value: \(hex)")
        }
        return Int(value)
    }

    /// Reads `balanceOf` and converts it to a human-readable `Decimal` (balance ÷ 10^decimals).
    /// - Note: See the type-level note on `Decimal` precision (38 significant digits).
    public static func formattedBalance(
        token: String,
        owner: String,
        decimals: Int,
        rpcURL: URL
    ) async throws -> Decimal {
        let raw = try await balance(token: token, owner: owner, rpcURL: rpcURL)
        guard let units = hexToDecimal(strip0x(raw)) else {
            throw OFERC20Error.decodingFailed("balanceOf returned non-numeric value: \(raw)")
        }
        return units / pow(Decimal(10), max(0, decimals))
    }

    // MARK: - Transfer history

    /// Reads recent `Transfer` events touching `owner` on `token` via chunked `eth_getLogs`.
    ///
    /// Public Base RPC endpoints cap `eth_getLogs` at **2000 blocks per query**, so a single call
    /// can't cover a meaningful window. This walks back `blocks` from the latest block in `chunk`-
    /// sized ranges, querying two filters per range — `owner` as topic1 (`from`, outgoing) and as
    /// topic2 (`to`, incoming) — and merging the results. Chunks run concurrently via `async let`.
    ///
    /// - Parameters:
    ///   - token: ERC-20 contract address (`0x`-prefixed).
    ///   - owner: Address whose transfers to collect (matched as either `from` or `to`).
    ///   - rpcURL: JSON-RPC endpoint.
    ///   - blocks: Total block depth to scan back from the latest block (default `24_000`).
    ///   - chunk: Max blocks per `eth_getLogs` query (default `2_000`, the public Base cap).
    /// - Returns: Transfers across the window, newest block first.
    /// - Throws: ``OFERC20Error`` on RPC or decoding failure.
    public static func transferHistory(
        token: String,
        owner: String,
        rpcURL: URL,
        blocks: Int = 24_000,
        chunk: Int = 2_000
    ) async throws -> [OFTokenTransfer] {
        let latest = try await blockNumber(rpcURL: rpcURL)
        let span = max(0, min(blocks, latest))
        let safeChunk = max(1, min(chunk, 2_000))
        let ranges = blockRanges(latest: latest, span: span, chunk: safeChunk)
        let ownerKey = owner.lowercased()

        var collected: [OFTokenTransfer] = []
        for batch in ranges.chunked(into: 8) {
            collected += try await fetchRanges(batch, token: token, owner: owner, rpcURL: rpcURL)
        }
        return collected
            .sorted { $0.blockNumber > $1.blockNumber }
            .map {
                OFTokenTransfer(
                    hash: $0.hash, from: $0.from, to: $0.to, value: $0.value,
                    blockNumber: $0.blockNumber, isOutgoing: $0.from.lowercased() == ownerKey
                )
            }
    }

    private static func fetchRanges(
        _ ranges: [(from: Int, to: Int)],
        token: String,
        owner: String,
        rpcURL: URL
    ) async throws -> [OFTokenTransfer] {
        try await withThrowingTaskGroup(of: [OFTokenTransfer].self) { group in
            for range in ranges {
                group.addTask {
                    async let outgoing = logs(token: token, range: range, fromOwner: owner, rpcURL: rpcURL)
                    async let incoming = logs(token: token, range: range, toOwner: owner, rpcURL: rpcURL)
                    return try await outgoing + incoming
                }
            }
            var merged: [OFTokenTransfer] = []
            for try await transfers in group { merged += transfers }
            return merged
        }
    }

    /// Queries one `eth_getLogs` range for the `Transfer` topic, filtered by `owner` as `from` or
    /// `to`. Pass exactly one of `fromOwner` / `toOwner`.
    private static func logs(
        token: String,
        range: (from: Int, to: Int),
        fromOwner: String? = nil,
        toOwner: String? = nil,
        rpcURL: URL
    ) async throws -> [OFTokenTransfer] {
        let topics: [Any] = [
            transferTopic,
            fromOwner.map { addressTopic($0) } as Any? ?? NSNull(),
            toOwner.map { addressTopic($0) } as Any? ?? NSNull(),
        ]
        let filter: [String: Any] = [
            "address": token,
            "fromBlock": hex(range.from),
            "toBlock": hex(range.to),
            "topics": topics,
        ]
        guard case let .array(rawLogs) = try await rpcCall(method: "eth_getLogs", params: [filter], rpcURL: rpcURL)
        else { return [] }
        return rawLogs.compactMap { parseTransferLog($0) }
    }

    private static func parseTransferLog(_ raw: Any) -> OFTokenTransfer? {
        guard let log = raw as? [String: Any],
              let topics = log["topics"] as? [String], topics.count >= 3,
              let data = log["data"] as? String,
              let hash = log["transactionHash"] as? String,
              let blockHex = log["blockNumber"] as? String,
              let block = UInt64(strip0x(blockHex), radix: 16)
        else { return nil }
        let from = addressFromTopic(topics[1])
        let to = addressFromTopic(topics[2])
        let value = hexToDecimal(strip0x(data)).map { "\($0)" } ?? "0"
        return OFTokenTransfer(
            hash: hash, from: from, to: to, value: value, blockNumber: Int(block), isOutgoing: false
        )
    }

    /// Reads the latest block number via `eth_blockNumber`.
    public static func blockNumber(rpcURL: URL) async throws -> Int {
        guard case let .string(hex) = try await rpcCall(method: "eth_blockNumber", params: [], rpcURL: rpcURL),
              let value = UInt64(strip0x(hex), radix: 16) else {
            throw OFERC20Error.decodingFailed("eth_blockNumber returned a non-numeric value.")
        }
        return Int(value)
    }

    /// Splits the `span` of blocks ending at `latest` into inclusive `[from, to]` ranges of at most
    /// `chunk` blocks each, newest range first.
    static func blockRanges(latest: Int, span: Int, chunk: Int) -> [(from: Int, to: Int)] {
        guard span > 0, chunk > 0 else { return [] }
        let oldest = max(0, latest - span + 1)
        var ranges: [(from: Int, to: Int)] = []
        var to = latest
        while to >= oldest {
            let from = max(oldest, to - chunk + 1)
            ranges.append((from: from, to: to))
            if from == 0 { break }
            to = from - 1
        }
        return ranges
    }

    // MARK: - JSON-RPC

    private static func ethCall(to: String, data: String, rpcURL: URL) async throws -> String {
        guard case let .string(result) = try await rpcCall(
            method: "eth_call",
            params: [["to": to, "data": data], "latest"],
            rpcURL: rpcURL
        ) else {
            throw OFERC20Error.decodingFailed("eth_call returned a non-string result.")
        }
        return result
    }

    /// A decoded JSON-RPC `result`, preserving whether it was a string (most reads), an array
    /// (`eth_getLogs`), or some other JSON value.
    enum RPCResult {
        case string(String)
        case array([Any])
        case other
    }

    /// Performs a single JSON-RPC POST and returns the decoded `result`. Throws on RPC errors.
    static func rpcCall(method: String, params: [Any], rpcURL: URL) async throws -> RPCResult {
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": method, "params": params]
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, _) = try await URLSession.shared.data(for: request)
        guard let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw OFERC20Error.decodingFailed("RPC response was not a JSON object.")
        }
        if let error = object["error"] as? [String: Any] {
            throw OFERC20Error.rpcError((error["message"] as? String) ?? "Unknown RPC error")
        }
        switch object["result"] {
        case let string as String: return .string(string)
        case let array as [Any]: return .array(array)
        case .some: return .other
        case nil: throw OFERC20Error.decodingFailed("RPC response had no result.")
        }
    }

    // MARK: - Hex helpers

    /// `keccak256("Transfer(address,address,uint256)")` — topic0 of every ERC-20 `Transfer` event.
    static let transferTopic = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

    private static func strip0x(_ hex: String) -> String {
        hex.hasPrefix("0x") || hex.hasPrefix("0X") ? String(hex.dropFirst(2)) : hex
    }

    /// `0x`-prefixed hex of a non-negative `Int` (for block numbers in `eth_getLogs` filters).
    private static func hex(_ value: Int) -> String { "0x" + String(value, radix: 16) }

    /// Left-pads an address into the 32-byte topic encoding used for indexed `address` event args.
    private static func addressTopic(_ address: String) -> String { "0x" + pad32(address) }

    /// Recovers a checksum-free lowercase address from a 32-byte indexed topic (low 20 bytes).
    private static func addressFromTopic(_ topic: String) -> String {
        let clean = strip0x(topic).lowercased()
        return "0x" + String(clean.suffix(40))
    }

    /// Left-pads a hex value (address or integer) to a 32-byte (64 hex char) ABI word.
    private static func pad32(_ value: String) -> String {
        let clean = strip0x(value).lowercased()
        guard clean.count <= 64 else { return String(clean.suffix(64)) }
        return String(repeating: "0", count: 64 - clean.count) + clean
    }

    /// Parses an arbitrary-length hex string into an exact `Decimal` (up to 38 significant digits).
    private static func hexToDecimal(_ hex: String) -> Decimal? {
        var result = Decimal(0)
        let sixteen = Decimal(16)
        for character in hex.lowercased() {
            guard let digit = character.hexDigitValue else { return nil }
            result = result * sixteen + Decimal(digit)
        }
        return result
    }

    /// Converts a non-negative integer `Decimal` to a `0x`-prefixed hex string.
    private static func decimalToHex(_ value: Decimal) -> String {
        var remaining = value
        let sixteen = Decimal(16)
        var digits = ""
        let symbols = Array("0123456789abcdef")
        while remaining >= 1 {
            var quotient = Decimal()
            var divided = remaining / sixteen
            NSDecimalRound(&quotient, &divided, 0, .down)
            let remainder = remaining - quotient * sixteen
            digits.append(symbols[(remainder as NSDecimalNumber).intValue])
            remaining = quotient
        }
        return digits.isEmpty ? "0x0" : "0x" + String(digits.reversed())
    }
}

/// A single ERC-20 `Transfer` event, as decoded by ``OFERC20/transferHistory(token:owner:rpcURL:blocks:chunk:)``.
public struct OFTokenTransfer: Sendable, Equatable {
    /// Transaction hash the transfer was emitted in (`0x`-prefixed).
    public let hash: String
    /// Sender address (`from`, lowercase, `0x`-prefixed).
    public let from: String
    /// Recipient address (`to`, lowercase, `0x`-prefixed).
    public let to: String
    /// Transferred amount in base units, as a decimal `String` (lossless for the full uint256 range).
    public let value: String
    /// Block number the transfer was mined in.
    public let blockNumber: Int
    /// `true` when `from` is the queried owner (an outgoing transfer), `false` when incoming.
    public let isOutgoing: Bool

    public init(hash: String, from: String, to: String, value: String, blockNumber: Int, isOutgoing: Bool) {
        self.hash = hash
        self.from = from
        self.to = to
        self.value = value
        self.blockNumber = blockNumber
        self.isOutgoing = isOutgoing
    }
}

/// Errors raised by `OFERC20` read helpers.
public enum OFERC20Error: Error, LocalizedError {
    case rpcError(String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .rpcError(let message): return "ERC-20 RPC error: \(message)"
        case .decodingFailed(let detail): return "ERC-20 response could not be decoded: \(detail)"
        }
    }
}

extension Array {
    /// Splits the array into consecutive sub-arrays of at most `size` elements.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}
