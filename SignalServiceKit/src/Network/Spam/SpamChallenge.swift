//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

protocol SpamChallengeSchedulingDelegate: AnyObject {
    var workQueue: DispatchQueue { get }
    func spamChallenge(_: SpamChallenge, stateDidChangeFrom: SpamChallenge.State)
}

class SpamChallenge: Codable {
    weak var schedulingDelegate: SpamChallengeSchedulingDelegate? = nil
    var workQueue: DispatchQueue { schedulingDelegate?.workQueue ?? .sharedUtility }

    /// The date the challenge was first registered
    let creationDate: Date

    /// The date this challenge will expire.
    var expirationDate: Date

    enum State: Equatable {
        case actionable
        case inProgress
        case deferred(Date)
        case complete

        var isActionable: Bool {
            switch self {
            case .actionable: return true
            case let .deferred(date) where date.isBeforeNow: return true
            default: return false
            }
        }

        var deferralDate: Date? {
            switch self {
            case let .deferred(date): return date
            default: return nil
            }
        }
    }

    var state: State = .actionable {
        didSet {
            guard oldValue != state else { return }
            schedulingDelegate?.spamChallenge(self, stateDidChangeFrom: oldValue)
        }
    }

    init(expiry: Date) {
        creationDate = Date()
        expirationDate = expiry
    }

    public func resolveChallenge() {
        // Subclass work should happen here.
        // Subclasses a responsible for updating their state
        // once they've completed their attempt, successfully or not.
        
        // For now, to avoid re-enterancy...
        state = .inProgress
    }

    // MARK: - <Codable>

    enum CodingKeys: String, CodingKey {
        case creationDate
        case expirationDate
        case isComplete
        case deferralDate
    }

    required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        creationDate = try values.decode(Date.self, forKey: .creationDate)
        expirationDate = try values.decode(Date.self, forKey: .expirationDate)

        let isComplete = try values.decode(Bool.self, forKey: .isComplete)
        let deferralDate = try values.decode(Date?.self, forKey: .deferralDate)

        switch (isComplete, deferralDate) {
        case let (_, date?):
            state = .deferred(date)
        case (true, _):
            state = .complete
        default:
            state = .actionable
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(creationDate, forKey: .creationDate)
        try container.encode(expirationDate, forKey: .expirationDate)

        let (deferralDate, isComplete) = { () -> (Date?, Bool) in
            switch state {
            case .complete:
                return (nil, true)
            case let .deferred(date):
                return (date, false)
            default:
                return (nil, false)
            }
        }()
        try container.encode(deferralDate, forKey: .deferralDate)
        try container.encode(isComplete, forKey: .isComplete)
    }
}
