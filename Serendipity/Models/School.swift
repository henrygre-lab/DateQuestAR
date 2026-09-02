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
//     unverified party, and for any cross-school pair outside a live SB window

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
            // Same school only. Both parties must belong to *this* campus, not
            // merely to some campus — a Michigan student standing on the UCLA
            // lawn is still out of pool.
            guard let viewerSchool = viewer.schoolId,
                  let candidateSchool = candidate.schoolId else { return false }
            return viewerSchool == schoolId && candidateSchool == schoolId

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
