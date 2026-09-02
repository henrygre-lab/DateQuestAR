//  DQDesignSystem.swift
//  Serendipity — DesignSystem v2 (DQ tokens)
//
//  ┌──────────────────────────────────────────────────────────────────────┐
//  │ THE APP IS MID-MIGRATION BETWEEN TWO DESIGN SYSTEMS.                  │
//  │                                                                      │
//  │  • v1 — `enum DQ` in Utilities/DesignSystem.swift. Legacy. Dark-only, │
//  │    purple accent, static namespaced constants (`DQ.Colors.accent`).   │
//  │    Still read by 17 files.                                           │
//  │  • v2 — this file. Dual-theme, ember accent, read from the            │
//  │    environment: `@Environment(\.dq)` for colour, `DQRadius`/`DQSpace`/ │
//  │    `DQSize` for geometry, `DQFont` for type.                          │
//  │                                                                      │
//  │ The two names are close enough to be a trap. If you are touching a    │
//  │ view, check which system it already reads and stay in it — do not     │
//  │ mix them in one view. docs/UI_REWORK_STATUS.md §1 lists what has      │
//  │ moved; everything else moves in a later pass.                         │
//  └──────────────────────────────────────────────────────────────────────┘
//
//  Dual-theme token layer. Views must read `DQ.<token>` from the environment
//  theme — never hard-code a hex. See docs/DESIGN_SYSTEM.md for rationale.

import SwiftUI

// MARK: - Theme

public enum DQTheme: String, CaseIterable, Sendable {
    case light, dark
}

// MARK: - Palette

public struct DQPalette: Sendable {
    // Surfaces & ink
    public let bg, surface, surface2: Color
    public let text, text2, text3: Color
    public let line, lineStrong, track: Color

    // Accents
    public let ember, emberSoft, emberLine, emberText, emberGlow: Color
    public let verify, live, liveText, danger: Color

    // CTA & nav
    public let cta, ctaText: Color
    public let nav, navInk, navActive, navActiveInk: Color

    // Trust tiers
    public let bronze, silver, gold, platinumInk, platinumFill: Color

    // Debug affordance (#if DEBUG surfaces only)
    public let demoBg, demoLine, demoChip, demoInk: Color

    public static let dark = DQPalette(
        bg: .hex(0x101113), surface: .hex(0x1A1B1E), surface2: .hex(0x24262A),
        text: .hex(0xF6F7F8), text2: .hex(0x9BA0A8), text3: .hex(0x6A6F77),
        line: .white.opacity(0.09), lineStrong: .white.opacity(0.18), track: .white.opacity(0.12),
        ember: .hex(0xF2683C), emberSoft: .hex(0xF2683C, 0.16), emberLine: .hex(0xF2683C, 0.38),
        emberText: .hex(0xFF8A5F), emberGlow: .hex(0xF2683C, 0.32),
        verify: .hex(0x2E9BF0), live: .hex(0x4ADE80), liveText: .hex(0x4ADE80), danger: .hex(0xE5484D),
        cta: .white, ctaText: .hex(0x15161A),
        nav: .hex(0x24262A, 0.94), navInk: .hex(0x8B9098), navActive: .white, navActiveInk: .hex(0x15161A),
        bronze: .hex(0xC08457), silver: .hex(0xB9C0CA), gold: .hex(0xE8B44A),
        platinumInk: .hex(0xD9E6F2), platinumFill: .hex(0xD9E6F2, 0.14),
        demoBg: .white.opacity(0.03), demoLine: .white.opacity(0.22),
        demoChip: .white.opacity(0.12), demoInk: .hex(0xC9CED6)
    )

    public static let light = DQPalette(
        bg: .hex(0xEFEFF1), surface: .white, surface2: .hex(0xF5F5F7),
        text: .hex(0x16171A), text2: .hex(0x6E727A), text3: .hex(0x767B84),
        line: .hex(0x14161A, 0.09), lineStrong: .hex(0x14161A, 0.18), track: .hex(0x14161A, 0.10),
        ember: .hex(0xF2683C), emberSoft: .hex(0xF2683C, 0.11), emberLine: .hex(0xF2683C, 0.30),
        emberText: .hex(0xD2481F), emberGlow: .hex(0xF2683C, 0.30),
        verify: .hex(0x2E9BF0), live: .hex(0x3E9E63), liveText: .hex(0x2F8F55), danger: .hex(0xE5484D),
        cta: .hex(0x1B1C1F), ctaText: .white,
        nav: .hex(0x1B1C1F), navInk: .hex(0x9A9EA6), navActive: .white, navActiveInk: .hex(0x15161A),
        bronze: .hex(0xB4753F), silver: .hex(0x8D95A1), gold: .hex(0xC79320),
        platinumInk: .hex(0x5B7C97), platinumFill: .hex(0x5B7C97, 0.12),
        demoBg: .hex(0x14161A, 0.03), demoLine: .hex(0x14161A, 0.22),
        demoChip: .hex(0x14161A, 0.10), demoInk: .hex(0x4A4E56)
    )

    public static func of(_ theme: DQTheme) -> DQPalette { theme == .dark ? .dark : .light }
}

// MARK: - Over-imagery tokens
//
// §5: text over imagery is always white, in both themes — the scrim guarantees
// contrast. These live here rather than in DQPalette because they are
// theme-invariant, and so views never spell out a raw white opacity.

public enum DQGlass {
    /// Tints for `dqGlass`. §5 specifies the over-imagery material as
    /// `rgba(255,255,255,0.16)` + `backdrop-blur(14)`; on Liquid Glass the blur
    /// comes from the material itself, so only the white lands, as a tint.
    public static let chipTint = Color.white.opacity(0.16)
    public static let meterTint = Color.white.opacity(0.14)

    /// Track behind the over-photo RevealMeter fill. Still painted, not tinted —
    /// it is a bar inside the glass pill, not the pill itself.
    public static let meterTrack = Color.white.opacity(0.24)

    /// Ink on glass.
    public static let ink = Color.white
    public static let inkLabel = Color.white.opacity(0.80)
    public static let inkDim = Color.white.opacity(0.62)

    /// Radar pulse rings (§7).
    public static let pulse = Color.white.opacity(0.85)

    /// Glass tint for the floating tab bar. `nav` is near-opaque by design —
    /// used raw it would cancel the material out — so the same hue lands at a
    /// strength the glass can actually carry. Tinting rather than dropping the
    /// token keeps the bar reading as dark chrome in *both* palettes; untinted,
    /// a light theme would put `navInk` grey on light glass.
    public static func nav(_ p: DQPalette) -> Color { p.nav.opacity(0.55) }
}

// MARK: - Liquid Glass
//
// Liquid Glass belongs to the layer *above* content: controls, navigation
// chrome, and anything floating over a photo or a camera feed. Content itself —
// cards, rows, panels, sheets — stays on the opaque `surface` tokens. A screen
// where everything is glass has nothing left for glass to float above, and the
// reveal hero in particular has to stay the brightest thing on screen.
//
// Reduce Transparency and Increase Contrast are handled by the material itself;
// nothing here needs to branch on them. The material also draws its own
// specular edge, which is why every call site below drops the 1pt border the
// hand-rolled version needed.

public extension View {
    /// Applies Liquid Glass with the app's tokens.
    ///
    /// - Parameters:
    ///   - shape: The glass shape. Defaults to a capsule — `DQRadius.pill`
    ///     expressed natively, so it cannot drift from the token.
    ///   - tint: An optional wash over the material. Over imagery this carries
    ///     the §5 white; over chrome it carries `nav`.
    ///   - interactive: Whether the glass reacts to touch. On for anything the
    ///     user can press, off for passive chrome.
    func dqGlass(
        in shape: some Shape = Capsule(),
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
    }
}

public enum DQScrim {
    /// RevealHero scrim (§5). Identical in both themes.
    public static let hero = LinearGradient(
        stops: [
            .init(color: .hex(0x0C0D0F, 0.5), location: 0.00),
            .init(color: .hex(0x0C0D0F, 0.0), location: 0.32),
            .init(color: .hex(0x0C0D0F, 0.0), location: 0.46),
            .init(color: .hex(0x0C0D0F, 0.9), location: 1.00)
        ],
        startPoint: .top, endPoint: .bottom
    )

    /// Behind a blocking commit overlay. Heavy enough to take the form out of
    /// reading contrast, light enough to leave it recognisable underneath — the
    /// user should still be able to see what is being saved.
    public static func heavy(_ theme: DQTheme) -> Color {
        theme == .dark ? .hex(0x0A0B0D, 0.72) : .hex(0xEFEFF1, 0.72)
    }

    /// Nearby-signal cards on HomeView — shorter card, so the scrim closes
    /// higher and harder than the hero's.
    public static let signal = LinearGradient(
        stops: [
            .init(color: .hex(0x0C0D0F, 0.30), location: 0.00),
            .init(color: .hex(0x0C0D0F, 0.0),  location: 0.40),
            .init(color: .hex(0x0C0D0F, 0.88), location: 1.00)
        ],
        startPoint: .top, endPoint: .bottom
    )
}

// MARK: - Geometry

public enum DQRadius {
    public static let hero: CGFloat = 28
    public static let card: CGFloat = 24
    public static let row: CGFloat = 20
    /// Text fields and text areas. Sits below `rRow` so an input reads as a
    /// tighter, more mechanical object than a tappable row.
    public static let field: CGFloat = 16
    public static let thumb: CGFloat = 17
    public static let sheet: CGFloat = 32
    public static let pill: CGFloat = 999
}

public enum DQSpace {
    public static let gutter: CGFloat = 16
    public static let block: CGFloat = 14
    public static let tight: CGFloat = 9
    public static let card: CGFloat = 18
    public static let safeTop: CGFloat = 58
    public static let safeBottom: CGFloat = 22
}

public enum DQSize {
    public static let ctaHeight: CGFloat = 54
    public static let ghostHeight: CGFloat = 52
    public static let iconButton: CGFloat = 38
    public static let iconButtonLarge: CGFloat = 46
    public static let minHitTarget: CGFloat = 44
    public static let meterHeight: CGFloat = 5
    public static let stepperHeight: CGFloat = 5
    /// RevealHero floor before it starts flexing (§5).
    public static let heroMinHeight: CGFloat = 200
    /// RatingBar segment height (§5).
    public static let ratingSegment: CGFloat = 9
}

// MARK: - Typography
//
// Plus Jakarta Sans (400–800) and IBM Plex Mono (400–500) ship in
// Resources/Fonts and are registered via `UIAppFonts` in Info.plist. Both are
// SIL Open Font License 1.1; the licences ship beside them.
//
// Faces are addressed by exact PostScript name rather than by asking for a
// family and a `.weight()`, which leaves the match up to the font engine and
// picks the wrong face often enough to matter at 800. Note IBM Plex Mono's
// names are irregular: Regular is `IBMPlexMono` (no suffix) and Medium is
// `IBMPlexMono-Medm`.
//
// `fixedSize:` — not `size:` — because `.custom(_:size:)` opts into Dynamic
// Type scaling, which `.system(size:)` never did. Using it here would silently
// change layout across the app under a skin change. Dynamic Type is its own
// piece of work.

public enum DQFont {
    private static func jakarta(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .custom(jakartaFace(weight), fixedSize: size)
    }
    private static func plexMono(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .custom(plexFace(weight), fixedSize: size)
    }

    private static func plexFace(_ weight: Font.Weight) -> String {
        switch weight {
        case .medium, .semibold, .bold, .heavy, .black: "IBMPlexMono-Medm"  // 500
        default:                                        "IBMPlexMono"       // 400
        }
    }

    private static func jakartaFace(_ weight: Font.Weight) -> String {
        switch weight {
        case .black, .heavy:   "PlusJakartaSans-ExtraBold"  // 800
        case .bold:            "PlusJakartaSans-Bold"       // 700
        case .semibold:        "PlusJakartaSans-SemiBold"   // 600
        case .medium:          "PlusJakartaSans-Medium"     // 500
        default:               "PlusJakartaSans-Regular"    // 400
        }
    }

    public static let displayL = jakarta(30, .heavy)   // tracking -3%
    public static let displayM = jakarta(25, .heavy)   // tracking -3%
    public static let displayS = jakarta(22, .heavy)   // tracking -2.5%
    public static let title    = jakarta(21, .heavy)   // tracking -2%
    public static let titleS   = jakarta(16, .heavy)   // tracking -2%
    public static let body     = jakarta(14, .medium)
    public static let bodyS    = jakarta(12.5, .medium)
    public static let chip     = jakarta(11.5, .semibold)
    public static let label    = jakarta(10, .bold)    // UPPERCASE, tracking +18%
    public static let mono     = plexMono(11, .medium) // tracking +10%
    public static let button   = jakarta(15, .bold)    // §5 Buttons

    /// §2 `label` is a range (9–11pt, 600–700). Use this for the sizes the
    /// screens call for rather than adding a constant per occurrence.
    public static func labelSized(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        jakarta(size, weight)
    }
    /// §2 `mono` is a range (9–12pt, 500).
    public static func monoSized(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        plexMono(size, weight)
    }
    /// Body/UI at a size the scale does not name outright.
    public static func uiSized(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        jakarta(size, weight)
    }

    // Tracking in points. SwiftUI wants points; the spec states em, so these
    // are `size × em` at each style's design size.
    public static let trackDisplay: CGFloat = -0.9    // displayL, 30 × -3%
    public static let trackDisplayM: CGFloat = -0.75  // 25 × -3%
    public static let trackDisplayS: CGFloat = -0.55  // 22 × -2.5%
    public static let trackTitle: CGFloat = -0.42     // 21 × -2%
    public static let trackTitleS: CGFloat = -0.32    // 16 × -2%
    public static let trackLabel: CGFloat = 1.8       // 10 × +18%
    public static let trackMono: CGFloat = 1.1        // 11 × +10%

    /// Tracking in points for an em letter-spacing at an arbitrary size.
    public static func track(_ size: CGFloat, em: CGFloat) -> CGFloat { size * em }
}

// MARK: - Shadows

public struct DQShadow: Sendable {
    public let color: Color
    public let radius: CGFloat
    public let y: CGFloat

    public static func standard(_ t: DQTheme) -> DQShadow {
        t == .dark ? .init(color: .black.opacity(0.50), radius: 24, y: 22)
                   : .init(color: .hex(0x121418, 0.14), radius: 22, y: 20)
    }
    public static func small(_ t: DQTheme) -> DQShadow {
        t == .dark ? .init(color: .black.opacity(0.34), radius: 11, y: 8)
                   : .init(color: .hex(0x121418, 0.08), radius: 10, y: 8)
    }
    /// Glow beneath the ember commit CTA.
    public static func ember(_ p: DQPalette) -> DQShadow {
        .init(color: p.emberGlow, radius: 15, y: 12)
    }
}

// MARK: - Motion (§7)

public enum DQMotion {
    /// Stage advance: blur + stepper + meter move together. Never stagger them.
    public static let stage: Animation = DQReveal.stageAnimation
    /// Live/presence dot: opacity 1 → 0.28 → 1.
    public static let live: Animation = .easeInOut(duration: 2).repeatForever(autoreverses: true)
    public static let liveDimOpacity: Double = 0.28
    /// Radar pulse: scale 0.6 → 2.4, opacity 0.65 → 0, two rings offset 1.3s.
    public static let radarDuration: Double = 2.6
    public static let radarRingOffset: Double = 1.3
    public static let radarScaleFrom: CGFloat = 0.6
    public static let radarScaleTo: CGFloat = 2.4
    /// Tier upgrade: breathing glow, 0 → 26px platinum → 0.
    public static let tierGlow: Animation = .easeInOut(duration: 3).repeatForever(autoreverses: true)
    public static let tierGlowRadius: CGFloat = 13   // CSS 26px blur ≈ SwiftUI radius 13
    /// Button press.
    public static let press: Animation = .easeOut(duration: 0.12)
    public static let pressScale: CGFloat = 0.97
    /// Tab-bar selection slide. Springy rather than eased: the pill is moving
    /// through a glass bar, and a linear slide reads as a swap instead.
    public static let tabSelect: Animation = .smooth(duration: 0.32)
}

// MARK: - Reveal ladder
//
// The single source of truth for the hero interaction. `EncounterSession`
// remains authoritative for advancing `revealProgress`; this only maps it.

public enum DQReveal {
    public static let maxBlur: CGFloat = 40
    /// Scale applied to the blurred image layer so blur never shows a soft edge.
    public static let layerScale: CGFloat = 1.18
    /// Progress added per successful icebreaker action.
    public static let stepGain: Double = 0.08
    public static let stageAnimation: Animation = .easeOut(duration: 0.4)

    /// Scale for the small blurred thumbnail in the icebreaker partner strip.
    /// Slightly higher than `layerScale` — from the IcebreakerScreenV2 mock.
    public static let thumbLayerScale: CGFloat = 1.22
    /// Width the §4 blur curve is calibrated against: the hero's content width
    /// (393pt frame less the 16pt gutters), not the frame itself.
    public static let referenceWidth: CGFloat = 361

    public static func blurRadius(for progress: Double) -> CGFloat {
        maxBlur * CGFloat(1 - min(max(progress, 0), 1))
    }

    /// Blur for a thumbnail narrower than the hero. The §4 curve is calibrated
    /// to a full-width card; applied raw to a 62pt thumb every stage is an
    /// identical featureless blob, which defeats the partner strip's whole
    /// purpose — keeping the unblur legible during play. Scaled by width.
    public static func blurRadius(for progress: Double, width: CGFloat) -> CGFloat {
        blurRadius(for: progress) * (width / referenceWidth)
    }

    public enum Stage: Int, CaseIterable, Sendable {
        case nearby = 1, icebreaker, revealed, connected

        public var progress: Double {
            switch self {
            case .nearby: 0.0
            case .icebreaker: 0.30
            case .revealed: 0.70
            case .connected: 1.0
            }
        }
        public var title: String {
            switch self {
            case .nearby: "Nearby"
            case .icebreaker: "Icebreaker"
            case .revealed: "Revealed"
            case .connected: "Connected"
            }
        }
        public var primaryCTA: String {
            switch self {
            case .nearby: "Start icebreaker"
            // §6.1: was "Continue". A stage-2 CTA needs somewhere to go, and the
            // only thing to continue is the icebreaker session already in flight.
            case .icebreaker: "Resume icebreaker"
            case .revealed: "NameDrop to connect"
            case .connected: "Say hello"
            }
        }
        /// Only the commit stage earns the ember CTA.
        public var usesEmberCTA: Bool { self == .revealed }
    }
}

// MARK: - Trust tiers

public enum DQTrustTier: Int, CaseIterable, Sendable {
    case bronze = 0, silver, gold, platinum

    public var name: String {
        switch self {
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold: "Gold"
        case .platinum: "Platinum"
        }
    }
    /// What each tier actually requires, in the app as built.
    ///
    /// The ladder is the campus gate, not a generic identity ladder: Bronze is
    /// the school gate, Silver the student ID card photo + liveness, Gold the
    /// ID <-> liveness face match that opens the Dating intent and NameDrop.
    public var requirement: String {
        switch self {
        case .bronze: "School email verified"
        case .silver: "Student ID and liveness check passed"
        case .gold: "Student ID matches your selfie"
        case .platinum: "Average post-meet rating ≥ 4.0"
        }
    }
    public func color(_ p: DQPalette) -> Color {
        switch self {
        case .bronze: p.bronze
        case .silver: p.silver
        case .gold: p.gold
        case .platinum: p.platinumInk
        }
    }

    /// Tinted fill behind a tier glyph. Generalises `platinumFill`'s
    /// relationship to `platinumInk` across every tier, so an upgrade reads in
    /// the destination tier's own colour rather than always in platinum.
    public func fill(_ p: DQPalette, _ theme: DQTheme) -> Color {
        self == .platinum ? p.platinumFill : color(p).opacity(theme == .dark ? 0.14 : 0.12)
    }
}

// MARK: - Environment

/// The **single** place the app's theme is decided.
///
/// Apply it once, at the app root, with `.dqTheme(DQThemePreference.resolved)`.
/// Never pin a theme per surface: a screen that hard-codes its own palette can
/// never follow a user-facing appearance setting, and shipping one is the whole
/// reason this system carries two palettes.
///
/// Pinned dark for now because the un-migrated v1 surfaces are dark-only — a
/// light theme would render half the app wrong. When the migration finishes and
/// an appearance setting lands, read it here and every v2 surface follows with
/// no other change.
public enum DQThemePreference {
    public static var resolved: DQTheme { .dark }
}

private struct DQThemeKey: EnvironmentKey {
    static let defaultValue: DQTheme = .dark
}

public extension EnvironmentValues {
    var dqTheme: DQTheme {
        get { self[DQThemeKey.self] }
        set { self[DQThemeKey.self] = newValue }
    }
    var dq: DQPalette { .of(dqTheme) }
}

public extension View {
    func dqTheme(_ theme: DQTheme) -> some View { environment(\.dqTheme, theme) }

    func dqShadow(_ shadow: DQShadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: 0, y: shadow.y)
    }
}

// MARK: - Color helper

public extension Color {
    static func hex(_ value: UInt32, _ opacity: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: opacity
        )
    }
}
