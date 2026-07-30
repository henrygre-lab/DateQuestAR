//  DesignSystem.swift
//  Serendipity — DesignSystem v2 (DQ tokens)
//
//  Dual-theme token layer. Views must read `DQ.<token>` from the environment
//  theme — never hard-code a hex. See DESIGN_SYSTEM.md for rationale and usage.

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

// MARK: - Geometry

public enum DQRadius {
    public static let hero: CGFloat = 28
    public static let card: CGFloat = 24
    public static let row: CGFloat = 20
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
}

// MARK: - Typography
//
// Bundle "Plus Jakarta Sans" and "IBM Plex Mono". `.system` fallbacks keep the
// hierarchy intact if the fonts are missing.

public enum DQFont {
    private static func jakarta(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .custom("PlusJakartaSans", size: size).weight(weight)
    }
    private static func plexMono(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .custom("IBMPlexMono", size: size).weight(weight)
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

    /// Tracking in points for a given style at its design size.
    public static let trackDisplay: CGFloat = -0.9
    public static let trackTitle: CGFloat = -0.42
    public static let trackLabel: CGFloat = 1.8
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

    public static func blurRadius(for progress: Double) -> CGFloat {
        maxBlur * CGFloat(1 - min(max(progress, 0), 1))
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
    public var requirement: String {
        switch self {
        case .bronze: "Email verified"
        case .silver: "Liveness check passed"
        case .gold: "Government ID face match"
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
}

// MARK: - Environment

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
