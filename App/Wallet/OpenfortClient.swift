import Foundation
import OpenfortSwift

/// Thin async wrapper over `OFSDK`. Centralizes the two awkward bits of the SDK: waiting for
/// the WebView bridge to be ready before any call (FRICTION_LOG #3), and bridging the
/// callback-based EIP-1193 provider back into async/await (FRICTION_LOG #6).
@MainActor
enum OpenfortClient {
    /// Base Sepolia gas-sponsorship policy (MAIN project), so sends are gasless.
    static let gasPolicy = "pol_e62f490a-eb28-45e6-8134-50681c65ee49"

    struct ClientError: LocalizedError { let message: String; var errorDescription: String? { message } }

    // MARK: - Readiness

    /// Blocks until the SDK's WebView bridge finishes loading `openfort.js`. The SDK has no
    /// `await ready()` API, so we poll `isInitialized`.
    static func awaitReady(timeout: TimeInterval = 12) async throws {
        let start = Date()
        while !OFSDK.shared.isInitialized {
            if Date().timeIntervalSince(start) > timeout {
                throw ClientError(message: "Openfort SDK did not become ready in time.")
            }
            try await Task.sleep(nanoseconds: 120_000_000)
        }
    }

    // MARK: - Auth (Email OTP)

    static func requestEmailOTP(_ email: String) async throws {
        try await awaitReady()
        try await OFSDK.shared.requestEmailOtp(params: OFRequestEmailOtpParams(email: email))
    }

    static func verifyEmailOTP(email: String, code: String) async throws {
        _ = try await OFSDK.shared.logInWithEmailOtp(
            params: OFLogInWithEmailOtpParams(email: email, otp: code)
        )
    }

    static func currentEmail() async -> String? {
        (try? await OFSDK.shared.getUser())??.email
    }

    static func logOut() async throws {
        try await OFSDK.shared.logOut()
    }

    // MARK: - Wallet

    /// Creates or recovers the embedded wallet on Base Sepolia as an **EOA** (password recovery;
    /// the password lives in the Keychain). The EOA is upgraded to a smart account at send time via
    /// EIP-7702 (`sendDelegatedTransaction`), so the wallet address is the EOA that gets delegated
    /// and that the user funds.
    /// Fixed demo recovery password. A production app uses automatic recovery (a backend
    /// encryption-session) or a user-chosen password; a constant keeps this single-device testnet
    /// demo deterministic and reset-proof (a random per-device password breaks recovery whenever
    /// the Keychain is cleared).
    private static let recoveryPassword = "openfort-cash-demo-recovery-v1"

    @discardableResult
    static func configureWallet() async throws -> OFEmbeddedAccount? {
        // EOAs are chain-agnostic — Openfort rejects a `chainId` for the EOA account type.
        try await OFSDK.shared.configure(
            params: OFEmbeddedAccountConfigureParams(
                recoveryParams: OFRecoveryParamsDTO(
                    recoveryMethod: .password,
                    password: recoveryPassword
                ),
                accountType: .eoa
            )
        )
    }

    /// The first embedded account (used when the wallet is already configured on app relaunch
    /// and we never called `configure` this session).
    static func walletAccount() async throws -> OFEmbeddedAccount? {
        try await OFSDK.shared.list()?.first
    }

    static func exportPrivateKey() async throws -> String? {
        try await OFSDK.shared.exportPrivateKey()
    }

    // MARK: - Send (gasless USDC transfer via EIP-7702)

    /// Sends USDC gaslessly via EIP-7702: the SDK signs a one-time delegation authorization and
    /// submits a sponsored user operation through Openfort's bundler + paymaster. Returns the hash.
    static func sendUSDC(from: String, to: String, amount: Decimal) async throws -> String {
        try await OFSDK.shared.sendDelegatedTransaction(
            to: EVM.usdc,
            data: EVM.transferCalldata(to: to, amountBaseUnits: EVM.toBaseUnits(amount)),
            value: "0x0",
            policy: gasPolicy
        )
    }

    /// Sends USDC as a **normal, non-sponsored** transaction through the EIP-1193 provider with no
    /// gas policy — the wallet's EOA pays its own gas (requires Base Sepolia ETH). Returns the hash.
    static func sendUSDCNormal(from: String, to: String, amount: Decimal) async throws -> String {
        let provider = try await OFSDK.shared.getEthereumProvider(params: OFGetEthereumProviderParams())
        guard let provider else { throw ClientError(message: "No Ethereum provider.") }
        // A chain-agnostic EOA with no stored chainId defaults to Base mainnet, so switch it to
        // Base Sepolia before sending.
        _ = try await provider.request(
            method: "wallet_switchEthereumChain",
            params: [["chainId": EVM.chainHex]]
        )
        let tx: [String: String] = [
            "from": from,
            "to": EVM.usdc,
            "value": "0x0",
            "data": EVM.transferCalldata(to: to, amountBaseUnits: EVM.toBaseUnits(amount)),
        ]
        guard let hash = try await provider.request(method: "eth_sendTransaction", params: [tx]) else {
            throw ClientError(message: "Transaction returned no hash.")
        }
        return hash
    }
}
