//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public extension OWSDisappearingConfigurationUpdateInfoMessage {
    @objc
    static func legacyDisappearingMessageUpdateDescription(
        token newToken: DisappearingMessageToken,
        wasAddedToExistingGroup: Bool,
        updaterName: String?
    ) -> String {
        // This might be zero if DMs are not enabled.
        let durationString = String.formatDurationLossless(
            durationSeconds: newToken.durationSeconds
        )

        if wasAddedToExistingGroup {
            assert(newToken.isEnabled)
            let format = OWSLocalizedString("DISAPPEARING_MESSAGES_CONFIGURATION_GROUP_EXISTING_FORMAT",
                                            comment: "Info Message when added to a group which has enabled disappearing messages. Embeds {{time amount}} before messages disappear. See the *_TIME_AMOUNT strings for context.")
            return String(format: format, durationString)
        } else if let updaterName = updaterName {
            if newToken.isEnabled {
                let format = OWSLocalizedString("OTHER_UPDATED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                                comment: "Info Message when another user enabled disappearing messages. Embeds {{name of other user}} and {{time amount}} before messages disappear. See the *_TIME_AMOUNT strings for context.")
                return String(format: format, updaterName, durationString)
            } else {
                let format = OWSLocalizedString("OTHER_DISABLED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                                comment: "Info Message when another user disabled disappearing messages. Embeds {{name of other user}}.")
                return String(format: format, updaterName)
            }
        } else {
            // Changed by localNumber on this device or via synced transcript
            if newToken.isEnabled {
                let format = OWSLocalizedString("YOU_UPDATED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                                comment: "Info Message when you update disappearing messages duration. Embeds a {{time amount}} before messages disappear. see the *_TIME_AMOUNT strings for context.")
                return String(format: format, durationString)
            } else {
                return OWSLocalizedString("YOU_DISABLED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                          comment: "Info Message when you disabled disappearing messages.")
            }
        }
    }
}
