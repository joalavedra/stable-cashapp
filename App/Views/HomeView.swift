import SwiftUI

/// The iconic Cash App home: a giant amount, a number pad, and Request / Pay actions.
struct HomeView: View {
    @EnvironmentObject private var wallet: WalletStore
    @State private var amount = "0"
    @State private var showProfile = false
    @State private var showActivity = false
    @State private var showPay = false
    @State private var showRequest = false

    private var amountDecimal: Decimal { Decimal(string: amount) ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            smartAccountChip
            Spacer(minLength: 8)
            amountDisplay
            Spacer(minLength: 8)
            AmountKeypad(amount: $amount)
                .padding(.horizontal, 8)
            actionButtons
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 8)
        }
        .background(Color.white)
        .sheet(isPresented: $showProfile) { ProfileView() }
        .sheet(isPresented: $showActivity) { ActivityView() }
        .sheet(isPresented: $showPay) { SendView(presetAmount: amountDecimal) }
        .sheet(isPresented: $showRequest) { ReceiveView(presetAmount: amountDecimal) }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button { showProfile = true } label: {
                Avatar(seed: wallet.userEmail ?? "?")
            }
            Spacer()
            balancePill
            Spacer()
            Button { showActivity = true } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var smartAccountChip: some View {
        Label(
            wallet.isDeployed ? "EIP-7702 · gasless · active" : "EIP-7702 · gasless",
            systemImage: "bolt.fill"
        )
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(Theme.greenDark)
        .padding(.top, 6)
    }

    private var balancePill: some View {
        Button {
            Task { await wallet.refreshBalance() }
        } label: {
            HStack(spacing: 6) {
                if wallet.balanceLoading {
                    ProgressView().scaleEffect(0.7).tint(Theme.greenDark)
                }
                Text(formatUSD(wallet.balance))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("USDC")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.subtle)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(Theme.surface)
            .clipShape(Capsule())
            .foregroundStyle(Theme.ink)
        }
    }

    // MARK: - Amount

    private var amountDisplay: some View {
        Text(formatUSD(amountDecimal))
            .font(.amount(amountFontSize))
            .foregroundStyle(Theme.ink)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .padding(.horizontal, 24)
            .contentTransition(.numericText())
            .animation(.snappy, value: amount)
    }

    private var amountFontSize: CGFloat {
        switch amount.count {
        case 0...4: return 76
        case 5...7: return 64
        default: return 50
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: 14) {
            Button("Request") { showRequest = true }
                .buttonStyle(PrimaryButtonStyle(filled: false))
            Button("Pay") { showPay = true }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(amountDecimal <= 0)
                .opacity(amountDecimal <= 0 ? 0.5 : 1)
        }
    }
}

/// Cash App–style numeric keypad that edits a decimal-amount string in place.
struct AmountKeypad: View {
    @Binding var amount: String
    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 6) {
            ForEach(keys, id: \.self) { key in
                Button { tap(key) } label: {
                    Text(key)
                        .font(.system(size: 30, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                }
            }
        }
    }

    private func tap(_ key: String) {
        var value = amount
        switch key {
        case "⌫":
            value = String(value.dropLast())
            if value.isEmpty { value = "0" }
        case ".":
            if !value.contains(".") { value += "." }
        default:
            if value == "0" { value = key } else { value += key }
        }
        if let dot = value.firstIndex(of: "."), value.distance(from: dot, to: value.endIndex) > 3 {
            return // cap at 2 decimal places
        }
        amount = value
    }
}
