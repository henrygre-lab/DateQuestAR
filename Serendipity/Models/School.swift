// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens — no school allowlist is compiled
//     into the client; domains and geofences are read from schools/{schoolId}
// [x] schools/* is auth-read, admin-write (firestore.rules) — the client can read
//     a school doc but can never create or amend one
// [x] Campus and destination geofences are backend documents, never client polygons
// [x] No raw coordinates stored — geofence centres are geohash precision 7,
//     decoded on-device only to arm a CLCircularRegion, never rendered
// [x] displayName / displayLabel are server-supplied community identity strings and
//     are the ONLY place names allowed in the UI (DESIGN_SYSTEM.md §8) — no
//     neighbourhood, venue, landmark, building or geohash is ever shown
// [x] Fail-closed pairing — CommunityGate returns false for .none scope, for any
//     unverified party, and for any cross-school pair without a live claim
// [x] Visiting a campus requires a server-issued, expiring presence claim.
//     isPresent() checks the expiry, so a lapsed claim stops qualifying with no
//     write and no cleanup pass.
// [x] SpringBreakStatus is presentation state only. It never widens a pool: when
//     it is .paused the scope has already fallen back to campus or .none, and
//     CommunityGate does not read it.

import Foundation
import FirebaseFirestore

// MARK: - Campus Geofence

/// A circular campus boundary, stored on the school document. Quest Mode runs
/// inside it and auto-pauses outside it.
struct CampusGeofence: Codable, Equatable {
    /// Geohash precision 7 (~150 m cell). Decoded on-device solely to arm a
    /// `CLCircularRegion`; never written back, never displayed.
    var centerGeohash: String
    var radiusMeters: Double
}

// MARK: - School

/// A verified campus community. Written by admins and `schoolGate.ts`; the
/// client reads it to render community identity and arm the campus geofence.
struct School: Identifiable, Codable, Equatable {
    /// Firestore document ID — this is the canonical `schoolId`.
    @DocumentID var id: String?

    /// Community identity shown in the UI, e.g. "UCLA" in "Quest Mode · UCLA".
    var displayName: String

    /// Longer form for settings and the trust centre, e.g. "University of California, Los Angeles".
    var fullName: String

    /// Mirror of the server allowlist, for client-side copy only ("use your
    /// @ucla.edu address"). The authoritative check runs in `schoolGate.ts` —
    /// a client that edits this list gains nothing.
    var allowlistedEmailDomains: [String]

    /// Hosted-domain hints for the school Google / Microsoft OAuth path.
    /// Advisory: the server re-checks the domain on the returned token.
    var oauthTenantHints: [String]

    var campus: CampusGeofence

    /// False parks the whole community — no Quest Mode, no new gate passes.
    var isActive: Bool
}

// MARK: - Spring Break Destination

/// A time-boxed, server-dated destination where verified students from *any*
/// allowlisted school may see each other. Colleges travel to the same handful of
/// places; the product follows them there without becoming a city nightlife app.
///
/// Both the geofence and the window come from this backend document. There is no
/// client-side destination list and no client-supplied polygon.
struct SpringBreakDestination: Identifiable, Codable, Equatable {
    @DocumentID var id: String?

    /// Official destination label, server-supplied, e.g. "Cancún · Spring Break".
    /// Renderable as data (ruling #3) — it is not a user-typed place name and not
    /// a statement about where any individual is standing.
    var displayLabel: String

    /// Geohash precision 7 centre + radius. Same handling as `CampusGeofence`:
    /// decoded only to arm a region, never rendered.
    var centerGeohash: String
    var radiusMeters: Double

    /// Server-dated activation window. Outside it the destination is inert even
    /// if the user is standing inside the fence.
    var windowStart: Timestamp
    var windowEnd: Timestamp

    /// Kill switch, independent of the window.
    var isActive: Bool

    /// Local hour (0–23) after which the destination is treated as dusk: Squad
    /// Radar becomes the default and the radius tightens.
    var duskLocalHour: Int

    /// Tightened Quest radius, in miles, applied after `duskLocalHour`.
    var duskRadiusMiles: Double

    // MARK: - Window

    /// True only when the destination is switched on *and* inside its dated
    /// window. Fail-closed: a malformed window yields false.
    func isLive(at date: Date = Date()) -> Bool {
        guard isActive else { return false }
        let start = windowStart.dateValue()
        let end = windowEnd.dateValue()
        guard start < end else { return false }
        return date >= start && date <= end
    }

    /// True after the destination's local dusk hour, using the device calendar.
    /// Cosmetic only — it selects Squad Radar defaults and the tighter radius.
    /// It never relaxes a gate, so a device clock skew cannot widen the pool.
    func isAfterDusk(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        calendar.component(.hour, from: date) >= duskLocalHour
    }
}

// MARK: - Community Scope

/// Which pool the current user may see, decided by where they physically are.
///
/// This is the single place the same-school rule and its one exception live.
/// `.none` is the default and means Quest Mode is paused.
enum CommunityScope: Equatable {
    /// On the verified campus of `schoolId` — same-school pool only.
    case campus(schoolId: String)

    /// Inside a live Spring Break destination fence — cross-school pool of
    /// school-verified students, scoped to that destination.
    case springBreak(destinationId: String, displayLabel: String)

    /// Off campus and not inside any live destination fence. Quest Mode pauses.
    case none

    var allowsQuestMode: Bool {
        self != .none
    }

    /// True only inside a live Spring Break fence. Used to widen the pool and to
    /// switch on the destination's dusk safety posture.
    var isSpringBreak: Bool {
        if case .springBreak = self { return true }
        return false
    }
}

// MARK: - Visiting Campus Status

/// Whether the device is confirmed on a campus that is not the user's own, and
/// if not, why it stopped.
///
/// Deliberately a separate type from `SpringBreakStatus` rather than one shared
/// "presence" enum. They follow the same pattern — claim, 15-minute refresh,
/// explicit pause — but they answer different questions ("which campus am I
/// visiting" versus "is the destination window live"), carry different copy, and
/// the Spring Break path is working and frozen. Merging them would mean
/// reworking a path that has nothing wrong with it to save two dozen lines.
enum VisitingCampusStatus: Equatable {

    /// Not visiting. Either on the home campus, or nowhere in particular.
    case inactive

    /// Server-confirmed presence on another school's campus.
    case active(schoolId: String, displayName: String)

    /// The visiting claim lapsed. The pool has already narrowed; this is what
    /// tells the user so.
    case paused(displayName: String, reason: PauseReason)

    enum PauseReason: Equatable {
        /// Walked off the campus fence.
        case leftFence
        /// Quest Mode was switched off, so presence stopped being refreshed.
        case questModeOff
        /// The backend declined or could not be reached on a refresh.
        case refreshFailed
    }

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    /// The campus being visited, for the Quest card title.
    var schoolDisplayName: String? {
        switch self {
        case .inactive:                    return nil
        case .active(_, let name):         return name
        case .paused(let name, _):         return name
        }
    }

    /// One line for Home and Radar. Nil unless paused.
    ///
    /// Says what happened and what the rule is, because "Quest stopped" without
    /// "you have to be on a campus" reads like a bug rather than a boundary.
    var pausedMessage: String? {
        guard case .paused = self else { return nil }
        return "Left campus — Quest is only on a school fence."
    }
}

// MARK: - Spring Break Status

/// Whether the cross-school Spring Break pool is open for this device, and if
/// not, why.
///
/// Deliberately separate from `CommunityScope`. The scope answers "who may I
/// see", and `CommunityGate` reads it; this answers "what should the screen tell
/// me". Folding a paused state into the scope would either add a case
/// `CommunityGate` has to interpret — widening the surface of the same-school
/// rule — or reduce to `.none`, which is the silent fallback this type exists to
/// prevent.
enum SpringBreakStatus: Equatable {

    /// Not at a destination. The ordinary case, for almost everyone, almost always.
    case inactive

    /// Server-confirmed presence at a live destination. The cross-school pool is open.
    case active(destinationId: String, displayLabel: String)

    /// Presence has lapsed. The pool is closed and the user is back to
    /// same-school, and the UI says so rather than letting them assume otherwise.
    case paused(displayLabel: String, reason: PauseReason)

    enum PauseReason: Equatable {
        /// Walked out of the destination fence.
        case leftFence
        /// Quest Mode was switched off, so presence stopped being refreshed.
        case questModeOff
        /// The backend declined or could not be reached on a refresh.
        case refreshFailed
        /// The destination's server-dated window closed.
        case windowEnded
    }

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    /// Copy for the Home and Radar surfaces.
    ///
    /// `windowEnded` gets its own line: telling someone to keep Quest Mode on at
    /// the destination would be false once the window has closed, and there is
    /// nothing they can do about it.
    var pausedMessage: String? {
        guard case .paused(_, let reason) = self else { return nil }
        switch reason {
        case .windowEnded:
            return "Spring Break has ended — you're back to your own school only."
        case .leftFence, .questModeOff, .refreshFailed:
            return "Spring Break paused — keep Quest on at the destination to stay in the multi-school pool."
        }
    }

    /// The destination this status refers to, for a badge or a title.
    var displayLabel: String? {
        switch self {
        case .inactive:                          return nil
        case .active(_, let label):              return label
        case .paused(let label, _):              return label
        }
    }
}

// MARK: - Community Gate

/// Pairwise eligibility. Every nearby, match and icebreaker path runs through
/// `canShare` before a partner is surfaced.
///
/// Client-side this is a courtesy filter — `firestore.rules` enforces the same
/// same-school predicate on the server, and it is the rules that count.
enum CommunityGate {

    /// Whether `viewer` may see `candidate` in the given scope.
    ///
    /// Fail-closed by construction: every branch requires both parties to hold a
    /// server-issued `schoolId`, an enrollment status that grants access, an
    /// active account and a verified student ID. Locals and unverified tourists
    /// inside a Spring Break fence match no branch.
    static func canShare(viewer: UserProfile,
                         candidate: UserProfile,
                         in scope: CommunityScope) -> Bool {
        guard viewer.uid != candidate.uid else { return false }
        guard viewer.canStartQuestMode, candidate.canStartQuestMode else { return false }

        switch scope {
        case .none:
            // Off campus, outside every live window. No pool at all.
            return false

        case .campus(let schoolId):
            // Both parties must be on *this* campus. Two ways to qualify, and
            // the asymmetry is the point:
            //
            // - a home student, whose schoolId is this campus; or
            // - a visitor from another allowlisted school holding a live,
            //   server-issued presence claim on it.
            //
            // A Michigan student standing on the UCLA lawn is in pool now — that
            // is the Big Game rule. A Michigan student who merely says they are
            // is not, because the claim comes from the server and expires.
            guard viewer.schoolId != nil, candidate.schoolId != nil else { return false }
            return viewer.isPresent(onCampus: schoolId)
                && candidate.isPresent(onCampus: schoolId)

        case .springBreak:
            // Cross-school, but school-verified only. Both parties already
            // cleared canStartQuestMode above, which requires a schoolId, an
            // access-granting enrollment status and a verified student ID.
            return viewer.schoolId != nil && candidate.schoolId != nil
        }
    }

    /// Whether the pair may match on Dating specifically. Adds the ID ↔ liveness
    /// face match and verified-adult requirements on top of `canShare`.
    static func canShareForDating(viewer: UserProfile,
                                  candidate: UserProfile,
                                  in scope: CommunityScope) -> Bool {
        canShare(viewer: viewer, candidate: candidate, in: scope)
            && viewer.canUseDatingIntent
            && candidate.canUseDatingIntent
    }
}
