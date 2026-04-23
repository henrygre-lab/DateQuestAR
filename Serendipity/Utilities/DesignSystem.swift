import SwiftUI

// MARK: - DQ Design System
// Centralized design tokens for Serendipity.
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
