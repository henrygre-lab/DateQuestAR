import SwiftUI

// MARK: - DQ Design System (v1 — LEGACY)
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │ THIS IS THE LEGACY SYSTEM. THE APP IS MID-MIGRATION.                  │
// │                                                                      │
// │  • v1 — this file. `enum DQ`, dark-only, purple accent, reached as    │
// │    static constants: `DQ.Colors.accent`, `DQ.Spacing.xl`. Still used  │
// │    by ~30 views, which is why it is still here.                      │
// │  • v2 — Utilities/DQDesignSystem.swift. Dual-theme, ember accent,     │
// │    read from the environment: `@Environment(\.dq)` for colour,        │
// │    `DQRadius`/`DQSpace`/`DQSize` for geometry, `DQFont` for type.     │
// │                                                                      │
// │ The two names are close enough to be a trap. If you are touching a    │
// │ view, check which system it already reads and stay in it — do not     │
// │ mix them in one view. Migrated so far: EncounterView and the          │
// │ components it owns. New work should target v2.                        │
// └──────────────────────────────────────────────────────────────────────┘
//
// Usage: DQ.Colors.accent, DQ.Typography.screenTitle(), DQ.Spacing.xl, etc.

enum DQ {

    // MARK: - Colors

    enum Colors {
        // Backgrounds
        static let backgroundPrimary   = Color(hex: "#000000")
        static let backgroundSecondary = Color(hex: "#0A0A14")
        static let backgroundTertiary  = Color(hex: "#0F0F1A")

        // Accent
        static let accent              = Color(hex: "#A855F7")   // vibrant purple
        static let accentSecondary     = Color(hex: "#A855F7").opacity(0.5)
        static let accentSubtle        = Color(hex: "#A855F7").opacity(0.15)
        static let accentBold          = Color(hex: "#A855F7").opacity(0.4)
        static let accentPink          = Color(hex: "#EC4899")
        static let accentOrange        = Color(hex: "#F97316")

        // Surfaces (white-on-dark overlays)
        static let surfaceElevated     = Color.white.opacity(0.10)
        static let surfaceCard         = Color.white.opacity(0.06)
        static let surfaceSubtle       = Color.white.opacity(0.04)
        static let surfaceFaint        = Color.white.opacity(0.05)

        // Text
        static let textPrimary         = Color.white
        static let textSecondary       = Color.white.opacity(0.7)
        static let textTertiary        = Color.white.opacity(0.55)
        static let textQuaternary      = Color.white.opacity(0.4)
        static let textPlaceholder     = Color.white.opacity(0.3)

        // Status
        static let success             = Color(hex: "#22C55E")
        static let warning             = Color(hex: "#F59E0B")
        static let error               = Color(hex: "#EF4444")
        static let info                = Color(hex: "#3B82F6")

        // Signal — single restrained action/active accent (Rebuild direction:
        // dark-only, high-contrast, no purple/pink/neon).
        static let signal              = Color(hex: "#4D8DFF")
        static let signalMuted         = Color(hex: "#4D8DFF").opacity(0.45)
        static let signalSubtle        = Color(hex: "#4D8DFF").opacity(0.14)

        // Danger — named per the Rebuild token set (shares the status red).
        static let danger              = Color(hex: "#EF4444")

        // Monochrome ramp — dark-first, high contrast. Foundation of the Rebuild
        // surfaces so the UI reads calm and neutral rather than tinted.
        static let mono0               = Color(hex: "#000000")
        static let mono50              = Color(hex: "#0A0A0C")
        static let mono100             = Color(hex: "#131317")
        static let mono200             = Color(hex: "#1C1C22")
        static let mono300             = Color(hex: "#26262E")
        static let mono400             = Color(hex: "#33333D")
        static let mono500             = Color(hex: "#4A4A57")
        static let mono600             = Color(hex: "#6B6B7A")
        static let mono700             = Color(hex: "#9494A2")
        static let mono800             = Color(hex: "#C4C4CE")
        static let mono900             = Color(hex: "#F4F4F6")

        // Trust Tiers
        static let trustBronze         = Color(hex: "#CD7F32")
        static let trustSilver         = Color(hex: "#C0C0C0")
        static let trustGold           = Color(hex: "#FFD700")
        static let trustPlatinum       = Color(hex: "#E5E4E2")

        static func trustColor(for level: UserProfile.TrustLevel) -> Color {
            switch level {
            case .bronze:   trustBronze
            case .silver:   trustSilver
            case .gold:     trustGold
            case .platinum: trustPlatinum
            }
        }

        // Gamification
        static let xpColor             = Color(hex: "#F97316")
        static let levelColor          = Color(hex: "#FBBF24")
        static let questColor          = Color(hex: "#A855F7")
        static let connectionColor     = Color(hex: "#3B82F6")
    }

    // MARK: - Typography

    enum Typography {
        static func screenTitle() -> Font { .system(size: 32, weight: .bold, design: .default) }
        static func sectionHeader() -> Font { .system(size: 22, weight: .bold, design: .default) }
        static func cardTitle() -> Font { .system(size: 17, weight: .semibold, design: .default) }
        static func body() -> Font { .system(size: 16, weight: .regular, design: .default) }
        static func bodyBold() -> Font { .system(size: 16, weight: .semibold, design: .default) }
        static func caption() -> Font { .system(size: 13, weight: .regular, design: .default) }
        static func captionSmall() -> Font { .system(size: 11, weight: .medium, design: .default) }
        static func footnote() -> Font { .system(size: 12, weight: .regular, design: .default) }
        static func heroNumber() -> Font { .system(size: 28, weight: .bold, design: .rounded) }
        static func buttonLabel() -> Font { .system(size: 17, weight: .semibold, design: .default) }
        static func statValue() -> Font { .system(size: 20, weight: .bold, design: .rounded) }
        static func statLabel() -> Font { .system(size: 11, weight: .medium, design: .default) }
        static func settingTitle() -> Font { .system(size: 16, weight: .medium, design: .default) }
        static func sectionLabel() -> Font { .system(size: 13, weight: .semibold, design: .default) }

        /// Monospaced scale for numerics (compatibility %, distance, timers, counts).
        /// Keeps figures tabular and calm in the Rebuild surfaces.
        static func mono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxxs: CGFloat = 4
        static let xxs: CGFloat  = 6
        static let xs: CGFloat   = 8
        static let sm: CGFloat   = 10
        static let md: CGFloat   = 12
        static let lg: CGFloat   = 16
        static let xl: CGFloat   = 20
        static let xxl: CGFloat  = 24
        static let xxxl: CGFloat = 28
        static let huge: CGFloat = 32
        static let giant: CGFloat = 40
    }

    // MARK: - Corner Radii

    enum Radii {
        static let small: CGFloat  = 8
        static let medium: CGFloat = 12
        static let large: CGFloat  = 16
        static let xl: CGFloat     = 20
        static let xxl: CGFloat    = 24
        static let pill: CGFloat   = 100
    }

    // MARK: - Sizing

    enum Sizing {
        static let buttonHeight: CGFloat      = 56
        static let oauthButtonHeight: CGFloat = 52
        static let iconLarge: CGFloat         = 80
        static let iconMedium: CGFloat        = 72
        static let iconSmall: CGFloat         = 64
        static let avatarSize: CGFloat        = 56
        static let avatarLarge: CGFloat       = 120
        static let timerRingSize: CGFloat     = 80
        static let radarBlipSize: CGFloat     = 12
        static let strokeWidth: CGFloat       = 1
        static let strokeWidthThick: CGFloat  = 6
        static let statCardHeight: CGFloat    = 88
    }

    // MARK: - Gradients

    enum Gradients {
        static let background = LinearGradient(
            colors: [Colors.backgroundPrimary, Colors.backgroundTertiary],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let splash = LinearGradient(
            colors: [.black, Colors.backgroundSecondary],
            startPoint: .top, endPoint: .bottom
        )
        static let proximity = LinearGradient(
            colors: [Colors.info, Colors.accent],
            startPoint: .leading, endPoint: .trailing
        )
        static let topFade = LinearGradient(
            colors: [.black.opacity(0.6), .clear],
            startPoint: .top, endPoint: .bottom
        )
        static let bottomFade = LinearGradient(
            colors: [.clear, .black.opacity(0.8)],
            startPoint: .top, endPoint: .bottom
        )
        // Premium accent gradients
        static let accentGlow = LinearGradient(
            colors: [Colors.accent, Colors.accentPink],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let ctaGradient = LinearGradient(
            colors: [Colors.accentOrange, Colors.accentPink],
            startPoint: .leading, endPoint: .trailing
        )
        static let heroOverlay = RadialGradient(
            colors: [Colors.accent.opacity(0.2), .clear],
            center: .topTrailing, startRadius: 50, endRadius: 300
        )
    }

    // MARK: - Shadows

    enum Shadows {
        static let card = Color.black.opacity(0.25)
        static let cardRadius: CGFloat = 16
        static let glow = Colors.accent.opacity(0.3)
        static let glowRadius: CGFloat = 20
    }

    // MARK: - Animation

    enum Anim {
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let quick = SwiftUI.Animation.easeOut(duration: 0.15)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.6)
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.7)
        static let bouncy = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.6)
        static let stateTransition = SwiftUI.Animation.easeInOut(duration: 0.4)
    }
}
