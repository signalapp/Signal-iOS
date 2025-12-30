//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct OWSPoll: Equatable {
    public enum Constants {
        static let maxCharacterLength = 100
    }

    public enum PendingVoteType {
        case pendingVote
        case pendingUnvote
    }

    public typealias OptionIndex = UInt32

    public struct OWSPollOption: Equatable, Identifiable {
        public let optionIndex: OptionIndex
        public let text: String
        public let acis: [Aci]
        public var id: OptionIndex { optionIndex }
        public let latestPendingState: PendingVoteType?

        init(
            optionIndex: OptionIndex,
            text: String,
            acis: [Aci],
            latestPendingState: PendingVoteType?,
        ) {
            self.optionIndex = optionIndex
            self.text = text
            self.acis = acis
            self.latestPendingState = latestPendingState
        }

        public func localUserHasVoted(localAci: Aci) -> Bool {
            return acis.contains(localAci)
        }
    }

    public let interactionId: Int64
    public let question: String
    public var isEnded: Bool
    public let allowsMultiSelect: Bool
    public let ownerIsLocalUser: Bool
    private let options: [OptionIndex: OWSPollOption]

    public init(
        interactionId: Int64,
        question: String,
        options: [String],
        localUserPendingState: [OptionIndex: PendingVoteType],
        allowsMultiSelect: Bool,
        votes: [OptionIndex: [Aci]],
        isEnded: Bool,
        ownerIsLocalUser: Bool,
    ) {
        self.interactionId = interactionId
        self.question = question
        self.allowsMultiSelect = allowsMultiSelect
        self.isEnded = isEnded
        self.ownerIsLocalUser = ownerIsLocalUser

        self.options = Dictionary(uniqueKeysWithValues: options.enumerated().map { index, option in
            let optionIndex = OWSPoll.OptionIndex(index)
            let votes = votes[optionIndex] ?? []
            var latestPendingState: PendingVoteType?
            if let pendingState = localUserPendingState[optionIndex] {
                switch pendingState {
                case .pendingVote:
                    latestPendingState = .pendingVote
                case .pendingUnvote:
                    latestPendingState = .pendingUnvote
                }
            }
            return (optionIndex, OWSPollOption(optionIndex: optionIndex, text: option, acis: votes, latestPendingState: latestPendingState))
        })
    }

    public static func ==(lhs: OWSPoll, rhs: OWSPoll) -> Bool {
        return lhs.interactionId == rhs.interactionId
            && lhs.isEnded == rhs.isEnded
            && lhs.options == rhs.options
    }

    public func totalVoters() -> Int {
        return Set(options.values.flatMap { $0.acis }).count
    }

    public func sortedOptions() -> [OWSPollOption] {
        return options.sorted { $0.key < $1.key }.map { $0.value }
    }

    public func optionForIndex(optionIndex: OptionIndex) -> OWSPollOption? {
        return options[optionIndex]
    }

    public func pendingVotesCount() -> Int {
        return options.count { $0.value.latestPendingState != nil }
    }

    public func maxVoteCount() -> Int {
        return options.values.map { $0.acis.count }.max() ?? 0
    }
}
