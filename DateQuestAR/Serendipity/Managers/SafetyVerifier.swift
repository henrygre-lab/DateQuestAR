import Foundation
import Combine
import UIKit
import Vision
import AVFoundation

// MARK: - SafetyVerifier

@MainActor
final class SafetyVerifier: ObservableObject {
    @Published var verificationState: VerificationState = .idle
    @Published var errorMessage: String?

    /// Results populated during verification
    private(set) var livenessCheckPassed = false
    private(set) var faceMatchPassed = false
    private(set) var idValidationResult: IDValidationResult?

    /// Stored selfie for face matching against ID
    private var selfieImage: UIImage?

    let livenessDetector = LivenessDetector()

    private let faceMatchThreshold: Double = 0.70

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

    // MARK: - Verification Flow

    /// Initiates verification: liveness check → ID scan → face match → age check.
    func beginVerification() {
        livenessCheckPassed = false
        faceMatchPassed = false
        idValidationResult = nil
        selfieImage = nil
        livenessDetector.start()
        if case .prompting(let action) = livenessDetector.state {
            verificationState = .livenessCheck(action)
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

    /// Processes a driver's license or passport image.
    func processIDDocument(_ image: UIImage, profileAge: Int) async {
        verificationState = .uploading

        do {
            // Step 1: OCR text extraction
            let extractedText = try await performOCR(on: image)
            guard !extractedText.isEmpty else {
                verificationState = .failed("Could not read ID. Ensure the document is clear and well-lit.")
                return
            }

            // Step 2: Age verification from OCR
            let ageResult = parseAndValidateID(extractedText, profileAge: profileAge)
            idValidationResult = ageResult

            if let reason = ageResult.failureReason, !ageResult.isValid {
                verificationState = .failed(reason)
                return
            }

            // Step 3: Face match (selfie vs ID photo)
            if let selfie = selfieImage {
                verificationState = .processing
                let similarity = try await compareFaces(selfie: selfie, idPhoto: image)
                faceMatchPassed = similarity >= faceMatchThreshold

                if !faceMatchPassed {
                    verificationState = .failed("Your selfie doesn't match your ID photo. Please try again.")
                    return
                }
            }

            // FUTURE: Send image + text to verification backend (AWS Rekognition, Onfido)
            verificationState = .processing
            await simulateBackendVerification()
        } catch {
            verificationState = .failed(error.localizedDescription)
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

    // MARK: - Backend Simulation

    private func simulateBackendVerification() async {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        verificationState = .verified
    }

    // MARK: - Trust Level Mapping

    /// Computes the trust level achieved from the verification results.
    var achievedTrustLevel: UserProfile.TrustLevel {
        if faceMatchPassed && livenessCheckPassed && (idValidationResult?.extractedAge != nil) {
            return .gold
        } else if livenessCheckPassed {
            return .silver
        }
        return .bronze
    }

    // MARK: - Reporting

    func reportUser(reportedUID: String, reason: ReportReason, details: String) async {
        do {
            try await FirestoreService.shared.submitReport(
                reportedUID: reportedUID,
                reason: reason.rawValue,
                details: details
            )
            print("[Safety] Report submitted for \(reportedUID)")
        } catch {
            self.errorMessage = "Failed to submit report: \(error.localizedDescription)"
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
}
