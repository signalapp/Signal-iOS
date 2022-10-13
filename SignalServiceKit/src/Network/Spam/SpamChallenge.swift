//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

protocol SpamChallengeSchedulingDelegate: AnyObject {
    var workQueue: DispatchQueue { get }
    func spamChallenge(_: SpamChallenge, stateDidChangeFrom: SpamChallenge.State)
}

class SpamChallenge: Codable {
    weak var schedulingDelegate: SpamChallengeSchedulingDelegate?
    var workQueue: DispatchQueue { schedulingDelegate?.workQueue ?? .sharedUtility }

    /// The date the challenge was first registered
    let creationDate: Date

    /// The date this challenge will expire.
    var expirationDate: Date

    /// Does this challenge pause victim sends for an extended period of time
    var pausesMessages: Bool { true }

    var completionHandlers: [(Bool) -> Void] = []

    enum State: Equatable {
        case actionable
        case inProgress
        case deferred(Date)
        case complete
        case failed

        var isActionable: Bool {
            switch self {
            case .actionable: return true
            case let .deferred(date) where date.isBeforeNow: return true
            default: return false
            }
        }
    }

    var state: State = .actionable {
        didSet {
            // Complete and failed are final states
            owsAssertDebug([.complete, .failed].contains(oldValue) == false)

            guard oldValue != state else { return }
            schedulingDelegate?.spamChallenge(self, stateDidChangeFrom: oldValue)

            if state == .complete || state == .failed {
                for handler in completionHandlers {
                    handler(state == .complete)
                }
                completionHandlers = []
            }
        }
    }

    var isLive: Bool {
        guard expirationDate.isAfterNow else {
            return false
        }
        switch state {
        case .actionable, .inProgress, .deferred: return true
        case .complete, .failed: return false
        }
    }

    var nextActionableDate: Date {
        switch state {
        case let .deferred(date): return min(date, expirationDate)
        default: return expirationDate
        }
    }

    init(expiry: Date) {
        creationDate = Date()
        expirationDate = expiry
    }

    deinit {
        // If we haven't fired our completion handlers yet, fire a failure.
        for handler in completionHandlers {
            handler(false)
        }
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
        case isFailed
        case deferralDate
    }

    required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decodedCreationDate = try values.decodeIfPresent(Date.self, forKey: .creationDate)
        let decodedExpirationDate = try values.decodeIfPresent(Date.self, forKey: .expirationDate)
        let decodedIsComplete = try values.decodeIfPresent(Bool.self, forKey: .isComplete)
        let decodedIsFailed = try values.decodeIfPresent(Bool.self, forKey: .isFailed)
        let decodedDeferralDate = try values.decodeIfPresent(Date.self, forKey: .deferralDate)

        creationDate = decodedCreationDate ?? Date()
        expirationDate = decodedExpirationDate ?? Date()
        if let date = decodedDeferralDate {
            state = .deferred(date)
        } else if decodedIsFailed == true {
            state = .failed
        } else if decodedIsComplete == true {
            state = .complete
        } else {
            state = .actionable
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(creationDate, forKey: .creationDate)
        try container.encode(expirationDate, forKey: .expirationDate)

        let (deferralDate, isComplete, isFailed) = { () -> (Date?, Bool, Bool) in
            switch state {
            case .complete:
                return (nil, true, false)
            case .failed:
                return (nil, false, true)
            case let .deferred(date):
                return (date, false, false)
            default:
                return (nil, false, false)
            }
        }()
        try container.encode(deferralDate, forKey: .deferralDate)
        try container.encode(isComplete, forKey: .isComplete)
        try container.encode(isFailed, forKey: .isFailed)
    }
}
