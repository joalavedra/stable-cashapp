import SwiftUI

/// Activity tab — recent USDC transfers for the wallet, read from on-chain `Transfer` events.
struct ActivityView: View {
    @EnvironmentObject private var wallet: WalletStore
    @Environment(\.dismiss) private var dismiss
    @State private var transfers: [USDCTransfer] = []
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    balanceHeader
                    if loading && transfers.isEmpty {
                        ProgressView().tint(Theme.green).padding(.vertical, 24)
                    } else if transfers.isEmpty {
                        emptyState
                    } else {
                        transferList
                    }
                    if let address = wallet.address {
                        Link("View full history on BaseScan",
                             destination: URL(string: "https://sepolia.basescan.org/address/\(address)")!)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.greenDark)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .refreshable { await load() }
            .task { await load() }
        }
        .presentationDragIndicator(.visible)
    }

    private var balanceHeader: some View {
        VStack(spacing: 4) {
            Text("Balance")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.subtle)
            Text(formatUSD(wallet.balance)).font(.amount(44))
            Text("USDC · Base Sepolia")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.subtle)
        }
        .padding(.top, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.system(size: 34)).foregroundStyle(Theme.subtle)
            Text("No activity yet").font(.system(size: 17, weight: .semibold, design: .rounded))
            Text("Your sends and receives will appear here.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.subtle)
        }
        .padding(.vertical, 24)
    }

    private var transferList: some View {
        VStack(spacing: 0) {
            ForEach(transfers) { transfer in
                Link(destination: URL(string: "https://sepolia.basescan.org/tx/\(transfer.hash)")!) {
                    transferRow(transfer)
                }
                if transfer.id != transfers.last?.id { Divider() }
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func transferRow(_ transfer: USDCTransfer) -> some View {
        HStack(spacing: 12) {
            Image(systemName: transfer.isOutgoing ? "arrow.up.right" : "arrow.down.left")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(transfer.isOutgoing ? Theme.ink : Theme.greenDark)
                .frame(width: 36, height: 36)
                .background(Theme.hairline)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(transfer.isOutgoing ? "Sent" : "Received")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text(shortAddress(transfer.counterparty))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.subtle)
            }
            Spacer()
            Text((transfer.isOutgoing ? "-" : "+") + formatUSD(transfer.amount))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(transfer.isOutgoing ? Theme.ink : Theme.greenDark)
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
    }

    private func load() async {
        guard let address = wallet.address else { return }
        loading = true
        defer { loading = false }
        await wallet.refreshBalance()
        if let result = try? await RPC.usdcTransfers(of: address) { transfers = result }
    }
}
