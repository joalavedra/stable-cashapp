import SwiftUI

/// Request flow: show the wallet's address as a QR + copyable string.
struct ReceiveView: View {
    @EnvironmentObject private var wallet: WalletStore
    @Environment(\.dismiss) private var dismiss

    var presetAmount: Decimal
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if presetAmount > 0 {
                    Text("Requesting \(formatUSD(presetAmount))")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
                QRCode(payload: wallet.address ?? "")
                    .padding(20)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                Text("Your USDC address (Base Sepolia)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.subtle)
                Text(wallet.address ?? "—")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button {
                    UIPasteboard.general.string = wallet.address
                    copied = true
                } label: {
                    Label(copied ? "Copied!" : "Copy address", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(PrimaryButtonStyle(filled: false))
                .padding(.horizontal, 40)
                Spacer()
            }
            .padding(.top, 12)
            .navigationTitle("Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDragIndicator(.visible)
    }
}
