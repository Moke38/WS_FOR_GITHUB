import SwiftUI

enum Format {
    static func price(_ value: Double?, currency: String) -> String {
        guard let value else { return "—" }
        return value.formatted(.currency(code: currency).precision(.fractionLength(2)))
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return (value / 100).formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always()))
    }

    static func compact(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    static func ratio(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(1))) + "倍"
    }

    static func changeColor(_ value: Double?) -> Color {
        guard let value, value != 0 else { return .secondary }
        return value > 0 ? .green : .red
    }
}

struct SignalBadge: View {
    let signal: MoverSignal

    var body: some View {
        Label(signal.label, systemImage: signal.symbolName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch signal {
        case .surge, .near52WeekHigh: .green
        case .plunge, .near52WeekLow: .red
        case .volumeSpike: .orange
        }
    }
}
