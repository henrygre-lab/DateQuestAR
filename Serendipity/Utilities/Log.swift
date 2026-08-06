import Foundation
import os

/// Unified logging, one instance per subsystem area.
///
/// This replaces the `print("[Tag] …")` calls the app used to carry. Two things
/// were wrong with those, and the first matters here more than it would in most
/// apps:
///
/// - **`print` is not compiled out of release builds.** Every line went to the
///   device log on a shipping build, and some of them carried the exact facts
///   this product exists to keep quiet — a user's geohash, a match's display
///   name, a reported user's uid. Storing coordinates as a geohash is worth
///   nothing if the app prints one on the way past.
/// - There was no level, no category and no subsystem, so nothing could be
///   filtered, and severity was carried by emoji in the string.
///
/// Both are fixed by handing the message to `Logger` as a `String` marked
/// `.private`, which redacts it in any log a shipping device hands out while
/// leaving it readable when attached to Xcode or Console. The message is built
/// through an autoclosure behind an `isEnabled` check, so a disabled level
/// costs nothing — including the interpolation.
///
/// Passing an already-built `String` rather than interpolating into the
/// `Logger` call directly is deliberate: `OSLogMessage` interpolation only
/// accepts a fixed set of types, and most of what gets logged here is enums and
/// `Error`s that would each need a `String(describing:)` at the call site.
struct Log {
    // MARK: - Categories

    static let app = Log("App")
    static let ar = Log("ARKit")
    static let alertCaps = Log("AlertCaps")
    static let balance = Log("Balance")
    static let firestore = Log("Firestore")
    static let gamification = Log("Gamification")
    static let haptics = Log("Haptics")
    static let location = Log("Location")
    static let match = Log("Match")
    static let proximity = Log("Proximity")
    static let referral = Log("Referral")
    static let reveal = Log("Reveal")
    static let safety = Log("Safety")
    static let waitlist = Log("Waitlist")
    static let xp = Log("XP")

    // MARK: - Storage

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.serendipity.app"

    private let logger: Logger

    private init(_ category: String) {
        logger = Logger(subsystem: Self.subsystem, category: category)
    }

    // MARK: - Levels

    /// Development tracing. Not persisted, and dropped entirely unless
    /// something is listening — the right level for anything that describes
    /// normal operation.
    func debug(_ message: @autoclosure () -> String) {
        guard logger.isEnabled(type: .debug) else { return }
        // Bound to a local first: `OSLogMessage` interpolation escapes what it
        // captures, which a non-escaping autoclosure cannot supply directly.
        let text = message()
        logger.debug("\(text, privacy: .private)")
    }

    /// A failure, or an event a human should see in the log without being
    /// asked to look. Severity lives here rather than in an emoji in the string.
    func error(_ message: @autoclosure () -> String) {
        let text = message()
        logger.error("\(text, privacy: .private)")
    }
}
