// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] The student ID decision is made by studentIdVerification.ts. The on-device
//     Vision comparison here is a pre-flight hint shown to the user before an
//     upload — it sets no field and gates nothing.
// [x] studentIDStatus, verifiedAge and trustLevel are read back from the server,
//     never written by this client; firestore.rules rejects such a write
// [x] Student ID photos and liveness frames go to the write-only Storage prefix
//     verification/{uid}/ — unreadable to every client including the uploader,
//     deleted by the function once the outcome is recorded, and never written to
//     a profile document or a nearby payload
// [x] Returned data is minimal: {studentIDStatus, capability booleans} — no image,
//     no score, no extracted document text
// [x] No PII logged — status transitions only; no uid, name, DOB or document text
// [x] Rate limiting enforced server-side (3 attempts/hour) — client cannot bypass
// [x] Analytics events contain no raw UIDs or PII — only status
// [x] Group anomaly detection stub for POTENTIAL_ISSUES.md #6
// [x] isSafeToAlert is community-aware: it fails closed unless the candidate can
//     start Quest Mode, which requires the school gate and a verified student ID
// [x] §02 — verification and report failures surface generic copy; the backend
//     error goes to the log, never onto an onboarding or reporting screen

import Foundation
import Combine
import UIKit
import Vision
import AVFoundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - SafetyVerifier

@MainActor
final class SafetyVerifier: ObservableObject {
    @Published var verificationState: VerificationState = .idle
    @Published var errorMessage: String?
    @Published var verificationBadge: VerificationBadge = .none

    /// Results populated during verification
    private(set) var livenessCheckPassed = false

    /// On-device face-comparison hint. Named `Hint` deliberately: it exists so a
    /// user can retake an obviously bad photo before spending an upload and one
    /// of their three hourly attempts. The server's decision is the only one
    /// that changes `studentIDStatus`.
    private(set) var faceMatchHint: Bool?

    private(set) var idValidationResult: IDValidationResult?

    /// The server's answer. This is the value the rest of the app reads.
    @Published private(set) var studentIDStatus: StudentIDStatus = .none

    /// Stored liveness selfie, uploaded alongside the student ID card photo.
    private var selfieImage: UIImage?

    let livenessDetector = LivenessDetector()

    /// Threshold for the on-device hint only. The authoritative threshold lives
    /// in studentIdVerification.ts and is deliberately higher.
    private let faceMatchHintThreshold: Double = 0.70
    private lazy var functions = Functions.functions()
    private let analytics = AnalyticsService.shared

    enum VerificationState: Equatable {
        case idle
        case livenessCheck(LivenessDetector.LivenessAction)
        case capturingID
        case uploading
        case processing
        case verified
        case failed(String)
    }

    struct IDValidationResult {
        let isValid: Bool
        let extractedDOB: Date?
        let extractedAge: Int?
        let failureReason: String?
    }

    /// Badge displayed in the UI based on verification status.
    enum VerificationBadge: String {
        case none = ""
        case verified = "Verified"
        case pending = "Pending"
        case flagged = "Flagged"
    }

    // MARK: - Verification Flow

    /// Initiates verification: liveness check → ID scan → face match → age check.
    func beginVerification() {
        livenessCheckPassed = false
        faceMatchHint = nil
        idValidationResult = nil
        selfieImage = nil
        livenessDetector.start()
        if case .prompting(let action) = livenessDetector.state {
            verificationState = .livenessCheck(action)
        }
    }

    // MARK: - Identity Verification (Cloud Function Proxy)

    /// Calls the server-side identity verification Cloud Function.
    ///
    /// This is the **optional** third-party document check, not the campus gate.
    /// Quest Mode, the Dating intent and NameDrop all read `studentIDStatus`,
    /// which only `submitStudentIDVerification` can set. Nothing here opens any
    /// of them; it exists for accounts that want an extra verification signal.
    ///
    /// The Persona/Onfido API key lives on the server — never on the client.
    /// Returns a badge for UI display and updates trustScore server-side.
    func verifyIdentity() async -> VerificationBadge {
        verificationState = .processing

        do {
            // Step 1: Create verification session via Cloud Function
            let createResult = try await functions.httpsCallable("createVerificationSession").call()

            guard let data = createResult.data as? [String: Any],
                  let inquiryId = data["inquiryId"] as? String else {
                verificationState = .failed("Could not start verification session.")
                return .none
            }

            // Step 2: In production, the Persona SDK would open here using inquiryId.
            // For now, we proceed directly to completion check.
            // TODO: Integrate Persona iOS SDK with inquiryId

            // Step 3: Check verification result via Cloud Function
            let completeResult = try await functions.httpsCallable("onVerificationComplete")
                .call(["inquiryId": inquiryId])

            guard let resultData = completeResult.data as? [String: Any] else {
                verificationState = .failed("Verification result unavailable.")
                return .none
            }

            // Parse minimal response — server already applied trustScore delta
            let statusRaw = resultData["verificationStatus"] as? String ?? "unverified"
            let badgeName = resultData["badge"] as? String
            let trustDelta = resultData["trustScoreDelta"] as? Double ?? 0.0

            // Map to badge
            let badge: VerificationBadge
            switch statusRaw {
            case "verified":
                verificationState = .verified
                badge = .verified
            case "pending":
                verificationState = .processing
                badge = .pending
            case "flagged":
                verificationState = .failed("Verification flagged. Contact support.")
                badge = .flagged
            default:
                verificationState = .idle
                badge = .none
            }

            verificationBadge = badge

            // Log verification completion to analytics
            analytics.logVerificationCompleted(status: statusRaw, trustDelta: trustDelta)

            Log.safety.debug("Verification complete: status=\(statusRaw), badge=\(badgeName ?? "none"), trustDelta=\(trustDelta)")
            return badge

        } catch {
            // Don't expose server error details to the UI
            verificationState = .failed("Verification unavailable. Please try again later.")
            verificationBadge = .none
            Log.safety.error("Verification error: \(error.localizedDescription)")
            return .none
        }
    }

    // MARK: - Liveness Check

    /// Called when liveness detection completes with the final selfie frame.
    func completeLivenessCheck(selfie: UIImage) {
        guard livenessDetector.evaluateLiveness() else {
            verificationState = .failed("Liveness check failed. Please try again.")
            return
        }
        livenessCheckPassed = true
        selfieImage = selfie
        verificationState = .capturingID
    }

    // MARK: - Document Scan + Face Match + Age Verification

    /// Processes a **student ID card** photo.
    ///
    /// The on-device work here is advisory: OCR for an obvious age problem and a
    /// landmark-geometry face comparison, both shown to the user so they can
    /// retake a bad photo. Neither decides anything. The card and the liveness
    /// frame are then uploaded to the write-only verification prefix and
    /// `studentIdVerification.ts` makes the call — because a client that could
    /// decide its own face match could decide to pass.
    ///
    /// Passing this opens Quest Mode. Passing it *with* a face match opens the
    /// Dating intent and NameDrop.
    func processStudentIDCard(_ image: UIImage, profileAge: Int) async {
        guard livenessCheckPassed, let selfie = selfieImage else {
            verificationState = .failed("Finish the liveness check first.")
            return
        }

        verificationState = .uploading

        do {
            // Pre-flight 1: can we read the card at all? Catches a blurred or
            // upside-down photo before it costs an upload.
            let extractedText = try await performOCR(on: image)
            guard !extractedText.isEmpty else {
                verificationState = .failed("Could not read your student ID. Ensure the card is clear and well-lit.")
                return
            }

            // Pre-flight 2: age sanity. Advisory — the server re-reads the card
            // and it is the server's number that gates the Dating intent.
            let ageResult = parseAndValidateID(extractedText, profileAge: profileAge)
            idValidationResult = ageResult
            if let reason = ageResult.failureReason, !ageResult.isValid {
                verificationState = .failed(reason)
                return
            }

            // Pre-flight 3: face comparison hint.
            let similarity = try await compareFaces(selfie: selfie, idPhoto: image)
            faceMatchHint = similarity >= faceMatchHintThreshold

            // Upload and let the server decide.
            verificationState = .processing
            try await submitToServer(idCard: image, livenessFrame: selfie)
        } catch {
            // §02: `.failed`'s message is rendered verbatim by
            // StudentIDStepView, so it must read like the hand-written cases
            // above it — not like a Firestore, Storage or Vision error. A raw
            // `permission-denied` here would print collection and rule shape
            // onto an onboarding screen.
            verificationState = .failed("Verification could not be completed. Please try again.")
            Log.safety.error("Student ID verification failed: \(error.localizedDescription)")
        }
    }

    /// Uploads the artefacts and calls the verification function.
    ///
    /// The upload targets `verification/{uid}/…`, which `storage.rules` makes
    /// create-only for the owner and readable by nobody. The function deletes
    /// both objects once it has recorded an outcome, so neither the card nor the
    /// frame outlives the decision.
    private func submitToServer(idCard: UIImage, livenessFrame: UIImage) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            verificationState = .failed("Verification could not be completed. Please try again.")
            return
        }

        guard let cardData = idCard.jpegData(compressionQuality: 0.85),
              let frameData = livenessFrame.jpegData(compressionQuality: 0.85) else {
            verificationState = .failed("Verification could not be completed. Please try again.")
            return
        }

        let stamp = UUID().uuidString
        let service = FirestoreService.shared

        let cardPath = try await service.uploadVerificationArtifact(
            cardData, uid: uid, filename: "studentid_\(stamp).jpg"
        )
        let framePath = try await service.uploadVerificationArtifact(
            frameData, uid: uid, filename: "liveness_\(stamp).jpg"
        )

        do {
            let result = try await functions
                .httpsCallable("submitStudentIDVerification")
                .call([
                    "studentIDStoragePath": cardPath,
                    "livenessFrameStoragePaths": [framePath]
                ])

            let payload = result.data as? [String: Any]
            let statusRaw = payload?["studentIDStatus"] as? String ?? "none"
            studentIDStatus = StudentIDStatus(rawValue: statusRaw) ?? .none

            // firestore.rules reads the claim, not the profile field, so the
            // token has to be refreshed before Quest Mode can actually query.
            await SchoolGateManager.shared.refreshClaims()

            switch studentIDStatus {
            case .faceMatched, .verified:
                verificationState = .verified
                verificationBadge = .verified
            case .pending:
                verificationState = .processing
                verificationBadge = .pending
            case .rejected, .none:
                verificationState = .failed("We couldn't verify your student ID. Try again in good lighting.")
                verificationBadge = .flagged
            }

            analytics.logVerificationCompleted(status: statusRaw, trustDelta: 0)
            Log.safety.debug("Student ID verification returned \(statusRaw)")
        } catch {
            // The function returns one generic message for every rejection
            // reason on purpose; do not try to unpack it here.
            verificationState = .failed("We couldn't verify your student ID. Try again in good lighting.")
            verificationBadge = .none
            Log.safety.error("Student ID verification call failed: \(error.localizedDescription)")
        }
    }

    // MARK: - OCR

    private func performOCR(on image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { return "" }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let text = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: - Age Verification

    /// Parses DOB from OCR text and validates against profile age.
    private nonisolated func parseAndValidateID(_ text: String, profileAge: Int) -> IDValidationResult {
        guard let dob = extractDOB(from: text) else {
            // Can't parse DOB — allow through at silver level (liveness only)
            return IDValidationResult(isValid: true, extractedDOB: nil, extractedAge: nil, failureReason: nil)
        }

        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: dob, to: Date())
        guard let extractedAge = ageComponents.year else {
            return IDValidationResult(isValid: true, extractedDOB: dob, extractedAge: nil, failureReason: nil)
        }

        if extractedAge < 18 {
            return IDValidationResult(
                isValid: false,
                extractedDOB: dob,
                extractedAge: extractedAge,
                failureReason: "You must be at least 18 years old to use this app."
            )
        }

        if abs(extractedAge - profileAge) > 2 {
            return IDValidationResult(
                isValid: false,
                extractedDOB: dob,
                extractedAge: extractedAge,
                failureReason: "Your ID age doesn't match your profile. Please update your profile age."
            )
        }

        return IDValidationResult(isValid: true, extractedDOB: dob, extractedAge: extractedAge, failureReason: nil)
    }

    /// Attempts to extract a date of birth from OCR text using common ID formats.
    private nonisolated func extractDOB(from text: String) -> Date? {
        // Each entry: (pattern, isISO) — isISO means first group is the year
        let patterns: [(String, Bool)] = [
            // "DOB: 01/15/1995" or "DATE OF BIRTH 01-15-1995"
            (#"(?:DOB|DATE\s*OF\s*BIRTH)[:\s]*(\d{2})[/\-](\d{2})[/\-](\d{4})"#, false),
            // ISO format YYYY-MM-DD (must be checked before generic MM/DD/YYYY)
            (#"(\d{4})-(\d{2})-(\d{2})"#, true),
            // Standalone MM/DD/YYYY or MM-DD-YYYY
            (#"(\d{2})[/\-](\d{2})[/\-](\d{4})"#, false),
        ]

        let calendar = Calendar.current

        for (pattern, isISO) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(text.startIndex..., in: text)

            if let match = regex.firstMatch(in: text, range: range) {
                let groups = (1..<match.numberOfRanges).compactMap { i -> String? in
                    guard let range = Range(match.range(at: i), in: text) else { return nil }
                    return String(text[range])
                }

                guard groups.count >= 3,
                      let g1 = Int(groups[0]),
                      let g2 = Int(groups[1]),
                      let g3 = Int(groups[2]) else { continue }

                var components = DateComponents()

                if isISO {
                    // YYYY-MM-DD
                    components.year = g1
                    components.month = g2
                    components.day = g3
                } else {
                    // MM/DD/YYYY
                    components.month = g1
                    components.day = g2
                    components.year = g3
                }

                if let date = calendar.date(from: components) {
                    // Sanity check: DOB should be in the past and person should be < 120
                    let age = calendar.dateComponents([.year], from: date, to: Date()).year ?? 0
                    if age >= 0 && age < 120 {
                        return date
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Face Matching

    /// Compares selfie face to ID document face using landmark geometry.
    /// FUTURE: Replace with backend API (AWS Rekognition CompareFaces) for production accuracy.
    private func compareFaces(selfie: UIImage, idPhoto: UIImage) async throws -> Double {
        async let selfieGeometry = extractFaceGeometry(from: selfie)
        async let idGeometry = extractFaceGeometry(from: idPhoto)

        guard let sg = try await selfieGeometry, let ig = try await idGeometry else {
            return 0.0
        }

        return computeGeometricSimilarity(sg, ig)
    }

    private struct FaceGeometry {
        var interEyeDistance: CGFloat      // Normalized
        var noseToMouthRatio: CGFloat
        var faceWidthToHeight: CGFloat
        var eyeToNoseRatio: CGFloat
    }

    private func extractFaceGeometry(from image: UIImage) async throws -> FaceGeometry? {
        guard let cgImage = image.cgImage else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectFaceLandmarksRequest { request, error in
                if let error { continuation.resume(throwing: error); return }

                guard let face = (request.results as? [VNFaceObservation])?.first,
                      let landmarks = face.landmarks,
                      let leftEye = landmarks.leftEye,
                      let rightEye = landmarks.rightEye,
                      let nose = landmarks.nose,
                      let outerLips = landmarks.outerLips else {
                    continuation.resume(returning: nil)
                    return
                }

                let leftEyeCenter = self.centroid(leftEye)
                let rightEyeCenter = self.centroid(rightEye)
                let noseCenter = self.centroid(nose)
                let mouthCenter = self.centroid(outerLips)

                let interEye = self.distance(leftEyeCenter, rightEyeCenter)
                guard interEye > 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                let noseToMouth = self.distance(noseCenter, mouthCenter)
                let eyeMidpoint = CGPoint(
                    x: (leftEyeCenter.x + rightEyeCenter.x) / 2,
                    y: (leftEyeCenter.y + rightEyeCenter.y) / 2
                )
                let eyeToNose = self.distance(eyeMidpoint, noseCenter)

                let bbox = face.boundingBox
                let faceRatio = bbox.width / max(bbox.height, 0.001)

                let geometry = FaceGeometry(
                    interEyeDistance: interEye,
                    noseToMouthRatio: noseToMouth / interEye,
                    faceWidthToHeight: faceRatio,
                    eyeToNoseRatio: eyeToNose / interEye
                )

                continuation.resume(returning: geometry)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    private nonisolated func computeGeometricSimilarity(_ a: FaceGeometry, _ b: FaceGeometry) -> Double {
        let diffs: [Double] = [
            abs(Double(a.noseToMouthRatio - b.noseToMouthRatio)),
            abs(Double(a.faceWidthToHeight - b.faceWidthToHeight)),
            abs(Double(a.eyeToNoseRatio - b.eyeToNoseRatio)),
        ]
        // Average difference → similarity (1.0 = identical, 0.0 = completely different)
        let avgDiff = diffs.reduce(0, +) / Double(diffs.count)
        return max(0, 1.0 - avgDiff * 2.0)  // Scale: 0.5 diff → 0.0 similarity
    }

    private nonisolated func centroid(_ region: VNFaceLandmarkRegion2D) -> CGPoint {
        guard region.pointCount > 0 else { return .zero }
        let buffer = region.normalizedPoints
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for i in 0..<region.pointCount {
            sumX += CGFloat(buffer[i].x)
            sumY += CGFloat(buffer[i].y)
        }
        let count = CGFloat(region.pointCount)
        return CGPoint(x: sumX / count, y: sumY / count)
    }

    private nonisolated func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
    }

    // MARK: - Trust Level Mapping

    /// The trust level implied by the server's verification outcome.
    ///
    /// Read-only, and derived from `studentIDStatus` rather than from local
    /// flags: the on-device face hint must not be able to imply Gold. Nothing
    /// writes `trustLevel` from the client — `studentIdVerification.ts` sets it
    /// and `firestore.rules` refuses any client write. This exists so a view can
    /// render the tier it is about to be granted, not to grant it.
    var achievedTrustLevel: UserProfile.TrustLevel {
        switch studentIDStatus {
        case .faceMatched:            return .gold
        case .verified:               return .silver
        case .pending, .rejected, .none:
            return livenessCheckPassed ? .silver : .bronze
        }
    }

    // MARK: - Reporting

    func reportUser(reportedUID: String, reason: ReportReason, details: String) async {
        do {
            try await FirestoreService.shared.submitReport(
                reportedUID: reportedUID,
                reason: reason.rawValue,
                details: details
            )
            // Deliberately no uid: this file's compliance block claims no PII is
            // logged, and a reported user's uid is exactly the PII that claim is
            // about. The report itself is the audit trail.
            Log.safety.debug("Report submitted")
        } catch {
            // §02: no backend error text in the UI — and least of all here.
            // Someone filing a harassment report needs to know it did not send
            // and that they can retry, not to read a Firestore rule failure at
            // the worst possible moment.
            self.errorMessage = "Your report couldn't be sent. Please check your connection and try again."
            Log.safety.error("Report submission failed: \(error.localizedDescription)")
        }
    }

    enum ReportReason: String, CaseIterable {
        case fakeProfile = "Fake Profile"
        case harassment  = "Harassment"
        case underage    = "Appears Underage"
        case inappropriate = "Inappropriate Content"
        case scam        = "Scam / Catfish"
        case other       = "Other"
    }

    // MARK: - Proximity Safety Gate

    /// Critical safety gate used by MatchManager.shouldTriggerAlert.
    ///
    /// Community-aware and fail-closed. `canStartQuestMode` folds in the three
    /// facts that matter before anyone's phone buzzes: a server-issued school, an
    /// enrollment status that still grants access, and a verified student ID.
    /// An account that was suspended, graduated, or had its ID revoked stops
    /// clearing this gate the moment the server says so.
    ///
    /// Future: group anomaly detection, unsafe report history.
    static func isSafeToAlert(_ match: UserProfile) -> Bool {
        guard match.accountStatus == .active else { return false }
        guard match.canStartQuestMode else { return false }
        return match.verificationStatus == .verified
    }

    static func reportUnsafeProximity(matchID: String, reason: String) async {
        Log.safety.error("Unsafe proximity reported: \(reason)")

        // Terminate the session immediately and free the slot. The reason is
        // recorded as `.unsafeProximity` rather than `.pass` so the audit trail
        // says what actually happened — the slot outcome is identical, but a
        // report and a shrug are not the same event to review later.
        await RevealManager.shared.endSession(for: matchID, reason: .unsafeProximity)

        // TODO: Firestore report record + BalanceEnforcer escalation
    }
}
