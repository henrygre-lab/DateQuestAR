import SwiftUI

// MARK: - DesignSystem v2 — home components (§5, §6 row 1)
//
// All read `@Environment(\.dq)`; no view here names a hex.

/// §5 QuestCard. The only ember-bordered surface in the app, and the hero of
/// HomeView. The 3px sweeping bar on the top edge is an indeterminate "active"
/// signal — it reports that scanning is running, not how far along it is.
struct QuestCard: View {
    let isActive: Bool
    let title: String
    let detail: String
    /// Constraint chips — real limits only.
    let chips: [String]
    var onToggle: (Bool) -> Void

    @Environment(\.dq) private var p
    @Environment(\.dqTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if isActive { LiveDot() }
                        Text(isActive ? "Quest mode active" : "Quest mode off")
                            .font(DQFont.labelSized(10))
                            .tracking(DQFont.track(10, em: 0.18))
                            .textCase(.uppercase)
                            .foregroundStyle(isActive ? p.liveText : p.text2)
                    }

                    Text(title)
                        .font(DQFont.uiSized(20, .heavy))
                        .tracking(DQFont.track(20, em: -0.02))
                        .foregroundStyle(p.text)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(detail)
                        .font(DQFont.bodyS)
                        .foregroundStyle(p.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 250, alignment: .leading)
                }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Toggle("", isOn: Binding(get: { isActive }, set: onToggle))
                        .labelsHidden()
                        .tint(p.ember)
                        .fixedSize()
                        .accessibilityLabel("Quest Mode")
                        .accessibilityHint("Double tap to toggle quest scanning")

                    if isActive {
                        RadarPulse(color: p.ember, ringSize: 20, dotSize: 10, extent: 52)
                    }
                }
            }

            if !chips.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(chips, id: \.self) { chip in
                        DQChip(text: chip)
                    }
                }
            }
        }
        .padding(DQSpace.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DQRadius.hero, style: .continuous)
                .fill(p.surface)
        )
        .overlay(alignment: .top) {
            if isActive { sweepBar }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DQRadius.hero, style: .continuous)
                // The ember border, the sweep and the pulse are the signal that
                // the app is live. A card that looks identical when off is a
                // bug — inactive drops all three back to a plain surface.
                .strokeBorder(isActive ? p.emberLine : p.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DQRadius.hero, style: .continuous))
        .dqShadow(.standard(theme))
    }

    private var sweepBar: some View {
        GeometryReader { geo in
            Capsule()
                .fill(p.ember)
                .frame(width: geo.size.width * 0.34)
                .offset(x: sweepOffset(in: geo.size.width))
                .animation(
                    reduceMotion ? nil
                    : .easeInOut(duration: 2.8).repeatForever(autoreverses: false),
                    value: sweeping
                )
        }
        .frame(height: 3)
        .background(p.track)
        .onAppear { sweeping = true }
        .accessibilityHidden(true)
    }

    @State private var sweeping = false

    private func sweepOffset(in width: CGFloat) -> CGFloat {
        sweeping ? width : -width * 0.34
    }
}

/// §5 DemoControl (`#if DEBUG`). A dashed border and a mono `DEBUG` chip are
/// the only signals it is not production — no hazard stripes, no emoji. It
/// should read as a deliberate developer affordance, not a sticker.
struct DemoControl: View {
    var onSimulate: () -> Void
    var onReset: () -> Void

    @Environment(\.dq) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: DQSpace.tight) {
                Text("DEBUG")
                    // Squared, NOT rPill — deliberately. Every interactive
                    // element in the product is a pill, so a pill-shaped DEBUG
                    // chip reads as product UI. The square corner is what puts
                    // the debug affordance in a different visual register.
                    .font(DQFont.monoSized(9, .medium))
                    .tracking(DQFont.track(9, em: 0.14))
                    .foregroundStyle(p.demoInk)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(p.demoChip))

                Text("Developer bypass · not shipped")
                    .font(DQFont.uiSized(11, .semibold))
                    .tracking(DQFont.track(11, em: 0.04))
                    .foregroundStyle(p.text2)

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button(action: onSimulate) {
                    Text("Simulate encounter")
                        .font(DQFont.uiSized(13, .bold))
                        .foregroundStyle(p.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: DQSize.minHitTarget)
                        .overlay(Capsule().strokeBorder(p.demoLine, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Starts a scripted walkthrough of a nearby match")

                Button(action: onReset) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(p.text2)
                        .frame(width: DQSize.minHitTarget, height: DQSize.minHitTarget)
                        .overlay(Circle().strokeBorder(p.demoLine, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset demo state")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous)
                .fill(p.demoBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous)
                .strokeBorder(p.demoLine, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
    }
}

/// A nearby signal: blurred photo, glass tier chip, vibe score. Identity stays
/// hidden until an encounter opens — same contract as the hero.
struct SignalCard: View {
    let name: String
    let tier: UserProfile.TrustLevel
    /// 0…1. Nil when no match record backs this profile yet.
    let vibeScore: Double?

    /// The signal's school, e.g. "UCLA".
    ///
    /// Community identity, which DESIGN_SYSTEM.md §8 permits — and load-bearing
    /// inside a Spring Break destination, where the pool is cross-school and the
    /// badge is the only thing telling you this person is from Michigan.
    var school: String?

    @Environment(\.dq) private var p

    private static let height: CGFloat = 168

    var body: some View {
        GeometryReader { geo in
            ZStack {
                PartnerPhotoPlaceholder(initials: name.dqInitials, glyphSize: 44)
                    .scaleEffect(1.2)
                    .blur(radius: DQReveal.blurRadius(for: 0, width: geo.size.width))

                DQScrim.signal

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        GlassChip(
                            symbol: "diamond.fill",
                            symbolColor: tier.dq.color(p),
                            text: tier.dq.name
                        )
                        if let school, !school.isEmpty {
                            GlassChip(symbol: "graduationcap.fill",
                                      symbolColor: DQGlass.ink,
                                      text: school)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)

                    Spacer(minLength: 0)

                    // Vibe match is the primary line. There is no per-signal
                    // distance in production, and a distance is never
                    // approximated — with no match record the line simply goes,
                    // leaving the tier chip to carry the card.
                    if let vibeScore {
                        Text("\(Int((vibeScore * 100).rounded())) vibe match")
                            .font(DQFont.uiSized(14, .heavy))
                            .tracking(DQFont.track(14, em: -0.01))
                            .foregroundStyle(DQGlass.ink)
                            .padding(11)
                    }
                }
            }
        }
        .frame(height: Self.height)
        .background(p.surface2)
        .clipShape(RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous)
                .strokeBorder(p.line, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["Nearby signal"]
        if let school, !school.isEmpty { parts.append(school) }
        parts.append("\(tier.dq.name) tier")
        if let vibeScore { parts.append("\(Int((vibeScore * 100).rounded())) vibe match") }
        return parts.joined(separator: ", ")
    }
}

/// §5 FloatingTabBar. A Liquid Glass pill sitting below the content, items at
/// 56×44, the active one a `navActive` pill.
///
/// The bar is the app's clearest case for glass: it floats over a scrolling
/// dashboard and is the only chrome on the screen. The glass replaces the `nav`
/// fill; `nav` becomes its tint so the bar still reads as dark chrome in either
/// palette (see `DQGlass.nav`).
///
/// The active pill stays **opaque**, not a second glass layer. It has to carry
/// `navActiveInk` at full contrast, and glass inside glass would either merge
/// with the bar or wash the ink out. It slides between items instead, which is
/// the motion the material implies anyway.
struct FloatingTabBar<Tab: Hashable>: View {
    struct Item: Identifiable {
        let tab: Tab
        let symbol: String
        let label: String
        var id: Tab { tab }
    }

    let items: [Item]
    @Binding var selection: Tab

    @Environment(\.dq) private var p
    @Environment(\.dqTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 5) {
            ForEach(items) { item in
                Button {
                    selection = item.tab
                } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(selection == item.tab ? p.navActiveInk : p.navInk)
                        .frame(width: 56, height: DQSize.minHitTarget)
                        .background {
                            if selection == item.tab {
                                Capsule()
                                    .fill(p.navActive)
                                    .matchedGeometryEffect(id: "tab.selection", in: indicator)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(selection == item.tab ? [.isButton, .isSelected] : .isButton)
            }
        }
        // Scoped to the bar rather than wrapped around the `selection` write:
        // the same binding drives the TabView, and animating the mutation would
        // put this animation on the tab *content* swap as well.
        .animation(reduceMotion ? nil : DQMotion.tabSelect, value: selection)
        .padding(8)
        .dqGlass(tint: DQGlass.nav(p))
        .dqShadow(.standard(theme))
        .padding(.top, 10)
        .padding(.bottom, DQSpace.safeBottom)
    }
}
