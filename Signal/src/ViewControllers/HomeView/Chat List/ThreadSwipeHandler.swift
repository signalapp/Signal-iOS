//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalMessaging
import UIKit

@objc
protocol ThreadSwipeHandler {
    @objc
    optional func updateUIAfterSwipeAction()
}

extension ThreadSwipeHandler where Self: UIViewController {

    func leadingSwipeActionsConfiguration(for threadViewModel: ThreadViewModel?) -> UISwipeActionsConfiguration? {
        AssertIsOnMainThread()

        guard let threadViewModel = threadViewModel else {
            return nil
        }

        let thread = threadViewModel.threadRecord
        let isThreadPinned = PinnedThreadManager.isThreadPinned(thread)
        let pinnedStateAction: UIContextualAction
        if isThreadPinned {
            pinnedStateAction = UIContextualAction(style: .normal, title: nil) { [weak self] (_, _, completion) in
                self?.unpinThread(threadViewModel: threadViewModel)
                completion(false)
            }
            pinnedStateAction.backgroundColor = UIColor(rgbHex: 0xff990a)
            pinnedStateAction.accessibilityLabel = CommonStrings.unpinAction
            pinnedStateAction.image = actionImage(name: "unpin-solid-24", title: CommonStrings.unpinAction)
        } else {
            pinnedStateAction = UIContextualAction(style: .destructive, title: nil) { [weak self] (_, _, completion) in
                self?.pinThread(threadViewModel: threadViewModel)
                completion(false)
            }
            pinnedStateAction.backgroundColor = UIColor(rgbHex: 0xff990a)
            pinnedStateAction.accessibilityLabel = CommonStrings.pinAction
            pinnedStateAction.image = actionImage(name: "pin-solid-24", title: CommonStrings.pinAction)
        }

        let readStateAction: UIContextualAction
        if threadViewModel.hasUnreadMessages {
            readStateAction = UIContextualAction(style: .destructive, title: nil) { [weak self] (_, _, completion) in
                completion(false)
                self?.markThreadAsRead(threadViewModel: threadViewModel)
            }
            readStateAction.backgroundColor = .ows_accentBlue
            readStateAction.accessibilityLabel = CommonStrings.readAction
            readStateAction.image = actionImage(name: "read-solid-24", title: CommonStrings.readAction)
        } else {
            readStateAction = UIContextualAction(style: .normal, title: nil) { [weak self] (_, _, completion) in
                completion(false)
                self?.markThreadAsUnread(threadViewModel: threadViewModel)
            }
            readStateAction.backgroundColor = .ows_accentBlue
            readStateAction.accessibilityLabel = CommonStrings.unreadAction
            readStateAction.image = actionImage(name: "unread-solid-24", title: CommonStrings.unreadAction)
        }

        // The first action will be auto-performed for "very long swipes".
        return UISwipeActionsConfiguration(actions: [ readStateAction, pinnedStateAction ])
    }

    func trailingSwipeActionsConfiguration(for threadViewModel: ThreadViewModel?, closeConversationBlock: (() -> Void)? = nil) -> UISwipeActionsConfiguration? {
        AssertIsOnMainThread()

        guard let threadViewModel = threadViewModel else {
            return nil
        }

        let muteAction = UIContextualAction(style: .normal, title: nil) { [weak self] (_, _, completion) in
            if threadViewModel.isMuted {
                self?.unmuteThread(threadViewModel: threadViewModel)
            } else {
                self?.muteThreadWithSelection(threadViewModel: threadViewModel)
            }
            completion(false)
        }
        muteAction.backgroundColor = .ows_accentIndigo
        muteAction.image = actionImage(name: threadViewModel.isMuted ? "bell-solid-24" : "bell-disabled-solid-24",
                                       title: threadViewModel.isMuted ? CommonStrings.unmuteButton : CommonStrings.muteButton)
        muteAction.accessibilityLabel = threadViewModel.isMuted ? CommonStrings.unmuteButton : CommonStrings.muteButton

        let deleteAction = UIContextualAction(style: .destructive, title: nil) { [weak self] (_, _, completion) in
            self?.deleteThreadWithConfirmation(threadViewModel: threadViewModel, closeConversationBlock: closeConversationBlock)
            completion(false)
        }
        deleteAction.backgroundColor = .ows_accentRed
        deleteAction.image = actionImage(name: "trash-solid-24", title: CommonStrings.deleteButton)
        deleteAction.accessibilityLabel = CommonStrings.deleteButton

        let archiveAction = UIContextualAction(style: .normal, title: nil) { [weak self] (_, _, completion) in
            self?.archiveThread(threadViewModel: threadViewModel, closeConversationBlock: closeConversationBlock)
            completion(false)
        }

        let archiveTitle = threadViewModel.isArchived ? CommonStrings.unarchiveAction : CommonStrings.archiveAction
        archiveAction.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray45 : .ows_gray25
        archiveAction.image = actionImage(name: "archive-solid-24", title: archiveTitle)
        archiveAction.accessibilityLabel = archiveTitle

        // The first action will be auto-performed for "very long swipes".
        return UISwipeActionsConfiguration(actions: [archiveAction, deleteAction, muteAction])
    }

    func actionImage(name imageName: String, title: String) -> UIImage? {
        AssertIsOnMainThread()
        // We need to bake the title text into the image because `UIContextualAction`
        // only displays title + image when the cell's height > 91. We want to always
        // show both.
        guard let image = UIImage(named: imageName) else {
            owsFailDebug("Missing image.")
            return nil
        }
        guard let image = image.withTitle(title,
                                          font: UIFont.systemFont(ofSize: 13),
                                          color: .ows_white,
                                          maxTitleWidth: 68,
                                          minimumScaleFactor: CGFloat(8) / CGFloat(13),
                                          spacing: 4) else {
            owsFailDebug("Missing image.")
            return nil
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    func archiveThread(threadViewModel: ThreadViewModel, closeConversationBlock: (() -> Void)?) {
        AssertIsOnMainThread()

        closeConversationBlock?()
        databaseStorage.write { transaction in
            threadViewModel.associatedData.updateWith(isArchived: !threadViewModel.isArchived,
                                                      updateStorageService: true,
                                                      transaction: transaction)
        }
        updateUIAfterSwipeAction?()
    }

    fileprivate func deleteThreadWithConfirmation(threadViewModel: ThreadViewModel, closeConversationBlock: (() -> Void)?) {
        AssertIsOnMainThread()

        let alert = ActionSheetController(title: NSLocalizedString("CONVERSATION_DELETE_CONFIRMATION_ALERT_TITLE",
                                                                   comment: "Title for the 'conversation delete confirmation' alert."),
                                          message: NSLocalizedString("CONVERSATION_DELETE_CONFIRMATION_ALERT_MESSAGE",
                                                                     comment: "Message for the 'conversation delete confirmation' alert."))
        alert.addAction(ActionSheetAction(title: CommonStrings.deleteButton,
                                          style: .destructive) { [weak self] _ in
            self?.deleteThread(threadViewModel: threadViewModel, closeConversationBlock: closeConversationBlock)
        })
        alert.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(alert)
    }

    func deleteThread(threadViewModel: ThreadViewModel, closeConversationBlock: (() -> Void)?) {
        AssertIsOnMainThread()

        closeConversationBlock?()
        databaseStorage.write { transaction in
            threadViewModel.threadRecord.softDelete(with: transaction)
        }
        updateUIAfterSwipeAction?()
    }

    func markThreadAsRead(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        databaseStorage.write { transaction in
            threadViewModel.threadRecord.markAllAsRead(updateStorageService: true, transaction: transaction)
        }
    }

    fileprivate func markThreadAsUnread(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        databaseStorage.write { transaction in
            threadViewModel.associatedData.updateWith(isMarkedUnread: true, updateStorageService: true, transaction: transaction)
        }
    }

    fileprivate func muteThreadWithSelection(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        let alert = ActionSheetController(title: NSLocalizedString("CONVERSATION_MUTE_CONFIRMATION_ALERT_TITLE",
                                                                   comment: "Title for the 'conversation mute confirmation' alert."))
        for (title, seconds) in [
            (NSLocalizedString("CONVERSATION_MUTE_CONFIRMATION_OPTION_1H", comment: "1 hour"), kHourInterval),
            (NSLocalizedString("CONVERSATION_MUTE_CONFIRMATION_OPTION_8H", comment: "8 hours"), 8 * kHourInterval),
            (NSLocalizedString("CONVERSATION_MUTE_CONFIRMATION_OPTION_1D", comment: "1 day"), kDayInterval),
            (NSLocalizedString("CONVERSATION_MUTE_CONFIRMATION_OPTION_1W", comment: "1 week"), kWeekInterval),
            (NSLocalizedString("CONVERSATION_MUTE_CONFIRMATION_OPTION_ALWAYS", comment: "Always"), -1)] {
            alert.addAction(ActionSheetAction(title: title, style: .default) { [weak self] _ in
                self?.muteThread(threadViewModel: threadViewModel, duration: seconds)
            })
        }
        alert.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(alert)
    }

    fileprivate func muteThread(threadViewModel: ThreadViewModel, duration seconds: TimeInterval) {
        AssertIsOnMainThread()

        databaseStorage.write { transaction in
            let timestamp = seconds < 0
            ? ThreadAssociatedData.alwaysMutedTimestamp
            : (seconds == 0 ? 0 : Date.ows_millisecondTimestamp() + UInt64(seconds * 1000))
            threadViewModel.associatedData.updateWith(mutedUntilTimestamp: timestamp, updateStorageService: true, transaction: transaction)
        }
    }

    fileprivate func unmuteThread(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        databaseStorage.write { transaction in
            threadViewModel.associatedData.updateWith(mutedUntilTimestamp: Date.ows_millisecondTimestamp(), updateStorageService: true, transaction: transaction)
        }
    }

    fileprivate func pinThread(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        do {
            try databaseStorage.write { transaction in
                try PinnedThreadManager.pinThread(threadViewModel.threadRecord, updateStorageService: true, transaction: transaction)
            }
        } catch {
            if case PinnedThreadError.tooManyPinnedThreads = error {
                OWSActionSheets.showActionSheet(title: NSLocalizedString("PINNED_CONVERSATION_LIMIT",
                                                                         comment: "An explanation that you have already pinned the maximum number of conversations."))
            } else {
                owsFailDebug("Error: \(error)")
            }
        }
    }

    fileprivate func unpinThread(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        do {
            try databaseStorage.write { transaction in
                try PinnedThreadManager.unpinThread(threadViewModel.threadRecord, updateStorageService: true, transaction: transaction)
            }
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }

}
