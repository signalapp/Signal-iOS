//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public class TSResourceMultisend {

    private init() {}

    public class func sendApprovedMedia(
        conversations: [ConversationItem],
        approvalMessageBody: MessageBody?,
        approvedAttachments: [SignalAttachment]
    ) -> AttachmentMultisend.Result {
        if AttachmentFeatureFlags.writeStories && AttachmentFeatureFlags.writeMessages {
            return AttachmentMultisend.sendApprovedMedia(
                conversations: conversations,
                approvedMessageBody: approvalMessageBody,
                approvedAttachments: approvedAttachments
            )
        } else if !AttachmentFeatureFlags.writeStories && !AttachmentFeatureFlags.writeMessages {
            return TSAttachmentMultisend.sendApprovedMedia(
                conversations: conversations,
                approvalMessageBody: approvalMessageBody,
                approvedAttachments: approvedAttachments
            )
        } else {
            // We need to mix and match.
            let storyConversations = conversations.filter(\.isStory)
            let messageConversations = conversations.filter(\.isStory.negated)

            func sendToStoryConversations(approvedAttachments: [SignalAttachment]) -> AttachmentMultisend.Result {
                if AttachmentFeatureFlags.writeStories {
                    return AttachmentMultisend.sendApprovedMedia(
                        conversations: storyConversations,
                        approvedMessageBody: approvalMessageBody,
                        approvedAttachments: approvedAttachments
                    )
                } else {
                    return TSAttachmentMultisend.sendApprovedMedia(
                        conversations: storyConversations,
                        approvalMessageBody: approvalMessageBody,
                        approvedAttachments: approvedAttachments
                    )
                }
            }

            func sendToMessageConversations(approvedAttachments: [SignalAttachment]) -> AttachmentMultisend.Result {
                if AttachmentFeatureFlags.writeMessages {
                    return AttachmentMultisend.sendApprovedMedia(
                        conversations: messageConversations,
                        approvedMessageBody: approvalMessageBody,
                        approvedAttachments: approvedAttachments
                    )
                } else {
                    return TSAttachmentMultisend.sendApprovedMedia(
                        conversations: messageConversations,
                        approvalMessageBody: approvalMessageBody,
                        approvedAttachments: approvedAttachments
                    )
                }
            }

            if storyConversations.isEmpty {
                return sendToMessageConversations(approvedAttachments: approvedAttachments)
            } else if messageConversations.isEmpty {
                return sendToStoryConversations(approvedAttachments: approvedAttachments)
            } else {
                // Clone attachments for the separate multisends
                let storyResult = sendToStoryConversations(
                    approvedAttachments: approvedAttachments.compactMap { try? $0.cloneAttachment() }
                )
                let messageResult = sendToMessageConversations(approvedAttachments: approvedAttachments)

                return .init(
                    preparedPromise: Promise
                        .when(
                            on: SyncScheduler(),
                            fulfilled: [storyResult.preparedPromise, messageResult.preparedPromise]
                        ).map(on: SyncScheduler()) { $0.reduce([], +) },
                    enqueuedPromise: Promise
                        .when(
                            on: SyncScheduler(),
                            fulfilled: [storyResult.enqueuedPromise, messageResult.enqueuedPromise]
                        ).map(on: SyncScheduler()) { $0.reduce([], +) },
                    sentPromise: Promise
                        .when(
                            on: SyncScheduler(),
                            fulfilled: [storyResult.sentPromise, messageResult.sentPromise]
                        ).map(on: SyncScheduler()) { $0.reduce([], +) }
                )
            }
        }
    }

    public class func sendTextAttachment(
        _ textAttachment: UnsentTextAttachment,
        to conversations: [ConversationItem]
    ) -> AttachmentMultisend.Result {
        if AttachmentFeatureFlags.writeStories {
            return AttachmentMultisend.sendTextAttachment(textAttachment, to: conversations)
        } else {
            return TSAttachmentMultisend.sendTextAttachment(textAttachment, to: conversations)
        }
    }
}
