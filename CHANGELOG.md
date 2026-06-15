# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0] - 2026-06-15

Surfaced by dogfooding the SDK to build a Cash App–style wallet.

### Breaking Changes

- **Removed the `Web3.swift` dependency.** This also drops the transitive
  swift-nio, PromiseKit, CryptoSwift, secp256k1, and BigInt dependencies.
- **`OpenfortEIP1193Web3Provider` no longer conforms to `Web3Provider`** and no
  longer exposes `Web3`/`Boilertalk` types. The completion-based
  `send(request: RPCRequest, response:)` API and the `Web3ResponseCompletion`
  typealias are removed, replaced by `request(method:params:) async throws -> String?`.
- `OpenfortEIP1193Web3Provider.init` no longer takes a `callbackQueue`; it now
  takes an optional `getProviderParams`.
- `OFConfig`'s `debug` key is now optional (the sample `OFConfig.plist` shipped
  without it, which previously failed to decode and left the SDK unconfigured).

### New

- **Native EIP-7702 / Calibur gasless sends.** Upgraded the vendored
  `openfort.js` bundle from 1.1.5 to 1.3.7, so a `.delegatedAccount` gasless send
  through `provider.request("eth_sendTransaction", policy)` signs the first-send
  7702 authorization in `sendCallsSync` (no longer reverts `AA24`). Removed the
  782KB bundled-viem workaround and `OF7702Sender` (net JS −390KB). Rebuildable
  via `js-src/openfort-entry.js`.
- `OFERC20` — token balances, `transfer` calldata, and `transferHistory`
  (chunked `eth_getLogs`) returning `[OFTokenTransfer]` for activity feeds.
- `OFEVM` — `waitForReceipt` and `waitForUserOperationReceipt` (Openfort bundler)
  so the UI can settle after a send.
- `waitUntilReady(timeout:)` plus public `.openfortReady` / `.openfortInitError`
  notifications. Embedded-wallet readiness is now event-driven (lifecycle events
  with a bounded backstop) instead of a 1s polling timer.

### Fixes

- `requestEmailOtp` no longer fails with an opaque `INVALID_CONFIGURATION` that
  masked a keychain error. `OFKeychainHelper.save` returns its `OSStatus` and
  `setupSDK()` throws a clear `OFError.keychainInaccessible` (e.g. on
  `errSecMissingEntitlement -34018`).
- `OFScriptMessageProcessor` decodes bare array responses (`list()` returns an
  array in openfort-js ≥1.3.2).
- Adapted to renamed JS SIWE methods (`initSIWE`→`initSiwe`,
  `authenticateWithSIWE`→`loginWithSiwe`).
- `OFError` now conforms to `LocalizedError`.

## [1.0.0] - 2026-02-06

### Breaking Changes

**Type renames** (aligned with openfort-js SDK naming):
- `OFAuthorizationResponse` → `OFAuthResponse`
- `OFGetUserInstanceResponse` → `OFUser`
- `OFUserLinkedAccount` → `OFUserAccount`
- `OFAuthSession` → `OFSession`
- `OFInitSIWEResponse` → `OFSIWEInitResponse`
- `OFConfigureEmbeddedWalletDTO` → `OFEmbeddedAccountConfigureParams`
- `OFAuthEmailPasswordParams` → `OFLogInWithEmailPasswordParams`
- `OFSignUpResponse` is now a typealias for `OFAuthResponse`

**Method renames**:
- `loginWith(params:)` → `logInWithEmailPassword(params:)`
- `signUpWith(params:)` → `signUpWithEmailPassword(params:)`

**DTO fixes** (params now match JS SDK signatures):
- `OFResetPasswordParams`: changed from `{email, password, state}` to `{password, token}`
- `OFVerifyEmailParams`: changed from `{email, state}` to `{token, callbackURL?}`
- `OFStoreCredentialsParams`: changed from `{provider, token, tokenType, ecosystemGame}` to `{token, userId}`

**Removed methods** (did not exist in JS SDK):
- `linkEmailPassword(params:)`
- `unlinkEmailPassword(params:)`
- `linkThirdPartyProvider(params:)`

### New Methods

- `requestEmailOtp(params:)` — Request an email OTP
- `logInWithEmailOtp(params:)` — Log in with email OTP
- `requestPhoneOtp(params:)` — Request a phone OTP
- `logInWithPhoneOtp(params:)` — Log in with phone OTP
- `linkPhoneOtp(params:)` — Link a phone number via OTP
- `verifyEmailOtp(params:)` — Verify email with OTP
- `loginWithSiwe(params:)` — Log in with Sign-In with Ethereum
- `initLinkSiwe(params:)` — Initialize SIWE wallet linking
- `linkWithSiwe(params:)` — Link a wallet via SIWE
- `addEmail(params:)` — Add an email to the account

### Fixes

- Response models now match actual JS SDK return shapes instead of backend OpenAPI types
- Auth methods correctly decode `{token, user, session}` responses
- `createdAt` fields handle both integer timestamps and ISO string dates via `FlexTimestamp`
- JS error messages are now forwarded to Swift callers
- Added `safeCall` wrapper in JS bridge to catch synchronous errors
- Regenerated `openfort.js` bundle from latest openfort-js v1.1.5

## [0.0.1] - 2025-09-08

Public Launch
