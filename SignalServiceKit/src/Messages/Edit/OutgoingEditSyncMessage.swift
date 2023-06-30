//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class OutgoingEditMessageSyncTranscript: OWSOutgoingSentMessageTranscript {

    public override func prepareDataSyncMessageContent(
        with sentBuilder: SSKProtoSyncMessageSentBuilder,
        transaction: SDSAnyReadTransaction
    ) -> Bool {
        guard let message = message as? OutgoingEditMessage else {
            return false
        }

        let editBuilder = SSKProtoEditMessage.builder()

        guard let dataBuilder = message.dataMessageBuilder(
            with: messageThread,
            transaction: transaction
        ) else {
            return false
        }

        editBuilder.setTargetSentTimestamp(message.targetMessageTimestamp)
        do {
            editBuilder.setDataMessage(try dataBuilder.build())
            sentBuilder.setEditMessage(try editBuilder.build())
        } catch {
            owsFailDebug("Failed to build edit message proto")
            return false
        }

        return true
    }
}
