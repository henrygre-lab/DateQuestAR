import Foundation
import FirebaseFirestore
import FirebaseStorage

// MARK: - FirestoreService

final class FirestoreService {
    static let shared = FirestoreService()
    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    private init() {}

    // MARK: - Collections

    private var usersCollection: CollectionReference { db.collection("users") }
    private var matchesCollection: CollectionReference { db.collection("matches") }
    private var reportsCollection: CollectionReference { db.collection("reports") }

    // MARK: - User CRUD

    func fetchUser(uid: String) async throws -> UserProfile? {
        let doc = try await usersCollection.document(uid).getDocument()
        guard doc.exists else { return nil }
        return try doc.data(as: UserProfile.self)
    }

    func createOrUpdateUser(_ profile: UserProfile) async throws {
        guard let uid = profile.id else { throw AppError.missingUID }
        try usersCollection.document(uid).setData(from: profile, merge: true)
    }

    func updateQuestModeStatus(uid: String, enabled: Bool) async throws {
        try await usersCollection.document(uid).updateData([
            "privacySettings.questModeEnabled": enabled,
            "lastActive": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Nearby Users (Geohash Query)

    /// Fetches active users within the geohash neighborhood.
    func fetchNearbyUsers(geohash: String, excludeUID: String) async throws -> [UserProfile] {
        // TODO: Use GeoFire or geohash range queries for efficient proximity search
        let snapshot = try await usersCollection
            .whereField("privacySettings.questModeEnabled", isEqualTo: true)
            .limit(to: 50)
            .getDocuments()

        return try snapshot.documents
            .compactMap { try $0.data(as: UserProfile.self) }
            .filter { $0.uid != excludeUID }
    }

    // MARK: - Matches

    func saveMatch(_ match: Match) async throws {
        try matchesCollection.document(match.id).setData(from: match)
    }

    func updateMatchStatus(matchID: String, status: Match.MatchStatus) async throws {
        try await matchesCollection.document(matchID).updateData([
            "status": status.rawValue
        ])
    }

    func updateMatchRating(matchID: String, rating: Int) async throws {
        try await matchesCollection.document(matchID).updateData([
            "postMeetRating": rating,
            "meetupOccurred": true
        ])
    }

    // MARK: - Photo Upload

    func uploadPhoto(_ imageData: Data, uid: String, index: Int) async throws -> URL {
        let ref = storage.reference().child("users/\(uid)/photos/photo_\(index).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        return try await ref.downloadURL()
    }

    // MARK: - Photo Deletion (cleanup on failed upload)

    func deletePhoto(uid: String, index: Int) async {
        let ref = storage.reference().child("users/\(uid)/photos/photo_\(index).jpg")
        try? await ref.delete()
    }

    // MARK: - Photo Accuracy Ratings

    /// Submits a photo accuracy rating for one side of a match.
    func submitPhotoAccuracyRating(matchID: String, raterUID: String, rating: Int) async throws {
        let doc = try await matchesCollection.document(matchID).getDocument()
        guard let match = try? doc.data(as: Match.self) else { return }

        let field = raterUID == match.userAUID ? "photoAccuracyRatingA" : "photoAccuracyRatingB"
        try await matchesCollection.document(matchID).updateData([
            field: rating,
            "meetupOccurred": true
        ])
    }

    /// Fetches all photo accuracy ratings given TO a user by their match partners.
    func fetchPhotoAccuracyRatings(forUID uid: String) async throws -> [Int] {
        var ratings: [Int] = []

        // Ratings where user was userB → ratingA is about them
        let asB = try await matchesCollection
            .whereField("userBUID", isEqualTo: uid)
            .whereField("meetupOccurred", isEqualTo: true)
            .getDocuments()
        for doc in asB.documents {
            if let rating = doc.data()["photoAccuracyRatingA"] as? Int {
                ratings.append(rating)
            }
        }

        // Ratings where user was userA → ratingB is about them
        let asA = try await matchesCollection
            .whereField("userAUID", isEqualTo: uid)
            .whereField("meetupOccurred", isEqualTo: true)
            .getDocuments()
        for doc in asA.documents {
            if let rating = doc.data()["photoAccuracyRatingB"] as? Int {
                ratings.append(rating)
            }
        }

        return ratings
    }

    // MARK: - Trust Level

    func updateTrustLevel(uid: String, level: UserProfile.TrustLevel) async throws {
        try await usersCollection.document(uid).updateData([
            "trustLevel": level.rawValue
        ])
    }

    // MARK: - Account Deletion

    /// Deletes the user's Firestore document and all associated Storage photos.
    func deleteUserData(uid: String) async throws {
        // Delete profile photos from Storage
        let photosRef = storage.reference().child("users/\(uid)/photos")
        if let photosList = try? await photosRef.listAll() {
            for item in photosList.items {
                try? await item.delete()
            }
        }

        // Delete user document from Firestore
        try await usersCollection.document(uid).delete()
    }

    // MARK: - Reports

    func submitReport(reportedUID: String, reason: String, details: String) async throws {
        try await reportsCollection.addDocument(data: [
            "reportedUID": reportedUID,
            "reason": reason,
            "details": details,
            "timestamp": FieldValue.serverTimestamp()
        ])
    }
}

// MARK: - AppError

enum AppError: LocalizedError {
    case missingUID
    case locationUnavailable
    case verificationFailed
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .missingUID:             return "User ID is missing."
        case .locationUnavailable:    return "Location services are unavailable."
        case .verificationFailed:     return "Verification could not be completed."
        case .networkError(let msg):  return "Network error: \(msg)"
        }
    }
}
