//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreServices
import LibSignalClient
import SignalServiceKit
import SignalUI
import UniformTypeIdentifiers

#if USE_DEBUG_UI

class DebugUIMessages: DebugUIPage {

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
                    SSKEnvironment.shared.databaseStorageRef.write { transaction in
                        DependenciesBridge.shared.threadSoftDeleteManager
                            .removeAllInteractions(thread: thread, sendDeleteForMeSyncMessage: false, tx: transaction.asV2Write)
                    }
                })
            ]

            items += DebugUIMessages.itemsForActions([
                DebugUIMessages.fakeAllContactShareAction(thread: thread),
                DebugUIMessages.sendMessageVariationsAction(thread: thread),
                // Send Media
                DebugUIMessages.sendAllMediaAction(thread: thread),
                DebugUIMessages.sendRandomMediaAction(thread: thread),
                // Fake Text
                DebugUIMessages.fakeAllTextAction(thread: thread),
                DebugUIMessages.fakeRandomTextAction(thread: thread),
                // Sequences
                DebugUIMessages.allFakeSequencesAction(thread: thread),
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
                            Task {
                                await DebugUIMessages.createFakeThreads(threadQuantity, withFakeMessages: messageQuantity)
                            }
                        }
                    }
                }),
                OWSTableItem(title: "Send text/x-signal-plain", actionBlock: {
                    DebugUIMessages.sendOversizeTextMessageInThread(thread)
                }),
                OWSTableItem(title: "Send unknown mimetype", actionBlock: {
                    DebugUIMessages.sendRandomAttachmentInThread(thread, uti: MimeTypeUtil.unknownTestAttachmentUti)
                }),
                OWSTableItem(title: "Send pdf", actionBlock: {
                    DebugUIMessages.sendRandomAttachmentInThread(thread, uti: UTType.pdf.identifier)
                }),
                OWSTableItem(title: "Create messages with variety of timestamps", actionBlock: {
                  DebugUIMessages.createTimestampMessagesInThread(thread)
                }),
                OWSTableItem(title: "Send text messages", actionBlock: {
                    DebugUIMessages.askForQuantityWithTitle("How many messages?") { quantity in
                        DebugUIMessages.sendTextMessages(quantity, thread: thread)
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
        [ 1, 10, 25, 100 ].forEach { count in
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

    // MARK: Exemplary

    private static func allFakeActionsAction(thread: TSThread) -> DebugUIMessagesAction {
        return DebugUIMessagesGroupAction.allGroupActionWithLabel(
            "All Fake",
            subactions: allFakeActions(thread: thread, includeLabels: true)
        )
    }

    private static func allFakeActions(thread: TSThread, includeLabels: Bool) -> [DebugUIMessagesAction] {
        var actions = [DebugUIMessagesAction]()
        actions.append(contentsOf: allFakeTextActions(thread: thread, includeLabels: includeLabels))
        actions.append(contentsOf: allFakeSequenceActions(thread: thread, includeLabels: includeLabels))
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

    private typealias CreateContactBlock = (TSMessage, SDSAnyWriteTransaction) -> Void

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
            contact: { message, tx in
                let contact = OWSContact(name: OWSContactName(givenName: "Alice"))
                contact.phoneNumbers = [ OWSContactPhoneNumber(type: .home, phoneNumber: "+13213214321") ]
                message.update(withContactShare: contact, transaction: tx)
            }
        ))

        actions.append(fakeContactShareMessageAction(
            thread: thread,
            label: "Name & Email",
            contact: { message, tx in
                let contact = OWSContact(name: OWSContactName(givenName: "Bob"))
                contact.emails = [ OWSContactEmail(type: .home, email: "a@b.com") ]
                message.update(withContactShare: contact, transaction: tx)
            }
        ))

        actions.append(fakeContactShareMessageAction(
            thread: thread,
            label: "Long values",
            contact: { message, tx in
                let contact = OWSContact(name: OWSContactName(
                    givenName: "Bobasdjasdlkjasldkjas",
                    familyName: "Bobasdjasdlkjasldkjas"
                ))
                contact.emails = [ OWSContactEmail(type: .mobile, email: "asdlakjsaldkjasldkjasdlkjasdlkjasdlkajsa@b.com") ]
                message.update(withContactShare: contact, transaction: tx)
            }
        ))

        actions.append(fakeContactShareMessageAction(
            thread: thread,
            label: "System Contact w/o Signal",
            contact: { message, tx in
                let contact = OWSContact(name: OWSContactName(givenName: "Add Me To Your Contacts"))
                contact.phoneNumbers = [ OWSContactPhoneNumber(type: .work, phoneNumber: "+32460205391") ]
                message.update(withContactShare: contact, transaction: tx)
            }
        ))

        actions.append(fakeContactShareMessageAction(
            thread: thread,
            label: "System Contact w. Signal",
            contact: { message, tx in
                let contact = OWSContact(name: OWSContactName(givenName: "Add Me To Your Contacts"))
                contact.phoneNumbers = [ OWSContactPhoneNumber(type: .work, phoneNumber: "+32460205392") ]
                message.update(withContactShare: contact, transaction: tx)
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
                    contactShareBlock: contact,
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
        guard let utiType = MimeTypeUtil.utiTypeForFileExtension(fileUrl.pathExtension) else {
            completion(.failure(DebugUIError.unknownFileExtension))
            return
        }

        let filename = fileUrl.lastPathComponent

        let dataSource: DataSource
        do {
            dataSource = try DataSourcePath(filePath: fileUrl.path, shouldDeleteOnDeallocation: false)
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
            thread: thread
        )
    }

    private static func sendRandomAttachmentInThread(_ thread: TSThread, uti: String, length: UInt32 = 256) {
        guard let dataSource = DataSourceValue(createRandomDataOfSize(length), utiType: uti) else {
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
                let dataSource = try? DataSourcePath(filePath: tempFilePath, shouldDeleteOnDeallocation: false),
                let uti = MimeTypeUtil.utiTypeForMimeType(fakeAssetLoader.mimeType)
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

        ThreadUtil.enqueueMessage(
            body: messageBody,
            mediaAttachments: attachments,
            thread: thread
        )
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
        ThreadUtil.enqueueMessage(
            body: MessageBody(text: text, ranges: .empty),
            thread: thread
        )
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

    private static func sendTextMessages(_ counter: UInt, thread: TSThread) {
        guard counter > 0 else { return }

        sendTextMessageInThread(thread, counter: counter)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            sendTextMessages(counter - 1, thread: thread)
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

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            for timestamp in timestamps {
                let randomText = randomText()

                // Legit usage of SenderTimestamp to backdate incoming sent messages for Debug
                let incomingMessageBuilder: TSIncomingMessageBuilder = .withDefaultValues(
                    thread: thread,
                    timestamp: timestamp,
                    authorAci: incomingSenderAci,
                    messageBody: randomText
                )
                let incomingMessage = incomingMessageBuilder.build()
                incomingMessage.anyInsert(transaction: transaction)
                incomingMessage.debugonly_markAsReadNow(transaction: transaction)

                // MJK TODO - this might be the one place we actually use senderTimestamp
                let outgoingMessageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: randomText)
                outgoingMessageBuilder.timestamp = timestamp
                let outgoingMessage = outgoingMessageBuilder.build(transaction: transaction)
                outgoingMessage.anyInsert(transaction: transaction)
                outgoingMessage.updateWithFakeMessageState(.sent, tx: transaction)
                outgoingMessage.updateWithSentRecipient(incomingSenderAci, wasSentByUD: false, transaction: transaction)
                outgoingMessage.update(
                    withDeliveredRecipient: SignalServiceAddress(incomingSenderAci),
                    deviceId: 0,
                    deliveryTimestamp: timestamp,
                    context: PassthroughDeliveryReceiptContext(),
                    tx: transaction
                )
                outgoingMessage.update(
                    withReadRecipient: SignalServiceAddress(incomingSenderAci),
                    deviceId: 0,
                    readTimestamp: timestamp,
                    tx: transaction
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
                owsFail("Unknown thread type")
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

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            try! runner.initialize(senderClient: senderClient,
                                   recipientClient: localClient,
                                   transaction: transaction)
        }

        let envelopeBuilder = try! fakeService.envelopeBuilder(fromSenderClient: senderClient)
        envelopeBuilder.setSourceServiceID(senderClient.serviceId.serviceIdString)
        let envelopeData = try! envelopeBuilder.buildSerializedData()
        SSKEnvironment.shared.messageProcessorRef.processReceivedEnvelopeData(
            envelopeData,
            serverDeliveryTimestamp: 0,
            envelopeSource: .debugUI
        ) { _ in }
    }

    private static func createUUIDGroup() {
        let uuidMembers = (0...3).map { _ in CommonGenerator.address(hasPhoneNumber: false) }
        let members = uuidMembers + [DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction!.aciAddress]
        let groupName = "UUID Group"

        Task {
            _ = try? await GroupManager.localCreateNewGroup(
                members: members,
                name: groupName,
                disappearingMessageToken: .disabledToken,
                shouldSendMessage: true
            )
        }
    }

    // MARK: Fake Threads & Messages

    private static func createFakeThreads(_ threadQuantity: UInt, withFakeMessages messageQuantity: UInt) async {
        await DebugContactsUtils.createRandomContacts(threadQuantity) { contact, index, stop in
            guard
                let phoneNumberText = contact.phoneNumbers.first?.value.stringValue,
                let e164 = SSKEnvironment.shared.phoneNumberUtilRef.parsePhoneNumber(userSpecifiedText: phoneNumberText)?.e164
            else {
                owsFailDebug("Invalid phone number")
                return
            }

            let messageContents = try! createFakeMessageContents(
                count: messageQuantity,
                messageContentType: .longText
            )

            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
                let address = SignalServiceAddress(phoneNumber: e164)
                let contactThread = TSContactThread.getOrCreateThread(withContactAddress: address, transaction: transaction)
                SSKEnvironment.shared.profileManagerRef.addThread(
                    toProfileWhitelist: contactThread,
                    userProfileWriter: .localUser,
                    transaction: transaction
                )
                createFakeMessages(messageContents, inThread: contactThread, transaction: transaction)
                Logger.info("Created a fake thread for \(e164) with \(messageQuantity) messages")
            }
        }
    }

    private enum FakeMessageContent {
        case incomingTextOnly(String)
        case outgoingTextOnly(String)
        case outgoingAttachments([AttachmentDataSource])
        case incomingAttachments([AttachmentDataSource])
    }

    private static func createFakeMessageContents(
        count: UInt,
        messageContentType: MessageContentType
    ) throws -> [FakeMessageContent] {
        var contents = [FakeMessageContent]()
        for i in 0..<count {
            let randomText: String
            if messageContentType == .shortText {
                randomText = DebugUIMessages.randomShortText() + " \(i + 1)"
            } else {
                randomText = DebugUIMessages.randomText() + " (sequence: \(i + 1)"
            }
            let isTextOnly = messageContentType != .normal

            let numberOfCases = isTextOnly ? 2 : 4
            switch Int.random(in: 0..<numberOfCases) {
            case 0:
                contents.append(.incomingTextOnly(randomText))
            case 1:
                contents.append(.outgoingTextOnly(randomText))
            case 2:
                let attachmentDataSource = try DependenciesBridge.shared.attachmentContentValidator.validateContents(
                    data: UIImage.image(color: .blue, size: .square(100)).jpegData(compressionQuality: 0.1)!,
                    mimeType: "image/jpg",
                    renderingFlag: .default,
                    sourceFilename: "test.jpg"
                )
                contents.append(.incomingAttachments([.from(pendingAttachment: attachmentDataSource)]))
            case 3:
                let attachmentCount = Int.random(in: 0...SignalAttachment.maxAttachmentsAllowed)
                var attachmentDataSources = [AttachmentDataSource]()
                for _ in (0..<attachmentCount) {
                    let dataSource = try DependenciesBridge.shared.attachmentContentValidator.validateContents(
                        dataSource: DataSourceValue(
                            ImageFactory().buildPNGData(),
                            fileExtension: "png"
                        ),
                        shouldConsume: true,
                        mimeType: "image/png",
                        renderingFlag: .default,
                        sourceFilename: "test.png"
                    )
                    attachmentDataSources.append(.from(pendingAttachment: dataSource))
                }
                contents.append(.outgoingAttachments(attachmentDataSources))
            default:
                break
            }
        }
        return contents
    }

    private static func createFakeMessages(
        _ contents: [FakeMessageContent],
        inThread thread: TSThread,
        transaction: SDSAnyWriteTransaction
    ) {
        guard let incomingSenderAci = anyIncomingSenderAddress(forThread: thread)?.aci else {
            owsFailDebug("Missing incomingSenderAci.")
            return
        }

        for content in contents {
            switch content {
            case .incomingTextOnly(let text):
                let incomingMessageBuilder: TSIncomingMessageBuilder = .withDefaultValues(
                    thread: thread,
                    authorAci: incomingSenderAci,
                    messageBody: text
                )
                let message = incomingMessageBuilder.build()
                message.anyInsert(transaction: transaction)
                message.debugonly_markAsReadNow(transaction: transaction)

            case .outgoingTextOnly(let text):
                createFakeOutgoingMessage(
                    thread: thread,
                    messageBody: text,
                    messageState: .sent,
                    transaction: transaction
                )

            case .incomingAttachments(let dataSources):
                let incomingMessageBuilder: TSIncomingMessageBuilder = .withDefaultValues(
                    thread: thread,
                    authorAci: incomingSenderAci
                )

                let message = incomingMessageBuilder.build()
                message.anyInsert(transaction: transaction)
                message.debugonly_markAsReadNow(transaction: transaction)

                try? DependenciesBridge.shared.attachmentManager.createAttachmentStreams(
                    consuming: dataSources.map { dataSource in
                        return .init(
                            dataSource: dataSource,
                            owner: .messageBodyAttachment(.init(
                                messageRowId: message.sqliteRowId!,
                                receivedAtTimestamp: message.receivedAtTimestamp,
                                threadRowId: thread.sqliteRowId!,
                                isViewOnce: message.isViewOnceMessage,
                                isPastEditRevision: message.isPastEditRevision()
                            ))
                        )
                    },
                    tx: transaction.asV2Write
                )

            case .outgoingAttachments(let dataSources):
                let conversationFactory = ConversationFactory()
                conversationFactory.threadCreator = { _ in return thread }
                conversationFactory.createSentMessage(bodyAttachmentDataSources: dataSources, transaction: transaction)
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

            let groupContext = try! GroupsV2Protos.buildGroupContextProto(groupModel: groupModel, groupChangeProtoData: nil)
            dataMessageBuilder.setGroupV2(groupContext)
        }

        let payloadBuilder = SSKProtoContent.builder()
        if let dataMessage = dataMessageBuilder.buildIgnoringErrors() {
            payloadBuilder.setDataMessage(dataMessage)
        }
        let plaintextData = payloadBuilder.buildIgnoringErrors()!.serializedDataIgnoringErrors()!

        // Try to use an arbitrary member of the current thread that isn't
        // ourselves as the sender.
        let address = thread.recipientAddressesWithSneakyTransaction.first!

        let envelopeBuilder = SSKProtoEnvelope.builder(timestamp: NSDate.ows_millisecondTimeStamp())
        envelopeBuilder.setType(.ciphertext)
        envelopeBuilder.setSourceServiceID(address.aci!.serviceIdString)
        envelopeBuilder.setSourceDevice(1)
        envelopeBuilder.setContent(plaintextData)
        envelopeBuilder.setServerTimestamp(NSDate.ows_millisecondTimeStamp())

        let envelope = try! envelopeBuilder.build()
        processDecryptedEnvelope(envelope, plaintextData: plaintextData)
    }

    // MARK: Disappearing Messages

    private static func createDisappearingMessagesWhichFailedToStartInThread(_ thread: TSThread) {
        guard let aci = thread.recipientAddressesWithSneakyTransaction.first?.aci else {
            owsFailDebug("No recipient")
            return
        }

        let now = Date.ows_millisecondTimestamp()
        let messageBody = "Should disappear 60s after \(now)"
        let incomingMessageBuilder: TSIncomingMessageBuilder = .withDefaultValues(
            thread: thread,
            authorAci: aci,
            messageBody: messageBody,
            expiresInSeconds: 60
        )
        let message = incomingMessageBuilder.build()
        // private setter to avoid starting expire machinery.
        message.wasRead = true
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
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
            ThreadUtil.enqueueMessage(
                body: MessageBody(text: "\(count)", ranges: .empty),
                thread: groupThread
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                createNewGroups(count: count - 1, recipientAddress: recipientAddress)
            }
        }

        Task {
            let groupName = randomShortText()
            await createRandomGroupWithName(groupName, member: recipientAddress, completion: completion)
        }
    }

    private static func createRandomGroupWithName(
        _ groupName: String,
        member: SignalServiceAddress,
        completion: @escaping (TSGroupThread) -> Void
    ) async {
        let members = [ member, DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction!.aciAddress ]
        do {
            let groupThread = try await GroupManager.localCreateNewGroup(
                members: members,
                disappearingMessageToken: .disabledToken,
                shouldSendMessage: true
            )
            completion(groupThread)
        } catch {
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

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            for string in strings {
                // DO NOT log these strings with the debugger attached.
                //        OWSLogInfo(@"%@", string);

                createFakeIncomingMessage(
                    thread: thread,
                    messageBody: string,
                    transaction: transaction
                )

                let member = SignalServiceAddress(Aci(fromUUID: UUID()))
                Task {
                    await createRandomGroupWithName(string, member: member, completion: { _ in })
                }
            }
        }
    }

    private static func testIndicScriptsInThread(_ thread: TSThread) {
        let strings = [
            "\u{0C1C}\u{0C4D}\u{0C1E}\u{200C}\u{0C3E}",
            "\u{09B8}\u{09CD}\u{09B0}\u{200C}\u{09C1}",
            "non-crashing string"
        ]

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            for string in strings {
                // DO NOT log these strings with the debugger attached.
                //        OWSLogInfo(@"%@", string);

                createFakeIncomingMessage(
                    thread: thread,
                    messageBody: string,
                    transaction: transaction
                )

                let member = SignalServiceAddress(Aci(fromUUID: UUID()))
                Task {
                    await createRandomGroupWithName(string, member: member, completion: { _ in })
                }
            }
        }
    }

    private static func testZalgoTextInThread(_ thread: TSThread) {
        let strings = [
            "Ṱ̴̤̺̣͚͚̭̰̤̮̑̓̀͂͘͡h̵̢̤͔̼̗̦̖̬͌̀͒̀͘i̴̮̤͎͎̝̖̻͓̅̆͆̓̎͘͡ͅŝ̡̡̳͔̓͗̾̀̇͒͘͢͢͡͡ ỉ̛̲̩̫̝͉̀̒͐͋̾͘͢͡͞s̶̨̫̞̜̹͛́̇͑̅̒̊̈ s̵͍̲̗̠̗͈̦̬̉̿͂̏̐͆̾͐͊̾ǫ̶͍̼̝̉͊̉͢͜͞͝ͅͅṁ̵̡̨̬̤̝͔̣̄̍̋͊̿̄͋̈ͅe̪̪̻̱͖͚͈̲̍̃͘͠͝ z̷̢̢̛̩̦̱̺̼͑́̉̾ą͕͎̠̮̹̱̓̔̓̈̈́̅̐͢l̵̨͚̜͉̟̜͉͎̃͆͆͒͑̍̈̚͜͞ğ͔̖̫̞͎͍̒̂́̒̿̽̆͟o̶̢̬͚̘̤̪͇̻̒̋̇̊̏͢͡͡͠ͅ t̡̛̥̦̪̮̅̓̑̈́̉̓̽͛͢͡ȩ̡̩͓͈̩͎͗̔͑̌̓͊͆͝x̫̦͓̤͓̘̝̪͊̆͌͊̽̃̏͒͘͘͢ẗ̶̢̨̛̰̯͕͔́̐͗͌͟͠.̷̩̼̼̩̞̘̪́͗̅͊̎̾̅̏̀̕͟ͅ",
            "This is some normal text"
        ]

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            for string in strings {
                Logger.info("sending zalgo")

                createFakeIncomingMessage(
                    thread: thread,
                    messageBody: string,
                    transaction: transaction
                )

                let member = SignalServiceAddress(Aci(fromUUID: UUID()))
                Task {
                    await createRandomGroupWithName(string, member: member, completion: { _ in })
                }
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

            let type = UTType.data
            let dataLength: UInt32 = 32
            guard let dataSource = DataSourceValue(createRandomDataOfSize(dataLength), utiType: type.identifier) else { return }

            dataSource.sourceFilename = filename
            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: type.identifier)

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
        let numActions = Int.random(in: 1...4)
        var actions = [(SDSAnyWriteTransaction) -> Void]()
        for _ in (0..<numActions) {
            let randomAction = Int.random(in: 0...2)
            let action: (SDSAnyWriteTransaction) -> Void = {
                switch randomAction {
                case 0:
                    return { transaction in
                        // injectIncomingMessageInThread doesn't take a transaction.
                        DispatchQueue.main.async {
                            injectIncomingMessageInThread(thread, counter: counter)
                        }
                    }
                case 1:
                    return { _ in
                        // sendTextMessageInThread doesn't take a transaction.
                        DispatchQueue.main.async {
                            sendTextMessageInThread(thread, counter: counter)
                        }
                    }
                default:
                    let messageCount = UInt.random(in: 1...4)
                    let messageContents = try! createFakeMessageContents(count: messageCount, messageContentType: .normal)

                    return  { transaction in
                        createFakeMessages(messageContents, inThread: thread, transaction: transaction)
                    }
                }
            }()
            actions.append(action)
        }

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            actions.forEach { $0(transaction) }
        }
    }

    // MARK: Utility

    @discardableResult
    private static func createFakeOutgoingMessage(
        thread: TSThread,
        messageBody: String?,
        messageState: TSOutgoingMessageState,
        isDelivered: Bool = false,
        isRead: Bool = false,
        quotedMessageBuilder: OwnedAttachmentBuilder<TSQuotedMessage>? = nil,
        contactShareBlock: CreateContactBlock? = nil,
        linkPreview: OWSLinkPreview? = nil,
        messageSticker: MessageSticker? = nil,
        transaction: SDSAnyWriteTransaction
    ) -> TSOutgoingMessage {
        owsAssertDebug(!messageBody.isEmptyOrNil || contactShareBlock != nil)

        let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: messageBody)
        messageBuilder.isVoiceMessage = false

        let message = messageBuilder.build(transaction: transaction)

        quotedMessageBuilder.map { message.update(with: $0.info, transaction: transaction) }
        linkPreview.map { message.update(with: $0, transaction: transaction) }
        messageSticker.map { message.update(with: $0, transaction: transaction) }

        message.anyInsert(transaction: transaction)

        contactShareBlock?(message, transaction)

        message.updateWithFakeMessageState(messageState, tx: transaction)

        try? quotedMessageBuilder?.finalize(
            owner: .quotedReplyAttachment(.init(
                messageRowId: message.sqliteRowId!,
                receivedAtTimestamp: message.receivedAtTimestamp,
                threadRowId: thread.sqliteRowId!,
                isPastEditRevision: message.isPastEditRevision()
            )),
            tx: transaction.asV2Write
        )

        if isDelivered {
            if let address = thread.recipientAddresses(with: transaction).last {
                owsAssertDebug(address.isValid)
                message.update(
                    withDeliveredRecipient: address,
                    deviceId: 0,
                    deliveryTimestamp: Date.ows_millisecondTimestamp(),
                    context: PassthroughDeliveryReceiptContext(),
                    tx: transaction
                )
            }
        }

        if isRead {
            if let address = thread.recipientAddresses(with: transaction).last {
                owsAssertDebug(address.isValid)
                message.update(
                    withReadRecipient: address,
                    deviceId: 0,
                    readTimestamp: Date.ows_millisecondTimestamp(),
                    tx: transaction
                )
            }
        }

        return message
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
        filename: String? = nil,
        isAttachmentDownloaded: Bool = false,
        quotedMessage: TSQuotedMessage? = nil,
        transaction: SDSAnyWriteTransaction
    ) -> TSIncomingMessage {

        owsAssertDebug(!messageBody.isEmptyOrNil)

        let authorAci = DebugUIMessages.anyIncomingSenderAddress(forThread: thread)!.aci!

        let incomingMessageBuilder: TSIncomingMessageBuilder = .withDefaultValues(
            thread: thread,
            authorAci: authorAci,
            messageBody: messageBody
        )
        let message = incomingMessageBuilder.build()
        quotedMessage.map { message.update(with: $0, transaction: transaction) }
        message.anyInsert(transaction: transaction)
        message.debugonly_markAsReadNow(transaction: transaction)

        return message
    }

    @discardableResult
    private static func createFakeIncomingMessage(
        thread: TSThread,
        messageBody: String?,
        isAttachmentDownloaded: Bool = false,
        quotedMessageBuilder: OwnedAttachmentBuilder<TSQuotedMessage>? = nil,
        transaction: SDSAnyWriteTransaction
    ) -> TSIncomingMessage {
        owsAssertDebug(!messageBody.isEmptyOrNil)

        let authorAci = DebugUIMessages.anyIncomingSenderAddress(forThread: thread)!.aci!

        let incomingMessageBuilder: TSIncomingMessageBuilder = .withDefaultValues(
            thread: thread,
            authorAci: authorAci,
            messageBody: messageBody
        )
        let message = incomingMessageBuilder.build()
        quotedMessageBuilder.map { message.update(with: $0.info, transaction: transaction) }
        message.anyInsert(transaction: transaction)
        message.debugonly_markAsReadNow(transaction: transaction)

        try? quotedMessageBuilder?.finalize(
            owner: .quotedReplyAttachment(.init(
                messageRowId: message.sqliteRowId!,
                receivedAtTimestamp: message.receivedAtTimestamp,
                threadRowId: thread.sqliteRowId!,
                isPastEditRevision: message.isPastEditRevision()
            )),
            tx: transaction.asV2Write
        )

        return message
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
            guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress else {
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
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            SSKEnvironment.shared.messageReceiverRef.processEnvelope(
                envelope,
                plaintextData: plaintextData,
                wasReceivedByUD: false,
                serverDeliveryTimestamp: 0,
                shouldDiscardVisibleMessages: false,
                localIdentifiers: DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)!,
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
        while message.lengthOfBytes(using: .utf8) <= kOversizeTextMessageSizeThreshold {
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
        return Randomness.generateRandomBytes(UInt(size))
    }
}

#endif
