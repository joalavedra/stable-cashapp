<div align="center">

# Stable CashApp

**A Cash App–style stablecoin wallet for iOS — gasless USDC payments via native EIP-7702, built on the [Openfort](https://www.openfort.io) Swift SDK.**

<img src="assets/home.png" width="300" alt="Stable CashApp home screen" />

</div>

## What it is

A native SwiftUI iOS app that looks and feels like Cash App, but moves **USDC on Base Sepolia** through an Openfort embedded wallet. Email-OTP login, an embedded wallet created on device, a live balance, an activity feed, and **gasless payments** — the user never holds ETH or signs a gas prompt.

Payments use **EIP-7702**: the embedded EOA is delegated to a smart-account implementation and the user operation is sponsored by an Openfort gas policy, so the recipient gets the full amount.

## Features

- 📧 **Email-OTP sign-in** — no passwords, no seed phrases
- 👛 **Embedded wallet** — created/recovered on device (password recovery in the Keychain)
- ⚡ **Gasless EIP-7702 payments** — one-time authorization signed natively by the embedded signer (no key export), sponsored via Openfort's bundler + paymaster
- 💵 **Live USDC balance** + **activity feed** (on-chain `Transfer` history)
- 📲 The iconic Cash App number pad, Pay / Request, QR receive, profile, key export

## Architecture

| Layer | What |
|---|---|
| `App/Wallet/OpenfortClient.swift` | Thin async wrapper over `OFSDK` — readiness gate, email OTP, wallet configure, gasless `sendUSDC` |
| `App/Wallet/WalletStore.swift` | `ObservableObject` driven by the SDK's embedded-state events |
| `App/Wallet/EVM.swift` | ERC-20 calldata + JSON-RPC reads (balance, code, transfer history) |
| `App/Views/*` | The Cash App UI (home/number pad, send, receive, activity, profile) |

Built on the [Openfort Swift SDK](https://github.com/openfort-xyz/swift-sdk) (v2.0.0), which provides native EIP-7702 gasless sends and dependency-free ERC-20 helpers.

## Build & run

Requires Xcode 26+, [`xcodegen`](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
open OpenfortCash.xcodeproj   # then Run, or:

xcodebuild build -project OpenfortCash.xcodeproj -scheme OpenfortCash \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build
```

> The app must be **signed** (it ships a `keychain-access-groups` entitlement and signs ad-hoc) — the SDK stores session state in the Keychain. To try a real payment, fund the EOA address shown under **Account** with [Base Sepolia USDC](https://faucet.circle.com/).

## Notes

This is a **testnet demo**. `App/Resources/OFConfig.plist` contains *publishable* Openfort keys (client-safe, no secrets). Not production-hardened — recovery is single-device and keys are bundled for convenience.
