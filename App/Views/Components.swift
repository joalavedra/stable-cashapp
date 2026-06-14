import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Branded full-screen splash used for the launching / setting-up states.
struct SplashScreen: View {
    var caption: String
    var body: some View {
        VStack(spacing: 20) {
            LogoMark(size: 72)
            ProgressView().tint(Theme.green)
            Text(caption)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.subtle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

/// The green dollar badge that stands in for the Cash App logo.
struct LogoMark: View {
    var size: CGFloat = 56
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Theme.green)
            .frame(width: size, height: size)
            .overlay(
                Text("$")
                    .font(.system(size: size * 0.55, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            )
    }
}

/// Circular monogram avatar derived from an email/identifier.
struct Avatar: View {
    var seed: String
    var size: CGFloat = 36
    private var initial: String { String(seed.first ?? "?").uppercased() }
    var body: some View {
        Circle()
            .fill(Theme.ink)
            .frame(width: size, height: size)
            .overlay(
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
    }
}

/// Truncated monospace address, e.g. `0x1234…ab9F`.
func shortAddress(_ address: String?) -> String {
    guard let address, address.count > 12 else { return address ?? "—" }
    return "\(address.prefix(6))…\(address.suffix(4))"
}

/// Renders a QR code for a string payload.
struct QRCode: View {
    var payload: String
    var size: CGFloat = 220
    var body: some View {
        if let image = Self.generate(payload) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }

    private static func generate(_ string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

extension View {
    /// Binds an optional error string to a dismissible alert.
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Error",
            isPresented: Binding(get: { message.wrappedValue != nil },
                                 set: { if !$0 { message.wrappedValue = nil } })
        ) {
            Button("OK", role: .cancel) { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

/// USD-style formatting for a USDC `Decimal`.
func formatUSD(_ amount: Decimal, symbol: Bool = true) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    let number = formatter.string(from: amount as NSDecimalNumber) ?? "0.00"
    return symbol ? "$\(number)" : number
}
