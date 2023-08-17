//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreServices
import SignalCoreKit
import SignalMessaging
import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugUIMessages: DebugUIPage, Dependencies {

    private enum MessageContentType {
        case normal
        case longText
        case shortText
    }

    let name = "Messages"

    func section(thread: TSThread?) -> OWSTableSection? {
        var items = [OWSTableItem]()

        if let thread {
            items += [
                OWSTableItem(title: "Delete All Messages in Thread", actionBlock: {
                    self.databaseStorage.write { transaction in
                        thread.removeAllThreadInteractions(transaction: transaction)
                    }
                })
            ]

            items += DebugUIMessages.itemsForActions([
                DebugUIMessages.fakeAllContactShareAction(thread: thread),
                DebugUIMessages.sendMessageVariationsAction(thread: thread),
                // Send Media
                DebugUIMessages.sendAllMediaAction(thread: thread),
                DebugUIMessages.sendRandomMediaAction(thread: thread),
                // Fake Media
                DebugUIMessages.fakeAllMediaAction(thread: thread),
                DebugUIMessages.fakeRandomMediaAction(thread: thread),
                // Fake Text
                DebugUIMessages.fakeAllTextAction(thread: thread),
                DebugUIMessages.fakeRandomTextAction(thread: thread),
                // Sequences
                DebugUIMessages.allFakeSequencesAction(thread: thread),
                // Quoted Replies
                DebugUIMessages.allQuotedReplyAction(thread: thread),
                // Exemplary
                DebugUIMessages.allFakeActionsAction(thread: thread),
                DebugUIMessages.allFakeBackDatedAction(thread: thread)
            ])

            items += [
                // MARK: - Actions
                OWSTableItem(title: "Send N text messages (1/sec.)", actionBlock: {
                    DebugUIMessages.sendNTextMessagesInThread(thread)
                }),
                OWSTableItem(title: "Receive UUID message", actionBlock: {
                    DebugUIMessages.receiveUUIDEnvelopeInNewThread()
                }),
                OWSTableItem(title: "Create UUID group", actionBlock: {
                    DebugUIMessages.createUUIDGroup()
                }),
                OWSTableItem(title: "Send Media Gallery", actionBlock: {
                    DebugUIMessages.sendMediaAlbumInThread(thread)
                }),
                OWSTableItem(title: "Send Exemplary Media Galleries", actionBlock: {
                    DebugUIMessages.sendExemplaryMediaGalleriesInThread(thread)
                }),
                OWSTableItem(title: "Select Fake", actionBlock: {
                    DebugUIMessages.selectFakeAction(thread: thread)
                }),
                OWSTableItem(title: "Select Send Media", actionBlock: {
                    DebugUIMessages.selectSendMediaAction(thread: thread)
                }),
                OWSTableItem(title: "Send All Contact Shares", actionBlock: {
                    DebugUIMessages.sendAllContacts(thread: thread)
                }),
                OWSTableItem(title: "Select Quoted Reply", actionBlock: {
                    DebugUIMessages.selectQuotedReplyAction(thread: thread)
                }),
                OWSTableItem(title: "Select Back-Dated", actionBlock: {
                    DebugUIMessages.selectBackDatedAction(thread: thread)
                }),

                // MARK: - Misc.
                OWSTableItem(title: "Perform random actions", actionBlock: {
                    DebugUIMessages.askForQuantityWithTitle("How many actions?") { quantity in
                        DebugUIMessages.performRandomActions(quantity, inThread: thread)
                    }
                }),
                OWSTableItem(title: "Create Threads", actionBlock: {
                    DebugUIMessages.askForQuantityWithTitle("How many threads?") { threadQuantity in
                        DebugUIMessages.askForQuantityWithTitle("How many messages in each thread?") { messageQuantity in
                            DebugUIMessages.createFakeThreads(threadQuantity, withFakeMessages: messageQuantity)
                        }
                    }
                }),
                OWSTableItem(title: "Send text/x-signal-plain", actionBlock: {
                    DebugUIMessages.sendOversizeTextMessageInThread(thread)
                }),
                OWSTableItem(title: "Send unknown mimetype", actionBlock: {
                    DebugUIMessages.sendRandomAttachmentInThread(thread, uti: kUnknownTestAttachmentUTI)
                }),
                OWSTableItem(title: "Send pdf", actionBlock: {
                    DebugUIMessages.sendRandomAttachmentInThread(thread, uti: kUTTypePDF as String)
                }),
                OWSTableItem(title: "Create all system messages", actionBlock: {
                    DebugUIMessages.createSystemMessagesInThread(thread)
                }),
                OWSTableItem(title: "Create messages with variety of timestamps", actionBlock: {
                  DebugUIMessages.createTimestampMessagesInThread(thread)
                }),
                OWSTableItem(title: "Send text and system messages", actionBlock: {
                    DebugUIMessages.askForQuantityWithTitle("How many messages?") { quantity in
                        DebugUIMessages.sendTextAndSystemMessages(quantity, thread: thread)
                    }
                }),
                OWSTableItem(title: "Message with stalled timer", actionBlock: {
                    DebugUIMessages.createDisappearingMessagesWhichFailedToStartInThread(thread)
                }),
                OWSTableItem(title: "Inject fake incoming messages", actionBlock: {
                    DebugUIMessages.askForQuantityWithTitle("How many messages?") { quantity in
                        DebugUIMessages.injectFakeIncomingMessages(quantity, inThread: thread)
                    }
                }),

                OWSTableItem(title: "Test Indic Scripts", actionBlock: {
                    DebugUIMessages.testIndicScriptsInThread(thread)
                }),
                OWSTableItem(title: "Test Zalgo", actionBlock: {
                    DebugUIMessages.testZalgoTextInThread(thread)
                }),
                OWSTableItem(title: "Test Directional Filenames", actionBlock: {
                    DebugUIMessages.testDirectionalFilenamesInThread(thread)
                }),
                OWSTableItem(title: "Test Linkification", actionBlock: {
                    DebugUIMessages.testLinkificationInThread(thread)
                })
            ]
        }

        if let contactThread = thread as? TSContactThread {
            let recipientAddress = contactThread.contactAddress
            items.append(OWSTableItem(title: "Create New Groups", actionBlock: {
                DebugUIMessages.askForQuantityWithTitle("How many Groups?") { quantity in
                    DebugUIMessages.createNewGroups(count: quantity, recipientAddress: recipientAddress)
                }
            }))
        }
        if let groupThread = thread as? TSGroupThread {
            items.append(OWSTableItem(title: "Send message to all members", actionBlock: {
                    DebugUIMessages.sendMessages(1, toAllMembersOfGroup: groupThread)
                }
            ))
        }

        return OWSTableSection(title: name, items: items)
    }

    private static func itemsForActions(_ actions: [DebugUIMessagesAction]) -> [OWSTableItem] {
        let items: [OWSTableItem] = actions.map { action in
            OWSTableItem(
                title: action.label,
                actionBlock: {
                    // For "all in group" actions, do each subaction in the group
                    // exactly once, in a predictable order.
                    if let groupAction = action as? DebugUIMessagesGroupAction,
                       groupAction.mode == .ordered {
                        groupAction.prepareAndPerformNTimes(UInt(groupAction.subactions.count))
                        return
                    }
                    DebugUIMessages.performActionNTimes(action)
                }
            )
        }
        return items
    }

    // MARK: Infra

    private static func askForQuantityWithTitle(_ title: String, completion: @escaping (UInt) -> Void) {
        guard let fromViewController = UIApplication.shared.frontmostViewController else { return }

        let actionSheet = ActionSheetController(title: title)
        [ 1, 10, 25, 100, 1 * 1000, 10 * 1000 ].forEach { count in
            actionSheet.addAction(ActionSheetAction(
                title: String(count),
                handler: { _ in
                    completion(UInt(count))
                }
            ))
        }
        actionSheet.addAction(OWSActionSheets.cancelAction)
        fromViewController.presentActionSheet(actionSheet)
    }

    private static func performActionNTimes(_ action: DebugUIMessagesAction) {
        askForQuantityWithTitle("How many?") { quantity in
            action.prepareAndPerformNTimes(quantity)
        }
    }

    private static func selectActionUI(_ actions: [DebugUIMessagesAction], label: String) {
        guard let fromViewController = UIApplication.shared.frontmostViewController else {
            owsFailDebug("No frontmost view controller.")
            return
        }

        let actionSheet = ActionSheetController(title: label)
        for action in actions {
            actionSheet.addAction(ActionSheetAction(
                title: action.label,
                handler: { _ in
                    self.performActionNTimes(action)
                }
            ))
        }
        actionSheet.addAction(OWSActionSheets.cancelAction)
        fromViewController.presentActionSheet(actionSheet)
    }

    private static func selectFakeAction(thread: TSThread) {
        selectActionUI(allFakeActions(thread: thread, includeLabels: false), label: "Select Fake")
    }

    // MARK: Fake Media

    private static func fakeAllMediaAction(thread: TSThread) -> DebugUIMessagesAction {
        return DebugUIMessagesGroupAction.allGroupActionWithLabel(
            "All Fake Media",
            subactions: allFakeMediaActions(thread: thread, includeLabels: true)
        )
    }

    private static func fakeRandomMediaAction(thread: TSThread) -> DebugUIMessagesAction {
        return DebugUIMessagesGroupAction.randomGroupActionWithLabel(
            "Random Fake Media",
            subactions: allFakeMediaActions(thread: thread, includeLabels: false)
        )
    }

    private static func allFakeMediaActions(thread: TSThread, includeLabels: Bool) -> [DebugUIMessagesAction] {
        var actions = [DebugUIMessagesAction]()

        // Outgoing

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "⚠️ Outgoing Jpeg ⚠️"))
        }
        actions += [
            fakeOutgoingJpegAction(thread: thread, messageState: .failed, hasCaption: false),
            fakeOutgoingJpegAction(thread: thread, messageState: .failed, hasCaption: true),
            fakeOutgoingJpegAction(thread: thread, messageState: .sending, hasCaption: false),
            fakeOutgoingJpegAction(thread: thread, messageState: .sending, hasCaption: true),
            fakeOutgoingJpegAction(thread: thread, messageState: .sent, hasCaption: false),
            fakeOutgoingJpegAction(thread: thread, messageState: .sent, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "⚠️ Outgoing Gif ⚠️"))
        }
        actions += [
            // Don't bother with multiple GIF states.
            fakeOutgoingGifAction(thread: thread, messageState: .sent, hasCaption: false),
            fakeOutgoingLargeGifAction(thread: thread, messageState: .sent, hasCaption: false)
        ]

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "⚠️ Outgoing Mp3 ⚠️"))
        }
        actions += [
            fakeOutgoingMp3Action(thread: thread, messageState: .sending, hasCaption: true),
            fakeOutgoingMp3Action(thread: thread, messageState: .sending, hasCaption: false),
            fakeOutgoingMp3Action(thread: thread, messageState: .failed, hasCaption: false),
            fakeOutgoingMp3Action(thread: thread, messageState: .failed, hasCaption: true),
            fakeOutgoingMp3Action(thread: thread, messageState: .sent, hasCaption: false),
            fakeOutgoingMp3Action(thread: thread, messageState: .sent, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "⚠️ Outgoing Mp4 ⚠️"))
        }
        actions += [
            fakeOutgoingMp4Action(thread: thread, messageState: .sending, hasCaption: false),
            fakeOutgoingMp4Action(thread: thread, messageState: .sending, hasCaption: true),
            fakeOutgoingMp4Action(thread: thread, messageState: .failed, hasCaption: false),
            fakeOutgoingMp4Action(thread: thread, messageState: .failed, hasCaption: true),
            fakeOutgoingMp4Action(thread: thread, messageState: .sent, hasCaption: false),
            fakeOutgoingMp4Action(thread: thread, messageState: .sent, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "⚠️ Outgoing Compact Landscape Png ⚠️"))
        }
        actions += [
            fakeOutgoingCompactLandscapePngAction(thread: thread, messageState: .sending, hasCaption: false),
            fakeOutgoingCompactLandscapePngAction(thread: thread, messageState: .sending, hasCaption: true),
            fakeOutgoingCompactLandscapePngAction(thread: thread, messageState: .failed, hasCaption: false),
            fakeOutgoingCompactLandscapePngAction(thread: thread, messageState: .failed, hasCaption: true),
            fakeOutgoingCompactLandscapePngAction(thread: thread, messageState: .sent, hasCaption: false),
            fakeOutgoingCompactLandscapePngAction(thread: thread, messageState: .sent, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "⚠️ Outgoing Compact Portrait Png ⚠️"))
        }
        actions += [
            fakeOutgoingCompactPortraitPngAction(thread: thread, messageState: .sending, hasCaption: false),
            fakeOutgoingCompactPortraitPngAction(thread: thread, messageState: .sending, hasCaption: true),
            fakeOutgoingCompactPortraitPngAction(thread: thread, messageState: .failed, hasCaption: false),
            fakeOutgoingCompactPortraitPngAction(thread: thread, messageState: .failed, hasCaption: true),
            fakeOutgoingCompactPortraitPngAction(thread: thread, messageState: .sent, hasCaption: false),
            fakeOutgoingCompactPortraitPngAction(thread: thread, messageState: .sent, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "⚠️ Outgoing Wide Landscape Png ⚠️"))
        }
        actions += [
            fakeOutgoingWideLandscapePngAction(thread: thread, messageState: .sending, hasCaption: false),
            fakeOutgoingWideLandscapePngAction(thread: thread, messageState: .sending, hasCaption: true),
            fakeOutgoingWideLandscapePngAction(thread: thread, messageState: .failed, hasCaption: false),
            fakeOutgoingWideLandscapePngAction(thread: thread, messageState: .failed, hasCaption: true),
            fakeOutgoingWideLandscapePngAction(thread: thread, messageState: .sent, hasCaption: false),
            fakeOutgoingWideLandscapePngAction(thread: thread, messageState: .sent, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "⚠️ Outgoing Tall Portrait Png ⚠️"))
        }
        actions += [
            fakeOutgoingTallPortraitPngAction(thread: thread, messageState: .sending, hasCaption: false),
            fakeOutgoingTallPortraitPngAction(thread: thread, messageState: .sending, hasCaption: true),
            fakeOutgoingTallPortraitPngAction(thread: thread, messageState: .failed, hasCaption: false),
            fakeOutgoingTallPortraitPngAction(thread: thread, messageState: .failed, hasCaption: true),
            fakeOutgoingTallPortraitPngAction(thread: thread, messageState: .sent, hasCaption: false),
            fakeOutgoingTallPortraitPngAction(thread: thread, messageState: .sent, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "⚠️ Outgoing Large Png ⚠️"))
        }
        actions += [
            fakeOutgoingLargePngAction(thread: thread, messageState: .sent, hasCaption: false),
            fakeOutgoingLargePngAction(thread: thread, messageState: .sent, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "⚠️ Outgoing Tiny Png ⚠️"))
        }
        actions += [
            fakeOutgoingTinyPngAction(thread: thread, messageState: .sent, hasCaption: false),
            fakeOutgoingTinyPngAction(thread: thread, messageState: .sent, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "⚠️ Outgoing Reserved Color Png ⚠️"))
        }
        let bubbleColorIncoming = ConversationStyle.bubbleColorIncoming(hasWallpaper: false, isDarkThemeEnabled: Theme.isDarkThemeEnabled)
        actions += [
            fakeOutgoingPngAction(
                thread: thread,
                actionLabel: "Fake Outgoing White Png",
                imageSize: .square(200),
                backgroundColor: .white,
                textColor: Theme.accentBlueColor,
                imageLabel: "W",
                messageState: .failed,
                hasCaption: true
            ),
            fakeOutgoingPngAction(
                thread: thread,
                actionLabel: "Fake Outgoing White Png",
                imageSize: .square(200),
                backgroundColor: .white,
                textColor: Theme.accentBlueColor,
                imageLabel: "W",
                messageState: .sending,
                hasCaption: true
            ),
            fakeOutgoingPngAction(
                thread: thread,
                actionLabel: "Fake Outgoing White Png",
                imageSize: .square(200),
                backgroundColor: .white,
                textColor: Theme.accentBlueColor,
                imageLabel: "W",
                messageState: .sent,
                hasCaption: true
            ),

            fakeOutgoingPngAction(
                thread: thread,
                actionLabel: "Fake Outgoing 'Outgoing' Png",
                imageSize: .square(200),
                backgroundColor: bubbleColorIncoming,
                textColor: .white,
                imageLabel: "W",
                messageState: .failed,
                hasCaption: true
            ),
            fakeOutgoingPngAction(
                thread: thread,
                actionLabel: "Fake Outgoing 'Outgoing' Png",
                imageSize: .square(200),
                backgroundColor: bubbleColorIncoming,
                textColor: .white,
                imageLabel: "W",
                messageState: .sending,
                hasCaption: true
            ),
            fakeOutgoingPngAction(
                thread: thread,
                actionLabel: "Fake Outgoing 'Outgoing' Png",
                imageSize: .square(200),
                backgroundColor: bubbleColorIncoming,
                textColor: .white,
                imageLabel: "W",
                messageState: .sent,
                hasCaption: true
            )
        ]

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "⚠️ Outgoing Tiny Pdf ⚠️"))
        }
        actions += [
            fakeOutgoingTinyPdfAction(thread: thread, messageState: .sending, hasCaption: false),
            fakeOutgoingTinyPdfAction(thread: thread, messageState: .sending, hasCaption: true),
            fakeOutgoingTinyPdfAction(thread: thread, messageState: .failed, hasCaption: false),
            fakeOutgoingTinyPdfAction(thread: thread, messageState: .failed, hasCaption: true),
            fakeOutgoingTinyPdfAction(thread: thread, messageState: .sent, hasCaption: false),
            fakeOutgoingTinyPdfAction(thread: thread, messageState: .sent, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "⚠️ Outgoing Large Pdf ⚠️"))
        }
        actions += [
            fakeOutgoingLargePdfAction(thread: thread, messageState: .failed, hasCaption: false)
        ]

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "⚠️ Outgoing Missing Png ⚠️"))
        }
        actions += [
            fakeOutgoingMissingPngAction(thread: thread, messageState: .failed, hasCaption: false)
        ]

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "⚠️ Outgoing Large Pdf ⚠️"))
        }
        actions += [
            fakeOutgoingMissingPdfAction(thread: thread, messageState: .failed, hasCaption: false)
        ]

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "⚠️ Outgoing Oversize Text ⚠️"))
        }
        actions += [
            fakeOutgoingOversizeTextAction(thread: thread, messageState: .failed, hasCaption: false),
            fakeOutgoingOversizeTextAction(thread: thread, messageState: .sending, hasCaption: false),
            fakeOutgoingOversizeTextAction(thread: thread, messageState: .sent, hasCaption: false)
        ]

        // Incoming

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Incoming Jpg ⚠️"))
        }
        actions += [
            fakeIncomingJpegAction(thread: thread, isAttachmentDownloaded: false, hasCaption: false),
            fakeIncomingJpegAction(thread: thread, isAttachmentDownloaded: true, hasCaption: false),
            fakeIncomingJpegAction(thread: thread, isAttachmentDownloaded: false, hasCaption: true),
            fakeIncomingJpegAction(thread: thread, isAttachmentDownloaded: true, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Incoming Gif ⚠️"))
        }
        actions += [
            fakeIncomingGifAction(thread: thread, isAttachmentDownloaded: true, hasCaption: false),
            fakeIncomingLargeGifAction(thread: thread, isAttachmentDownloaded: true, hasCaption: false)
        ]

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Incoming Mp3 ⚠️"))
        }
        actions += [
            fakeIncomingMp3Action(thread: thread, isAttachmentDownloaded: false, hasCaption: false),
            fakeIncomingMp3Action(thread: thread, isAttachmentDownloaded: true, hasCaption: false),
            fakeIncomingMp3Action(thread: thread, isAttachmentDownloaded: false, hasCaption: true),
            fakeIncomingMp3Action(thread: thread, isAttachmentDownloaded: true, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Incoming Mp4 ⚠️"))
        }
        actions += [
            fakeIncomingMp4Action(thread: thread, isAttachmentDownloaded: false, hasCaption: false),
            fakeIncomingMp4Action(thread: thread, isAttachmentDownloaded: true, hasCaption: false),
            fakeIncomingMp4Action(thread: thread, isAttachmentDownloaded: false, hasCaption: true),
            fakeIncomingMp4Action(thread: thread, isAttachmentDownloaded: true, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Incoming Compact Landscape Png ⚠️"))
        }
        actions += [
            fakeIncomingCompactLandscapePngAction(thread: thread, isAttachmentDownloaded: false, hasCaption: false),
            fakeIncomingCompactLandscapePngAction(thread: thread, isAttachmentDownloaded: true, hasCaption: false),
            fakeIncomingCompactLandscapePngAction(thread: thread, isAttachmentDownloaded: false, hasCaption: true),
            fakeIncomingCompactLandscapePngAction(thread: thread, isAttachmentDownloaded: true, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Incoming Compact Portrait Png ⚠️"))
        }
        actions += [
            fakeIncomingCompactPortraitPngAction(thread: thread, isAttachmentDownloaded: false, hasCaption: false),
            fakeIncomingCompactPortraitPngAction(thread: thread, isAttachmentDownloaded: true, hasCaption: false),
            fakeIncomingCompactPortraitPngAction(thread: thread, isAttachmentDownloaded: false, hasCaption: true),
            fakeIncomingCompactPortraitPngAction(thread: thread, isAttachmentDownloaded: true, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Incoming Wide Landscape Png ⚠️"))
        }
        actions += [
            fakeIncomingWideLandscapePngAction(thread: thread, isAttachmentDownloaded: false, hasCaption: false),
            fakeIncomingWideLandscapePngAction(thread: thread, isAttachmentDownloaded: true, hasCaption: false),
            fakeIncomingWideLandscapePngAction(thread: thread, isAttachmentDownloaded: false, hasCaption: true),
            fakeIncomingWideLandscapePngAction(thread: thread, isAttachmentDownloaded: true, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Incoming Tall Portrait Png ⚠️"))
        }
        actions += [
            fakeIncomingTallPortraitPngAction(thread: thread, isAttachmentDownloaded: false, hasCaption: false),
            fakeIncomingTallPortraitPngAction(thread: thread, isAttachmentDownloaded: true, hasCaption: false),
            fakeIncomingTallPortraitPngAction(thread: thread, isAttachmentDownloaded: false, hasCaption: true),
            fakeIncomingTallPortraitPngAction(thread: thread, isAttachmentDownloaded: true, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Incoming Large Png ⚠️"))
        }
        actions += [
            fakeIncomingLargePngAction(thread: thread, isAttachmentDownloaded: true, hasCaption: false),
            fakeIncomingLargePngAction(thread: thread, isAttachmentDownloaded: true, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Incoming Tiny Png ⚠️"))
        }
        actions += [
            fakeIncomingTinyPngAction(thread: thread, isAttachmentDownloaded: true, hasCaption: false),
            fakeIncomingTinyPngAction(thread: thread, isAttachmentDownloaded: true, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Incoming Reserved Color Png ⚠️"))
        }
        actions += [
            fakeIncomingPngAction(
                thread: thread,
                actionLabel: "Fake Incoming White Png",
                imageSize: .square(200),
                backgroundColor: .white,
                textColor: Theme.accentBlueColor,
                imageLabel: "W",
                isAttachmentDownloaded: true,
                hasCaption: true
            ),

            fakeIncomingPngAction(
                thread: thread,
                actionLabel: "Fake Incoming White Png",
                imageSize: .square(200),
                backgroundColor: .white,
                textColor: Theme.accentBlueColor,
                imageLabel: "W",
                isAttachmentDownloaded: false,
                hasCaption: true),

            fakeIncomingPngAction(
                thread: thread,
                actionLabel: "Fake Incoming 'Incoming' Png",
                imageSize: .square(200),
                backgroundColor: Theme.accentBlueColor,
                textColor: .white,
                imageLabel: "W",
                isAttachmentDownloaded: true,
                hasCaption: true
            ),

            fakeIncomingPngAction(
                thread: thread,
                actionLabel: "Fake Incoming 'Incoming' Png",
                imageSize: .square(200),
                backgroundColor: Theme.accentBlueColor,
                textColor: .white,
                imageLabel: "W",
                isAttachmentDownloaded: true,
                hasCaption: true
            ),

            fakeIncomingPngAction(
                thread: thread,
                actionLabel: "Fake Incoming 'Incoming' Png",
                imageSize: .square(200),
                backgroundColor: Theme.accentBlueColor,
                textColor: .white,
                imageLabel: "W",
                isAttachmentDownloaded: false,
                hasCaption: true
            ),

            fakeIncomingPngAction(
                thread: thread,
                actionLabel: "Fake Incoming 'Incoming' Png",
                imageSize: .square(200),
                backgroundColor: Theme.accentBlueColor,
                textColor: .white,
                imageLabel: "W",
                isAttachmentDownloaded: false,
                hasCaption: true
            )
        ]

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Incoming Tiny Pdf ⚠️"))
        }
        actions += [
            fakeIncomingTinyPdfAction(thread: thread, isAttachmentDownloaded: false, hasCaption: false),
            fakeIncomingTinyPdfAction(thread: thread, isAttachmentDownloaded: true, hasCaption: false),
            fakeIncomingTinyPdfAction(thread: thread, isAttachmentDownloaded: false, hasCaption: true),
            fakeIncomingTinyPdfAction(thread: thread, isAttachmentDownloaded: true, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Incoming Large Pdf ⚠️"))
        }
        actions += [
            fakeIncomingLargePdfAction(thread: thread, isAttachmentDownloaded: true, hasCaption: false)
        ]

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Incoming Missing Png ⚠️"))
        }
        actions += [
            fakeIncomingMissingPngAction(thread: thread, isAttachmentDownloaded: true, hasCaption: false),
            fakeIncomingMissingPngAction(thread: thread, isAttachmentDownloaded: true, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Incoming Missing Pdf ⚠️"))
        }
        actions += [
            fakeIncomingMissingPdfAction(thread: thread, isAttachmentDownloaded: true, hasCaption: false),
            fakeIncomingMissingPdfAction(thread: thread, isAttachmentDownloaded: true, hasCaption: true)
        ]

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Incoming Oversize Text ⚠️"))
        }
        actions += [
            fakeIncomingOversizeTextAction(thread: thread, isAttachmentDownloaded: false, hasCaption: false),
            fakeIncomingOversizeTextAction(thread: thread, isAttachmentDownloaded: true, hasCaption: false)
        ]

        return actions
    }

    // MARK: Fake Outgoing Media

    private static func fakeOutgoingJpegAction(
        thread: TSThread,
        messageState: TSOutgoingMessageState,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeOutgoingMediaAction(
            label: "Fake Outgoing Jpeg",
            messageState: messageState,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.jpegInstance,
            thread: thread
        )
    }

    private static func fakeOutgoingGifAction(
        thread: TSThread,
        messageState: TSOutgoingMessageState,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeOutgoingMediaAction(
            label: "Fake Outgoing Gif",
            messageState: messageState,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.gifInstance,
            thread: thread
        )
    }

    private static func fakeOutgoingLargeGifAction(
        thread: TSThread,
        messageState: TSOutgoingMessageState,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeOutgoingMediaAction(
            label: "Fake Outgoing Large Gif",
            messageState: messageState,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.largeGifInstance,
            thread: thread
        )
    }

    private static func fakeOutgoingMp3Action(
        thread: TSThread,
        messageState: TSOutgoingMessageState,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeOutgoingMediaAction(
            label: "Fake Outgoing Mp3",
            messageState: messageState,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.mp3Instance,
            thread: thread
        )
    }

    private static func fakeOutgoingMp4Action(
        thread: TSThread,
        messageState: TSOutgoingMessageState,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeOutgoingMediaAction(
            label: "Fake Outgoing Mp4",
            messageState: messageState,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.mp4Instance,
            thread: thread
        )
    }

    private static func fakeOutgoingCompactPortraitPngAction(
        thread: TSThread,
        messageState: TSOutgoingMessageState,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeOutgoingMediaAction(
            label: "Fake Outgoing Portrait Png",
            messageState: messageState,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.compactLandscapePngInstance,
            thread: thread
        )
    }

    private static func fakeOutgoingCompactLandscapePngAction(
        thread: TSThread,
        messageState: TSOutgoingMessageState,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeOutgoingMediaAction(
            label: "Fake Outgoing Landscape Png",
            messageState: messageState,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.compactPortraitPngInstance,
            thread: thread
        )
    }

    private static func fakeOutgoingTallPortraitPngAction(
        thread: TSThread,
        messageState: TSOutgoingMessageState,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeOutgoingMediaAction(
            label: "Fake Outgoing Tall Portrait Png",
            messageState: messageState,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.tallPortraitPngInstance,
            thread: thread
        )
    }

    private static func fakeOutgoingWideLandscapePngAction(
        thread: TSThread,
        messageState: TSOutgoingMessageState,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeOutgoingMediaAction(
            label: "Fake Outgoing Wide Landscape Png",
            messageState: messageState,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.wideLandscapePngInstance,
            thread: thread
        )
    }

    private static func fakeOutgoingLargePngAction(
        thread: TSThread,
        messageState: TSOutgoingMessageState,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeOutgoingMediaAction(
            label: "Fake Outgoing Large Png",
            messageState: messageState,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.largePngInstance,
            thread: thread
        )
    }

    private static func fakeOutgoingTinyPngAction(
        thread: TSThread,
        messageState: TSOutgoingMessageState,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeOutgoingMediaAction(
            label: "Fake Outgoing Tiny Png",
            messageState: messageState,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.tinyPngInstance,
            thread: thread
        )
    }

    private static func fakeOutgoingPngAction(
        thread: TSThread,
        actionLabel: String,
        imageSize: CGSize,
        backgroundColor: UIColor,
        textColor: UIColor,
        imageLabel: String,
        messageState: TSOutgoingMessageState,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeOutgoingMediaAction(
            label: actionLabel,
            messageState: messageState,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.pngInstance(
                size: imageSize,
                backgroundColor: backgroundColor,
                textColor: textColor,
                label: imageLabel),
            thread: thread
        )
    }

    private static func fakeOutgoingTinyPdfAction(
        thread: TSThread,
        messageState: TSOutgoingMessageState,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeOutgoingMediaAction(
            label: "Fake Outgoing Tiny Pdf",
            messageState: messageState,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.tinyPdfInstance,
            thread: thread
        )
    }

    private static func fakeOutgoingLargePdfAction(
        thread: TSThread,
        messageState: TSOutgoingMessageState,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeOutgoingMediaAction(label: "Fake Outgoing Large Pdf",
                                       messageState: messageState,
                                       hasCaption: hasCaption,
                                       fakeAssetLoader: DebugUIMessagesAssetLoader.largePdfInstance,
                                       thread: thread
        )
    }

    private static func fakeOutgoingMissingPngAction(
        thread: TSThread,
        messageState: TSOutgoingMessageState,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeOutgoingMediaAction(
            label: "Fake Outgoing Missing Png",
            messageState: messageState,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.missingPngInstance,
            thread: thread
        )
    }

    private static func fakeOutgoingMissingPdfAction(
        thread: TSThread,
        messageState: TSOutgoingMessageState,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeOutgoingMediaAction(
            label: "Fake Outgoing Missing Pdf",
            messageState: messageState,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.missingPdfInstance,
            thread: thread
        )
    }

    private static func fakeOutgoingOversizeTextAction(
        thread: TSThread,
        messageState: TSOutgoingMessageState,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeOutgoingMediaAction(
            label: "Fake Outgoing Oversize Text",
            messageState: messageState,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.oversizeTextInstance,
            thread: thread
        )
    }

    private static func fakeOutgoingMediaAction(
        label labelParam: String,
        messageState: TSOutgoingMessageState,
        hasCaption: Bool,
        fakeAssetLoader: DebugUIMessagesAssetLoader,
        thread: TSThread
    ) -> DebugUIMessagesAction {

        let label = labelParam + actionLabelForHasCaption(hasCaption, outgoingMessageState: messageState, isDelivered: false, isRead: false)
        return DebugUIMessagesSingleAction(
            label: label,
            unstaggeredAction: { index, transaction in
                owsAssertDebug(!fakeAssetLoader.filePath.isEmptyOrNil)
                createFakeOutgoingMedia(
                    index: index,
                    messageState: messageState,
                    hasCaption: hasCaption,
                    fakeAssetLoader: fakeAssetLoader,
                    thread: thread,
                    transaction: transaction
                )
            },
            prepare: fakeAssetLoader.prepare
        )
    }

    private static func createFakeOutgoingMedia(
        index: UInt,
        messageState: TSOutgoingMessageState,
        hasCaption: Bool,
        fakeAssetLoader: DebugUIMessagesAssetLoader,
        thread: TSThread,
        transaction: SDSAnyWriteTransaction
    ) {
        owsAssertDebug(!fakeAssetLoader.filePath.isEmptyOrNil)

        var messageBody: String?
        if hasCaption {
            // We want a message body that is "more than one line on all devices,
            // using all dynamic type sizes."
            let sampleText = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Lorem ipsum dolor sit amet, " +
            "consectetur adipiscing elit."
            messageBody = "\(index) " + sampleText
            messageBody? += actionLabelForHasCaption(
                hasCaption,
                outgoingMessageState: messageState,
                isDelivered: false,
                isRead: false
            )
        }

        let message = createFakeOutgoingMessage(
            thread: thread,
            messageBody: messageBody,
            fakeAssetLoader: fakeAssetLoader,
            messageState: messageState,
            isDelivered: true,
            transaction: transaction
        )

        // This is a hack to "back-date" the message.
        let timestamp = Date.ows_millisecondTimestamp()
        message.replaceTimestamp(timestamp, transaction: transaction)
    }

    // MARK: Fake Incoming Media

    private static func fakeIncomingJpegAction(
        thread: TSThread,
        isAttachmentDownloaded: Bool,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeIncomingMediaAction(
            label: "Fake Incoming Jpeg",
            isAttachmentDownloaded: isAttachmentDownloaded,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.jpegInstance,
            thread: thread
        )
    }

    private static func fakeIncomingGifAction(
        thread: TSThread,
        isAttachmentDownloaded: Bool,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeIncomingMediaAction(
            label: "Fake Incoming Gif",
            isAttachmentDownloaded: isAttachmentDownloaded,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.gifInstance,
            thread: thread
        )
    }

    private static func fakeIncomingLargeGifAction(
        thread: TSThread,
        isAttachmentDownloaded: Bool,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeIncomingMediaAction(
            label: "Fake Incoming Large Gif",
            isAttachmentDownloaded: isAttachmentDownloaded,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.largeGifInstance,
            thread: thread
        )
    }

    private static func fakeIncomingMp3Action(
        thread: TSThread,
        isAttachmentDownloaded: Bool,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeIncomingMediaAction(
            label: "Fake Incoming Mp3",
            isAttachmentDownloaded: isAttachmentDownloaded,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.mp3Instance,
            thread: thread
        )
    }

    private static func fakeIncomingMp4Action(
        thread: TSThread,
        isAttachmentDownloaded: Bool,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeIncomingMediaAction(
            label: "Fake Incoming Mp4",
            isAttachmentDownloaded: isAttachmentDownloaded,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.mp4Instance,
            thread: thread
        )
    }

    private static func fakeIncomingCompactPortraitPngAction(
        thread: TSThread,
        isAttachmentDownloaded: Bool,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeIncomingMediaAction(
            label: "Fake Incoming Portrait Png",
            isAttachmentDownloaded: isAttachmentDownloaded,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.compactPortraitPngInstance,
            thread: thread
        )
    }

    private static func fakeIncomingCompactLandscapePngAction(
        thread: TSThread,
        isAttachmentDownloaded: Bool,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeIncomingMediaAction(
            label: "Fake Incoming Landscape Png",
            isAttachmentDownloaded: isAttachmentDownloaded,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.compactLandscapePngInstance,
            thread: thread
        )
    }

    private static func fakeIncomingTallPortraitPngAction(
        thread: TSThread,
        isAttachmentDownloaded: Bool,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeIncomingMediaAction(
            label: "Fake Incoming Tall Portrait Png",
            isAttachmentDownloaded: isAttachmentDownloaded,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.tallPortraitPngInstance,
            thread: thread
        )
    }

    private static func fakeIncomingWideLandscapePngAction(
        thread: TSThread,
        isAttachmentDownloaded: Bool,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeIncomingMediaAction(
            label: "Fake Incoming Wide Landscape Png",
            isAttachmentDownloaded: isAttachmentDownloaded,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.wideLandscapePngInstance,
            thread: thread
        )
    }

    private static func fakeIncomingLargePngAction(
        thread: TSThread,
        isAttachmentDownloaded: Bool,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeIncomingMediaAction(
            label: "Fake Incoming Large Png",
            isAttachmentDownloaded: isAttachmentDownloaded,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.largePngInstance,
            thread: thread
        )
    }

    private static func fakeIncomingTinyPngAction(
        thread: TSThread,
        isAttachmentDownloaded: Bool,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeIncomingMediaAction(
            label: "Tiny Incoming Large Png",
            isAttachmentDownloaded: isAttachmentDownloaded,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.tinyPngInstance,
            thread: thread
        )
    }

    private static func fakeIncomingPngAction(
        thread: TSThread,
        actionLabel: String,
        imageSize: CGSize,
        backgroundColor: UIColor,
        textColor: UIColor,
        imageLabel: String,
        isAttachmentDownloaded: Bool,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeIncomingMediaAction(
            label: actionLabel,
            isAttachmentDownloaded: isAttachmentDownloaded,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.pngInstance(
                size: imageSize,
                backgroundColor: backgroundColor,
                textColor: textColor,
                label: imageLabel
            ),
            thread: thread
        )
    }

    private static func fakeIncomingTinyPdfAction(
        thread: TSThread,
        isAttachmentDownloaded: Bool,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeIncomingMediaAction(
            label: "Fake Incoming Tiny Pdf",
            isAttachmentDownloaded: isAttachmentDownloaded,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.tinyPdfInstance,
            thread: thread
        )
    }

    private static func fakeIncomingLargePdfAction(
        thread: TSThread,
        isAttachmentDownloaded: Bool,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeIncomingMediaAction(
            label: "Fake Incoming Large Pdf",
            isAttachmentDownloaded: isAttachmentDownloaded,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.largePdfInstance,
            thread: thread
        )
    }

    private static func fakeIncomingMissingPngAction(
        thread: TSThread,
        isAttachmentDownloaded: Bool,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeIncomingMediaAction(
            label: "Fake Incoming Missing Png",
            isAttachmentDownloaded: isAttachmentDownloaded,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.missingPngInstance,
            thread: thread
        )
    }

    private static func fakeIncomingMissingPdfAction(
        thread: TSThread,
        isAttachmentDownloaded: Bool,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeIncomingMediaAction(
            label: "Fake Incoming Missing Pdf",
            isAttachmentDownloaded: isAttachmentDownloaded,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.missingPdfInstance,
            thread: thread
        )
    }

    private static func fakeIncomingOversizeTextAction(
        thread: TSThread,
        isAttachmentDownloaded: Bool,
        hasCaption: Bool
    ) -> DebugUIMessagesAction {
        return fakeIncomingMediaAction(
            label: "Fake Incoming Oversize Text",
            isAttachmentDownloaded: isAttachmentDownloaded,
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.oversizeTextInstance,
            thread: thread
        )
    }

    private static func fakeIncomingMediaAction(
        label labelParam: String,
        isAttachmentDownloaded: Bool,
        hasCaption: Bool,
        fakeAssetLoader: DebugUIMessagesAssetLoader,
        thread: TSThread
    ) -> DebugUIMessagesAction {

        var label = labelParam
        if hasCaption {
            label += " 🔤"
        }
        if isAttachmentDownloaded {
            label += " 👍"
        }

        return DebugUIMessagesSingleAction(
            label: label,
            unstaggeredAction: { index, transaction in
                owsAssertDebug(!fakeAssetLoader.filePath.isEmptyOrNil)
                createFakeIncomingMedia(
                    index: index,
                    isAttachmentDownloaded: isAttachmentDownloaded,
                    hasCaption: hasCaption,
                    fakeAssetLoader: fakeAssetLoader,
                    thread: thread,
                    transaction: transaction
                )
            },
            prepare: fakeAssetLoader.prepare
        )
    }

    @discardableResult
    private static func createFakeIncomingMedia(
        index: UInt,
        isAttachmentDownloaded: Bool,
        hasCaption: Bool,
        fakeAssetLoader: DebugUIMessagesAssetLoader,
        thread: TSThread,
        transaction: SDSAnyWriteTransaction
    ) -> TSIncomingMessage {

        let caption: String?
        if hasCaption {
            // We want a message body that is "more than one line on all devices,
            // using all dynamic type sizes."
            caption = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Lorem ipsum dolor sit amet, " +
                      "consectetur adipiscing elit."
        } else {
            caption = nil
        }
        return createFakeIncomingMedia(
            index: index,
            isAttachmentDownloaded: isAttachmentDownloaded,
            caption: caption,
            fakeAssetLoader: fakeAssetLoader,
            thread: thread,
            transaction: transaction
        )
    }

    private static func createFakeIncomingMedia(
        index: UInt,
        isAttachmentDownloaded: Bool,
        caption: String?,
        fakeAssetLoader: DebugUIMessagesAssetLoader,
        thread: TSThread,
        transaction: SDSAnyWriteTransaction
    ) -> TSIncomingMessage {

        owsAssertDebug(!fakeAssetLoader.filePath.isEmptyOrNil)

        var messageBody: String?
        if let caption {
            messageBody = "\(index) " + caption + " 🔤"
            if isAttachmentDownloaded {
                messageBody? += " 👍"
            }
        }

        return createFakeIncomingMessage(
            thread: thread,
            messageBody: messageBody,
            fakeAssetLoader: fakeAssetLoader,
            isAttachmentDownloaded: isAttachmentDownloaded,
            transaction: transaction
        )
    }

    // MARK: Fake Text Messages

    private static func fakeAllTextAction(thread: TSThread) -> DebugUIMessagesAction {
        return DebugUIMessagesGroupAction.allGroupActionWithLabel(
            "All Fake Text",
            subactions: allFakeTextActions(thread: thread, includeLabels: true)
        )
    }

    private static func fakeRandomTextAction(thread: TSThread) -> DebugUIMessagesAction {
        return DebugUIMessagesGroupAction.randomGroupActionWithLabel(
            "Random Fake Text",
            subactions: allFakeTextActions(thread: thread, includeLabels: false)
        )
    }

    private static func allFakeTextActions(thread: TSThread, includeLabels: Bool) -> [DebugUIMessagesAction] {
        let messageBodies = [
            "Hi",
            "1️⃣",
            "1️⃣2️⃣",
            "1️⃣2️⃣3️⃣",
            "落",
            "﷽"
        ]

        var actions = [DebugUIMessagesAction]()

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Incoming Message Bodies ⚠️"))
        }
        actions.append(fakeShortIncomingTextMessageAction(thread: thread))
        actions += messageBodies.map { messageBody in
            fakeIncomingTextMessageAction(thread: thread, text: messageBody)
        }

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "⚠️ Outgoing Statuses ⚠️"))
        }
        actions += [
            fakeShortOutgoingTextMessageAction(thread: thread, messageState: .failed),
            fakeShortOutgoingTextMessageAction(thread: thread, messageState: .sending),
            fakeShortOutgoingTextMessageAction(thread: thread, messageState: .sent),
            fakeShortOutgoingTextMessageAction(thread: thread, messageState: .sent, isDelivered: true, isRead: false),
            fakeShortOutgoingTextMessageAction(thread: thread, messageState: .sent, isDelivered: true, isRead: true)
        ]

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "⚠️ Outgoing Message Bodies ⚠️"))
        }
        actions += messageBodies.map { messageBody in
            fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: messageBody)
        }

        return actions
    }

    private static func fakeOutgoingTextMessageAction(
        thread: TSThread,
        messageState: TSOutgoingMessageState,
        text: String
    ) -> DebugUIMessagesAction {
        return DebugUIMessagesSingleAction(
            label: "Fake Outgoing Text Message (\(text)",
            unstaggeredAction: { index, transaction in
                let messageBody = "\(index) " + text
                createFakeOutgoingMessage(
                    thread: thread,
                    messageBody: messageBody,
                    messageState: messageState,
                    transaction: transaction
                )
            }
        )
    }

    private static func fakeShortOutgoingTextMessageAction(
        thread: TSThread,
        messageState: TSOutgoingMessageState,
        isDelivered: Bool = false,
        isRead: Bool = false
    ) -> DebugUIMessagesAction {
        return fakeShortOutgoingTextMessageAction(
            thread: thread,
            text: randomText(),
            messageState: messageState,
            isDelivered: isDelivered,
            isRead: isRead
        )
    }

    private static func fakeShortOutgoingTextMessageAction(
        thread: TSThread,
        text: String,
        messageState: TSOutgoingMessageState,
        isDelivered: Bool,
        isRead: Bool
    ) -> DebugUIMessagesAction {

        let label = "Fake Short Incoming Text Message".appending(actionLabelForHasCaption(
            true,
            outgoingMessageState: messageState,
            isDelivered: isDelivered,
            isRead: isRead
        ))

        return DebugUIMessagesSingleAction(
            label: label,
            unstaggeredAction: { index, transaction in
                let messageBody = "\(index) " + text
                createFakeOutgoingMessage(
                    thread: thread,
                    messageBody: messageBody,
                    fakeAssetLoader: nil,
                    messageState: messageState,
                    isDelivered: isDelivered,
                    isRead: isRead,
                    transaction: transaction
                )
            }
        )
    }

    private static func fakeIncomingTextMessageAction(
        thread: TSThread,
        text: String
    ) -> DebugUIMessagesAction {
        return DebugUIMessagesSingleAction(
            label: "Fake Incoming Text Message \(text)",
            unstaggeredAction: { index, transaction in
                let messageBody = "\(index) " + text
                createFakeIncomingMessage(
                    thread: thread,
                    messageBody: messageBody,
                    fakeAssetLoader: nil,
                    transaction: transaction
                )
            }
        )
    }

    private static func fakeShortIncomingTextMessageAction(thread: TSThread) -> DebugUIMessagesAction {
        return DebugUIMessagesSingleAction(
            label: "Fake Short Incoming Text Message",
            unstaggeredAction: { index, transaction in
                 let messageBody = "\(index) " + randomText()
                 createFakeIncomingMessage(
                    thread: thread,
                                     messageBody: messageBody,
                                 fakeAssetLoader: nil,
                          isAttachmentDownloaded: false,
                                     transaction: transaction
                 )
             }
        )
    }

    // MARK: Sequences

    private static func allFakeSequenceActions(thread: TSThread, includeLabels: Bool) -> [DebugUIMessagesAction] {

        var actions = [DebugUIMessagesAction]()

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "⚠️ Short Message Sequences ⚠️"))
        }

        actions.append(fakeIncomingTextMessageAction(thread: thread, text: "Incoming"))
        actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "Outgoing"))
        actions.append(fakeIncomingTextMessageAction(thread: thread, text: "Incoming 1"))
        actions.append(fakeIncomingTextMessageAction(thread: thread, text: "Incoming 2"))
        actions.append(fakeIncomingTextMessageAction(thread: thread, text: "Incoming 3"))

        actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .failed, text: "Outgoing Unsent 1"))
        actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .failed, text: "Outgoing Unsent 2"))

        actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sending, text: "Outgoing Sending 1"))
        actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sending, text: "Outgoing Sending 2"))

        actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "Outgoing Sent 1"))
        actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "Outgoing Sent 2"))

        actions.append(fakeShortOutgoingTextMessageAction(
            thread: thread,
            text: "Outgoing Delivered 1",
            messageState: .sent,
            isDelivered: true,
            isRead: false
        ))
        actions.append(fakeShortOutgoingTextMessageAction(
            thread: thread,
            text: "Outgoing Delivered 2",
            messageState: .sent,
            isDelivered: true,
            isRead: false
        ))

        actions.append(fakeShortOutgoingTextMessageAction(
            thread: thread,
            text: "Outgoing Read 1",
            messageState: .sent,
            isDelivered: true,
            isRead: true
        ))
        actions.append(fakeShortOutgoingTextMessageAction(
            thread: thread,
            text: "Outgoing Read 2",
            messageState: .sent,
            isDelivered: true,
            isRead: true
        ))

        actions.append(fakeIncomingTextMessageAction(thread: thread, text: "Incoming"))

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "⚠️ Long Message Sequences ⚠️"))
        }

        let longText = "\nLorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse rutrum, nulla " +
                       "vitae pretium hendrerit, tellus turpis pharetra libero..."

        actions.append(fakeIncomingTextMessageAction(thread: thread, text: "Incoming " + longText))
        actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "Outgoing" + longText))
        actions.append(fakeIncomingTextMessageAction(thread: thread, text: "Incoming 1" + longText))
        actions.append(fakeIncomingTextMessageAction(thread: thread, text: "Incoming 2" + longText))
        actions.append(fakeIncomingTextMessageAction(thread: thread, text: "Incoming 3" + longText))

        actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .failed, text: "Outgoing Unsent 1" + longText))
        actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .failed, text: "Outgoing Unsent 2" + longText))

        actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sending, text: "Outgoing Sending 1" + longText))
        actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sending, text: "Outgoing Sending 2" + longText))

        actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "Outgoing Sent 1" + longText))
        actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "Outgoing Sent 2" + longText))

        actions.append(fakeShortOutgoingTextMessageAction(
            thread: thread,
            text: "Outgoing Delivered 1" + longText,
            messageState: .sent,
            isDelivered: true,
            isRead: false
        ))
        actions.append(fakeShortOutgoingTextMessageAction(
            thread: thread,
            text: "Outgoing Delivered 2" + longText,
            messageState: .sent,
            isDelivered: true,
            isRead: false
        ))

        actions.append(fakeShortOutgoingTextMessageAction(
            thread: thread,
            text: "Outgoing Read 1" + longText,
            messageState: .sent,
            isDelivered: true,
            isRead: true
        ))
        actions.append(fakeShortOutgoingTextMessageAction(
            thread: thread,
            text: "Outgoing Read 2" + longText,
            messageState: .sent,
            isDelivered: true,
            isRead: true
        ))
        actions.append(fakeIncomingTextMessageAction(thread: thread, text: "Incoming" + longText))

        return actions
    }

    private static func allFakeSequencesAction(thread: TSThread) -> DebugUIMessagesAction {
        return DebugUIMessagesGroupAction.allGroupActionWithLabel(
            "All Fake Sequences",
            subactions: allFakeSequenceActions(thread: thread, includeLabels: true)
        )
    }

    // MARK: Fake Quoted Replies

    private typealias PrepareBlock = (@escaping DebugUIMessagesAction.Completion) -> Void

    private static func fakeQuotedReplyAction(
        thread: TSThread,
        quotedMessageLabel: String,
        isQuotedMessageIncoming: Bool,
        // Optional. At least one of quotedMessageBody and quotedMessageAssetLoader should be non-nil.
        quotedMessageBody quotedMessageBodyParam: String?,
        // Optional. At least one of quotedMessageBody and quotedMessageAssetLoader should be non-nil.
        quotedMessageAssetLoader quotedMessageAssetLoaderParam: DebugUIMessagesAssetLoader?,
        replyLabel: String,
        isReplyIncoming: Bool = false,
        replyMessageBody replyMessageBodyParam: String?,
        replyAssetLoader replyAssetLoaderParam: DebugUIMessagesAssetLoader? = nil,
        // Only applies if !isReplyIncoming.
        replyMessageState: TSOutgoingMessageState = .sent
    ) -> DebugUIMessagesAction {

        // Use fixed values for properties that shouldn't matter much.
        let quotedMessageIsDelivered = false
        let quotedMessageIsRead = false
        let quotedMessageMessageState = TSOutgoingMessageState.sent
        let replyIsDelivered = false
        let replyIsRead = false

        // Seamlessly convert oversize text messages to oversize text attachments.
        var quotedMessageAssetLoader = quotedMessageAssetLoaderParam
        var quotedMessageBody = quotedMessageBodyParam
        if let quotedMessageBodyParam, quotedMessageBodyParam.lengthOfBytes(using: .utf8) >= kOversizeTextMessageSizeThreshold {
            owsAssertDebug(quotedMessageAssetLoaderParam == nil)
            quotedMessageAssetLoader = DebugUIMessagesAssetLoader.oversizeTextInstance(text: quotedMessageBodyParam)
            quotedMessageBody = nil
        }

        var replyAssetLoader = replyAssetLoaderParam
        var replyMessageBody = replyMessageBodyParam
        if let replyMessageBodyParam, replyMessageBodyParam.lengthOfBytes(using: .utf8) >= kOversizeTextMessageSizeThreshold {
            owsAssertDebug(replyAssetLoaderParam == nil)
            replyAssetLoader = DebugUIMessagesAssetLoader.oversizeTextInstance(text: replyMessageBodyParam)
            replyMessageBody = nil
        }

        var label = "Quoted Reply (" + replyLabel
        if !isReplyIncoming {
            label += actionLabelForHasCaption(
                false,
                outgoingMessageState: replyMessageState,
                isDelivered: replyIsDelivered,
                isRead: replyIsRead
            )
        }
        label += (") to (" + quotedMessageLabel)
        if let quotedMessageAssetLoader {
            label += " " + quotedMessageAssetLoader.labelEmoji
        }
        if !isQuotedMessageIncoming {
            label += actionLabelForHasCaption(
                !quotedMessageBody.isEmptyOrNil,
                outgoingMessageState: quotedMessageMessageState,
                isDelivered: quotedMessageIsDelivered,
                isRead: quotedMessageIsRead
            )
        }
        label += ")"

        let prepareBlocks = NSMutableArray()
        if let block = quotedMessageAssetLoader?.prepare {
            prepareBlocks.add(block)
        }
        if let block = replyAssetLoader?.prepare {
            prepareBlocks.add(block)
        }

        return DebugUIMessagesSingleAction(
            label: label,
            unstaggeredAction: { index, transaction in
                let quotedMessageBodyWIndex: String?
                if let quotedMessageBody {
                    quotedMessageBodyWIndex = "\(index) " + quotedMessageBody
                } else {
                    quotedMessageBodyWIndex = nil
                }

                let messageToQuote: TSInteraction = {
                    if isQuotedMessageIncoming {
                        return createFakeIncomingMessage(
                            thread: thread,
                            messageBody: quotedMessageBodyWIndex,
                            fakeAssetLoader: quotedMessageAssetLoader,
                            isAttachmentDownloaded: true,
                            transaction: transaction
                        )
                    } else {
                        return createFakeOutgoingMessage(
                            thread: thread,
                            messageBody: quotedMessageBodyWIndex,
                            fakeAssetLoader: quotedMessageAssetLoader,
                            messageState: quotedMessageMessageState,
                            isDelivered: quotedMessageIsDelivered,
                            isRead: quotedMessageIsRead,
                            transaction: transaction
                        )
                    }
                }()

                let threadAssociatedData = createFakeThreadAssociatedData(thread: thread)

                let containerView = UIView(frame: CGRect(origin: .zero, size: .square(100)))
                let renderItem = CVLoader.debugui_buildStandaloneRenderItem(
                    interaction: messageToQuote,
                    thread: thread,
                    threadAssociatedData: threadAssociatedData,
                    containerView: containerView,
                    transaction: transaction
                )
                let itemViewModel = CVItemViewModelImpl(renderItem: renderItem!)

                let quotedMessage = QuotedReplyModel.forSending(
                    item: itemViewModel,
                    transaction: transaction
                )!.buildQuotedMessageForSending()

                let replyMessageBodyWIndex: String?
                if let replyMessageBody {
                    replyMessageBodyWIndex = "\(index) " + replyMessageBody
                } else {
                    replyMessageBodyWIndex = nil
                }
                if isReplyIncoming {
                    createFakeIncomingMessage(
                        thread: thread,
                        messageBody: replyMessageBodyWIndex,
                        fakeAssetLoader: replyAssetLoader,
                        quotedMessage: quotedMessage,
                        transaction: transaction
                    )
                } else {
                    createFakeOutgoingMessage(
                        thread: thread,
                        messageBody: replyMessageBodyWIndex,
                        fakeAssetLoader: replyAssetLoader,
                        messageState: replyMessageState,
                        isDelivered: replyIsDelivered,
                        isRead: replyIsRead,
                        quotedMessage: quotedMessage,
                        transaction: transaction
                    )
                }
            },
            prepare: groupPrepareBlockWithPrepareBlocks(prepareBlocks)
        )
    }

    // Recursively perform a group of "prepare blocks" in sequence, aborting if any fail.
    private static func groupPrepareBlockWithPrepareBlocks(_ prepareBlocks: NSMutableArray) -> PrepareBlock {
        return { completion in
            groupPrepareBlockStepWithPrepareBlocks(prepareBlocks, completion: completion)
        }
    }

    private static func groupPrepareBlockStepWithPrepareBlocks(
        _ prepareBlocks: NSMutableArray,
        completion: @escaping DebugUIMessagesAction.Completion
    ) {
        guard prepareBlocks.count > 0 else {
            completion(.success(()))
            return
        }
        let nextPrepareBlock = prepareBlocks.lastObject as! PrepareBlock
        prepareBlocks.removeLastObject()

        nextPrepareBlock({ result in
            switch result {
            case .success:
                groupPrepareBlockStepWithPrepareBlocks(prepareBlocks, completion: completion)

            case .failure(let error):
                completion(.failure(error))
            }
        })
    }

    static private func allFakeQuotedReplyActions(thread: TSThread, includeLabels: Bool) -> [DebugUIMessagesAction] {
        let shortText = "Lorem ipsum"
        let mediumText = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Lorem ipsum dolor sit amet, " +
        "consectetur adipiscing elit."
        let longText = randomOversizeText()

        var actions = [DebugUIMessagesAction]()

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Quoted Replies (Message Lengths) ⚠️"))
        }
        actions += [
            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Short Text",
                isQuotedMessageIncoming: false,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: nil,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Short Text",
                isQuotedMessageIncoming: false,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: nil,
                replyLabel: "Medium Text",
                replyMessageBody: mediumText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Medium Text",
                isQuotedMessageIncoming: false,
                quotedMessageBody: mediumText,
                quotedMessageAssetLoader: nil,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Medium Text",
                isQuotedMessageIncoming: false,
                quotedMessageBody: mediumText,
                quotedMessageAssetLoader: nil,
                replyLabel: "Medium Text",
                replyMessageBody: mediumText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Long Text",
                isQuotedMessageIncoming: false,
                quotedMessageBody: longText,
                quotedMessageAssetLoader: nil,
                replyLabel: "Long Text",
                replyMessageBody: longText,
                replyMessageState: .sent
            )
        ]

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Quoted Replies (Attachment Types) ⚠️"))
        }
        actions += [
            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Jpg",
                isQuotedMessageIncoming: false,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.jpegInstance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Jpg",
                isQuotedMessageIncoming: false,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.jpegInstance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Mp3",
                isQuotedMessageIncoming: false,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.mp3Instance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Mp3",
                isQuotedMessageIncoming: false,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.mp3Instance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Mp4",
                isQuotedMessageIncoming: false,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.mp4Instance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Mp4",
                isQuotedMessageIncoming: false,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.mp4Instance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Gif",
                isQuotedMessageIncoming: false,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.gifInstance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Gif",
                isQuotedMessageIncoming: false,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.gifInstance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Pdf",
                isQuotedMessageIncoming: true,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.tinyPdfInstance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Missing Pdf",
                isQuotedMessageIncoming: true,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.missingPdfInstance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Tiny Png",
                isQuotedMessageIncoming: true,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.tinyPngInstance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Missing Png",
                isQuotedMessageIncoming: true,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.missingPngInstance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            )
        ]

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Quoted Replies (Attachment Layout) ⚠️"))
        }
        actions += [
            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Tall Portrait Png",
                isQuotedMessageIncoming: false,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.tallPortraitPngInstance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Tall Portrait Png",
                isQuotedMessageIncoming: false,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.tallPortraitPngInstance,
                replyLabel: "Medium Text",
                replyMessageBody: mediumText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Tall Portrait Png",
                isQuotedMessageIncoming: false,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.tallPortraitPngInstance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Wide Landscape Png",
                isQuotedMessageIncoming: false,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.wideLandscapePngInstance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Wide Landscape Png",
                isQuotedMessageIncoming: false,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.wideLandscapePngInstance,
                replyLabel: "Medium Text",
                replyMessageBody: mediumText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Wide Landscape Png",
                isQuotedMessageIncoming: false,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.wideLandscapePngInstance,
                replyLabel: "Medium Text",
                replyMessageBody: mediumText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Tiny Png",
                isQuotedMessageIncoming: true,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.tinyPngInstance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Tiny Png",
                isQuotedMessageIncoming: true,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.tinyPngInstance,
                replyLabel: "Medium Text",
                replyMessageBody: mediumText,
                replyMessageState: .sent
            )
        ]

        let directionActions: (Bool, Bool) -> Void = { isQuotedMessageIncoming, isReplyIncoming in
            actions.append(fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Short Text",
                isQuotedMessageIncoming: isQuotedMessageIncoming,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: nil,
                replyLabel: "Short Text",
                isReplyIncoming: isReplyIncoming,
                replyMessageBody: shortText,
                replyMessageState: .sent
            ))
        }

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Quoted Replies (Incoming v. Outgoing) ⚠️"))
        }
        directionActions(false, false)
        directionActions(true, false)
        directionActions(false, true)
        directionActions(true, true)

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Quoted Replies (Message States) ⚠️"))
        }
        actions += [
            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Jpg",
                isQuotedMessageIncoming: true,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.jpegInstance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Mp3",
                isQuotedMessageIncoming: true,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.mp3Instance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Mp4",
                isQuotedMessageIncoming: true,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.mp4Instance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Gif",
                isQuotedMessageIncoming: true,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.gifInstance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Pdf",
                isQuotedMessageIncoming: true,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.tinyPdfInstance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Missing Pdf",
                isQuotedMessageIncoming: true,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.missingPdfInstance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Tiny Png",
                isQuotedMessageIncoming: true,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.tinyPngInstance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Missing Png",
                isQuotedMessageIncoming: true,
                quotedMessageBody: nil,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.missingPngInstance,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Short Text",
                isQuotedMessageIncoming: false,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: nil,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sending
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Short Text",
                isQuotedMessageIncoming: false,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: nil,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Short Text",
                isQuotedMessageIncoming: false,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: nil,
                replyLabel: "Short Text",
                replyMessageBody: shortText,
                replyMessageState: .failed
            )
        ]

        if includeLabels {
            actions.append(fakeIncomingTextMessageAction(thread: thread, text: "⚠️ Quoted Replies (Reply W. Attachment) ⚠️"))
        }
        actions += [
            // Png + Text -> Png + Text
            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Tall Portrait Png",
                isQuotedMessageIncoming: false,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: DebugUIMessagesAssetLoader.tallPortraitPngInstance,
                replyLabel: "Tall Portrait Png",
                replyMessageBody: shortText,
                replyAssetLoader: DebugUIMessagesAssetLoader.tallPortraitPngInstance,
                replyMessageState: .sent
            ),

            // Text -> Png + Text
            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Short Text",
                isQuotedMessageIncoming: false,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: nil,
                replyLabel: "Tall Portrait Png",
                replyMessageBody: shortText,
                replyMessageState: .sent
            ),

            // Text -> Png
            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Short Text",
                isQuotedMessageIncoming: false,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: nil,
                replyLabel: "Tall Portrait Png",
                replyMessageBody: nil,
                replyAssetLoader: DebugUIMessagesAssetLoader.tallPortraitPngInstance,
                replyMessageState: .sent
            ),

            // Png -> Png + Text
            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Short Text",
                isQuotedMessageIncoming: false,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: nil,
                replyLabel: "Tall Portrait Png",
                replyMessageBody: shortText,
                replyAssetLoader: DebugUIMessagesAssetLoader.tallPortraitPngInstance,
                replyMessageState: .sent
            ),

            // Png -> Portrait Png + Text
            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Short Text",
                isQuotedMessageIncoming: false,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: nil,
                replyLabel: "Tall Portrait Png",
                replyMessageBody: shortText,
                replyAssetLoader: DebugUIMessagesAssetLoader.tallPortraitPngInstance,
                replyMessageState: .sent
            ),

            // Png -> Landscape Png + Text
            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Short Text",
                isQuotedMessageIncoming: false,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: nil,
                replyLabel: "Wide Landscape Png",
                replyMessageBody: shortText,
                replyAssetLoader: DebugUIMessagesAssetLoader.wideLandscapePngInstance,
                replyMessageState: .sent
            ),

            // Png -> Landscape Png + Text
            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Short Text",
                isQuotedMessageIncoming: false,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: nil,
                replyLabel: "Wide Landscape Png + Short Text",
                replyMessageBody: shortText,
                replyAssetLoader: DebugUIMessagesAssetLoader.wideLandscapePngInstance,
                replyMessageState: .sent
            ),

            // Png -> Landscape Png + Text
            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Short Text",
                isQuotedMessageIncoming: false,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: nil,
                replyLabel: "Wide Landscape Png + Short Text",
                replyMessageBody: shortText,
                replyAssetLoader: DebugUIMessagesAssetLoader.wideLandscapePngInstance,
                replyMessageState: .sent
            ),

            // Png -> Landscape Png + Text
            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Short Text",
                isQuotedMessageIncoming: false,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: nil,
                replyLabel: "Wide Landscape Png + Medium Text",
                replyMessageBody: mediumText,
                replyAssetLoader: DebugUIMessagesAssetLoader.wideLandscapePngInstance,
                replyMessageState: .sent
            ),

            // Png -> Landscape Png + Text
            fakeQuotedReplyAction(
                thread: thread,
                quotedMessageLabel: "Short Text",
                isQuotedMessageIncoming: false,
                quotedMessageBody: shortText,
                quotedMessageAssetLoader: nil,
                replyLabel: "Wide Landscape Png + Medium Text",
                replyMessageBody: mediumText,
                replyAssetLoader: DebugUIMessagesAssetLoader.wideLandscapePngInstance,
                replyMessageState: .sent
            )
        ]

        return actions
    }

    private static func selectQuotedReplyAction(thread: TSThread) {
        selectActionUI(allFakeQuotedReplyActions(thread: thread, includeLabels: false), label: "Select QuotedReply")
    }

    private static func allQuotedReplyAction(thread: TSThread) -> DebugUIMessagesAction {
        return DebugUIMessagesGroupAction.allGroupActionWithLabel(
            "All Quoted Reply",
            subactions: allFakeQuotedReplyActions(thread: thread, includeLabels: true)
        )
    }

    private static func randomQuotedReplyAction(thread: TSThread) -> DebugUIMessagesAction {
        return DebugUIMessagesGroupAction.randomGroupActionWithLabel(
            "Random Quoted Reply",
            subactions: allFakeQuotedReplyActions(thread: thread, includeLabels: false)
        )
    }

    // MARK: Exemplary

    private static func allFakeActionsAction(thread: TSThread) -> DebugUIMessagesAction {
        return DebugUIMessagesGroupAction.allGroupActionWithLabel(
            "All Fake",
            subactions: allFakeActions(thread: thread, includeLabels: true)
        )
    }

    private static func allFakeActions(thread: TSThread, includeLabels: Bool) -> [DebugUIMessagesAction] {
        var actions = [DebugUIMessagesAction]()
        actions.append(contentsOf: allFakeMediaActions(thread: thread, includeLabels: includeLabels))
        actions.append(contentsOf: allFakeTextActions(thread: thread, includeLabels: includeLabels))
        actions.append(contentsOf: allFakeSequenceActions(thread: thread, includeLabels: includeLabels))
        actions.append(contentsOf: allFakeQuotedReplyActions(thread: thread, includeLabels: includeLabels))
        actions.append(contentsOf: allFakeBackDatedActions(thread: thread, includeLabels: includeLabels))
        actions.append(contentsOf: allFakeContactShareActions(thread: thread, includeLabels: includeLabels))
        return actions
    }

    // MARK: Back-dated

    private static func allFakeBackDatedAction(thread: TSThread) -> DebugUIMessagesAction {
        return DebugUIMessagesGroupAction.allGroupActionWithLabel(
            "All Fake Back-Dated",
            subactions: allFakeBackDatedActions(thread: thread, includeLabels: true)
        )
    }

    private static func allFakeBackDatedActions(thread: TSThread, includeLabels: Bool) -> [DebugUIMessagesAction] {
        var actions = [DebugUIMessagesAction]()

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(thread: thread, messageState: .sent, text: "⚠️ Back-Dated ⚠️"))
        }

        actions.append(fakeBackDatedMessageAction(thread: thread, label: "One Minute Ago", dateOffset: -Int64(kMinuteInMs)))
        actions.append(fakeBackDatedMessageAction(thread: thread, label: "One Hour Ago", dateOffset: -Int64(kHourInMs)))
        actions.append(fakeBackDatedMessageAction(thread: thread, label: "One Day Ago", dateOffset: -Int64(kDayInMs)))
        actions.append(fakeBackDatedMessageAction(thread: thread, label: "Two Days Ago", dateOffset: -Int64(kDayInMs) * 2))
        actions.append(fakeBackDatedMessageAction(thread: thread, label: "Ten Days Ago", dateOffset: -Int64(kDayInMs) * 10))
        actions.append(fakeBackDatedMessageAction(thread: thread, label: "5 Months Ago", dateOffset: -Int64(kDayInMs) * 30 * 5))
        actions.append(fakeBackDatedMessageAction(thread: thread, label: "7 Months Ago", dateOffset: -Int64(kDayInMs) * 30 * 7))
        actions.append(fakeBackDatedMessageAction(thread: thread, label: "400 Days Ago", dateOffset: -Int64(kDayInMs) * 400))

        return actions
    }

    private static func fakeBackDatedMessageAction(thread: TSThread, label: String, dateOffset: Int64) -> DebugUIMessagesAction {
        return DebugUIMessagesSingleAction(
            label: "Fake Back-Date Message \(label)",
            unstaggeredAction: { index, transaction in
                let messageBody = ["\(index)", randomText(), label].joined(separator: " ")
                let message = createFakeOutgoingMessage(
                    thread: thread,
                    messageBody: messageBody,
                    messageState: .sent,
                    transaction: transaction
                )
                let timestamp = Int64(Date.ows_millisecondTimestamp()) + dateOffset
                message.replaceTimestamp(UInt64(timestamp), transaction: transaction)
                message.replaceReceived(atTimestamp: UInt64(timestamp), transaction: transaction)
            }
        )
    }

    private static func selectBackDatedAction(thread: TSThread) {
        selectActionUI(allFakeBackDatedActions(thread: thread, includeLabels: false), label: "Select Back-Dated")
    }

    // MARK: Contact Shares

    private typealias CreateContactBlock = (SDSAnyWriteTransaction) -> OWSContact

    private static func fakeAllContactShareAction(thread: TSThread) -> DebugUIMessagesAction {
        return DebugUIMessagesGroupAction.allGroupActionWithLabel(
            "All Fake Contact Shares",
            subactions: allFakeContactShareActions(thread: thread, includeLabels: true)
        )
    }

    private static func allFakeContactShareActions(thread: TSThread, includeLabels: Bool) -> [DebugUIMessagesAction] {
        var actions = [DebugUIMessagesAction]()

        if includeLabels {
            actions.append(fakeOutgoingTextMessageAction(
                thread: thread,
                messageState: .sent,
                text: "⚠️ Share Contact ⚠️"
            ))
        }

        actions.append(fakeContactShareMessageAction(
            thread: thread,
            label: "Name & Number",
            contact: { _ in
                let contact = OWSContact()!
                contact.name = {
                    let name = OWSContactName()!
                    name.givenName = "Alice"
                    return name
                }()
                let phoneNumber = OWSContactPhoneNumber()!
                phoneNumber.phoneType = .home
                phoneNumber.phoneNumber = "+13213214321"
                contact.phoneNumbers = [ phoneNumber ]
                return contact
            }
        ))

        actions.append(fakeContactShareMessageAction(
            thread: thread,
            label: "Name & Email",
            contact: { _ in
                let contact = OWSContact()!
                contact.name = {
                    let name = OWSContactName()!
                    name.givenName = "Bob"
                    return name
                }()
                let email = OWSContactEmail()!
                email.emailType = .home
                email.email = "a@b.com"
                contact.emails = [ email ]
                return contact
            }
        ))

        actions.append(fakeContactShareMessageAction(
            thread: thread,
            label: "Complicated",
            contact: { transaction in
                let contact = OWSContact()!
                contact.name = {
                    let name = OWSContactName()!
                    name.givenName = "Alice"
                    name.familyName = "Carol"
                    name.middleName = "Bob"
                    name.namePrefix = "Ms."
                    name.nameSuffix = "Esq."
                    name.organizationName = "Falafel Hut"
                    return name
                }()

                let phoneNumber1 = OWSContactPhoneNumber()!
                phoneNumber1.phoneType = .home
                phoneNumber1.phoneNumber = "+13213215555"
                let phoneNumber2 = OWSContactPhoneNumber()!
                phoneNumber2.phoneType = .custom
                phoneNumber2.label = "Carphone"
                phoneNumber2.phoneNumber = "+13332226666"
                contact.phoneNumbers = [ phoneNumber1, phoneNumber2 ]

                let emails = (0..<16).map { i in
                    let email = OWSContactEmail()!
                    email.emailType = .home
                    email.email = String(format: "a%zd@b.com", i)
                    return email
                }
                contact.emails = emails

                let address1 = OWSContactAddress()!
                address1.addressType = .home
                address1.street = "123 home st."
                address1.neighborhood = "round the bend."
                address1.city = "homeville"
                address1.region = "HO"
                address1.postcode = "12345"
                address1.country = "USA"
                let address2 = OWSContactAddress()!
                address2.addressType = .custom
                address2.label = "Otra casa"
                address2.pobox = "caja 123"
                address2.street = "123 casa calle"
                address2.city = "barrio norte"
                address2.region = "AB"
                address2.postcode = "53421"
                address2.country = "MX"
                contact.addresses = [ address1, address2 ]

                let avatarImage = AvatarBuilder.buildRandomAvatar(diameterPoints: 200)!
                contact.saveAvatarImage(avatarImage, transaction: transaction)

                return contact
            }
        ))

        actions.append(fakeContactShareMessageAction(
            thread: thread,
            label: "Long values",
            contact: { _ in
                let contact = OWSContact()!
                contact.name = {
                    let name = OWSContactName()!
                    name.givenName = "Bobasdjasdlkjasldkjas"
                    name.familyName = "Bobasdjasdlkjasldkjas"
                    return name
                }()

                let email = OWSContactEmail()!
                email.emailType = .mobile
                email.email = "asdlakjsaldkjasldkjasdlkjasdlkjasdlkajsa@b.com"
                contact.emails = [ email ]
                return contact
            }
        ))

        actions.append(fakeContactShareMessageAction(
            thread: thread,
            label: "System Contact w/o Signal",
            contact: { _ in
                let contact = OWSContact()!
                contact.name = {
                    let name = OWSContactName()!
                    name.givenName = "Add Me To Your Contacts"
                    return name
                }()

                let phoneNumber = OWSContactPhoneNumber()!
                phoneNumber.phoneType = .work
                phoneNumber.phoneNumber = "+32460205391"
                contact.phoneNumbers = [ phoneNumber ]
                return contact
            }
        ))

        actions.append(fakeContactShareMessageAction(
            thread: thread,
            label: "System Contact w. Signal",
            contact: { _ in
                let contact = OWSContact()!
                contact.name = {
                    let name = OWSContactName()!
                    name.givenName = "Add Me To Your Contacts"
                    return name
                }()
                let phoneNumber = OWSContactPhoneNumber()!
                phoneNumber.phoneType = .work
                phoneNumber.phoneNumber = "+32460205392"
                contact.phoneNumbers = [ phoneNumber ]
                return contact
            }
        ))

        return actions
    }

    private static func fakeContactShareMessageAction(
        thread: TSThread,
        label: String,
        contact: @escaping CreateContactBlock
    ) -> DebugUIMessagesAction {
        return DebugUIMessagesSingleAction(
            label: "Fake Contact Share \(label)",
            unstaggeredAction: { index, transaction in
                createFakeOutgoingMessage(
                    thread: thread,
                    messageBody: nil,
                    messageState: .sent,
                    contactShare: contact(transaction),
                    transaction: transaction
                )
            })
    }

    private static func sendAllContacts(thread: TSThread) {
        let subactions = allFakeContactShareActions(thread: thread, includeLabels: false)
        let action = DebugUIMessagesGroupAction.allGroupActionWithLabel("Send All Contact Shares", subactions: subactions)
        action.prepareAndPerformNTimes(UInt(subactions.count))
    }

    // MARK: Send Media

    private static func selectSendMediaAction(thread: TSThread) {
        selectActionUI(allSendMediaActions(thread: thread), label: "Select Send Media")
    }

    private static func sendAllMediaAction(thread: TSThread) -> DebugUIMessagesAction {
        return DebugUIMessagesGroupAction.allGroupActionWithLabel(
            "All Send Media",
            subactions: allSendMediaActions(thread: thread)
        )
    }

    private static func sendRandomMediaAction(thread: TSThread) -> DebugUIMessagesAction {
        return DebugUIMessagesGroupAction.randomGroupActionWithLabel(
            "Random Send Media",
            subactions: allSendMediaActions(thread: thread)
        )
    }

    private static func allSendMediaActions(thread: TSThread) -> [DebugUIMessagesAction] {
        return [
            sendJpegAction(thread: thread, hasCaption: false),
            sendJpegAction(thread: thread, hasCaption: true),

            sendGifAction(thread: thread, hasCaption: false),
            sendGifAction(thread: thread, hasCaption: true),

            sendLargeGifAction(thread: thread, hasCaption: false),
            sendLargeGifAction(thread: thread, hasCaption: true),

            sendMp3Action(thread: thread, hasCaption: false),
            sendMp3Action(thread: thread, hasCaption: true),

            sendMp4Action(thread: thread, hasCaption: false),
            sendMp4Action(thread: thread, hasCaption: true)
        ]
    }

    private static func sendJpegAction(thread: TSThread, hasCaption: Bool) -> DebugUIMessagesAction {
        return sendMediaAction(
            label: "Send Jpeg",
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.jpegInstance,
            thread: thread
        )
    }

    private static func sendGifAction(thread: TSThread, hasCaption: Bool) -> DebugUIMessagesAction {
        return sendMediaAction(
            label: "Send Gif",
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.gifInstance,
            thread: thread
        )
    }

    private static func sendLargeGifAction(thread: TSThread, hasCaption: Bool) -> DebugUIMessagesAction {
        return sendMediaAction(
            label: "Send Large Gif",
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.largeGifInstance,
            thread: thread
        )
    }

    private static func sendMp3Action(thread: TSThread, hasCaption: Bool) -> DebugUIMessagesAction {
        return sendMediaAction(
            label: "Send Mp3",
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.mp3Instance,
            thread: thread
        )
    }

    private static func sendMp4Action(thread: TSThread, hasCaption: Bool) -> DebugUIMessagesAction {
        return sendMediaAction(
            label: "Send Mp4",
            hasCaption: hasCaption,
            fakeAssetLoader: DebugUIMessagesAssetLoader.mp4Instance,
            thread: thread
        )
    }

    private static func sendMediaAction(
        label labelParam: String,
        hasCaption: Bool,
        fakeAssetLoader: DebugUIMessagesAssetLoader,
        thread: TSThread
    ) -> DebugUIMessagesAction {

        let label = hasCaption ? labelParam.appending(" 🔤") : labelParam
        return DebugUIMessagesSingleAction(
            label: label,
            staggeredAction: { index, transaction, completion in
                DispatchQueue.main.async {
                    owsAssertDebug(!fakeAssetLoader.filePath.isEmptyOrNil)
                    self.sendAttachmentWithFileUrl(
                        URL(fileURLWithPath: fakeAssetLoader.filePath!),
                        thread: thread,
                        label: label,
                        hasCaption: hasCaption,
                        completion: completion
                    )
                }
            },
            prepare: fakeAssetLoader.prepare
        )
    }

    private static func sendAttachmentWithFileUrl(
        _ fileUrl: URL,
        thread: TSThread,
        label: String,
        hasCaption: Bool,
        completion: (Result<Void, Error>) -> Void
    ) {
        guard let utiType = MIMETypeUtil.utiType(forFileExtension: fileUrl.pathExtension) else {
            completion(.failure(DebugUIError.unknownFileExtension))
            return
        }

        let filename = fileUrl.lastPathComponent

        let dataSource: DataSource
        do {
            dataSource = try DataSourcePath.dataSource(withFilePath: fileUrl.path, shouldDeleteOnDeallocation: false)
            dataSource.sourceFilename = filename
        } catch {
            owsFailDebug("error while creating data source: \(error)")
            completion(.failure(error))
            return
        }

        let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: utiType)

        let messageText: String?
        if hasCaption {
            // We want a message body that is "more than one line on all devices,
            // using all dynamic type sizes."
            let sampleText = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Lorem ipsum dolor sit amet, " +
                "consectetur adipiscing elit."
            messageText = label.appending(" ").appending(sampleText).appending(" 🔤")

            attachment.captionText = messageText
        } else {
            messageText = nil
        }

        if attachment.hasError {
            Logger.error("attachment[\(String(describing: attachment.sourceFilename))]: \(String(describing: attachment.errorName))")
            Logger.flush()
            owsAssertDebug(false)
        }

        sendAttachment(attachment, thread: thread, messageText: messageText)

        completion(.success(()))
    }

    private static func sendAttachment(
        _ attachment: SignalAttachment?,
        thread: TSThread,
        messageText: String?
    ) {
        databaseStorage.read { transaction in
            let attachments: [SignalAttachment]
            if let attachment {
                attachments = [ attachment ]
            } else {
                attachments = []
            }
            let messageBody: MessageBody?
            if let messageText {
                messageBody = MessageBody(text: messageText, ranges: .empty)
            } else {
                messageBody = nil
            }
            ThreadUtil.enqueueMessage(
                body: messageBody,
                mediaAttachments: attachments,
                thread: thread,
                transaction: transaction
            )
        }
    }

    private static func sendRandomAttachmentInThread(_ thread: TSThread, uti: String, length: UInt32 = 256) {
        guard let dataSource = DataSourceValue.dataSource(with: createRandomDataOfSize(length), utiType: uti) else {
            owsFailDebug("Failed to create data source.")
            return
        }

        let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: uti)
        if Bool.random() {
            // give 1/2 our attachments captions, and add a hint that it's a caption since we
            // style them indistinguishably from a separate text message.
            attachment.captionText = randomCaptionText()
        }
        sendAttachment(attachment, thread: thread, messageText: nil)
    }

    // MARK: Media Albums

    private static func sendExemplaryMediaGalleriesInThread(_ thread: TSThread) {
        sendMediaAlbumInThread(thread, imageCount: 2, messageText: nil)
        sendMediaAlbumInThread(thread, imageCount: 3, messageText: nil)
        sendMediaAlbumInThread(thread, imageCount: 4, messageText: nil)
        sendMediaAlbumInThread(thread, imageCount: 5, messageText: nil)
        sendMediaAlbumInThread(thread, imageCount: 6, messageText: nil)
        sendMediaAlbumInThread(thread, imageCount: 7, messageText: nil)
        let messageText = "This is the media gallery title..."
        sendMediaAlbumInThread(thread, imageCount: 2, messageText: messageText)
        sendMediaAlbumInThread(thread, imageCount: 3, messageText: messageText)
        sendMediaAlbumInThread(thread, imageCount: 4, messageText: messageText)
        sendMediaAlbumInThread(thread, imageCount: 5, messageText: messageText)
        sendMediaAlbumInThread(thread, imageCount: 6, messageText: messageText)
        sendMediaAlbumInThread(thread, imageCount: 7, messageText: messageText)
    }

    private static func sendMediaAlbumInThread(_ thread: TSThread) {
        let imageCount = UInt.random(in: 2...10)
        let messageText: String? = Bool.random() ? "This is the media gallery title..." : nil
        sendMediaAlbumInThread(thread, imageCount: imageCount, messageText: messageText)
    }

    private static func sendMediaAlbumInThread(_ thread: TSThread, imageCount: UInt, messageText: String?) {
        let fakeAssetLoaders: [DebugUIMessagesAssetLoader] = [
            DebugUIMessagesAssetLoader.jpegInstance,
            DebugUIMessagesAssetLoader.largePngInstance,
            DebugUIMessagesAssetLoader.tinyPngInstance,
            DebugUIMessagesAssetLoader.gifInstance,
            DebugUIMessagesAssetLoader.mp4Instance,
            DebugUIMessagesAssetLoader.mediumFilesizePngInstance
        ]
        DebugUIMessagesAssetLoader.prepareAssetLoaders(fakeAssetLoaders) { result in
            switch result {
            case .success:
                sendMediaAlbumInThread(thread, imageCount: imageCount, messageText: messageText, fakeAssetLoaders: fakeAssetLoaders)
            case .failure(let error):
                Logger.error("Could not prepare fake asset loaders. [\(error)]")
            }
        }
    }

    private static func sendMediaAlbumInThread(
        _ thread: TSThread,
        imageCount: UInt,
        messageText: String?,
        fakeAssetLoaders: [DebugUIMessagesAssetLoader]
    ) {
        let attachments: [SignalAttachment] = (0..<imageCount).compactMap { _ in
            let fakeAssetLoader = fakeAssetLoaders.randomElement()!
            owsAssertDebug(FileManager.default.fileExists(atPath: fakeAssetLoader.filePath!))

            let fileExtension = fakeAssetLoader.filePath?.fileExtension!
            let tempFilePath = OWSFileSystem.temporaryFilePath(fileExtension: fileExtension)
            do {
                try FileManager.default.copyItem(
                    at: URL(fileURLWithPath: fakeAssetLoader.filePath!),
                    to: URL(fileURLWithPath: tempFilePath)
                )
            } catch {
                return nil
            }

            guard
                let dataSource = try? DataSourcePath.dataSource(withFilePath: tempFilePath, shouldDeleteOnDeallocation: false),
                let uti = MIMETypeUtil.utiType(forMIMEType: fakeAssetLoader.mimeType)
            else {
                return nil
            }

            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: uti)
            if Bool.random() {
                attachment.captionText = randomText()
            }
            return attachment
        }

        let messageBody: MessageBody?
        if let messageText {
            messageBody = MessageBody(text: messageText, ranges: .empty)
        } else {
            messageBody = nil
        }

        databaseStorage.read { transaction in
            let message = ThreadUtil.enqueueMessage(
                body: messageBody,
                mediaAttachments: attachments,
                thread: thread,
                transaction: transaction
            )
            Logger.debug("timestamp: \(message.timestamp)")
        }
    }

    // MARK: Send Text Messages

    private static func sendMessageVariationsAction(thread: TSThread) -> DebugUIMessagesAction {
        return DebugUIMessagesGroupAction.allGroupActionWithLabel(
            "Send Conversation Cell Variations",
            subactions: [
                sendShortTextMessageAction(thread: thread),
                sendOversizeTextMessageAction(thread: thread)
            ]
        )
    }

    private static func sendShortTextMessageAction(thread: TSThread) -> DebugUIMessagesAction {
        return DebugUIMessagesSingleAction(
            label: "Send Short Text Message",
            staggeredAction: { index, transaction, completion in
                DispatchQueue.main.async {
                    self.sendTextMessageInThread(thread, counter: index)
                }
            }
        )
    }

    private static func sendOversizeTextMessageAction(thread: TSThread) -> DebugUIMessagesAction {
        return DebugUIMessagesSingleAction(
            label: "Send Oversize Text Message",
            staggeredAction: { index, transaction, completion in
                DispatchQueue.main.async {
                    self.sendOversizeTextMessageInThread(thread)
                }
            }
        )
    }

    private static func sendTextMessageInThread(_ thread: TSThread, counter: UInt) {
        Logger.info("sendTextMessageInThread: \(counter)")
        Logger.flush()

        let text = "\(counter) " + randomText()
        let message = databaseStorage.write { transaction in
            return ThreadUtil.enqueueMessage(
                body: MessageBody(text: text, ranges: .empty),
                thread: thread,
                transaction: transaction
            )
        }
        Logger.info("sendTextMessageInThread timestamp: \(message.timestamp).")
    }

    private static func sendOversizeTextMessageInThread(_ thread: TSThread) {
        sendAttachment(nil, thread: thread, messageText: randomOversizeText())
    }

    private static func sendNTextMessagesInThread(_ thread: TSThread) {
        performActionNTimes(sendTextMessagesActionInThread(thread))
    }

    private static func sendTextMessagesActionInThread(_ thread: TSThread) -> DebugUIMessagesAction {
        return DebugUIMessagesSingleAction(
            label: "Send Text Message",
            staggeredAction: { index, transaction, completion in
                DispatchQueue.main.async {
                    sendTextMessageInThread(thread, counter: index)
                    completion(.success(()))
                }
            })
    }

    // MARK: System Messages

    private static func createSystemMessageInThread(_ thread: TSThread) {
        let message = unsavedSystemMessagesInThread(thread).randomElement()!
        databaseStorage.write { transaction in
            message.anyInsert(transaction: transaction)
        }
    }

    private static func createSystemMessagesInThread(_ thread: TSThread) {
        let messages = unsavedSystemMessagesInThread(thread)
        databaseStorage.write { transaction in
            for message in messages {
                message.anyInsert(transaction: transaction)
            }
        }
    }

    private static func unsavedSystemMessagesInThread(_ thread: TSThread) -> [TSInteraction] {
        let messages = databaseStorage.write { transaction in
            return unsavedSystemMessagesInThread(thread, transaction: transaction)
        }
        return messages
    }

    private static func unsavedSystemMessagesInThread(_ thread: TSThread, transaction: SDSAnyWriteTransaction) -> [TSInteraction] {
        guard let incomingSenderAddress = anyIncomingSenderAddress(forThread: thread) else {
            owsFailDebug("Missing incomingSenderAddress.")
            return []
        }

        var results = [TSInteraction]()

        // Calls

        if let contactThread = thread as? TSContactThread {
            results += [
                TSCall(
                    callType: .incoming,
                    offerType: .audio,
                    thread: contactThread,
                    sentAtTimestamp: Date.ows_millisecondTimestamp()
                ),
                TSCall(
                    callType: .outgoing,
                    offerType: .audio,
                    thread: contactThread,
                    sentAtTimestamp: Date.ows_millisecondTimestamp()
                ),
                TSCall(
                    callType: .incomingMissed,
                    offerType: .audio,
                    thread: contactThread,
                    sentAtTimestamp: Date.ows_millisecondTimestamp()
                ),
                TSCall(
                    callType: .incomingMissedBecauseOfChangedIdentity,
                    offerType: .audio,
                    thread: contactThread,
                    sentAtTimestamp: Date.ows_millisecondTimestamp()
                ),
                TSCall(
                    callType: .outgoingIncomplete,
                    offerType: .audio,
                    thread: contactThread,
                    sentAtTimestamp: Date.ows_millisecondTimestamp()
                ),
                TSCall(
                    callType: .incomingIncomplete,
                    offerType: .audio,
                    thread: contactThread,
                    sentAtTimestamp: Date.ows_millisecondTimestamp()
                ),
                TSCall(
                    callType: .incomingDeclined,
                    offerType: .audio,
                    thread: contactThread,
                    sentAtTimestamp: Date.ows_millisecondTimestamp()
                ),
                TSCall(
                    callType: .outgoingMissed,
                    offerType: .audio,
                    thread: contactThread,
                    sentAtTimestamp: Date.ows_millisecondTimestamp()
                ),
                TSCall(
                    callType: .incomingMissedBecauseOfDoNotDisturb,
                    offerType: .audio,
                    thread: contactThread,
                    sentAtTimestamp: Date.ows_millisecondTimestamp()
                )
            ]
        }

        // Disappearing Messages

        if let durationSeconds = OWSDisappearingMessagesConfiguration.presetDurationsSeconds().first?.uint32Value {
            let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            let disappearingMessagesConfiguration = dmConfigurationStore
                .fetchOrBuildDefault(for: .thread(thread), tx: transaction.asV2Read)
                .copyAsEnabled(withDurationSeconds: durationSeconds)
            results.append(OWSDisappearingConfigurationUpdateInfoMessage(
                thread: thread,
                configuration: disappearingMessagesConfiguration,
                createdByRemoteName: "Alice",
                createdInExistingGroup: false
            ))
            results.append(OWSDisappearingConfigurationUpdateInfoMessage(
                thread: thread,
                configuration: disappearingMessagesConfiguration,
                createdByRemoteName: nil,
                createdInExistingGroup: true
            ))
        }

        if let durationSeconds = OWSDisappearingMessagesConfiguration.presetDurationsSeconds().last?.uint32Value {
            let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            let disappearingMessagesConfiguration = dmConfigurationStore
                .fetchOrBuildDefault(for: .thread(thread), tx: transaction.asV2Read)
                .copyAsEnabled(withDurationSeconds: durationSeconds)
            results.append(OWSDisappearingConfigurationUpdateInfoMessage(
                thread: thread,
                configuration: disappearingMessagesConfiguration,
                createdByRemoteName: "Alice",
                createdInExistingGroup: false
            ))
        }

        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        let disappearingMessagesConfiguration = dmConfigurationStore
            .fetchOrBuildDefault(for: .thread(thread), tx: transaction.asV2Read)
            .copy(withIsEnabled: false)
        results.append(OWSDisappearingConfigurationUpdateInfoMessage(
            thread: thread,
            configuration: disappearingMessagesConfiguration,
            createdByRemoteName: "Alice",
            createdInExistingGroup: false
        ))

        results += [
            TSInfoMessage.userNotRegisteredMessage(in: thread, address: incomingSenderAddress),

            TSInfoMessage(thread: thread, messageType: .typeSessionDidEnd),
            // TODO: customMessage?
            TSInfoMessage(thread: thread, messageType: .typeGroupUpdate),
            // TODO: customMessage?
            TSInfoMessage(thread: thread, messageType: .typeGroupQuit),

            OWSVerificationStateChangeMessage(
                thread: thread,
                recipientAddress: incomingSenderAddress,
                verificationState: .default,
                isLocalChange: true
            ),
            OWSVerificationStateChangeMessage(
                thread: thread,
                recipientAddress: incomingSenderAddress,
                verificationState: .verified,
                isLocalChange: true
            ),
            OWSVerificationStateChangeMessage(
                thread: thread,
                recipientAddress: incomingSenderAddress,
                verificationState: .noLongerVerified,
                isLocalChange: true
            ),

            OWSVerificationStateChangeMessage(
                thread: thread,
                recipientAddress: incomingSenderAddress,
                verificationState: .default,
                isLocalChange: false
            ),
            OWSVerificationStateChangeMessage(
                thread: thread,
                recipientAddress: incomingSenderAddress,
                verificationState: .verified,
                isLocalChange: false),
            OWSVerificationStateChangeMessage(
                thread: thread,
                recipientAddress: incomingSenderAddress,
                verificationState: .noLongerVerified,
                isLocalChange: false
            ),

            TSErrorMessage.missingSession(with: createEnvelopeForThread(thread), with: transaction),
            TSErrorMessage.invalidKeyException(with: createEnvelopeForThread(thread), with: transaction),
            TSErrorMessage.invalidVersion(with: createEnvelopeForThread(thread), with: transaction),
            TSErrorMessage.corruptedMessage(with: createEnvelopeForThread(thread), with: transaction),

            TSErrorMessage.nonblockingIdentityChange(in: thread, address: incomingSenderAddress, wasIdentityVerified: false),
            TSErrorMessage.nonblockingIdentityChange(in: thread, address: incomingSenderAddress, wasIdentityVerified: true)
        ]

        if let blockingSNChangeMessage = TSInvalidIdentityKeyReceivingErrorMessage.untrustedKey(
            with: createEnvelopeForThread(thread),
            fakeSourceE164: "+13215550123",
            with: transaction
        ) {
            results.append(blockingSNChangeMessage)
        }

        return results
    }

    private static func sendTextAndSystemMessages(_ counter: UInt, thread: TSThread) {
        guard counter > 0 else { return }

        if Bool.random() {
            sendTextMessageInThread(thread, counter: counter)
        } else {
            createSystemMessageInThread(thread)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            sendTextAndSystemMessages(counter - 1, thread: thread)
        }
    }

    private static func createTimestampMessagesInThread(_ thread: TSThread) {
        let now = Date.ows_millisecondTimestamp()
        let timestamps = [
            now + 1 * kHourInMs,
            now,
            now - 1 * kHourInMs,
            now - 12 * kHourInMs,
            now - 1 * kDayInMs,
            now - 2 * kDayInMs,
            now - 3 * kDayInMs,
            now - 6 * kDayInMs,
            now - 7 * kDayInMs,
            now - 8 * kDayInMs,
            now - 2 * kWeekInMs,
            now - 1 * 30 * kDayInMs,
            now - 2 * 30 * kDayInMs
        ]

        guard let incomingSenderAci = anyIncomingSenderAddress(forThread: thread)?.aci else {
            owsFailDebug("Missing incomingSenderAci.")
            return
        }

        databaseStorage.write { transaction in
            for timestamp in timestamps {
                let randomText = randomText()

                // Legit usage of SenderTimestamp to backdate incoming sent messages for Debug
                let incomingMessageBuilder = TSIncomingMessageBuilder(thread: thread, messageBody: randomText)
                incomingMessageBuilder.timestamp = timestamp
                incomingMessageBuilder.authorAci = AciObjC(incomingSenderAci)
                let incomingMessage = incomingMessageBuilder.build()
                incomingMessage.anyInsert(transaction: transaction)
                incomingMessage.debugonly_markAsReadNow(transaction: transaction)

                // MJK TODO - this might be the one place we actually use senderTimestamp
                let outgoingMessageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: randomText)
                outgoingMessageBuilder.timestamp = timestamp
                let outgoingMessage = outgoingMessageBuilder.build(transaction: transaction)
                outgoingMessage.anyInsert(transaction: transaction)
                outgoingMessage.update(withFakeMessageState: .sent, transaction: transaction)
                outgoingMessage.update(withSentRecipient: ServiceIdObjC.wrapValue(incomingSenderAci), wasSentByUD: false, transaction: transaction)
                outgoingMessage.update(
                    withDeliveredRecipient: SignalServiceAddress(incomingSenderAci),
                    recipientDeviceId: 0,
                    deliveryTimestamp: timestamp,
                    context: PassthroughDeliveryReceiptContext(),
                    transaction: transaction
                )
                outgoingMessage.update(
                    withReadRecipient: SignalServiceAddress(incomingSenderAci),
                    recipientDeviceId: 0,
                    readTimestamp: timestamp,
                    transaction: transaction
                )
            }
        }
    }

    private static func createEnvelopeForThread(_ thread: TSThread) -> SSKProtoEnvelope {
        let source: SignalServiceAddress = {
            if let groupThread = thread as? TSGroupThread {
                return groupThread.groupModel.groupMembers.first!
            } else if let contactThread = thread as? TSContactThread {
                return contactThread.contactAddress
            } else {
                owsFailDebug("Unknown thread type")
                return SignalServiceAddress(phoneNumber: "unknown-source-id")
            }
        }()

        let envelopeBuilder = SSKProtoEnvelope.builder(timestamp: NSDate.ows_millisecondTimeStamp())
        envelopeBuilder.setType(.ciphertext)
        envelopeBuilder.setSourceServiceID(source.aci!.serviceIdString)
        envelopeBuilder.setSourceDevice(1)

        let envelope = try! envelopeBuilder.build()
        return envelope
    }

    // MARK: -

    private static func receiveUUIDEnvelopeInNewThread() {
        let senderClient = FakeSignalClient.generate(e164Identifier: nil)
        let localClient = LocalSignalClient()
        let runner = TestProtocolRunner()
        let fakeService = FakeService(localClient: localClient, runner: runner)

        databaseStorage.write { transaction in
            try! runner.initialize(senderClient: senderClient,
                                   recipientClient: localClient,
                                   transaction: transaction)
        }

        let envelopeBuilder = try! fakeService.envelopeBuilder(fromSenderClient: senderClient)
        envelopeBuilder.setSourceServiceID(senderClient.uuidIdentifier)
        let envelopeData = try! envelopeBuilder.buildSerializedData()
        messageProcessor.processReceivedEnvelopeData(
            envelopeData,
            serverDeliveryTimestamp: 0,
            envelopeSource: .debugUI
        ) { _ in }
    }

    private static func createUUIDGroup() {
        let uuidMembers = (0...3).map { _ in CommonGenerator.address(hasPhoneNumber: false) }
        let members = uuidMembers + [TSAccountManager.localAddress!]
        let groupName = "UUID Group"

        _ = GroupManager.localCreateNewGroup(members: members, name: groupName, disappearingMessageToken: .disabledToken, shouldSendMessage: true)
    }

    // MARK: Fake Threads & Messages

    private static func createFakeThreads(_ threadQuantity: UInt, withFakeMessages messageQuantity: UInt) {
        DebugContactsUtils.createRandomContacts(threadQuantity) { contact, index, stop in
            guard
                let phoneNumberText = contact.phoneNumbers.first?.value.stringValue,
                let e164 = PhoneNumber.tryParsePhoneNumber(fromUserSpecifiedText: phoneNumberText)?.toE164()
            else {
                owsFailDebug("Invalid phone number")
                return
            }

            databaseStorage.write { transaction in
                let address = SignalServiceAddress(phoneNumber: e164)
                let contactThread = TSContactThread.getOrCreateThread(withContactAddress: address, transaction: transaction)
                profileManager.addThread(toProfileWhitelist: contactThread, transaction: transaction)
                createFakeMessagesInBatches(messageQuantity, inThread: contactThread, messageContentType: .longText, transaction: transaction)
                Logger.info("Created a fake thread for \(e164) with \(messageQuantity) messages")
            }
        }
    }

    private static func createFakeMessagesInBatches(
        _ counter: UInt,
        inThread thread: TSThread,
        messageContentType: MessageContentType,
        transaction: SDSAnyWriteTransaction
    ) {
        let maxBatchSize: UInt = 200
        var remainder = counter
        while remainder > 0 {
            autoreleasepool {
                let batchSize = min(maxBatchSize, remainder)
                createFakeMessages(
                    batchSize,
                    batchOffset: counter - remainder,
                    inThread: thread,
                    messageContentType: messageContentType,
                    transaction: transaction
                )
                remainder -= batchSize
                Logger.info("createFakeMessages \(counter - remainder) / \(counter)")
            }
        }
    }

    private static func createFakeMessages(
        _ counter: UInt,
        batchOffset: UInt,
        inThread thread: TSThread,
        messageContentType: MessageContentType,
        transaction: SDSAnyWriteTransaction
    ) {
        Logger.info("createFakeMessages: \(counter)")

        guard let incomingSenderAci = anyIncomingSenderAddress(forThread: thread)?.aci else {
            owsFailDebug("Missing incomingSenderAci.")
            return
        }

        for i in 0..<counter {
            let randomText: String
            if messageContentType == .shortText {
                randomText = DebugUIMessages.randomShortText() + " \(i + 1 + batchOffset)"
            } else {
                randomText = DebugUIMessages.randomText() + " (sequence: \(i + 1 + batchOffset)"
            }
            let isTextOnly = messageContentType != .normal

            let numberOfCases = isTextOnly ? 2 : 4
            switch Int.random(in: 0..<numberOfCases) {
            case 0:
                let incomingMessageBuilder = TSIncomingMessageBuilder(thread: thread, messageBody: randomText)
                incomingMessageBuilder.authorAci = AciObjC(incomingSenderAci)
                let message = incomingMessageBuilder.build()
                message.anyInsert(transaction: transaction)
                message.debugonly_markAsReadNow(transaction: transaction)

            case 1:
                createFakeOutgoingMessage(
                    thread: thread,
                    messageBody: randomText,
                    messageState: .sent,
                    transaction: transaction
                )

            case 2:
                let filesize: UInt32 = 64
                let pointer = TSAttachmentPointer(
                    serverId: 237391539706350548,
                    cdnKey: "",
                    cdnNumber: 0,
                    key: createRandomDataOfSize(filesize),
                    digest: nil,
                    byteCount: filesize,
                    contentType: "image/jpg",
                    sourceFilename: "test.jpg",
                    caption: nil,
                    albumMessageId: nil,
                    attachmentType: .default,
                    mediaSize: .zero,
                    blurHash: nil,
                    uploadTimestamp: 0,
                    videoDuration: nil
                )
                pointer.setAttachmentPointerStateDebug(.failed)
                pointer.anyInsert(transaction: transaction)

                let incomingMessageBuilder = TSIncomingMessageBuilder(thread: thread)
                incomingMessageBuilder.authorAci = AciObjC(incomingSenderAci)
                incomingMessageBuilder.attachmentIds = [ pointer.uniqueId ]

                let message = incomingMessageBuilder.build()
                message.anyInsert(transaction: transaction)
                message.debugonly_markAsReadNow(transaction: transaction)

            case 3:
                let conversationFactory = ConversationFactory()
                // We want to produce a variety of album sizes, but favoring smaller albums
                conversationFactory.attachmentCount = Int.random(in: 0...SignalAttachment.maxAttachmentsAllowed)
                conversationFactory.threadCreator = { _ in return thread }
                conversationFactory.createSentMessage(transaction: transaction)
            default:
                break
            }
        }
    }

    private static func injectFakeIncomingMessages(_ counter: UInt, inThread thread: TSThread) {
        // Wait 5 seconds so debug user has time to navigate to another
        // view before message processing occurs.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            for i in 0..<counter {
                injectIncomingMessageInThread(thread, counter: counter - i)
            }
        }
    }

    private static func injectIncomingMessageInThread(_ thread: TSThread, counter: UInt) {
        Logger.info("injectIncomingMessageInThread: \(counter)")

        var randomText = randomText()
        randomText = randomText.appending(randomText).appending("\n")
        randomText = randomText.appending(randomText).appending("\n")
        randomText = randomText.appending(randomText).appending("\n")
        randomText = randomText.appending(randomText).appending("\n")
        randomText = randomText.appending(randomText).appending("\n")
        let text = "\(counter) " + randomText

        let dataMessageBuilder = SSKProtoDataMessage.builder()
        dataMessageBuilder.setBody(text)

        if let groupThread = thread as? TSGroupThread, groupThread.isGroupV2Thread {
            let groupModel = groupThread.groupModel as! TSGroupModelV2

            let groupContext = try! groupsV2.buildGroupContextV2Proto(groupModel: groupModel, changeActionsProtoData: nil)
            dataMessageBuilder.setGroupV2(groupContext)
        }

        let payloadBuilder = SSKProtoContent.builder()
        if let dataMessage = dataMessageBuilder.buildIgnoringErrors() {
            payloadBuilder.setDataMessage(dataMessage)
        }
        let plaintextData = payloadBuilder.buildIgnoringErrors()!.serializedDataIgnoringErrors()!

        // Try to use an arbitrary member of the current thread that isn't
        // ourselves as the sender.
        // This might be an "empty" group with no other members.  If so, use a fake
        // sender id.
        let address = thread.recipientAddressesWithSneakyTransaction.first ?? SignalServiceAddress(phoneNumber: "+12345678901")

        let envelopeBuilder = SSKProtoEnvelope.builder(timestamp: NSDate.ows_millisecondTimeStamp())
        envelopeBuilder.setType(.ciphertext)
        envelopeBuilder.setSourceServiceID(address.aci!.serviceIdString)
        envelopeBuilder.setSourceDevice(1)
        envelopeBuilder.setContent(plaintextData)
        envelopeBuilder.setServerTimestamp(NSDate.ows_millisecondTimeStamp())

        let envelope = try! envelopeBuilder.build()
        processDecryptedEnvelope(envelope, plaintextData: plaintextData)
    }

    // MARK: -

    private static func deleteRandomMessages(_ count: UInt, inThread thread: TSThread, transaction: SDSAnyWriteTransaction) {
        Logger.info("deleteRandomMessages: \(count)")

        let interactionFinder = InteractionFinder(threadUniqueId: thread.uniqueId)
        let uniqueIds = try! interactionFinder.fetchUniqueIds(
            filter: .newest,
            excludingPlaceholders: !DebugFlags.showFailedDecryptionPlaceholders.get(),
            limit: 100_000,
            tx: transaction
        )
        let interactions = InteractionFinder.interactions(
            withInteractionIds: Set(uniqueIds.shuffled().prefix(Int(count))),
            transaction: transaction
        )
        for interaction in interactions {
            interaction.anyRemove(transaction: transaction)
        }
    }

    private static func deleteLastMessages(_ count: UInt, inThread thread: TSThread, transaction: SDSAnyWriteTransaction) {
        Logger.info("deleteLastMessages")

        var interactionIds = [String]()
        let interactionFinder = InteractionFinder(threadUniqueId: thread.uniqueId)
        do {
            try interactionFinder.enumerateInteractionIds(transaction: transaction) { interactionId, stop in
                interactionIds.append(interactionId)
                if interactionIds.count >= count {
                    stop.pointee = true
                }
            }
        } catch {
            owsFailDebug("Error: \(error)")
            return
        }

        for interactionId in interactionIds {
            guard let interaction = TSInteraction.anyFetch(uniqueId: interactionId, transaction: transaction) else {
                owsFailDebug("Couldn't load interaction.")
                continue
            }
            interaction.anyRemove(transaction: transaction)
        }
    }

    private static func deleteRandomRecentMessages(_ count: UInt, inThread thread: TSThread, transaction: SDSAnyWriteTransaction) {
        Logger.info("deleteRandomRecentMessages: \(count)")

        let recentMessageCount: Int = 10
        let interactionFinder = InteractionFinder(threadUniqueId: thread.uniqueId)
        var interactionIds = [String]()
        do {
            try interactionFinder.enumerateInteractionIds(transaction: transaction) { interactionId, stop in
                interactionIds.append(interactionId)
                if interactionIds.count >= recentMessageCount {
                    stop.pointee = true
                }
            }
        } catch {
            owsFailDebug("Error: \(error)")
            return
        }

        for _ in 0..<count {
            guard let randomIndex = interactionIds.indices.randomElement() else { break }

            let interactionId = interactionIds.remove(at: randomIndex)
            guard let interaction = TSInteraction.anyFetch(uniqueId: interactionId, transaction: transaction) else {
                owsFailDebug("Couldn't load interaction.")
                continue
            }
            interaction.anyRemove(transaction: transaction)
        }
    }

    private static func insertAndDeleteNewOutgoingMessages(_ count: UInt, inThread thread: TSThread, transaction: SDSAnyWriteTransaction) {
        Logger.info("insertAndDeleteNewOutgoingMessages: \(count)")

        let messages: [TSOutgoingMessage] = (1...count).map { _ in
            let text = randomText()
            let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            let expiresInSeconds = dmConfigurationStore.durationSeconds(for: thread, tx: transaction.asV2Read)
            let message = TSOutgoingMessage(in: thread, messageBody: text, attachmentId: nil, expiresInSeconds: expiresInSeconds)
            Logger.info("insertAndDeleteNewOutgoingMessages timestamp: \(message.timestamp)")
            return message
        }

        for message in messages {
            message.anyInsert(transaction: transaction)
        }

        for message in messages {
            message.anyRemove(transaction: transaction)
        }
    }

    private static func resurrectNewOutgoingMessages1(_ count: UInt, inThread thread: TSThread, transaction: SDSAnyWriteTransaction) {
        Logger.info("resurrectNewOutgoingMessages1.1: \(count)")

        let messages: [TSOutgoingMessage] = (1...count).map { _ in
            let text = randomText()
            let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            let expiresInSeconds = dmConfigurationStore.durationSeconds(for: thread, tx: transaction.asV2Read)
            let message = TSOutgoingMessage(in: thread, messageBody: text, attachmentId: nil, expiresInSeconds: expiresInSeconds)
            Logger.info("resurrectNewOutgoingMessages1 timestamp: \(message.timestamp)")
            return message
        }

        for message in messages {
            message.anyInsert(transaction: transaction)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            Logger.info("resurrectNewOutgoingMessages1.2: \(count)")
            databaseStorage.write { t in
                for message in messages {
                    message.anyRemove(transaction: t)
                }
                for message in messages {
                    message.anyInsert(transaction: t)
                }
            }
        }
    }

    private static func resurrectNewOutgoingMessages2(_ count: UInt, inThread thread: TSThread, transaction: SDSAnyWriteTransaction) {
        Logger.info("resurrectNewOutgoingMessages2.1: \(count)")

        let messages: [TSOutgoingMessage] = (1...count).map { _ in
            let text = randomText()
            let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            let expiresInSeconds = dmConfigurationStore.durationSeconds(for: thread, tx: transaction.asV2Read)
            let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: text)
            messageBuilder.expiresInSeconds = expiresInSeconds
            let message = messageBuilder.build(transaction: transaction)
            Logger.info("resurrectNewOutgoingMessages2 timestamp: \(message.timestamp)")
            return message
        }

        for message in messages {
            message.update(withFakeMessageState: .sending, transaction: transaction)
            message.anyInsert(transaction: transaction)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            Logger.info("resurrectNewOutgoingMessages2.2: \(count)")
            databaseStorage.write { t in
                for message in messages {
                    message.anyRemove(transaction: t)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                Logger.info("resurrectNewOutgoingMessages2.3: \(count)")
                databaseStorage.write { t in
                    for message in messages {
                        message.anyInsert(transaction: t)
                    }
                }
            }
        }
    }

    // MARK: Disappearing Messages

    private static func createDisappearingMessagesWhichFailedToStartInThread(_ thread: TSThread) {
        guard let aci = thread.recipientAddressesWithSneakyTransaction.first?.aci else {
            owsFailDebug("No recipient")
            return
        }

        let now = Date.ows_millisecondTimestamp()
        let messageBody = "Should disappear 60s after \(now)"
        let incomingMessageBuilder = TSIncomingMessageBuilder.incomingMessageBuilder(thread: thread, messageBody: messageBody)
        incomingMessageBuilder.authorAci = AciObjC(aci)
        incomingMessageBuilder.expiresInSeconds = 60
        let message = incomingMessageBuilder.build()
        // private setter to avoid starting expire machinery.
        message.wasRead = true
        databaseStorage.write { transaction in
            message.anyInsert(transaction: transaction)
        }
    }

    // MARK: Groups

    private static func sendMessages(_ count: UInt, toAllMembersOfGroup groupThread: TSGroupThread) {
        for address in groupThread.groupModel.groupMembers {
            let contactThread = TSContactThread.getOrCreateThread(contactAddress: address)
            let sendMessagesAction = sendTextMessagesActionInThread(contactThread)
            sendMessagesAction.prepareAndPerformNTimes(count)
        }
    }

    private static func createNewGroups(count: UInt, recipientAddress: SignalServiceAddress) {
        guard count > 0 else { return }

        let completion: (TSGroupThread) -> Void = { groupThread in
            databaseStorage.write { transaction in
                ThreadUtil.enqueueMessage(
                    body: MessageBody(text: "\(count)", ranges: .empty),
                    thread: groupThread,
                    transaction: transaction
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    createNewGroups(count: count - 1, recipientAddress: recipientAddress)
                }
            }
        }

        let groupName = randomShortText()
        createRandomGroupWithName(groupName, member: recipientAddress, completion: completion)
    }

    private static func createRandomGroupWithName(
        _ groupName: String,
        member: SignalServiceAddress,
        completion: @escaping (TSGroupThread) -> Void
    ) {
        let members = [ member, TSAccountManager.localAddress! ]
        GroupManager.localCreateNewGroup(
            members: members,
            disappearingMessageToken: .disabledToken,
            shouldSendMessage: true
        ).done { groupThread in
            completion(groupThread)
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }

    // MARK: International

    private static func testLinkificationInThread(_ thread: TSThread) {
        let strings = [
            "google.com",
            "foo.google.com",
            "https://foo.google.com",
            "https://foo.google.com/some/path.html",
            "http://кц.com",
            "кц.com",
            "http://asĸ.com",
            "кц.рф",
            "кц.рф/some/path",
            "https://кц.рф/some/path",
            "http://foo.кц.рф"
        ]

        databaseStorage.write { transaction in
            for string in strings {
                // DO NOT log these strings with the debugger attached.
                //        OWSLogInfo(@"%@", string);

                createFakeIncomingMessage(
                    thread: thread,
                    messageBody: string,
                    fakeAssetLoader: nil,
                    transaction: transaction
                )

                let member = SignalServiceAddress(phoneNumber: "+1323555555")
                createRandomGroupWithName(string, member: member, completion: { _ in })
            }
        }
    }

    private static func testIndicScriptsInThread(_ thread: TSThread) {
        let strings = [
            "\u{0C1C}\u{0C4D}\u{0C1E}\u{200C}\u{0C3E}",
            "\u{09B8}\u{09CD}\u{09B0}\u{200C}\u{09C1}",
            "non-crashing string"
        ]

        databaseStorage.write { transaction in
            for string in strings {
                // DO NOT log these strings with the debugger attached.
                //        OWSLogInfo(@"%@", string);

                createFakeIncomingMessage(
                    thread: thread,
                    messageBody: string,
                    fakeAssetLoader: nil,
                    transaction: transaction
                )

                let member = SignalServiceAddress(phoneNumber: "+1323555555")
                createRandomGroupWithName(string, member: member, completion: { _ in })
            }
        }
    }

    private static func testZalgoTextInThread(_ thread: TSThread) {
        let strings = [
            "Ṱ̴̤̺̣͚͚̭̰̤̮̑̓̀͂͘͡h̵̢̤͔̼̗̦̖̬͌̀͒̀͘i̴̮̤͎͎̝̖̻͓̅̆͆̓̎͘͡ͅŝ̡̡̳͔̓͗̾̀̇͒͘͢͢͡͡ ỉ̛̲̩̫̝͉̀̒͐͋̾͘͢͡͞s̶̨̫̞̜̹͛́̇͑̅̒̊̈ s̵͍̲̗̠̗͈̦̬̉̿͂̏̐͆̾͐͊̾ǫ̶͍̼̝̉͊̉͢͜͞͝ͅͅṁ̵̡̨̬̤̝͔̣̄̍̋͊̿̄͋̈ͅe̪̪̻̱͖͚͈̲̍̃͘͠͝ z̷̢̢̛̩̦̱̺̼͑́̉̾ą͕͎̠̮̹̱̓̔̓̈̈́̅̐͢l̵̨͚̜͉̟̜͉͎̃͆͆͒͑̍̈̚͜͞ğ͔̖̫̞͎͍̒̂́̒̿̽̆͟o̶̢̬͚̘̤̪͇̻̒̋̇̊̏͢͡͡͠ͅ t̡̛̥̦̪̮̅̓̑̈́̉̓̽͛͢͡ȩ̡̩͓͈̩͎͗̔͑̌̓͊͆͝x̫̦͓̤͓̘̝̪͊̆͌͊̽̃̏͒͘͘͢ẗ̶̢̨̛̰̯͕͔́̐͗͌͟͠.̷̩̼̼̩̞̘̪́͗̅͊̎̾̅̏̀̕͟ͅ",
            "This is some normal text"
        ]

        databaseStorage.write { transaction in
            for string in strings {
                Logger.info("sending zalgo")

                createFakeIncomingMessage(
                    thread: thread,
                    messageBody: string,
                    fakeAssetLoader: nil,
                    transaction: transaction
                )

                let member = SignalServiceAddress(phoneNumber: "+1323555555")
                createRandomGroupWithName(string, member: member, completion: { _ in })
            }
        }
    }

    private static func testDirectionalFilenamesInThread(_ thread: TSThread) {
        var filenames = [
            "a_test\u{202D}abc.exe",
            "b_test\u{202E}abc.exe",
            "c_testabc.exe"
        ]
        var sendUnsafeFile: (() -> Void)?
        sendUnsafeFile = {
            guard let filename = filenames.popLast() else { return }

            let utiType = kUTTypeData as String
            let dataLength: UInt32 = 32
            guard let dataSource = DataSourceValue.dataSource(with: createRandomDataOfSize(dataLength), utiType: utiType) else { return }

            dataSource.sourceFilename = filename
            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: utiType)

            guard attachment.hasError else {
                Logger.error("attachment[\(String(describing: attachment.sourceFilename))]: \(String(describing: attachment.errorName))")
                return
            }

            sendAttachment(attachment, thread: thread, messageText: nil)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                sendUnsafeFile?()
                sendUnsafeFile = nil
            }
        }
    }

    // MARK: Random Actions

    private static func performRandomActions(_ counter: UInt, inThread thread: TSThread) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            performRandomActionInThread(thread, counter: counter)
            if counter > 0 {
                performRandomActions(counter - 1, inThread: thread)
            }
        }
    }

    private static func performRandomActionInThread(_ thread: TSThread, counter: UInt) {
        let actions: [(SDSAnyWriteTransaction) -> Void] = [ { transaction in
                // injectIncomingMessageInThread doesn't take a transaction.
                DispatchQueue.main.async {
                    injectIncomingMessageInThread(thread, counter: counter)
                }
            }, { _ in
                // sendTextMessageInThread doesn't take a transaction.
                DispatchQueue.main.async {
                    sendTextMessageInThread(thread, counter: counter)
                }
            }, { transaction in
                let messageCount = UInt.random(in: 1...4)
                createFakeMessages(messageCount, batchOffset: 0, inThread: thread, messageContentType: .normal, transaction: transaction)
            }, { transaction in
                let messageCount = UInt.random(in: 1...4)
                deleteRandomMessages(messageCount, inThread: thread, transaction: transaction)
            }, { transaction in
                let messageCount = UInt.random(in: 1...4)
                deleteLastMessages(messageCount, inThread: thread, transaction: transaction)
            }, { transaction in
                let messageCount = UInt.random(in: 1...4)
                deleteRandomRecentMessages(messageCount, inThread: thread, transaction: transaction)
            }, { transaction in
                let messageCount = UInt.random(in: 1...4)
                insertAndDeleteNewOutgoingMessages(messageCount, inThread: thread, transaction: transaction)
            }, { transaction in
                let messageCount = UInt.random(in: 1...4)
                resurrectNewOutgoingMessages1(messageCount, inThread: thread, transaction: transaction)
            }, { transaction in
                let messageCount = UInt.random(in: 1...4)
                resurrectNewOutgoingMessages2(messageCount, inThread: thread, transaction: transaction)
            }
        ]

        databaseStorage.write { transaction in
            for _ in 1...Int.random(in: 1...4) {
                if let action = actions.randomElement() {
                    action(transaction)
                }
            }
        }
    }

    // MARK: Utility

    @discardableResult
    private static func createFakeOutgoingMessage(
        thread: TSThread,
        messageBody: String?,
        attachment: TSAttachment? = nil,
        filename: String? = nil,
        messageState: TSOutgoingMessageState,
        isDelivered: Bool = false,
        isRead: Bool = false,
        isVoiceMessage: Bool = false,
        quotedMessage: TSQuotedMessage? = nil,
        contactShare: OWSContact? = nil,
        linkPreview: OWSLinkPreview? = nil,
        messageSticker: MessageSticker? = nil,
        transaction: SDSAnyWriteTransaction
    ) -> TSOutgoingMessage {

        owsAssertDebug(!messageBody.isEmptyOrNil || attachment != nil || contactShare != nil)

        let attachmentIds: [String]
        if let attachmentId = attachment?.uniqueId {
            attachmentIds = [attachmentId]
        } else {
            attachmentIds = []
        }

        let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: messageBody)
        messageBuilder.attachmentIds = attachmentIds
        messageBuilder.isVoiceMessage = isVoiceMessage
        messageBuilder.quotedMessage = quotedMessage
        messageBuilder.contactShare = contactShare
        messageBuilder.linkPreview = linkPreview
        messageBuilder.messageSticker = messageSticker

        let message = messageBuilder.build(transaction: transaction)
        message.anyInsert(transaction: transaction)
        message.update(withFakeMessageState: messageState, transaction: transaction)

        if let attachment {
            updateAttachment(attachment, albumMessage: message, transaction: transaction)
        }

        if isDelivered {
            if let address = thread.recipientAddresses(with: transaction).last {
                owsAssertDebug(address.isValid)
                message.update(
                    withDeliveredRecipient: address,
                    recipientDeviceId: 0,
                    deliveryTimestamp: Date.ows_millisecondTimestamp(),
                    context: PassthroughDeliveryReceiptContext(),
                    transaction: transaction
                )
            }
        }

        if isRead {
            if let address = thread.recipientAddresses(with: transaction).last {
                owsAssertDebug(address.isValid)
                message.update(
                    withReadRecipient: address,
                    recipientDeviceId: 0,
                    readTimestamp: Date.ows_millisecondTimestamp(),
                    transaction: transaction
                )
            }
        }

        return message
    }

    @discardableResult
    private static func createFakeOutgoingMessage(
        thread: TSThread,
        messageBody messageBodyParam: String?,
        fakeAssetLoader fakeAssetLoaderParam: DebugUIMessagesAssetLoader?,
        messageState: TSOutgoingMessageState,
        isDelivered: Bool = false,
        isRead: Bool = false,
        quotedMessage: TSQuotedMessage? = nil,
        contactShare: OWSContact? = nil,
        linkPreview: OWSLinkPreview? = nil,
        messageSticker: MessageSticker? = nil,
        transaction: SDSAnyWriteTransaction
    ) -> TSOutgoingMessage {

        // Seamlessly convert oversize text messages to oversize text attachments.
        let messageBody: String?
        let fakeAssetLoader: DebugUIMessagesAssetLoader?
        if let messageBodyParam, messageBodyParam.lengthOfBytes(using: .utf8) >= kOversizeTextMessageSizeThreshold {
            owsAssertDebug(fakeAssetLoaderParam == nil)
            messageBody = nil
            fakeAssetLoader = DebugUIMessagesAssetLoader.oversizeTextInstance(text: messageBodyParam)
        } else {
            messageBody = messageBodyParam
            fakeAssetLoader = fakeAssetLoaderParam
        }

        let attachment: TSAttachment?
        if let fakeAssetLoader {
            attachment = createFakeAttachment(
                fakeAssetLoader: fakeAssetLoader,
                isAttachmentDownloaded: true,
                transaction: transaction
            )
            owsAssertDebug(attachment != nil)
        } else {
            attachment = nil
        }

        return createFakeOutgoingMessage(
            thread: thread,
            messageBody: messageBody,
            attachment: attachment,
            filename: fakeAssetLoader?.filename,
            messageState: messageState,
            isDelivered: isDelivered,
            isRead: isRead,
            isVoiceMessage: attachment?.isVoiceMessage ?? false,
            quotedMessage: quotedMessage,
            contactShare: contactShare,
            linkPreview: linkPreview,
            messageSticker: messageSticker,
            transaction: transaction
        )
    }

    private static func createFakeAttachment(
        fakeAssetLoader: DebugUIMessagesAssetLoader,
        isAttachmentDownloaded: Bool,
        transaction: SDSAnyWriteTransaction
    ) -> TSAttachment? {

        owsAssertDebug(!fakeAssetLoader.filePath.isEmptyOrNil)

        if isAttachmentDownloaded {
            let dataSource: DataSource
            do {
                dataSource = try DataSourcePath.dataSource(withFilePath: fakeAssetLoader.filePath!, shouldDeleteOnDeallocation: false)
            } catch {
                owsFailDebug("Failed to create dataSource: \(error)")
                return nil
            }

            guard let filename = dataSource.sourceFilename else {
                owsFailDebug("Empty filename: \(dataSource)")
                return nil
            }
            // To support "fake missing" attachments, we sometimes lie about the length of the data.
            let nominalDataLength: UInt32 = UInt32(max(1, dataSource.dataLength))
            let attachmentStream = TSAttachmentStream(
                contentType: fakeAssetLoader.mimeType,
                byteCount: nominalDataLength,
                sourceFilename: filename,
                caption: nil,
                albumMessageId: nil
            )
            do {
                try attachmentStream.write(dataSource.data)
                attachmentStream.anyInsert(transaction: transaction)
            } catch {
                owsFailDebug("Failed to write data: \(error)")
                return nil
            }

            return attachmentStream
        } else {
            let filesize: UInt32 = 64
            let attachmentPointer = TSAttachmentPointer(
                serverId: 237391539706350548,
                cdnKey: "",
                cdnNumber: 0,
                key: createRandomDataOfSize(filesize),
                digest: nil,
                byteCount: filesize,
                contentType: fakeAssetLoader.mimeType,
                sourceFilename: fakeAssetLoader.filename,
                caption: nil,
                albumMessageId: nil,
                attachmentType: .default,
                mediaSize: .zero,
                blurHash: nil,
                uploadTimestamp: 0,
                videoDuration: nil
            )
            attachmentPointer.setAttachmentPointerStateDebug(.failed)
            attachmentPointer.anyInsert(transaction: transaction)
            return attachmentPointer
        }
    }

    private static func updateAttachment(
        _ attachment: TSAttachment,
        albumMessage: TSMessage,
        transaction: SDSAnyWriteTransaction
    ) {
        attachment.anyUpdate(transaction: transaction) { latest in
            // There's no public setter for albumMessageId, since it's usually set in the
            // initializer. This isn't convenient for the DEBUG UI, so we abuse the
            // migrateAlbumMessageId method.
            latest.migrateAlbumMessageId(albumMessage.uniqueId)
        }
        if let attachmentStream = attachment as? TSAttachmentStream {
            MediaGalleryManager.didInsert(attachmentStream: attachmentStream, transaction: transaction)
        }
    }

    private static func actionLabelForHasCaption(
        _ hasCaption: Bool,
        outgoingMessageState: TSOutgoingMessageState,
        isDelivered: Bool = false,
        isRead: Bool = false
    ) -> String {
        var label = ""
        if hasCaption {
            label += " 🔤"
        }
        switch outgoingMessageState {
        case .failed:
            label += " (Unsent)"
        case .sending:
            label += " (Sending)"
        case .sent:
            if isRead {
                label += " (Read)"
            } else if isDelivered {
                label += " (Delivered)"
            } else {
                label += " (Sent)"
            }
        default:
            owsFailDebug("unknown message state.")
        }

        return label
    }

    @discardableResult
    private static func createFakeIncomingMessage(
        thread: TSThread,
        messageBody: String?,
        attachment: TSAttachment?,
        filename: String? = nil,
        isAttachmentDownloaded: Bool = false,
        quotedMessage: TSQuotedMessage? = nil,
        transaction: SDSAnyWriteTransaction
    ) -> TSIncomingMessage {

        owsAssertDebug(!messageBody.isEmptyOrNil || attachment != nil)

        let attachmentIds: [String]
        if let attachmentId = attachment?.uniqueId {
            attachmentIds = [attachmentId]
        } else {
            attachmentIds = []
        }

        let authorAci = DebugUIMessages.anyIncomingSenderAddress(forThread: thread)!.aci!

        let incomingMessageBuilder = TSIncomingMessageBuilder(thread: thread, messageBody: messageBody)
        incomingMessageBuilder.authorAci = AciObjC(authorAci)
        incomingMessageBuilder.attachmentIds = attachmentIds
        incomingMessageBuilder.quotedMessage = quotedMessage
        let message = incomingMessageBuilder.build()
        message.anyInsert(transaction: transaction)
        message.debugonly_markAsReadNow(transaction: transaction)

        if let attachment {
            updateAttachment(attachment, albumMessage: message, transaction: transaction)
        }

        return message
    }

    @discardableResult
    private static func createFakeIncomingMessage(
        thread: TSThread,
        messageBody messageBodyParam: String?,
        fakeAssetLoader fakeAssetLoaderParam: DebugUIMessagesAssetLoader?,
        isAttachmentDownloaded: Bool = false,
        quotedMessage: TSQuotedMessage? = nil,
        transaction: SDSAnyWriteTransaction
    ) -> TSIncomingMessage {

        // Seamlessly convert oversize text messages to oversize text attachments.
        let messageBody: String?
        let fakeAssetLoader: DebugUIMessagesAssetLoader?
        if let messageBodyParam, messageBodyParam.lengthOfBytes(using: .utf8) >= kOversizeTextMessageSizeThreshold {
            owsAssertDebug(fakeAssetLoaderParam == nil)
            messageBody = nil
            fakeAssetLoader = DebugUIMessagesAssetLoader.oversizeTextInstance(text: messageBodyParam)
        } else {
            messageBody = messageBodyParam
            fakeAssetLoader = fakeAssetLoaderParam
        }

        let attachment: TSAttachment?
        if let fakeAssetLoader {
            attachment = createFakeAttachment(
                fakeAssetLoader: fakeAssetLoader,
                isAttachmentDownloaded: isAttachmentDownloaded,
                transaction: transaction
            )
        } else {
            attachment = nil
        }

        return createFakeIncomingMessage(
            thread: thread,
            messageBody: messageBody,
            attachment: attachment,
            filename: fakeAssetLoader?.filename,
            isAttachmentDownloaded: isAttachmentDownloaded,
            quotedMessage: quotedMessage,
            transaction: transaction
        )
    }

    private static func createFakeThreadAssociatedData(thread: TSThread) -> ThreadAssociatedData {
        return ThreadAssociatedData(
            threadUniqueId: thread.uniqueId,
            isArchived: false,
            isMarkedUnread: false,
            mutedUntilTimestamp: 0,
            audioPlaybackRate: 1
        )
    }

    private static func anyIncomingSenderAddress(forThread thread: TSThread) -> SignalServiceAddress? {
        if let contactThread = thread as? TSContactThread {
            return contactThread.contactAddress
        } else if let groupThread = thread as? TSGroupThread {
            guard let localAddress = Self.tsAccountManager.localAddress else {
                owsFailDebug("Missing localAddress.")
                return nil
            }
            let members = groupThread.groupMembership.fullMembers
            let otherMembers = members.filter { $0 != localAddress }.shuffled()
            guard let anyOtherMember = otherMembers.first else {
                owsFailDebug("No other members.")
                return nil
            }
            return anyOtherMember
        } else {
            owsFailDebug("Invalid thread.")
            return nil
        }
    }

    private static func processDecryptedEnvelope(_ envelope: SSKProtoEnvelope, plaintextData: Data) {
        databaseStorage.write { tx in
            messageManager.processEnvelope(
                envelope,
                plaintextData: plaintextData,
                wasReceivedByUD: false,
                serverDeliveryTimestamp: 0,
                shouldDiscardVisibleMessages: false,
                localIdentifiers: tsAccountManager.localIdentifiers(transaction: tx)!,
                tx: tx
            )
        }
    }
}

// MARK: - Random

extension DebugUIMessages {

    private static func randomText() -> String {
        let randomTexts = [
            "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ",

            "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " +
            "Suspendisse rutrum, nulla vitae pretium hendrerit, tellus " +
            "turpis pharetra libero, vitae sodales tortor ante vel sem.",

            "In a time of universal deceit - telling the truth is a revolutionary act.",
            "If you want a vision of the future, imagine a boot stamping on a human face - forever.",
            "Who controls the past controls the future. Who controls the present controls the past.",
            "All animals are equal, but some animals are more equal than others.",
            "War is peace. Freedom is slavery. Ignorance is strength.",
            "All the war-propaganda, all the screaming and lies and hatred, comes invariably from people who are not fighting.",

            "Political language. . . is designed to make lies sound truthful and murder respectable, and to give an " +
            "appearance of solidity to pure wind.",

            "The nationalist not only does not disapprove of atrocities committed by his own side, but he has a " +
            "remarkable capacity for not even hearing about them.",

            "Every generation imagines itself to be more intelligent than the one that went before it, and wiser than the " +
            "one that comes after it.",

            "War against a foreign country only happens when the moneyed classes think they are going to profit from it.",
            "People have only as much liberty as they have the intelligence to want and the courage to take.",

            "You cannot buy the revolution. You cannot make the revolution. You can only be the revolution. It is in " +
            "your spirit, or it is nowhere.",

            "That is what I have always understood to be the essence of anarchism: the conviction that the burden of " +
            "proof has to be placed on authority, and that it should be dismantled if that burden cannot be met.",

            "Ask for work. If they don't give you work, ask for bread. If they do not give you work or bread, then take bread.",
            "Every society has the criminals it deserves.",

            "Anarchism is founded on the observation that since few men are wise enough to rule themselves, even fewer " +
            "are wise enough to rule others.",

            "If you would know who controls you see who you may not criticise.",
            "At one time in the world there were woods that no one owned."
        ]
        return randomTexts.randomElement()!
    }

    private static func randomOversizeText() -> String {
        var message = String()
        while message.lengthOfBytes(using: .utf8) < kOversizeTextMessageSizeThreshold {
            message += """
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse rutrum, nulla
vitae pretium hendrerit, tellus turpis pharetra libero, vitae sodales tortor ante vel
sem. Fusce sed nisl a lorem gravida tincidunt. Suspendisse efficitur non quam ac
sodales. Aenean ut velit maximus, posuere sem a, accumsan nunc. Donec ullamcorper
turpis lorem. Quisque dignissim purus eu placerat ultricies. Proin at urna eget mi
semper congue. Aenean non elementum ex. Praesent pharetra quam at sem vestibulum,
vestibulum ornare dolor elementum. Vestibulum massa tortor, scelerisque sit amet
pulvinar a, rhoncus vitae nisl. Sed mi nunc, tempus at varius in, malesuada vitae
dui. Vivamus efficitur pulvinar erat vitae congue. Proin vehicula turpis non felis
congue facilisis. Nullam aliquet dapibus ligula ac mollis. Etiam sit amet posuere
lorem, in rhoncus nisi.


"""
        }
        return message
    }

    private static func randomShortText() -> String {
        let alphabet: [Character] = (97...122).map { (ascii: Int) in
            Character(Unicode.Scalar(ascii)!)
        }

        let chars: [Character] = (0..<4).map { _ in
            let index = UInt.random(in: 0..<UInt(alphabet.count))
            return alphabet[Int(index)]
        }

        return String(chars)
    }

    private static func randomCaptionText() -> String {
        return randomText() + " (caption)"
    }

    private static func createRandomDataOfSize(_ size: UInt32) -> Data {
        owsAssertDebug(size % 4 == 0)
        owsAssertDebug(size < Int.max)
        return Randomness.generateRandomBytes(Int32(size))
    }
}

#endif
