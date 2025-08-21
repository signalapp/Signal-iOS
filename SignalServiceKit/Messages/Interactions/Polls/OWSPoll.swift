//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct OWSPoll: Equatable {
    public typealias OptionID = Int

    public struct OWSPollOption {
        public let optionID: OptionID
        public let text: String
        public var votes: Int

        init(
            optionID: OptionID,
            text: String
        ) {
            self.optionID = optionID
            self.text = text
            self.votes = 0
        }
    }

    public let pollID: String
    public let question: String
    public let isEnded: Bool
    public let allowMultiSelect: Bool

    private let options: [OptionID: OWSPollOption]

    init(
        pollID: String,
        question: String,
        options: [String],
        allowMultiSelect: Bool
    ) {
        self.pollID = pollID
        self.question = question
        self.allowMultiSelect = allowMultiSelect
        self.isEnded = false

        self.options = Dictionary(uniqueKeysWithValues: options.enumerated().map { index, option in
            return (index, OWSPollOption(optionID: index, text: option))
        })
    }

    public static func == (lhs: OWSPoll, rhs: OWSPoll) -> Bool {
        return lhs.pollID == rhs.pollID
    }

    public func totalVotes() -> Int {
        return options.values.reduce(0) { $0 + $1.votes }
    }

    public func sortedOptions() -> [OWSPollOption] {
        return options.sorted { $0.key < $1.key }.map { $0.value }
    }

    public func optionForIndex(optionID: OptionID) -> OWSPollOption? {
        return options[optionID]
    }
}
