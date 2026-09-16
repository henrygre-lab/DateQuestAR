// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets — no school allowlist, domain list or API key in the
//     client; the allowlist is enforced by schoolGate.ts against Firestore
// [x] schoolId and enrollmentStatus are never written here. This manager calls
//     Cloud Functions and reads back what they issued; firestore.rules rejects a
//     client write to either field.
// [x] Phone number is stored in Keychain (kSecClassGenericPassword, device-only,
//     ThisDeviceOnly accessibility) — never UserDefaults, never the profile
//     document, never analytics, never a log line
// [x] The school email is submitted to the function but never persisted on-device
//     and never written to the profile — the verification record holds it
// [x] Errors are generic — a caller cannot learn whether an address, account or
//     school exists from the message shown
// [x] Custom claims are refreshed via getIDTokenResult(forcingRefresh:) after any
//     gate transition, because firestore.rules reads claims, not the profile
// [x] LocalAuthentication is not used here; the Firebase session is authoritative
// [x] No PII logged — Log.auth messages carry status transitions only

import Foundation
import Combine
import Security
import FirebaseAuth
import FirebaseFunctions

// MARK: - School Gate State

/// Where the user is in the Fizz-style gate. `.none` and `.pending` grant
/// nothing; only `.verified` carries a community.
enum SchoolGateState: Equatable {
    case idle
    case awaitingPhoneCode
    case awaitingMagicLink(schoolDisplayName: String)
    case awaitingEnrollmentReview
    case verified(schoolId: String, schoolDisplayName: String)
    case failed(String)
}

// MARK: - SchoolGateManager

/// Owns the school gate: phone + allowlisted .edu magic link, school Google /
/// Microsoft OAuth, or incoming-student enrollment proof.
///
/// Every decision in here is made by a Cloud Function. This type's job is to
/// collect input, call the function, refresh the ID token so the new custom
/// claims take effect, and publish the result.
@MainActor
final class SchoolGateManager: ObservableObject {
    static let shared = SchoolGateManager()

    @Published private(set) var state: SchoolGateState = .idle
    @Published private(set) var isBusy = false

    /// The community the server issued, once the gate has passed.
    @Published private(set) var schoolId: String?
    @Published private(set) var schoolDisplayName: String?

    private let functions = Functions.functions()
    private var phoneVerificationID: String?

    private init() {}

    // MARK: - Generic failure
    //
    // One message for every failure mode. Distinguishing "that domain isn't
    // allowlisted" from "you've used your attempts" hands an attacker a probe for
    // which schools and accounts exist.
    private static let genericFailure =
        "We couldn't verify your school. Check your school email and try again."

    // MARK: - Phone Step

    /// Starts phone verification. The number is held in Keychain, not in a
    /// property that could end up in a crash log or a Firestore write.
    func startPhoneVerification(phoneNumber: String) async {
        isBusy = true
        defer { isBusy = false }

        do {
            let verificationID = try await PhoneAuthProvider.provider()
                .verifyPhoneNumber(phoneNumber, uiDelegate: nil)
            phoneVerificationID = verificationID
            KeychainStore.set(phoneNumber, for: KeychainStore.phoneNumberKey)
            state = .awaitingPhoneCode
            Log.school.debug("Phone verification started")
        } catch {
            // The provider's message distinguishes real numbers from fake ones.
            state = .failed(Self.genericFailure)
            Log.school.error("Phone verification could not start")
        }
    }

    /// Confirms the SMS code and signs the user in (or links the credential).
    func confirmPhoneCode(_ code: String) async {
        guard let verificationID = phoneVerificationID else {
            state = .failed(Self.genericFailure)
            return
        }

        isBusy = true
        defer { isBusy = false }

        let credential = PhoneAuthProvider.provider()
            .credential(withVerificationID: verificationID, verificationCode: code)

        do {
            if let user = Auth.auth().currentUser {
                _ = try await user.link(with: credential)
            } else {
                _ = try await Auth.auth().signIn(with: credential)
            }
            phoneVerificationID = nil
            state = .idle
            Log.school.debug("Phone verified")
        } catch {
            state = .failed(Self.genericFailure)
            Log.school.error("Phone code rejected")
        }
    }

    // MARK: - Magic Link Step

    /// Asks the backend to send a sign-in link to a school address.
    ///
    /// The address is checked against the server-side allowlist; this client
    /// carries no list of its own, so there is nothing here to edit.
    func requestMagicLink(schoolEmail: String) async {
        isBusy = true
        defer { isBusy = false }

        do {
            let result = try await functions
                .httpsCallable("requestSchoolMagicLink")
                .call(["schoolEmail": schoolEmail])

            let payload = result.data as? [String: Any]
            let name = payload?["schoolDisplayName"] as? String ?? "your school"
            state = .awaitingMagicLink(schoolDisplayName: name)
            Log.school.debug("School magic link requested")
        } catch {
            state = .failed(Self.genericFailure)
            Log.school.error("School magic link request failed")
        }
    }

    /// Completes sign-in from a tapped email link, then finishes the gate.
    func completeMagicLink(url: URL, schoolEmail: String) async {
        guard Auth.auth().isSignIn(withEmailLink: url.absoluteString) else {
            state = .failed(Self.genericFailure)
            return
        }

        isBusy = true
        defer { isBusy = false }

        let credential = EmailAuthProvider.credential(withEmail: schoolEmail,
                                                      link: url.absoluteString)
        do {
            if let user = Auth.auth().currentUser {
                // Links the school address to the phone-authenticated account, so
                // the token carries both a phone and a verified school email.
                _ = try await user.link(with: credential)
            } else {
                _ = try await Auth.auth().signIn(with: credential)
            }
            await completeGate()
        } catch {
            state = .failed(Self.genericFailure)
            Log.school.error("School email link could not be completed")
        }
    }

    // MARK: - OAuth Step

    /// Finishes the gate after a school Google / Microsoft sign-in.
    ///
    /// There is nothing extra to send: the function reads the verified email off
    /// the ID token, so the tenant check happens on evidence the client cannot
    /// author.
    func completeOAuthGate() async {
        await completeGate()
    }

    // MARK: - Enrollment Proof Step

    /// Submits an admission or enrollment document for an incoming student.
    ///
    /// `storagePath` must be inside the caller's write-only verification prefix;
    /// the function re-checks that, and Storage rules make the object unreadable
    /// to every client including its uploader.
    func submitEnrollmentProof(schoolId: String, storagePath: String) async {
        isBusy = true
        defer { isBusy = false }

        do {
            _ = try await functions
                .httpsCallable("submitEnrollmentProof")
                .call(["schoolId": schoolId, "storagePath": storagePath])
            await refreshClaims()
            state = .awaitingEnrollmentReview
            Log.school.debug("Enrollment proof submitted")
        } catch {
            state = .failed(Self.genericFailure)
            Log.school.error("Enrollment proof submission failed")
        }
    }

    // MARK: - Gate Completion

    /// Calls `completeSchoolGate` and adopts whatever community it issued.
    private func completeGate() async {
        do {
            let result = try await functions.httpsCallable("completeSchoolGate").call()
            guard let payload = result.data as? [String: Any],
                  let issuedSchoolId = payload["schoolId"] as? String,
                  let issuedName = payload["schoolDisplayName"] as? String else {
                state = .failed(Self.genericFailure)
                return
            }

            // Claims decide what firestore.rules will allow. Until the token is
            // refreshed the client holds a community it cannot actually read.
            await refreshClaims()

            schoolId = issuedSchoolId
            schoolDisplayName = issuedName
            state = .verified(schoolId: issuedSchoolId, schoolDisplayName: issuedName)
            Log.school.debug("School gate passed")
        } catch {
            state = .failed(Self.genericFailure)
            Log.school.error("School gate could not be completed")
        }
    }

    /// Forces an ID token refresh so newly issued custom claims take effect.
    func refreshClaims() async {
        guard let user = Auth.auth().currentUser else { return }
        _ = try? await user.getIDTokenResult(forcingRefresh: true)
    }

    // MARK: - Spring Break Presence

    /// Asks the backend to confirm the device is inside a live destination fence.
    ///
    /// Sends a precision-7 geohash, never a coordinate. The server decodes it,
    /// compares it against the destination's own centre and radius, checks the
    /// server-dated window, and only then issues the short-lived claim that opens
    /// the cross-school pool. There is no way to assert presence from here.
    ///
    /// Returns the destination's official display label on success.
    func confirmDestinationPresence(destinationId: String, geohash: String) async -> String? {
        do {
            let result = try await functions
                .httpsCallable("confirmDestinationPresence")
                .call(["destinationId": destinationId, "geohash": geohash])
            await refreshClaims()
            let payload = result.data as? [String: Any]
            Log.school.debug("Destination presence confirmed")
            return payload?["displayLabel"] as? String
        } catch {
            // Not an error worth surfacing: being outside the fence is the normal
            // case for almost every user, almost all of the time.
            Log.school.debug("Destination presence not confirmed")
            return nil
        }
    }

    // MARK: - Campus Presence (the Big Game rule)

    /// Asks the backend to confirm the device is standing on a given campus.
    ///
    /// Same mechanism as destination presence, aimed at a `schools/{id}` fence
    /// instead: a precision-7 geohash goes up, the server decodes it against the
    /// school document's own centre and radius, and only then issues the claim
    /// that puts the user in that campus's pool.
    ///
    /// Returns the campus display name on success. A home student gets a
    /// confirmation with `isVisiting` false and no claim — their `schoolId`
    /// already places them there, and issuing one would make them look like a
    /// visitor to the security rules.
    func confirmCampusPresence(schoolId: String, geohash: String) async -> (name: String, isVisiting: Bool)? {
        do {
            let result = try await functions
                .httpsCallable("confirmCampusPresence")
                .call(["schoolId": schoolId, "geohash": geohash])

            let payload = result.data as? [String: Any]
            let isVisiting = payload?["isVisiting"] as? Bool ?? false

            // Only a visiting confirmation mints a claim, so only that one needs
            // the token refreshed before firestore.rules will honour it.
            if isVisiting { await refreshClaims() }

            guard let name = payload?["schoolDisplayName"] as? String else { return nil }
            Log.school.debug("Campus presence confirmed")
            return (name, isVisiting)
        } catch {
            // Being off every campus is the normal state for most people most of
            // the time; this is not an error worth surfacing on its own.
            Log.school.debug("Campus presence not confirmed")
            return nil
        }
    }

    /// Drops a visiting claim when the user leaves the campus or it lapses.
    func clearCampusPresence() async {
        _ = try? await functions.httpsCallable("clearCampusPresence").call()
        await refreshClaims()
        Log.school.debug("Campus presence cleared")
    }

    /// Drops destination presence when the window closes or the user leaves.
    /// Clears both the claim and the profile flag, so no cross-school visibility
    /// survives the trip home.
    func clearDestinationPresence() async {
        _ = try? await functions.httpsCallable("clearDestinationPresence").call()
        await refreshClaims()
        Log.school.debug("Destination presence cleared")
    }

    // MARK: - Sign Out

    /// Clears the on-device phone number alongside the session. A number left in
    /// Keychain after sign-out belongs to nobody.
    func clearLocalIdentity() {
        KeychainStore.delete(KeychainStore.phoneNumberKey)
        schoolId = nil
        schoolDisplayName = nil
        state = .idle
    }
}

// MARK: - Keychain

/// Minimal Keychain wrapper for the one value that must never touch
/// `UserDefaults`: the user's phone number.
///
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` keeps it out of iCloud Keychain
/// and out of encrypted backups, so restoring a backup onto another device does
/// not carry the number with it.
enum KeychainStore {
    static let phoneNumberKey = "serendipity.schoolgate.phone"

    private static let service = "app.serendipity.schoolgate"

    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
