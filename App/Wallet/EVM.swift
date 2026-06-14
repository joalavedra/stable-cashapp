import Foundation

/// Chain + token constants and the hand-rolled ERC-20 encoding the SDK doesn't provide.
/// See FRICTION_LOG #7 — a payments SDK leaving balance/transfer to the app.
enum EVM {
    static let chainId = 84532                                  // Base Sepolia
    static let chainHex = "0x14a34"
    static let rpcURL = URL(string: "https://sepolia.base.org")!

    /// Circle USDC on Base Sepolia (6 decimals).
    static let usdc = "0x036CbD53842c5426634e7929541eC2318f3dCF7e"
    static let usdcDecimals = 6

    // MARK: - ABI encoding (manual)

    /// `balanceOf(address)` calldata: selector `0x70a08231` + 32-byte left-padded address.
    static func balanceOfCalldata(_ owner: String) -> String {
        "0x70a08231" + pad32(address: owner)
    }

    /// `transfer(address,uint256)` calldata: selector `0xa9059cbb` + padded args.
    static func transferCalldata(to: String, amountBaseUnits: UInt64) -> String {
        "0xa9059cbb" + pad32(address: to) + pad32(uint: amountBaseUnits)
    }

    /// USDC display amount (e.g. 5.25) -> base units (5_250_000).
    static func toBaseUnits(_ amount: Decimal) -> UInt64 {
        let scaled = amount * pow(10, usdcDecimals)
        return NSDecimalNumber(decimal: scaled).uint64Value
    }

    /// 32-byte hex of a `balanceOf` result -> human USDC amount.
    static func usdcFromHex(_ hex: String) -> Decimal {
        let clean = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard let raw = UInt64(clean.suffix(16), radix: 16) else { return 0 }
        return Decimal(raw) / pow(10, usdcDecimals)
    }

    private static func pad32(address: String) -> String {
        let clean = address.hasPrefix("0x") ? String(address.dropFirst(2)) : address
        return String(repeating: "0", count: 64 - clean.count) + clean.lowercased()
    }

    private static func pad32(uint value: UInt64) -> String {
        let hex = String(value, radix: 16)
        return String(repeating: "0", count: 64 - hex.count) + hex
    }
}

/// Minimal JSON-RPC read path. Used for `eth_call balanceOf` because expressing a
/// heterogeneous `eth_call` through the SDK provider's generic `RPCRequest` is awkward
/// (FRICTION_LOG #6). Reads don't need the wallet, so a plain RPC call is simpler here.
enum RPC {
    struct CallError: LocalizedError { let message: String; var errorDescription: String? { message } }

    static func usdcBalance(of address: String) async throws -> Decimal {
        let params: [Any] = [
            ["to": EVM.usdc, "data": EVM.balanceOfCalldata(address)],
            "latest",
        ]
        let hex = try await call(method: "eth_call", params: params)
        return EVM.usdcFromHex(hex)
    }

    /// A smart account is counterfactual until its first transaction deploys it; afterwards
    /// `eth_getCode` returns its contract bytecode rather than empty (`0x`).
    static func isContractDeployed(_ address: String) async throws -> Bool {
        let code = try await call(method: "eth_getCode", params: [address, "latest"])
        return code != "0x" && !code.isEmpty
    }

    // keccak256("Transfer(address,address,uint256)")
    private static let transferTopic =
        "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

    /// Recent USDC transfers (sent + received) for `address` via `eth_getLogs`. Bounded to a
    /// recent block window to stay within public-RPC limits.
    static func usdcTransfers(of address: String) async throws -> [USDCTransfer] {
        let latest = try await blockNumber()
        let fromBlock = "0x" + String(max(0, latest - 9_000), radix: 16)
        let topic = topicAddress(address)
        let sent = (try? await getLogs(topics: [transferTopic, topic], fromBlock: fromBlock)) ?? []
        let received = (try? await getLogs(topics: [transferTopic, nil, topic], fromBlock: fromBlock)) ?? []

        var seen = Set<String>()
        return (sent + received)
            .compactMap { USDCTransfer(log: $0, owner: address.lowercased()) }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.blockNumber > $1.blockNumber }
    }

    private static func blockNumber() async throws -> Int {
        let hex = try await call(method: "eth_blockNumber", params: [])
        return Int(hex.dropFirst(2), radix: 16) ?? 0
    }

    private static func getLogs(topics: [String?], fromBlock: String) async throws -> [[String: Any]] {
        let jsTopics: [Any] = topics.map { $0 as Any? ?? NSNull() }
        let filter: [String: Any] = [
            "address": EVM.usdc,
            "fromBlock": fromBlock,
            "toBlock": "latest",
            "topics": jsTopics,
        ]
        let result = try await rawResult(method: "eth_getLogs", params: [filter])
        return result as? [[String: Any]] ?? []
    }

    private static func rawResult(method: String, params: [Any]) async throws -> Any? {
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": method, "params": params]
        var request = URLRequest(url: EVM.rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let error = json?["error"] as? [String: Any] {
            throw CallError(message: (error["message"] as? String) ?? "RPC error")
        }
        return json?["result"]
    }

    private static func topicAddress(_ address: String) -> String {
        let clean = address.hasPrefix("0x") ? String(address.dropFirst(2)) : address
        return "0x" + String(repeating: "0", count: 64 - clean.count) + clean.lowercased()
    }

    private static func call(method: String, params: [Any]) async throws -> String {
        let body: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": method, "params": params,
        ]
        var request = URLRequest(url: EVM.rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let result = json?["result"] as? String { return result }
        let message = (json?["error"] as? [String: Any])?["message"] as? String ?? "eth_call failed"
        throw CallError(message: message)
    }
}

/// A single USDC transfer parsed from a `Transfer` event log.
struct USDCTransfer: Identifiable {
    let id: String
    let hash: String
    let counterparty: String
    let amount: Decimal
    let isOutgoing: Bool
    let blockNumber: Int

    init?(log: [String: Any], owner: String) {
        guard let topics = log["topics"] as? [String], topics.count >= 3,
              let data = log["data"] as? String,
              let hash = log["transactionHash"] as? String,
              let blockHex = log["blockNumber"] as? String else { return nil }
        let from = "0x" + topics[1].suffix(40).lowercased()
        let to = "0x" + topics[2].suffix(40).lowercased()
        let outgoing = from == owner
        self.hash = hash
        self.isOutgoing = outgoing
        self.counterparty = outgoing ? to : from
        self.amount = EVM.usdcFromHex(data)
        self.blockNumber = Int(blockHex.dropFirst(2), radix: 16) ?? 0
        self.id = hash + "-" + ((log["logIndex"] as? String) ?? "0")
    }
}
