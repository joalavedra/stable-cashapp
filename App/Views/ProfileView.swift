import SwiftUI

/// Account screen: identity, address, key export, and sign-out.
struct ProfileView: View {
    @EnvironmentObject private var wallet: WalletStore
    @Environment(\.dismiss) private var dismiss
    @State private var exportedKey: String?
    @State private var showKey = false

    private var cashtag: String {
        let local = (wallet.userEmail ?? "user").split(separator: "@").first.map(String.init) ?? "user"
        return "$" + local.filter(\.isLetter)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                header
                rows
                Spacer()
                footerButtons
            }
            .padding(24)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showKey) { keySheet }
        }
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Avatar(seed: wallet.userEmail ?? "?", size: 72)
            Text(cashtag).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(wallet.userEmail ?? "")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.subtle)
        }
        .padding(.top, 8)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            row(title: "Balance", value: "\(formatUSD(wallet.balance)) USDC")
            Divider()
            Button {
                UIPasteboard.general.string = wallet.address
            } label: {
                row(title: "Address", value: shortAddress(wallet.address), chevron: "doc.on.doc")
            }
            Divider()
            row(title: "Account", value: wallet.isDeployed ? "EIP-7702 delegated" : "EOA")
            Divider()
            row(title: "Gas", value: "Sponsored")
            Divider()
            row(title: "Network", value: "Base Sepolia")
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func row(title: String, value: String, chevron: String? = nil) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.subtle)
            if let chevron {
                Image(systemName: chevron).font(.system(size: 13)).foregroundStyle(Theme.subtle)
            }
        }
        .padding(.vertical, 16).padding(.horizontal, 18)
    }

    private var footerButtons: some View {
        VStack(spacing: 12) {
            Button("Export private key") {
                Task {
                    exportedKey = await wallet.exportPrivateKey()
                    showKey = exportedKey != nil
                }
            }
            .buttonStyle(PrimaryButtonStyle(filled: false))

            Button(role: .destructive) {
                Task { await wallet.signOut(); dismiss() }
            } label: {
                Text("Sign out").frame(maxWidth: .infinity)
            }
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.red)
            .frame(height: 52)
        }
    }

    private var keySheet: some View {
        VStack(spacing: 18) {
            Image(systemName: "key.fill").font(.system(size: 40)).foregroundStyle(Theme.green)
            Text("Private key").font(.system(size: 20, weight: .bold, design: .rounded))
            Text("Anyone with this key controls your funds. Never share it.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.subtle)
                .multilineTextAlignment(.center)
            Text(exportedKey ?? "")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button("Copy") { UIPasteboard.general.string = exportedKey }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}
