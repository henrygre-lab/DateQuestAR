import Foundation

// MARK: - Icebreaker

struct IcebreakerChallenge: Identifiable, Codable {
    var id: String
    var type: ChallengeType
    var prompt: String
    var options: [String]?              // For trivia
    var correctAnswer: String?
    var durationSeconds: Int

    enum ChallengeType: String, Codable {
        case trivia
        case gesture
        case arObject                   // Place same AR object
        case wordAssociation
    }
}
