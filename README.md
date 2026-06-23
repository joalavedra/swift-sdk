<img width="1920" height="1080" alt="Group 48096483" src="https://github.com/user-attachments/assets/62af14ff-bd36-451d-bd29-46b32fec4749" />


<div align="center">
  <h4>
    <a href="https://www.openfort.io/">
      Website
    </a>
    <span> | </span>
    <a href="https://www.openfort.io/docs/products/embedded-wallet/swift">
      Documentation
    </a>
    <span> | </span>
    <a href="https://x.com/openfort_hq">
      X
    </a>
  </h4>
</div>


# Openfort iOS SDK

[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-openfort.io-blue)](https://www.openfort.io/docs/products/embedded-wallet/swift)

The easiest way to use embedded wallets, with built-in authentication and payments capabilities in Swift.

## Requirements

Two prerequisites are easy to miss because they only fail at runtime:

- **Keychain access.** The SDK stores all session state in the iOS Keychain. Your app must be
  able to use it: enable the **Keychain Sharing** capability (or otherwise sign the app with a
  `keychain-access-groups` entitlement). On the **iOS Simulator**, run a *signed* build — an
  unsigned target returns `errSecMissingEntitlement` (-34018) and `setupSDK()` will throw
  `OFError.keychainInaccessible`.
- **Allowed app origin.** Native apps must have their **bundle identifier** added to the app
  client in the Openfort dashboard (**Account Management → Configuration → Security**). An empty
  list denies all requests, and the embedded wallet will fail with *"Failed to establish iFrame
  connection."* See [Configure allowed native apps](https://www.openfort.io/docs/configuration/native-apps).

## Account types

When you `configure` an embedded wallet you choose an `accountType` (`OFAccountType`) that
determines its capabilities:

| `accountType` | Gas sponsorship | Batching | Notes |
|---------------|-----------------|----------|-------|
| `.eoa` | No | No | A plain externally-owned account. Chain-agnostic; users pay their own gas. |
| `.smartAccount` | **Yes** | **Yes** | ERC-4337 smart account. Gasless + batching through the embedded provider with no extra setup — recommended for most apps. |
| `.delegatedAccount` | **Yes** | **Yes** | EIP-7702: the user's EOA is delegated to a smart-account implementation (Calibur), so the wallet keeps a single address. Gasless through the provider — the SDK signs the one-time delegation authorization on the first send automatically. |

A **smart account** is the simplest way to get gasless transactions: set
`accountType: .smartAccount`, then pass a [gas sponsorship policy](https://www.openfort.io/docs/configuration/gas-sponsorship)
to the provider and omit `gas`/`gasPrice` (see
[Ethereum Provider & Transactions](#ethereum-provider--transactions)). It is counterfactual until
its first transaction deploys it.

```swift
let account = try await OFSDK.shared.configure(
    params: OFEmbeddedAccountConfigureParams(
        chainId: 84532, // Base Sepolia
        recoveryParams: OFRecoveryParamsDTO(recoveryMethod: .password, password: recoveryPassword),
        accountType: .smartAccount
    )
)
```

## Installation

Adding OpenfortSwift to Your Project (Swift Package Manager)

You can integrate OpenfortSwift into your iOS project using Swift Package Manager (SPM).

**1. Open Your Xcode Project**

- In Xcode, open your project or workspace.
- Select your project file from the Project Navigator.

**2. Add the Package Dependency**

- Go to File > Add Packages...
- In the search field, paste the GitHub repository URL for this SDK:

 ```plaintext
https://github.com/openfort-xyz/swift-sdk.git
 ```

**3. Import the Framework**

 ```swift
import OpenfortSwift
 ```

**4. Configure `OFConfig.plist`**

1. Download the [`OFConfig.plist`](./OFConfig.plist) and add it to your Xcode project.
2. Make sure to select **"Copy items if needed"** when adding the file to your project.
3. Open the file in Xcode and configure the following keys with your own values:
   - **openfortPublishableKey** – Your Openfort publishable key (**required**).
   - **shieldPublishableKey** – Your Shield publishable key (**required**).
   - **debug** – Enable verbose SDK logging (optional, defaults to `false`).
   - **backendUrl** / **iframeUrl** / **shieldUrl** – URL overrides (optional; leave empty unless
     instructed by Openfort). Keys are case-sensitive — note the lowercase `Url`.

**5. Initialize the SDK**

In your AppDelegate:

 ```swift
import UIKit
import OpenfortSwift

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        do {
            try OFSDK.setupSDK()
        } catch {
            // Surfaces actionable setup errors, e.g. OFError.keychainInaccessible or
            // OFError.missingConfiguration. See Requirements above.
            print("Openfort setup failed: \(error.localizedDescription)")
        }

        return true
    }
}
```

**6. Wait until the bridge is ready**

`setupSDK()` returns *before* the embedded WebView bridge has finished loading, so calling SDK
methods immediately can fail. Await readiness (or observe `.openfortReady`) before your first call:

```swift
try await OFSDK.shared.waitUntilReady()
// ...now safe to authenticate, configure the wallet, etc.
```

```swift
// Or observe the notification:
NotificationCenter.default.addObserver(forName: .openfortReady, object: nil, queue: .main) { _ in
    // bridge ready
}
```

## Usage

All methods are available as both async/await and completion handler variants.

### Authentication

```swift
// Email/password login
let response: OFAuthResponse? = try await OFSDK.shared.logInWithEmailPassword(
    params: OFLogInWithEmailPasswordParams(email: "user@example.com", password: "password")
)

// Email/password signup
let response: OFAuthResponse? = try await OFSDK.shared.signUpWithEmailPassword(
    params: OFSignUpWithEmailPasswordParams(email: "user@example.com", password: "password")
)

// Guest signup
let response: OFAuthResponse? = try await OFSDK.shared.signUpGuest()

// Third-party login with ID token
let response: OFAuthResponse? = try await OFSDK.shared.loginWithIdToken(
    params: OFLoginWithIdTokenParams(provider: "firebase", token: idToken)
)

// Email OTP
try await OFSDK.shared.requestEmailOtp(params: OFRequestEmailOtpParams(email: "user@example.com"))
let response: OFAuthResponse? = try await OFSDK.shared.logInWithEmailOtp(
    params: OFLogInWithEmailOtpParams(email: "user@example.com", otp: "123456")
)

// Phone OTP
try await OFSDK.shared.requestPhoneOtp(params: OFRequestPhoneOtpParams(phoneNumber: "+1234567890"))
let response: OFAuthResponse? = try await OFSDK.shared.logInWithPhoneOtp(
    params: OFLogInWithPhoneOtpParams(phoneNumber: "+1234567890", otp: "123456")
)

// OAuth
let oauthResponse = try await OFSDK.shared.initOAuth(
    params: OFInitOAuthParams(provider: "google")
)

// Logout
try await OFSDK.shared.logOut()
```

### User

```swift
let user: OFUser? = try await OFSDK.shared.getUser()
print(user?.email)
print(user?.linkedAccounts) // [OFUserAccount]
```

### Embedded Wallet

```swift
// Configure wallet with password recovery
let account: OFEmbeddedAccount? = try await OFSDK.shared.configure(
    params: OFEmbeddedAccountConfigureParams(
        chainId: 80002,
        recoveryParams: OFRecoveryParamsDTO(recoveryMethod: .password, password: "recovery-password")
    )
)

// Configure wallet with automatic recovery
let account: OFEmbeddedAccount? = try await OFSDK.shared.configure(
    params: OFEmbeddedAccountConfigureParams(
        chainId: 80002,
        recoveryParams: OFRecoveryParamsDTO(recoveryMethod: .automatic, encryptionSession: session)
    )
)

// Sign a message
let signature: String? = try await OFSDK.shared.signMessage(
    params: OFSignMessageParams(message: "Hello, World!")
)

// Get embedded state
let state: Int? = try await OFSDK.shared.getEmbeddedState()

// Export private key
let privateKey: String? = try await OFSDK.shared.exportPrivateKey()

// List accounts
let accounts: [OFEmbeddedAccount]? = try await OFSDK.shared.list()
```

### Ethereum Provider & Transactions

Get an EIP-1193 provider, optionally with a gas-sponsorship policy. The provider exposes an
`async` `request(method:params:)` that returns the result as a `String` (e.g. a transaction hash).
The SDK has no third-party Web3 dependency — `request` is the single JSON-RPC entry point:

```swift
let provider = try await OFSDK.shared.getEthereumProvider(
    params: OFGetEthereumProviderParams(policy: "pol_...") // optional, for gasless tx
)

// Send a transaction (returns the tx hash)
let txHash = try await provider?.request(
    method: "eth_sendTransaction",
    params: [[
        "from": fromAddress,
        "to": toAddress,
        "value": "0x0",
        "data": calldata,
    ]]
)

// Read-only call (returns hex)
let result = try await provider?.request(
    method: "eth_call",
    params: [["to": tokenAddress, "data": balanceOfCalldata], "latest"]
)
```

### Token helpers & on-chain utilities

`OFERC20` and `OFEVM` are dependency-free helpers (plain `URLSession` JSON-RPC) for reading token
state and waiting on transactions. Use any public RPC URL for the target chain.

```swift
let rpc = URL(string: "https://mainnet.base.org")!

// Read a balance and build transfer calldata
let raw = try await OFERC20.balance(token: usdc, owner: wallet, rpcURL: rpc)
let calldata = OFERC20.transfer(to: recipient, amount: OFERC20.baseUnits(1.5, decimals: 6))

// Transfer history (incoming + outgoing) for an owner.
// eth_getLogs is chunked because public Base RPC caps each query at 2000 blocks.
let transfers = try await OFERC20.transferHistory(
    token: usdc, owner: wallet, rpcURL: rpc, blocks: 24_000, chunk: 2_000
)
for t in transfers {
    print(t.isOutgoing ? "sent" : "received", t.value, "in", t.hash)
}

// Wait for a plain transaction to be mined (returns false on timeout)
let mined = try await OFEVM.waitForReceipt(txHash: txHash, rpcURL: rpc, timeout: 60)

// Wait for an ERC-4337 user operation via Openfort's bundler
let opMined = try await OFEVM.waitForUserOperationReceipt(
    userOpHash: userOpHash, chainId: 8453, publishableKey: "pk_...", timeout: 60
)
```

`OFTokenTransfer` exposes `hash`, `from`, `to`, `value` (raw base units as a `String`),
`blockNumber`, and `isOutgoing` (relative to the queried `owner`).

### SIWE (Sign-In with Ethereum)

```swift
// Initialize SIWE
let siweInit: OFSIWEInitResponse? = try await OFSDK.shared.initSIWE(
    params: OFInitSIWEParams(address: walletAddress)
)

// Login with SIWE
let response: OFAuthResponse? = try await OFSDK.shared.loginWithSiwe(
    params: OFLoginWithSiweParams(
        signature: signature,
        message: siweMessage,
        walletClientType: "metamask",
        connectorType: "injected",
        address: walletAddress
    )
)
```

### Funding (cross-chain deposit)

Fund an embedded wallet from any chain or a centralized exchange. `OFFunding` is an
`ObservableObject` — the SwiftUI counterpart of `@openfort/react`'s `useFunding` hook — that
creates a deposit session, sets a payment method, and polls until it settles, publishing
`session` / `status` / `loading` / `error`. Funding authenticates with the project publishable
key, so it works for guest and authenticated users alike.

```swift
let funding = OFFunding() // hold with @StateObject in a View

// EVM → EVM (e.g. fund a Base USDC wallet from Polygon USDC)
let session = try await funding.fund(
    OFFundingTarget(
        chain: "eip155:8453",                                   // Base
        currency: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", // USDC
        address: walletAddress
    ),
    .evm(source: OFFundingSource(
        chain: "eip155:137",                                    // from Polygon
        currency: "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359", // USDC
        amount: "10000000"                                      // 10 USDC (base units)
    ))
)
// session.paymentMethod?.receiverAddress — address the user sends to
// session.paymentMethod?.addressUri      — BIP-21 / EIP-681 / Solana Pay URI for a QR
// session.paymentMethod?.deeplinks       — prefilled wallet deeplinks
```

In SwiftUI, hold it with `@StateObject` and observe `funding.status` / `funding.session` /
`funding.loading` to drive the screen. Centralized-exchange deposits use a session-bound
Coinbase pay-link:

```swift
let session = try await funding.createSession(target)
let url = try await funding.payLink(OFPayLinkParams(sessionId: session.id, amount: "25"))
// open `url`, then watch the session settle:
try await funding.track(id: session.id, clientSecret: session.clientSecret)
```

The lower-level namespace is also available directly on `OFSDK.shared` for headless use:
`fundingCreateSession`, `fundingSetPaymentMethod`, `fundingGetSession`, `fundingPayLink`, and
`fundingChains` (each with `async` and completion-handler variants).

## Types

### Response Types

| Type | Description |
|------|-------------|
| `OFAuthResponse` | Auth response with `token`, `user`, `session`, `action` |
| `OFUser` | User profile with `id`, `email`, `name`, `linkedAccounts` |
| `OFUserAccount` | Linked account entry (provider, email, address, etc.) |
| `OFSession` | Auth session with `id`, `token`, `userId`, `expiresAt` |
| `OFEmbeddedAccount` | Embedded wallet account with `address`, `chainType`, `accountType` |
| `OFSIWEInitResponse` | SIWE init response with `address`, `nonce` |
| `OFFundingSession` | Deposit session with `status`, `clientSecret`, `target`, `paymentMethod` |

### Enums

| Enum | Values |
|------|--------|
| `OFEmbeddedState` | `.none`, `.unauthenticated`, `.embeddedSignerNotConfigured`, `.creatingAccount`, `.ready` |
| `OFRecoveryMethod` | `.password`, `.automatic`, `.passkey` |
| `OFAccountType` | `.eoa`, `.smartAccount` |
| `OFChainType` | `.evm`, `.svm` |

### Errors

`OFError` conforms to `LocalizedError`, so `error.localizedDescription` is user-readable:

| Case | When |
|------|------|
| `.keychainInaccessible(status:)` | The app can't use the Keychain (unsigned simulator build, missing entitlement — see Requirements). |
| `.missingConfiguration(_:)` | `OFConfig.plist` is missing, unreadable, or missing required keys. |
| `.notReady(_:)` | `waitUntilReady()` timed out, or the WebView bridge failed to load. |
| `.encodingFailed` | A request payload could not be encoded. |

## License

[MIT](LICENSE)
