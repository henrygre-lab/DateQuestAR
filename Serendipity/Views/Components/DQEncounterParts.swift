import SwiftUI

// MARK: - DesignSystem v2 shared parts
//
// The small components §5 specifies that EncounterView and its panels compose
// from. All read `@Environment(\.dq)` — no view in this file names a hex.
//
// `Capsule()` is used wherever the spec says `rPill` (999): it is the native
// expression of the same shape and cannot drift from the token.

// MARK: - Stage bridge
//
// The app's own `RevealStage` stays authoritative (README: map to it, don't
// replace it). This is a presentation-only bridge so the v2 components can read
// the stage numbering, CTA copy and ember-CTA rule straight from the spec.

extension RevealStage {
    var dq: DQReveal.Stage {
        switch self {
        case .blurred:   .nearby
        case .partial:   .icebreaker
        case .revealed:  .revealed
        case .connected: .connected
        }
    }
}

extension UserProfile.TrustLevel {
    var dq: DQTrustTier {
        switch self {
        case .bronze:   .bronze
        case .silver:   .silver
        case .gold:     .gold
        case .platinum: .platinum
        }
    }
}

// MARK: - Buttons (§5)

/// Primary / neutral / ghost pills. One primary per screen; ember is reserved
/// for the commit action.
struct DQPillButtonStyle: ButtonStyle {
    enum Kind { case ember, neutral, ghost, danger }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        Pill(kind: kind, configuration: configuration)
    }

    // ButtonStyle itself gets no environment injection — the label has to be a
    // View for `@Environment(\.dq)` to resolve. (Not named `Body`: that collides
    // with ButtonStyle's own associated type.)
    private struct Pill: View {
        let kind: Kind
        let configuration: Configuration
        @Environment(\.dq) private var p
        @Environment(\.dqTheme) private var theme
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(DQFont.button)
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity)
                .frame(height: kind == .ghost ? DQSize.ghostHeight : DQSize.ctaHeight)
                .background(Capsule().fill(fill))
                .overlay {
                    if kind == .ghost {
                        Capsule().strokeBorder(p.lineStrong, lineWidth: 1)
                    }
                }
                .dqShadow(shadow)
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed && !reduceMotion ? DQMotion.pressScale : 1)
                .animation(reduceMotion ? nil : DQMotion.press, value: configuration.isPressed)
        }

        private var fill: Color {
            switch kind {
            case .ember:   p.ember
            case .neutral: p.cta
            case .ghost:   .clear
            // Filled danger is allowed in exactly one place: a confirm step.
            // Never on a settings row — there the label ink carries it.
            case .danger:  p.danger
            }
        }

        private var ink: Color {
            switch kind {
            case .ember:   .white
            case .neutral: p.ctaText
            case .ghost:   p.text2
            case .danger:  .white
            }
        }

        private var shadow: DQShadow {
            switch kind {
            case .ember:   .ember(p)
            case .neutral, .danger: .small(theme)
            case .ghost:   .init(color: .clear, radius: 0, y: 0)
            }
        }
    }
}

extension ButtonStyle where Self == DQPillButtonStyle {
    static var dqEmber: DQPillButtonStyle { DQPillButtonStyle(kind: .ember) }
    static var dqNeutral: DQPillButtonStyle { DQPillButtonStyle(kind: .neutral) }
    static var dqGhost: DQPillButtonStyle { DQPillButtonStyle(kind: .ghost) }
}

/// Icon-button chrome (§5): 38pt circle, `surface` fill, `line` border,
/// `shadowSm`. Factored out so a `Menu` label can wear the same chrome as a
/// `Button` without either restating it.
struct DQIconChrome: ViewModifier {
    @Environment(\.dq) private var p
    @Environment(\.dqTheme) private var theme

    func body(content: Content) -> some View {
        content
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(p.text)
            .frame(width: DQSize.iconButton, height: DQSize.iconButton)
            .background(Circle().fill(p.surface))
            .overlay(Circle().strokeBorder(p.line, lineWidth: 1))
            .dqShadow(.small(theme))
    }
}

extension View {
    func dqIconChrome() -> some View { modifier(DQIconChrome()) }
}

/// Circular icon button — `surface` fill, `line` border, `shadowSm` (§5).
struct DQIconButton: View {
    let symbol: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).dqIconChrome()
        }
        .frame(width: DQSize.minHitTarget, height: DQSize.minHitTarget)
        .contentShape(Rectangle())
        .accessibilityLabel(label)
    }
}

// MARK: - Chips (§5)

/// On-surface chip. `selected` uses the `cta` fill so it reads as a choice,
/// not as progress — ember stays reserved for commitment.
struct DQChip: View {
    let text: String
    var selected: Bool = false

    @Environment(\.dq) private var p

    var body: some View {
        Text(text)
            .font(DQFont.chip)
            .foregroundStyle(selected ? p.ctaText : p.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(selected ? p.cta : p.surface2))
            .overlay(Capsule().strokeBorder(selected ? .clear : p.line, lineWidth: 1))
    }
}

/// Glass chip — only ever used on top of a photo (§5).
struct GlassChip: View {
    var symbol: String? = nil
    var symbolColor: Color? = nil
    let text: String
    var weight: Font.Weight = .bold

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(symbolColor ?? DQGlass.ink)
            }
            Text(text)
                .font(DQFont.labelSized(11, weight))
                .foregroundStyle(DQGlass.ink)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(DQGlass.chipFill)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .overlay(Capsule().strokeBorder(DQGlass.chipBorder, lineWidth: 1))
    }
}

// MARK: - RevealMeter (§5)

/// Both §5 variants. `overPhoto` is a glass pill with a white track and fill;
/// `onSurface` sits on a card with the `track` background and an `ember` fill.
struct RevealMeter: View {
    enum Style { case overPhoto, onSurface }

    let progress: Double
    var style: Style = .overPhoto

    @Environment(\.dq) private var p

    private var clamped: Double { min(max(progress, 0), 1) }
    private var pct: Int { Int((clamped * 100).rounded()) }

    var body: some View {
        HStack(spacing: style == .overPhoto ? 10 : DQSpace.tight) {
            Text("Reveal")
                .font(DQFont.labelSized(9))
                .tracking(DQFont.track(9, em: style == .overPhoto ? 0.18 : 0.16))
                .textCase(.uppercase)
                .foregroundStyle(style == .overPhoto ? DQGlass.inkLabel : p.text3)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(style == .overPhoto ? DQGlass.meterTrack : p.track)
                    Capsule()
                        .fill(style == .overPhoto ? DQGlass.ink : p.ember)
                        .frame(width: geo.size.width * clamped)
                }
            }
            .frame(height: DQSize.meterHeight)

            Text("\(pct)%")
                .font(DQFont.uiSized(style == .overPhoto ? 12 : 11, .heavy))
                .foregroundStyle(style == .overPhoto ? DQGlass.ink : p.emberText)
                .monospacedDigit()
        }
        .modifier(RevealMeterChrome(style: style))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reveal \(pct) percent")
    }
}

/// The glass pill exists only on the over-photo variant; on a surface the meter
/// is bare, sitting directly on the card.
private struct RevealMeterChrome: ViewModifier {
    let style: RevealMeter.Style

    func body(content: Content) -> some View {
        switch style {
        case .onSurface:
            content
        case .overPhoto:
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    Capsule()
                        .fill(DQGlass.meterFill)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .overlay(Capsule().strokeBorder(DQGlass.meterBorder, lineWidth: 1))
        }
    }
}

// MARK: - Partner photo placeholder
//
// No partner imagery is licensed (handoff README). This neutral stand-in fills
// its whole frame so the blur stays uniform with no transparent edge — the
// scale factor is what keeps blur off the card bounds.

struct PartnerPhotoPlaceholder: View {
    let initials: String
    var glyphSize: CGFloat = 96

    @Environment(\.dq) private var p

    var body: some View {
        LinearGradient(
            colors: [p.surface2, p.surface, p.bg],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay {
            Text(initials)
                .font(DQFont.uiSized(glyphSize, .heavy))
                .foregroundStyle(p.text3.opacity(0.45))
        }
    }
}

extension String {
    /// Two-letter initials for the photo placeholder.
    var dqInitials: String {
        let parts = split(separator: " ")
        if parts.count >= 2 { return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased() }
        return String(prefix(1)).uppercased()
    }
}

// MARK: - RatingBar (§5)

/// Five equal segments — no stars. Each segment carries a full 44pt hit target
/// even though the bar itself is 9pt tall.
struct RatingBar: View {
    let value: Int
    var onSelect: (Int) -> Void

    @Environment(\.dq) private var p

    var body: some View {
        HStack(spacing: 11) {
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { step in
                    Capsule()
                        .fill(step <= value ? p.ember : p.track)
                        .frame(height: DQSize.ratingSegment)
                        .frame(maxWidth: .infinity, minHeight: DQSize.minHitTarget)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(step) }
                        .accessibilityLabel("Rate \(step) out of 5")
                        .accessibilityAddTraits(step == value ? [.isButton, .isSelected] : .isButton)
                }
            }
            Text(value > 0 ? String(format: "%.1f", Double(value)) : "—")
                .font(DQFont.titleS)
                .tracking(DQFont.trackTitleS)
                .foregroundStyle(p.text)
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
    }
}

// MARK: - Ambient loops (§7)

/// Presence dot: opacity 1 → 0.28 → 1, 2s.
struct LiveDot: View {
    var size: CGFloat = 8

    @Environment(\.dq) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(p.live)
            .frame(width: size, height: size)
            .opacity(dim ? DQMotion.liveDimOpacity : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(DQMotion.live) { dim = true }
            }
    }
}

/// Radar pulse: two rings, scale 0.6 → 2.4, opacity 0.65 → 0, offset 1.3s.
/// White over imagery (the encounter hero); ember on a surface (the quest card).
struct RadarPulse: View {
    var color: Color = DQGlass.pulse
    var ringSize: CGFloat = 16
    var dotSize: CGFloat = 9
    var extent: CGFloat = DQSize.iconButton

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(0..<2, id: \.self) { ring in
                    Circle()
                        .strokeBorder(color, lineWidth: 1.5)
                        .frame(width: ringSize, height: ringSize)
                        .scaleEffect(expanded ? DQMotion.radarScaleTo : DQMotion.radarScaleFrom)
                        .opacity(expanded ? 0 : 0.65)
                        .animation(
                            .easeOut(duration: DQMotion.radarDuration)
                                .repeatForever(autoreverses: false)
                                .delay(Double(ring) * DQMotion.radarRingOffset),
                            value: expanded
                        )
                }
            }
            Circle()
                .fill(color)
                .frame(width: dotSize, height: dotSize)
                .shadow(color: color.opacity(0.9), radius: 5)
        }
        .frame(width: extent, height: extent)
        .onAppear { expanded = true }
        .accessibilityHidden(true)
    }
}

// MARK: - Safety line (§8 — on every pre-connect screen)

struct SafetyLine: View {
    let text: String

    @Environment(\.dq) private var p

    var body: some View {
        HStack(spacing: DQSpace.tight) {
            Image(systemName: "smallcircle.filled.circle")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(p.text3)
            Text(text)
                .font(DQFont.uiSized(10.5, .medium))
                .foregroundStyle(p.text3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
