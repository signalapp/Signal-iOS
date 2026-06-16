//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@objc(UsernameChangeSyncMessage)
class UsernameChangeSyncMessage: OutgoingSyncMessage {
    override class var supportsSecureCoding: Bool { true }

    override var isUrgent: Bool { true }

    override func syncMessageBuilder(tx: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let builder = SSKProtoSyncMessage.builder()

        let usernameChangeProtoBuilder = SSKProtoSyncMessageUsernameChange.builder()
        builder.setUsernameChange(usernameChangeProtoBuilder.buildInfallibly())

        return builder
    }
}
