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

    // MARK: - JSON-RPC

    private static func ethCall(to: String, data: String, rpcURL: URL) async throws -> String {
        let body: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "eth_call",
            "params": [["to": to, "data": data], "latest"],
        ]
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
        guard let result = object["result"] as? String else {
            throw OFERC20Error.decodingFailed("RPC response had no string result.")
        }
        return result
    }

    // MARK: - Hex helpers

    private static func strip0x(_ hex: String) -> String {
        hex.hasPrefix("0x") || hex.hasPrefix("0X") ? String(hex.dropFirst(2)) : hex
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
