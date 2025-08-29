//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct OWSPoll: Equatable {
    public typealias OptionIndex = UInt32

    public struct OWSPollOption {
        public let optionIndex: OptionIndex
        public let text: String
        public var votes: Int
        public let acis: [Aci]

        init(
            optionIndex: OptionIndex,
            text: String,
            votes: Int = 0,
            acis: [Aci] = []
        ) {
            self.optionIndex = optionIndex
            self.text = text
            self.votes = votes
            self.acis = acis
        }
    }

    public let pollID: String
    public let question: String
    public let isEnded: Bool
    public let allowMultiSelect: Bool

    private let options: [OptionIndex: OWSPollOption]

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
            return (OWSPoll.OptionIndex(index), OWSPollOption(optionIndex: OWSPoll.OptionIndex(index), text: option))
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

    public func optionForIndex(optionIndex: OptionIndex) -> OWSPollOption? {
        return options[optionIndex]
    }
}
