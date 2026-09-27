//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

struct ConversationMuteManager {
    private let dateProvider: DateProvider = Date.provider
    private let db: DB = DependenciesBridge.shared.db

    func mute(_ threadViewModel: ThreadViewModel, choice: ConversationMuteChoice) {
        mute([threadViewModel], choice: choice)
    }

    func mute(_ threadViewModels: [ThreadViewModel], choice: ConversationMuteChoice) {
        setMutedUntilTimestamp(endTimestamp(for: choice), for: threadViewModels)
    }

    func unmute(_ threadViewModel: ThreadViewModel) {
        unmute([threadViewModel])
    }

    func unmute(_ threadViewModels: [ThreadViewModel]) {
        setMutedUntilTimestamp(0, for: threadViewModels)
    }

    private func endTimestamp(for choice: ConversationMuteChoice) -> UInt64 {
        switch choice {
        case .preset(let preset):
            dateProvider().addingTimeInterval(preset.duration).ows_millisecondsSince1970
        case .custom(let endDate):
            endDate.ows_millisecondsSince1970
        case .forever:
            TSThread.alwaysMutedTimestamp
        }
    }

    private func setMutedUntilTimestamp(
        _ timestamp: UInt64,
        for threadViewModels: [ThreadViewModel],
    ) {
        db.write { transaction in
            for threadViewModel in threadViewModels {
                threadViewModel.threadRecord.updateWith(
                    mutedUntilTimestamp: timestamp,
                    updateStorageService: true,
                    transaction: transaction,
                )
            }
        }
    }
}

enum ConversationMuteChoice {
    case preset(Preset)
    case custom(endDate: Date)
    case forever

    enum Preset: CaseIterable {
        case oneHour
        case eightHours
        case oneDay
        case oneWeek

        var duration: TimeInterval {
            switch self {
            case .oneHour: .hour
            case .eightHours: 8 * .hour
            case .oneDay: .day
            case .oneWeek: .week
            }
        }

        var localizedTitle: String {
            switch self {
            case .oneHour:
                OWSLocalizedString(
                    "CONVERSATION_SETTINGS_MUTE_ONE_HOUR_ACTION",
                    comment: "Label for button to mute a thread for an hour.",
                )
            case .eightHours:
                OWSLocalizedString(
                    "CONVERSATION_SETTINGS_MUTE_EIGHT_HOUR_ACTION",
                    comment: "Label for button to mute a thread for eight hours.",
                )
            case .oneDay:
                OWSLocalizedString(
                    "CONVERSATION_SETTINGS_MUTE_ONE_DAY_ACTION",
                    comment: "Label for button to mute a thread for a day.",
                )
            case .oneWeek:
                OWSLocalizedString(
                    "CONVERSATION_SETTINGS_MUTE_ONE_WEEK_ACTION",
                    comment: "Label for button to mute a thread for a week.",
                )
            }
        }
    }

    enum Option {
        case preset(Preset)
        case forever
        case custom

        static var all: [Option] {
            Preset.allCases.map { .preset($0) } + [.custom, .forever]
        }

        var title: String {
            switch self {
            case .preset(let preset):
                preset.localizedTitle
            case .forever:
                OWSLocalizedString(
                    "CONVERSATION_SETTINGS_MUTE_ALWAYS_ACTION",
                    comment: "Label for button to mute a thread forever.",
                )
            case .custom:
                OWSLocalizedString(
                    "CONVERSATION_SETTINGS_MUTE_CUSTOM_ACTION",
                    comment: "Label for button to mute a thread until a date the user picks.",
                )
            }
        }
    }
}
