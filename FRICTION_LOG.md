# Openfort Swift SDK — Friction Log

A running log of developer-experience friction encountered while building **Cash** (a
Cash App–style iOS wallet) on top of `OpenfortSwift`. Kept in parallel with the build so
it can feed back into the SDK.

- **SDK under test:** `github.com/openfort-xyz/swift-sdk` @ `1.0.0` (CHANGELOG dated 2026-02-06)
- **Build target:** native SwiftUI iOS app, iOS 16+, Email-OTP auth, USDC on Base Sepolia (84532)
- **App goal:** real auth → real embedded wallet → live USDC balance, Send flow wired to the SDK

Severity legend: 🔴 blocker · 🟠 major · 🟡 minor · 🔵 doc/papercut

---

## Scoreboard

| # | Severity | Area | One-line |
|---|----------|------|----------|
| 16 | 🔴 | Provider | **Every transaction fails.** Two bugs: (a) `send` passes an async-IIFE **Promise to `evaluateJavaScript`** → `WKError 5`; (b) it calls **`window.openfort.getEthereumProvider`**, which doesn't exist — the method is on `window.openfort.embeddedWalletInstance` (what the SDK's own bridge uses) → "provider not available". |
| 17 | ✅ | 7702 | Stock Swift can't do 7702 (no `signAuthorization`) → `AA24`. **Fixed in fork**: bundled `viem` + `OFSDK.shared.sendDelegatedTransaction(...)`, signing the authorization **natively via the embedded signer (no key export)**, chain-parameterized. Pending on-chain verification. |
| 14 | 🔴 | Errors | `requestEmailOtp` fails with opaque `INVALID_CONFIGURATION` that is really a **swallowed keychain error** (`errSecMissingEntitlement -34018`). Took source-diving + a keychain probe to find. The #1 DX failure. |
| 15 | 🟠 | Setup | Embedded wallet needs the app's **bundle id whitelisted in the dashboard** (Security → app client). Not in the SDK README; only surfaces as an iframe timeout *after* you've built and logged in. (The error message itself is good.) |
| 1 | 🔴 | Config | Shipped sample `OFConfig.plist` is missing the required `debug` key → SDK silently boots unconfigured |
| 2 | 🟠 | Config | Sample plist URL keys are miscased (`shieldURL`) vs decoded property (`shieldUrl`) → overrides silently ignored |
| 3 | 🟠 | Init | `setupSDK()` returns before the JS bridge is ready; readiness only via an undocumented `NotificationCenter` name; README usage ignores the race |
| 4 | 🟠 | Architecture | "Native Swift SDK" is a hidden `WKWebView` running `openfort.js`; not documented, leaks into mental model, startup cost |
| 5 | ✅ | State | ~~1-second polling `Timer`~~ **Fixed in fork**: event-driven via openfort-js lifecycle events + a bounded backstop poll (no more always-on busy loop). |
| 6 | 🟠 | Provider | EIP-1193 provider is completion-handler based while the rest of the SDK is `async/await`; leaks Boilertalk `Web3.swift` types into app code |
| 7 | ✅ | Wallet | ~~No token/balance helpers~~ **Fixed in fork**: added `OFERC20` (dependency-free `balanceOf`/`transfer`/`decimals` calldata + `eth_call` reads). |
| 8 | 🟡 | Recovery | Automatic recovery requires you to stand up a backend encryption-session endpoint; no local/dev story |
| 9 | 🔵 | Docs | Method/name drift across docs: `initialize()` vs `setupSDK()`; plist key casing; provider shown as async in skill but is callback-based |
| 10 | 🔵 | DX | No example app shipped in the SDK repo to copy mounting/wiring from |
| 11 | 🟡 | Architecture | WebView bridge works detached (no manual mount needed) — **verified at runtime** — but this isn't documented, so every integrator wonders |
| 12 | 🟠 | Wallet | No transaction-history API — an activity feed (table stakes for a wallet) has to come from an external indexer |
| 13 | 🟠 | Deps | Using the provider pulls a huge transitive tree (swift-nio, PromiseKit, CryptoSwift, secp256k1, swift-certificates, BigInt…) into a consumer app |

(Build- and runtime-verified entries follow. See "Runtime verification" at the bottom.)

---

## 15. 🟠 Embedded wallet needs the bundle id whitelisted in the dashboard — undocumented in the SDK

After login, `configure()` fails with:

> Failed to establish iFrame connection: Connection timed out after 10000ms … You must
> configure your origin in the openfort dashboard before using the embedded wallet.

For native apps the "origin" is the **bundle identifier** (`io.openfort.cashdemo`), which must be
added under **Dashboard → Account Management → Configuration → Security → app client**
(per the publishable key). An empty list denies all requests. This is a hard prerequisite for
the Swift/RN/Unity SDKs, but:

- It is **not mentioned anywhere in the Swift SDK README or the `OFConfig.plist` setup**, even
  though it's required for the embedded wallet to work at all.
- It's **dashboard-only** — no documented API/CLI to register an origin, so it can't be scripted
  into a project setup flow.
- It only surfaces **at runtime, after** you've installed and authenticated — late in the loop.

Credit where due: unlike #14, this error message is clear, names the platforms, and links the
docs. The friction is purely that the requirement isn't surfaced earlier (README / quickstart /
an API to set it).

**Fix:** add bundle-id setup to the Swift quickstart, and expose an API/CLI for app origins so
project bootstrap can be automated.

---

## 16. 🔴 `provider.send` hands a Promise to `evaluateJavaScript` → every transaction fails

Sending USDC (gasless, 7702) failed with:

> requestFailed(Error Domain=WKErrorDomain Code=5 "JavaScript execution returned a result of an
> unsupported type")

`OpenfortEIP1193Web3Provider.send` builds an **async IIFE** and runs it with
`webView.evaluateJavaScript(...)`:

```js
(async function(){ ... return { ok: true, result }; })();   // returns a Promise
```

`evaluateJavaScript(_:completionHandler:)` does **not** await Promises — it tries to bridge the
Promise object back to native and fails with `WKError.javaScriptResultTypeIsUnsupported` (code 5).
So **no transaction can ever succeed** through the provider on current iOS/WebKit. (The new async
`request` helper from #6 had the same latent bug.)

**Fix:** use `callAsyncJavaScript`, which runs the body as an async function and resolves the
returned promise before calling back. Applied in the fork to both `send` and `request`:

```swift
webView.callAsyncJavaScript(body, arguments: [:], in: nil, in: .page, completionHandler: { result in
    // result is the *resolved* value, not a Promise
})
```

**Second bug (the real killer):** even after the `callAsyncJavaScript` fix, sends failed with
`"Openfort provider not available in page"`. The provider JS calls
`window.openfort.getEthereumProvider(...)` — but that method doesn't exist on `window.openfort`.
The SDK's *own* working bridge (`openfort-sync.js`) calls
`window.openfort.embeddedWalletInstance.getEthereumProvider(...)`. So the provider's `send`/`request`
used the wrong access path from day one and could never have worked. (The content-world detour I
chased — `.page` vs `.defaultClient` — was a red herring caused by this wrong path always throwing
before the world ever mattered.)

**Final fix:** run the request in the page's default world via `evaluateJavaScript` (the same path
the SDK's other bridges use, where `window.openfort` lives), kick off the async work, stash the
settled result on `window`, and poll for it — then call the correct
`embeddedWalletInstance.getEthereumProvider`. Verified end-to-end: the send now reaches Openfort's
bundler + paymaster (confirmed by an on-chain `AA24` response, see #17).

---

## 17. 🟠 EIP-7702 delegated accounts can't transact from the Swift SDK

`configure(accountType: .delegatedAccount)` succeeds, but sending fails on-chain with
`UserOperation reverted with reason: AA24 signature error`. Per the docs, a Delegated Account's
**first** transaction on a chain must include a **one-time EIP-7702 authorization**
(signed via React's `use7702Authorization`). The Swift SDK has no equivalent, and the bundled
`openfort.js` (openfort-js v1.1.5) contains **no `signAuthorization` / 7702 API at all** (grep:
zero hits). So the userop is submitted without the authorization → the EOA isn't delegated →
`validateUserOp` fails → AA24.

This means **true 7702 is not achievable on the current Swift SDK**, for either path:
- The "automatic" path (`DELEGATED_ACCOUNT` + provider `eth_sendTransaction`) never signs the authorization.
- The "manual" path (React's `use7702Authorization` + viem bundler) has no Swift counterpart.

**Fix (SDK enhancement, not a quick patch):** ship a 7702-capable `openfort.js` bundle, add a Swift
`signAuthorization` / `use7702Authorization` equivalent, and thread the authorization into the
delegated-account send.

**Workaround used in the demo:** `accountType: .smartAccount` (ERC-4337). Smart accounts get the
same gasless, sponsored UX through the embedded provider with no authorization step — verified the
paymaster accepts the policy (the AA24 above is a *signature* error, not a policy rejection).

---

## 14. 🔴 `INVALID_CONFIGURATION` is a swallowed keychain entitlement error

**The single worst DX moment of the build.** Tapping "Send code" (`requestEmailOtp`) failed with
an alert reading only `INVALID_CONFIGURATION` — which screams "wrong API keys / dashboard
misconfiguration" and sends you hunting in completely the wrong place.

The real cause chain, found only by reading the bundled `openfort.js` + native source and then
writing a keychain probe:

1. openfort-js gates the first auth call on `initializeAsync()`:
   ```js
   if (!await Si.isStorageAccessible(this.storage))
       throw new vr("Storage is not accessible", INVALID_CONFIGURATION);
   ```
2. `isStorageAccessible` writes a test key and reads it back through the SDK's bridged
   `KeychainStorage`, which calls native `OFKeychainHelper`.
3. `OFKeychainHelper.save` **discards the `SecItemAdd` OSStatus entirely** (no error check), so
   when the keychain write fails the SDK has no idea.
4. On a simulator app built without code-signing/entitlements, every `SecItem*` call returns
   **`errSecMissingEntitlement` (-34018)**. Proven with a probe mirroring the SDK's exact query:
   `[KCTEST] add=-34018 get=-34018 match=false`.
5. So the test read returns `nil`, `isStorageAccessible` is `false`, and the user sees
   `INVALID_CONFIGURATION` with zero connection to the true cause.

**Two SDK fixes:**
- `OFKeychainHelper` should check `SecItemAdd`/`SecItemCopyMatching` status and the SDK should
  surface it (e.g. "Keychain not accessible (-34018): enable the Keychain Sharing capability or
  sign the app"), not collapse everything to `INVALID_CONFIGURATION`.
- Document that the host app needs keychain access (entitlement / signing) — this is a hard
  requirement because the SDK stores all session state in the Keychain, but it's undocumented.

**Bonus latent bug:** `isStorageAccessible` calls `e.save(t, r)` **without `await`** before
`await e.get(t)`. With the SDK's async bridged storage this is a race; it only "works" because
native delivers the Save and Get messages in order. Awaiting the save would be correct.

**Fix applied in this app:** ad-hoc sign the simulator build and add a `keychain-access-groups`
entitlement (`App/OpenfortCash.entitlements`, `CODE_SIGN_IDENTITY = "-"`). Verified:
`[KCTEST] add=0 get=0 match=true` and `[SMOKE] requestEmailOTP OK`.

---

## 1. 🔴 Shipped `OFConfig.plist` omits required `debug` key → silent total failure

**Where:** `Sources/OpenfortSwift/WebView/OFConfig.swift` vs the repo-root `OFConfig.plist`

```swift
internal struct OFConfig: Codable {
    let openfortPublishableKey: String
    let shieldPublishableKey: String
    let debug: Bool            // <-- NON-optional
    ...
    static func loadFromMainBundle() -> OFConfig? {
        ... PropertyListDecoder().decode(OFConfig.self, ...)   // throws if `debug` absent
    }
}
```

The sample `OFConfig.plist` in the repo root contains only
`backendURL, iframeURL, openfortPublishableKey, shieldPublishableKey, shieldURL` — **no
`debug`**. Because `debug` is a non-optional `Bool` with no default and there is no
`decodeIfPresent`, the decode throws `keyNotFound`, `loadFromMainBundle()` catches it and
returns `nil`, and `openfortSyncScript()` returns an empty string. The WebView then loads
with **no `new Openfort({...})` ever constructed** — `window.openfort` is undefined and
every subsequent call fails. The only signal is a `print("Failed to decode OFConfig.plist")`
to the console.

**Impact:** A developer who follows the README literally ("Download the `OFConfig.plist`
and add it to your project") ends up with a silently dead SDK. First-run TTHW is spent
hunting a `print` statement.

**Fix options (pick one):**
- Make `debug` optional with a default: `let debug: Bool?` and read `config.debug ?? false`.
- Ship a sample plist that includes `<key>debug</key><false/>`.
- Fail loudly: surface the decode error through `setupSDK()` as a thrown error instead of `print` + `nil`.

**Workaround used in this app:** added `<key>debug</key><true/>` to `App/Resources/OFConfig.plist`.

---

## 2. 🟠 Sample plist URL keys are miscased and silently ignored

`OFConfig` decodes `backendUrl`, `iframeUrl`, `shieldUrl` (lowercase `rl`). The shipped
sample plist uses `backendURL`, `iframeURL`, `shieldURL` (uppercase `URL`). With no
`CodingKeys` and no `keyDecodingStrategy`, these never match, so any override placed in the
sample plist is silently dropped. They're optional, so it's not fatal — but it means the
documented override mechanism doesn't work if you copy the sample verbatim.

**Fix:** align the sample plist keys with the decoded property names (or add `CodingKeys`).

---

## 3. 🟠 `setupSDK()` returns before the bridge is ready; readiness is undocumented

`OFSDK.setupSDK()` is synchronous and returns immediately, but it only kicks off an async
`WKWebView` load of the bundled `index.html` + `openfort.js`. Readiness is signalled by a
`NotificationCenter` post named `"openfortReady"` (failure: `"openfortInitError"`) — a bare
string, not a public `Notification.Name` constant, and not mentioned in the README's Usage
section, whose examples call `logInWithEmailPassword` right after `setupSDK()`. Calling any
method before the bridge loads fails.

**Fix:** expose `await OFSDK.shared.ready()` (or an `isReady` publisher) and document it;
publish public `Notification.Name` constants.

**Workaround used:** poll `OFSDK.shared.isInitialized` with a timeout before first call.

---

## 4. 🟠 The "native" SDK is a hidden WebView bridge (undocumented)

`OFSDK` creates an `OFWebView: WKWebView` at `frame: .zero`, injects `openfort.js` and a
sync shim, and every Swift method is a thin wrapper over `webView.evaluateJavaScript("window.xxxSync(...)")`.
This is never stated in the README. Implications a developer should know up front: a live
WebView lives for the app's lifetime; calls cross a JS serialization boundary; errors can
originate in JS; and the provider/state all depend on the page staying alive. The WebView is
**not** added to any view hierarchy by the SDK (see #11 for whether that's a problem).

**Fix:** document the architecture and its consequences (lifetime, threading, debugging).

---

## 6. 🟠 EIP-1193 provider is callback-based and leaks `Web3.swift` types

Everything in the SDK is `async throws` — except sending a transaction. `getEthereumProvider`
returns an `OpenfortEIP1193Web3Provider` whose only entry point is:

```swift
@MainActor public func send<Params, Result: Sendable>(
    request: RPCRequest<Params>,
    response: @escaping Web3ResponseCompletion<Result>)
```

`RPCRequest` and `Web3Response` are Boilertalk `Web3.swift` types, so an app that just wants
to send USDC must depend on (and learn) Web3.swift, hand-build a generic `RPCRequest`, and
bridge a completion handler back into async/await. Heterogeneous `eth_call` params (an object
plus a `"latest"` string) are especially awkward to express through the generic `Params`.

**Fix:** offer an `async` `request(method:params:) -> JSONValue` on the provider that doesn't
expose Web3.swift, mirroring the JS `provider.request({method, params})` it already calls
internally.

---

## 7. 🟠 No token / balance helpers in a payments SDK

The README headline is "embedded wallets, with built-in authentication and **payments**
capabilities." Yet to show a balance or send a stablecoin you must: know the USDC contract
address, hand-encode `balanceOf(address)` (`0x70a08231` + padded addr), `eth_call` it, decode
the 32-byte hex, divide by 10^6; and to send, hand-encode `transfer(address,uint256)`
(`0xa9059cbb` + padded args). For a money-movement product this is the single most common
operation and there is no abstraction for it.

**Fix:** ship a minimal token helper (`balanceOf`, `transfer`, decimals) or at least an
ABI-encode utility, so "send 5 USDC" isn't 40 lines of byte-packing.

---

## 8. 🟡 Automatic recovery has no local/dev story

`OFRecoveryMethod.automatic` requires an `encryptionSession` string minted by a backend that
holds the Shield secret. There is no documented way to develop against automatic recovery
without first deploying that endpoint. For a from-scratch app the only backend-free path is
`.password`, which then forces you to invent your own password-management UX.

**Workaround used:** `.password` recovery with a random password generated once and stored in
the iOS Keychain, so it stays invisible to the user (single-device only).

---

## 11. 🟡 WebView works detached, but nobody tells you that

`OFWebView` is created at `frame: .zero` and never added to a view hierarchy by the SDK.
A first integrator can't know whether JS will actually execute in a detached WKWebView (it's
a common source of bugs), so the safe assumption is "I must mount it somewhere invisible."

**Verified at runtime:** it works detached — the app reached `unauthenticated` and the SDK
logged `✅ WebView finished loading.` with no manual mounting. Good news, but it should be
stated explicitly in the docs so people don't add a defensive hidden WebView (as I almost did).

---

## 12. 🟠 No transaction-history API

A wallet's home screen needs an activity feed; Cash App's whole second tab is history. The SDK
returns transaction *hashes* from sends but offers no way to list a wallet's past transfers.
This app's Activity screen had to fall back to "No activity yet" + a BaseScan deep link.

**Fix:** a `transactions(for:)` / activity endpoint, or document the recommended indexer.

---

## 13. 🟠 The provider drags in a heavy transitive dependency tree

Adding the EIP-1193 send path pulled these into the app's resolved graph (via Boilertalk
Web3.swift): `swift-nio`, `swift-nio-ssl`, `swift-nio-http2`, `swift-certificates`,
`swift-asn1`, `swift-crypto`, `CryptoSwift`, `PromiseKit`, `BigInt`, `secp256k1`,
`websocket-kit`, `swift-async-algorithms`, and more. That's a large surface and a noticeable
first-build cost for an app that only wants to send a token. Compounds with #6 (provider
shouldn't expose Web3.swift types at all).

**Fix:** keep Web3.swift internal to the SDK and expose a dependency-free `request(method:params:)`.

---

## 9 / 10 — Doc drift & missing example app

- The embedded-wallet skill shows `OFSDK.initialize()`; the real method is `OFSDK.setupSDK()`.
- Skill shows `sdk.getEthereumProvider(policy:)` returning a provider you `await`-send on; the
  real provider is callback-based (see #6).
- Plist key casing differs between sample and decoder (see #2).
- The SDK repo ships no example app, so there's no reference for mounting the WebView, gating
  on readiness, or wiring a SwiftUI lifecycle — all of which a first integrator must invent.

---

## Runtime verification (what actually happened)

Built with `xcodegen` + `xcodebuild` against the iOS 26.3 simulator (iPhone 17). Package
resolution pulled `OpenfortSwift 1.0.1` (newer than the `1.0.0` floor).

Two real compile errors during the build, both in app code, neither from the SDK:
1. `switch must be exhaustive` — `OFEmbeddedState.none` collides with `Optional.none` when
   switching over `OFEmbeddedState?`. Not the SDK's fault, but naming a case `none` on an enum
   that's almost always used as an Optional is a sharp edge worth a 🔵 note.
2. (self-inflicted) used iOS-17 `ContentUnavailableView` on an iOS-16 target.

On launch (no code changes to the SDK, no manual WebView mount):
- `OFSDK.setupSDK()` in the AppDelegate started the bridge.
- The SDK logged `✅ WebView finished loading.`
- `embeddedStatePublisher` moved to `.unauthenticated`, the router showed the sign-in screen.
- **Confirms #1 was a real blocker:** the only reason this worked is the hand-added
  `<key>debug</key><true/>` in `OFConfig.plist`. With the repo's stock sample plist the decode
  would have thrown and the screen would have stayed on the launch splash forever.

Still to verify interactively (needs a human inbox for the OTP): `requestEmailOtp` →
`logInWithEmailOtp` → auto-`configure` → `.ready` → live balance. The full path is wired; only
the email code entry is human-in-the-loop.

### Suggested upstream priorities
1. **#14** stop collapsing keychain failures into `INVALID_CONFIGURATION`; check `SecItem`
   status, surface -34018 with a fix hint, and document that the host app needs keychain access.
   This is the one that actually blocks a new integrator from logging in at all.
2. **#1** ship/repair the sample `OFConfig.plist` (or make `debug` optional) — silent total failure.
3. **#6 + #13** give the provider a dependency-free async `request(method:params:)`.
4. **#3** expose `await ready()` and public `Notification.Name`s; fix the README race.
5. **#7 + #12** add token balance/transfer + activity helpers for the "payments" story.
6. **#4 + #11** document the WebView architecture (and that detached execution is fine).
