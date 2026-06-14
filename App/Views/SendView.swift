import SwiftUI

/// Pay flow: enter a recipient address and send USDC gaslessly via the SDK provider.
struct SendView: View {
    @EnvironmentObject private var wallet: WalletStore
    @Environment(\.dismiss) private var dismiss

    var presetAmount: Decimal
    @State private var recipient = ""
    @State private var amountText: String
    @State private var txHash: String?

    init(presetAmount: Decimal) {
        self.presetAmount = presetAmount
        _amountText = State(initialValue: formatUSD(presetAmount, symbol: false))
    }

    private var amount: Decimal { Decimal(string: amountText) ?? 0 }
    private var canSend: Bool {
        !wallet.busy && amount > 0 && recipient.hasPrefix("0x") && recipient.count == 42
    }

    var body: some View {
        NavigationStack {
            if let txHash {
                successView(txHash)
            } else {
                form
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var form: some View {
        VStack(spacing: 22) {
            amountField
            recipientField
            Spacer()
            Label("Gasless via EIP-7702 — sponsored, no ETH needed", systemImage: "bolt.fill")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.greenDark)
            Button {
                Task { txHash = await wallet.send(to: recipient, amount: amount) }
            } label: {
                Text(wallet.busy ? "Sending…" : "Pay \(formatUSD(amount))")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.5)
        }
        .padding(24)
        .navigationTitle("Pay")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }

    private var amountField: some View {
        VStack(spacing: 4) {
            Text("Amount (USDC)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.subtle)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Text("$").font(.amount(34)).foregroundStyle(Theme.subtle)
                TextField("0", text: $amountText)
                    .font(.amount(34))
                    .keyboardType(.decimalPad)
            }
            .padding(.vertical, 14).padding(.horizontal, 18)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var recipientField: some View {
        VStack(spacing: 4) {
            Text("To (wallet address)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.subtle)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                TextField("0x…", text: $recipient)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button {
                    recipient = UIPasteboard.general.string ?? recipient
                } label: {
                    Image(systemName: "doc.on.clipboard").foregroundStyle(Theme.greenDark)
                }
            }
            .padding(.vertical, 16).padding(.horizontal, 18)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func successView(_ hash: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64)).foregroundStyle(Theme.green)
            Text("Sent \(formatUSD(amount))")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Label("Gasless · EIP-7702 sponsored", systemImage: "bolt.fill")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.greenDark)
            Link("View on BaseScan", destination: explorerURL(hash))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.greenDark)
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
        .navigationTitle("Done").navigationBarTitleDisplayMode(.inline)
    }

    private func explorerURL(_ hash: String) -> URL {
        URL(string: "https://sepolia.basescan.org/tx/\(hash)")!
    }
}
