import SwiftUI

// MARK: - DesignSystem v2 — form, auth and system chrome (§5)
//
// The vocabulary the encounter-flow components never needed: rows, groups,
// fields, controls, top bars, empty and loading states. Everything reads
// `@Environment(\.dq)`; no view in this file names a hex.
//
// Standing rules these encode, so they cannot drift per screen:
//  • Focus is neutral (`cta`), never ember. Ember appears in a form in exactly
//    one place — a value being tuned live (the slider fill and its readout).
//  • Values are mono, words are Jakarta.
//  • Rows carry no icons. Leading glyphs stay reserved for trust, live and
//    verify states.
//  • A field looks identical on `bg` and inside a `surface` card.

// MARK: - Section header & footnote

/// Sits outside the group, above it.
struct DQSectionHeader: View {
    let title: String

    @Environment(\.dq) private var p

    var body: some View {
        Text(title)
            .font(DQFont.labelSized(9.5, .semibold))
            .tracking(DQFont.track(9.5, em: 0.20))
            .textCase(.uppercase)
            .foregroundStyle(p.text3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, DQFormMetrics.inset)
            .padding(.bottom, DQSpace.tight)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Explanatory line below a group, on the same inset.
struct DQFootnote: View {
    let text: String

    @Environment(\.dq) private var p

    var body: some View {
        Text(text)
            .font(DQFont.uiSized(11, .medium))
            .foregroundStyle(p.text3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DQFormMetrics.inset)
            .padding(.top, 7)
    }
}

enum DQFormMetrics {
    static let rowMinHeight: CGFloat = 56
    static let rowVPad: CGFloat = 14
    static let inset: CGFloat = 18
    static let rowGap: CGFloat = 14
    static let fieldHeight: CGFloat = 52
    static let fieldHPad: CGFloat = 16
}

// MARK: - Group

/// A card of rows. Dividers are drawn between children only — never after the
/// last one — and the whole thing is clipped so row fills respect the corner.
struct DQGroup<Content: View>: View {
    @ViewBuilder var content: Content

    @Environment(\.dq) private var p

    var body: some View {
        // `Group(subviews:)` is public API — it lets the group interleave its
        // own dividers so no caller has to remember to omit the last one.
        Group(subviews: content) { subviews in
            VStack(spacing: 0) {
                ForEach(Array(subviews.enumerated()), id: \.offset) { index, subview in
                    subview
                    if index < subviews.count - 1 {
                        Rectangle()
                            .fill(p.line)
                            .frame(height: 1)
                            .padding(.leading, DQFormMetrics.inset)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous).fill(p.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous)
                .strokeBorder(p.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous))
    }
}

// MARK: - Rows

/// The base row: a label block on the left, whatever the caller supplies on the
/// right. Not tappable on its own — wrap it in a Button, or use `DQValueRow`.
struct DQRow<Trailing: View>: View {
    let label: String
    var sublabel: String?
    @ViewBuilder var trailing: Trailing

    @Environment(\.dq) private var p

    var body: some View {
        HStack(spacing: DQFormMetrics.rowGap) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(DQFont.uiSized(14, .semibold))
                    .foregroundStyle(p.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let sublabel {
                    Text(sublabel)
                        .font(DQFont.uiSized(11.5, .medium))
                        .foregroundStyle(p.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.vertical, DQFormMetrics.rowVPad)
        .padding(.horizontal, DQFormMetrics.inset)
        .frame(minHeight: DQFormMetrics.rowMinHeight)
        .contentShape(Rectangle())
    }
}

extension DQRow where Trailing == EmptyView {
    init(label: String, sublabel: String? = nil) {
        self.init(label: label, sublabel: sublabel) { EmptyView() }
    }
}

/// A row that navigates: mono value + chevron.
struct DQValueRow: View {
    let label: String
    var sublabel: String?
    var value: String?
    var action: (() -> Void)?

    @Environment(\.dq) private var p

    var body: some View {
        Button { action?() } label: {
            DQRow(label: label, sublabel: sublabel) {
                HStack(spacing: DQSpace.tight) {
                    if let value {
                        Text(value)
                            .font(DQFont.monoSized(13, .medium))
                            .foregroundStyle(p.text2)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(p.text3)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
    }
}

struct DQToggleRow: View {
    let label: String
    var sublabel: String?
    @Binding var isOn: Bool

    @Environment(\.dq) private var p

    var body: some View {
        DQRow(label: label, sublabel: sublabel) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(p.ember)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

struct DQStepperRow: View {
    let label: String
    var sublabel: String?
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 1
    /// Formats the readout — e.g. an age, a count, a distance.
    var format: (Int) -> String = { "\($0)" }

    @Environment(\.dq) private var p

    var body: some View {
        DQRow(label: label, sublabel: sublabel) {
            HStack(spacing: 0) {
                stepButton("minus", enabled: value > range.lowerBound) {
                    value = max(range.lowerBound, value - step)
                }
                Text(format(value))
                    .font(DQFont.monoSized(15, .medium))
                    .foregroundStyle(p.text)
                    .frame(minWidth: 30)
                stepButton("plus", enabled: value < range.upperBound) {
                    value = min(range.upperBound, value + step)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p.surface2)
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            default: break
            }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(p.text)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(p.surface)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// The one place ember belongs in a form: a value being tuned live.
struct DQSliderRow: View {
    let label: String
    var sublabel: String?
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double?
    var format: (Double) -> String

    @Environment(\.dq) private var p
    @Environment(\.dqTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: DQFormMetrics.rowGap) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(DQFont.uiSized(14, .semibold))
                        .foregroundStyle(p.text)
                    if let sublabel {
                        Text(sublabel)
                            .font(DQFont.uiSized(11.5, .medium))
                            .foregroundStyle(p.text2)
                    }
                }
                Spacer(minLength: 0)
                Text(format(value))
                    .font(DQFont.monoSized(13, .medium))
                    .foregroundStyle(p.emberText)
            }

            DQSliderTrack(value: $value, range: range, step: step)
        }
        .padding(.vertical, DQFormMetrics.rowVPad)
        .padding(.horizontal, DQFormMetrics.inset)
        .frame(minHeight: DQFormMetrics.rowMinHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            let delta = step ?? (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(range.upperBound, value + delta)
            case .decrement: value = max(range.lowerBound, value - delta)
            default: break
            }
        }
    }
}

private struct DQSliderTrack: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double?

    @Environment(\.dq) private var p
    @Environment(\.dqTheme) private var theme

    private let knob: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let span = max(range.upperBound - range.lowerBound, .leastNonzeroMagnitude)
            let fraction = min(max((value - range.lowerBound) / span, 0), 1)
            let travel = max(geo.size.width - knob, 0)

            ZStack(alignment: .leading) {
                Capsule().fill(p.track).frame(height: 6)
                Capsule()
                    .fill(p.ember)
                    .frame(width: knob / 2 + travel * fraction, height: 6)
                Circle()
                    .fill(p.surface)
                    .frame(width: knob, height: knob)
                    .overlay(Circle().strokeBorder(p.line, lineWidth: 1))
                    .dqShadow(.small(theme))
                    .offset(x: travel * fraction)
            }
            .frame(height: knob)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    guard travel > 0 else { return }
                    let raw = range.lowerBound
                        + Double(min(max(drag.location.x - knob / 2, 0), travel) / travel) * span
                    value = step.map { (raw / $0).rounded() * $0 } ?? raw
                }
            )
        }
        .frame(height: knob)
    }
}

// MARK: - Segmented picker
//
// Stands alone, never inside a DQGroup. Two or three options only — beyond that
// the choice belongs in a pushed list.

struct DQSegmentedPicker<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    @Binding var selection: Option

    @Environment(\.dq) private var p

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button { selection = option } label: {
                    Text(title(option))
                        .font(DQFont.uiSized(12.5, isSelected ? .bold : .semibold))
                        .foregroundStyle(isSelected ? p.ctaText : p.text2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.cta)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(option))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(p.surface2)
        )
    }
}

// MARK: - Fields
//
// A field looks the same wherever it sits — `surface2` fill and a `line` border
// on `bg` and inside a `surface` card alike. Focus takes the border to 1.5pt
// `cta`: neutral, never ember, no glow.

struct DQTextField: View {
    var label: String = ""
    var placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var errorMessage: String? = nil
    var keyboardType: UIKeyboardType = .default

    @Environment(\.dq) private var p
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !label.isEmpty {
                DQFieldLabel(text: label)
            }

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(.never)
                }
            }
            .font(DQFont.body)
            .foregroundStyle(p.text)
            .tint(p.text)
            .focused($isFocused)
            .padding(.horizontal, DQFormMetrics.fieldHPad)
            .frame(height: DQFormMetrics.fieldHeight)
            .background(
                RoundedRectangle(cornerRadius: DQRadius.field, style: .continuous).fill(p.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DQRadius.field, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused ? 1.5 : 1)
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(DQFont.uiSized(11, .medium))
                    .foregroundStyle(p.danger)
                    .accessibilityLabel("Error: \(errorMessage)")
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label.isEmpty ? placeholder : label)
    }

    private var borderColor: Color {
        if errorMessage != nil { return p.danger }
        return isFocused ? p.cta : p.line
    }
}

struct DQTextArea: View {
    var label: String = ""
    var placeholder: String
    @Binding var text: String
    var characterLimit: Int?

    @Environment(\.dq) private var p
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !label.isEmpty || characterLimit != nil {
                HStack {
                    if !label.isEmpty { DQFieldLabel(text: label) }
                    Spacer(minLength: 0)
                    if let characterLimit {
                        Text("\(text.count)/\(characterLimit)")
                            .font(DQFont.monoSized(10.5, .medium))
                            .foregroundStyle(p.text3)
                    }
                }
            }

            TextField(placeholder, text: $text, axis: .vertical)
                .font(DQFont.body)
                .foregroundStyle(p.text)
                .tint(p.text)
                .focused($isFocused)
                .padding(.horizontal, DQFormMetrics.fieldHPad)
                .padding(.vertical, DQFormMetrics.rowVPad)
                .frame(minHeight: 84, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: DQRadius.field, style: .continuous).fill(p.surface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DQRadius.field, style: .continuous)
                        .strokeBorder(isFocused ? p.cta : p.line, lineWidth: isFocused ? 1.5 : 1)
                )
                .onChange(of: text) { _, newValue in
                    if let characterLimit, newValue.count > characterLimit {
                        text = String(newValue.prefix(characterLimit))
                    }
                }
        }
        .opacity(isEnabled ? 1 : 0.45)
    }
}

private struct DQFieldLabel: View {
    let text: String

    @Environment(\.dq) private var p

    var body: some View {
        Text(text)
            .font(DQFont.labelSized(9.5, .semibold))
            .tracking(DQFont.track(9.5, em: 0.16))
            .textCase(.uppercase)
            .foregroundStyle(p.text2)
    }
}

// MARK: - Danger

/// Destructive action as a row: `danger` ink on the label, nothing else.
/// A filled danger pill belongs only inside a confirm step.
struct DQDangerRow: View {
    let label: String
    var sublabel: String?
    var action: () -> Void

    @Environment(\.dq) private var p

    var body: some View {
        Button(action: action) {
            DQRow(label: label, sublabel: sublabel) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(p.danger.opacity(0.6))
            }
            .foregroundStyle(p.danger)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}

/// The confirm step — the only place a filled `danger` pill is allowed.
struct DQConfirmSheet: View {
    let title: String
    let message: String
    let confirmTitle: String
    var onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dq) private var p
    @State private var measuredHeight: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: DQSpace.gutter) {
            Capsule()
                .fill(p.track)
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(DQFont.displayS)
                    .tracking(DQFont.trackDisplayS)
                    .foregroundStyle(p.text)
                Text(message)
                    .font(DQFont.bodyS)
                    .foregroundStyle(p.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: DQSpace.tight) {
                Button(confirmTitle) {
                    dismiss()
                    onConfirm()
                }
                .buttonStyle(DQPillButtonStyle(kind: .danger))

                Button("Cancel") { dismiss() }
                    .buttonStyle(.dqGhost)
            }
        }
        .padding(.horizontal, DQSpace.gutter)
        .padding(.top, 14)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.bg)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: DQConfirmHeightKey.self, value: geo.size.height)
            }
        }
        .onPreferenceChange(DQConfirmHeightKey.self) { measuredHeight = $0 }
        .presentationDetents([.height(max(measuredHeight, 200))])
        .presentationCornerRadius(DQRadius.sheet)
        .presentationDragIndicator(.hidden)
    }
}

private struct DQConfirmHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Top bars
//
// Custom, not NavigationStack toolbars — the floating round back button is
// already the app's language.

struct DQTopBar<Trailing: View>: View {
    enum Style { case root, pushed }

    let title: String
    var style: Style = .root
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    @Environment(\.dq) private var p

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                DQIconButton(symbol: "chevron.left", label: "Back", action: onBack)
            }

            if style == .root {
                Text(title)
                    .font(DQFont.uiSized(21, .heavy))
                    .tracking(DQFont.track(21, em: -0.025))
                    .foregroundStyle(p.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text(title)
                    .font(DQFont.uiSized(15, .bold))
                    .foregroundStyle(p.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            trailing
        }
        .frame(minHeight: DQSize.minHitTarget)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }
}

extension DQTopBar where Trailing == EmptyView {
    init(title: String, style: Style = .root, onBack: (() -> Void)? = nil) {
        self.init(title: title, style: style, onBack: onBack) { EmptyView() }
    }
}

/// Trailing text action in a top bar.
struct DQTopBarAction: View {
    let title: String
    var action: () -> Void

    @Environment(\.dq) private var p

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DQFont.uiSized(13, .semibold))
                .foregroundStyle(p.emberText)
                .frame(minHeight: DQSize.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Auth
//
// One primary pill per screen: in auth that is the neutral filled button.
// Every other provider is ghost, and provider colour is confined to the glyph.

struct DQAuthButton: View {
    enum Kind { case filled, ghost, plain }

    let title: String
    var kind: Kind = .ghost
    var symbol: String?
    var symbolColor: Color?
    var action: () -> Void

    @Environment(\.dq) private var p
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: DQSpace.tight) {
                if let symbol, kind != .plain {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(symbolColor ?? ink)
                }
                Text(title)
                    .font(DQFont.uiSized(kind == .plain ? 13 : 14, kind == .filled ? .bold : .semibold))
                    .foregroundStyle(ink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: kind == .plain ? DQSize.minHitTarget : 52)
            .background {
                if kind == .filled { Capsule().fill(p.cta) }
            }
            .overlay {
                if kind == .ghost { Capsule().strokeBorder(p.lineStrong, lineWidth: 1) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(title)
    }

    private var ink: Color {
        switch kind {
        case .filled: p.ctaText
        case .ghost:  p.text
        case .plain:  p.text2
        }
    }
}

// MARK: - Empty & loading

struct DQEmptyState: View {
    let symbol: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    @Environment(\.dq) private var p

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(p.text3)
                .frame(width: 44, height: 44)
                .background(Circle().fill(p.surface2))

            Text(title)
                .font(DQFont.uiSized(14, .bold))
                .foregroundStyle(p.text)

            if let message {
                Text(message)
                    .font(DQFont.uiSized(11.5, .medium))
                    .foregroundStyle(p.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(DQFont.chip)
                        .foregroundStyle(p.text)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                        .overlay(Capsule().strokeBorder(p.lineStrong, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// Placeholder bar. Shape these like the content they stand in for — a spinner
/// is only for waits under about a second.
struct DQSkeleton: View {
    var width: CGFloat?
    var height: CGFloat = 14

    @Environment(\.dq) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(p.surface2)
            .frame(width: width, height: height)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, p.lineStrong, .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: shimmer ? geo.size.width : -geo.size.width * 0.6)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    shimmer = true
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Step dots
//
// Onboarding step progress. The current step elongates to a pill and that
// elongation is the *only* state difference, so a dot row can never be misread
// as a filled meter. Neutral throughout — no ember, no fill sweep, no
// connecting line. Display only: reverse navigation is `DQTopBar`'s job.
//
// `StageStepper` is deliberately not reused here — it reads as reveal progress.

struct DQStepDots: View {
    let total: Int
    /// Zero-based.
    let current: Int

    @Environment(\.dq) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Past this the row stops scaling; a flow that long needs sections.
    static let maxSteps = 10

    private var clampedTotal: Int { min(max(total, 1), Self.maxSteps) }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<clampedTotal, id: \.self) { index in
                Capsule()
                    .fill(color(for: index))
                    .frame(width: index == current ? 20 : 6, height: 6)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: current)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(clampedTotal)")
        .onAppear {
            assert(
                total <= Self.maxSteps,
                "DQStepDots: \(total) steps exceeds \(Self.maxSteps) — split the flow into sections."
            )
        }
    }

    private func color(for index: Int) -> Color {
        if index == current { return p.text }
        return index < current ? p.text3 : p.track
    }
}

// MARK: - Blocking save
//
// A commit the user cannot cancel. Skeleton-vs-spinner is FETCH vs COMMIT, not
// duration: a fetch has a known incoming shape so it skeletons, a commit has no
// shape to preview — the user is leaving the screen — so it spins, however long
// it takes. This supersedes the "under ~1 second" wording in the loading spec.
//
// If the work can be cancelled it is not blocking; use an inline field state.

extension View {
    /// Overlays a blocking commit indicator. Blocks all input, including the
    /// back gesture, until the work resolves or fails.
    func dqBlockingSave(
        isActive: Bool,
        title: String,
        message: String? = nil
    ) -> some View {
        modifier(DQBlockingSave(isActive: isActive, title: title, message: message))
    }
}

struct DQBlockingSave: ViewModifier {
    let isActive: Bool
    let title: String
    var message: String?

    @Environment(\.dq) private var p
    @Environment(\.dqTheme) private var theme

    @State private var visible = false
    @State private var shownAt: Date?
    @State private var isSlow = false
    @State private var spin = false

    /// Floor so a fast save does not flash.
    private static let minimumOnScreen: TimeInterval = 0.4
    /// Past this the sub-line admits it is taking a while.
    private static let slowAfter: TimeInterval = 8

    func body(content: Content) -> some View {
        content
            .blur(radius: visible ? 14 : 0)
            .overlay {
                if visible { overlay }
            }
            .animation(.easeOut(duration: 0.2), value: visible)
            // Both are needed: the first stops a sheet being pulled down, the
            // second stops the navigation back-swipe.
            .interactiveDismissDisabled(visible)
            .navigationBarBackButtonHidden(visible)
            .onChange(of: isActive) { _, active in
                if active { show() } else { hide() }
            }
            .onAppear { if isActive { show() } }
    }

    private var overlay: some View {
        ZStack {
            DQScrim.heavy(theme)
                .ignoresSafeArea()
                // Swallows every tap, including on the form underneath.
                .contentShape(Rectangle())
                .onTapGesture {}

            VStack(spacing: 14) {
                spinner

                Text(title)
                    .font(DQFont.uiSized(13.5, .semibold))
                    .foregroundStyle(p.text)
                    .multilineTextAlignment(.center)

                if let line = isSlow
                    ? "Still working — you can keep waiting or try again later"
                    : message {
                    Text(line)
                        .font(DQFont.uiSized(11.5, .medium))
                        .foregroundStyle(p.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 26)
            .frame(minWidth: 196)
            .background(
                RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous).fill(p.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous)
                    .strokeBorder(p.line, lineWidth: 1)
            )
            .dqShadow(.standard(theme))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// Track ring with a `text` head. Never ember — ember is not a waiting
    /// colour. Kept spinning under Reduce Motion: it is the only signal the app
    /// is still alive.
    private var spinner: some View {
        ZStack {
            Circle().strokeBorder(p.track, lineWidth: 2)
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(p.text, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(spin ? 360 : 0))
        }
        .frame(width: 22, height: 22)
        .onAppear {
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                spin = true
            }
        }
    }

    private func show() {
        shownAt = Date()
        isSlow = false
        visible = true
        Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.slowAfter * 1_000_000_000))
            if visible { isSlow = true }
        }
    }

    private func hide() {
        let elapsed = shownAt.map { Date().timeIntervalSince($0) } ?? Self.minimumOnScreen
        let remaining = max(0, Self.minimumOnScreen - elapsed)
        guard remaining > 0 else {
            visible = false
            isSlow = false
            return
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            visible = false
            isSlow = false
        }
    }
}
