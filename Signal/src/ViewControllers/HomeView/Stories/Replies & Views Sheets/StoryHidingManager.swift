//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

class StoryHidingManager: Dependencies {

    private let model: StoryViewModel

    init(model: StoryViewModel) {
        self.model = model
    }

    public func contextMenuAction(
        forPresentingController presentingController: UIViewController
    ) -> ContextMenuAction {
        let isHidden = model.isHidden
        let title: String
        let image: UIImage
        if isHidden {
            title = NSLocalizedString(
                "STORIES_UNHIDE_STORY_ACTION",
                comment: "Context menu action to unhide the selected story"
            )
            image = Theme.iconImage(.checkCircle)
        } else {
            title = NSLocalizedString(
                "STORIES_HIDE_STORY_ACTION",
                comment: "Context menu action to hide the selected story"
            )
            image = Theme.iconImage(.xCircle24)
        }
        return .init(
            title: title,
            image: image,
            handler: { [self, weak presentingController] _ in
                guard let presentingController = presentingController else {
                    return
                }
                if isHidden {
                    self.setHideStateAndShowToast(shouldHide: !isHidden, presentingController: presentingController)
                } else {
                    self.showActionSheetIfNeeded(shouldHide: !isHidden, on: presentingController)
                }
            }
        )
    }

    private func showActionSheetIfNeeded(shouldHide: Bool, on presentingController: UIViewController) {
        guard shouldHide else {
            // No need to show anything if unhiding, hide right away
            setHideStateAndShowToast(shouldHide: shouldHide, presentingController: presentingController)
            return
        }

        let actionSheet = createHidingActionSheetWithSneakyTransaction()

        let actionTitle: String
        if shouldHide {
            actionTitle = NSLocalizedString(
                "STORIES_HIDE_STORY_ACTION",
                comment: "Context menu action to hide the selected story"
            )
        } else {
            actionTitle = NSLocalizedString(
                "STORIES_UNHIDE_STORY_ACTION",
                comment: "Context menu action to unhide the selected story"
            )
        }

        actionSheet.addAction(ActionSheetAction(
            title: actionTitle,
            style: .default,
            handler: { [self, weak presentingController] _ in
                guard let presentingController = presentingController else {
                    return
                }
                self.setHideStateAndShowToast(shouldHide: shouldHide, presentingController: presentingController)
            }
        ))
        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentingController.presentActionSheet(actionSheet)
    }

    // MARK: - Loading data

    private func loadThread(_ transaction: SDSAnyReadTransaction) -> TSThread? {
        switch model.context {
        case .groupId(let groupId):
            return TSGroupThread.fetch(groupId: groupId, transaction: transaction)
        case .authorUuid(let authorUuid):
            return TSContactThread.getWithContactAddress(
                authorUuid.asSignalServiceAddress(),
                transaction: transaction
            )
        case .privateStory:
            owsFailDebug("Unexpectedly had private story when hiding")
            return nil
        case .none:
            owsFailDebug("Unexpectedly missing context for story when hiding")
            return nil
        }
    }

    // MARK: - Header configuration

    private func createHidingActionSheetWithSneakyTransaction() -> ActionSheetController {
        return ActionSheetController(
            title: NSLocalizedString(
                "STORIES_HIDE_STORY_ACTION_SHEET_TITLE",
                comment: "Title asking the user if they are sure they want to hide stories from another user"
            ),
            message: loadThreadDisplayNameWithSneakyTransaction().map {
                String(
                    format: NSLocalizedString(
                        "STORIES_HIDE_STORY_ACTION_SHEET_MESSAGE",
                        comment: "Message asking the user if they are sure they want to hide stories from {{other user's name}}"
                    ),
                    $0
                )
            }
        )
    }

    private func loadThreadDisplayNameWithSneakyTransaction() -> String? {
        return Self.databaseStorage.read { transaction -> String? in
            switch self.model.context {
            case .groupId(let groupId):
                return TSGroupThread.fetch(groupId: groupId, transaction: transaction)?.groupNameOrDefault
            case .authorUuid(let authorUuid):
                if authorUuid.asSignalServiceAddress().isSystemStoryAddress {
                    return NSLocalizedString(
                        "SYSTEM_ADDRESS_NAME",
                        comment: "Name to display for the 'system' sender, e.g. for release notes and the onboarding story"
                    )
                }
                return Self.contactsManager.shortDisplayName(
                    for: authorUuid.asSignalServiceAddress(),
                    transaction: transaction
                )
            case .privateStory:
                owsFailDebug("Unexpectedly had private story when hiding")
                return nil
            case .none:
                owsFailDebug("Unexpectedly missing context for story when hiding")
                return nil
            }
        }
    }

    // MARK: - Issuing changes

    private func setHideStateAndShowToast(
        shouldHide: Bool,
        presentingController: UIViewController
    ) {
        Self.databaseStorage.write { transaction in
            guard self.model.messages.first?.authorAddress.isSystemStoryAddress != true else {
                // System stories go through SystemStoryManager
                Self.systemStoryManager.setSystemStoriesHidden(shouldHide, transaction: transaction)
                return
            }
            guard let thread = self.model.context.thread(transaction: transaction) else {
                owsFailDebug("Hiding a story without a thread")
                return
            }
            let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: thread, transaction: transaction)
            threadAssociatedData.updateWith(
                hideStory: shouldHide,
                updateStorageService: true,
                transaction: transaction
            )
        }
        let toastText: String
        if shouldHide {
            toastText = NSLocalizedString(
                "STORIES_HIDE_STORY_CONFIRMATION_TOAST",
                comment: "Toast shown when a story is successfuly hidden"
            )
        } else {
            toastText = NSLocalizedString(
                "STORIES_UNHIDE_STORY_CONFIRMATION_TOAST",
                comment: "Toast shown when a story is successfuly unhidden"
            )
        }
        presentingController.presentToast(text: toastText)
    }
}
