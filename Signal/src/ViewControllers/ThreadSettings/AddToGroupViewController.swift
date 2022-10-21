//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

@objc
public class AddToGroupViewController: OWSTableViewController2 {

    private let address: SignalServiceAddress

    init(address: SignalServiceAddress) {
        self.address = address
        super.init()
    }

    public class func presentForUser(_ address: SignalServiceAddress,
                                     from fromViewController: UIViewController) {
        AssertIsOnMainThread()

        let view = AddToGroupViewController(address: address)
        let modal = OWSNavigationController(rootViewController: view)
        fromViewController.presentFormSheet(modal, animated: true)
    }

    // MARK: -

    public override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = NSLocalizedString("ADD_TO_GROUP_TITLE", comment: "Title of the 'add to group' view.")

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(didPressCloseButton))

        defaultSeparatorInsetLeading = Self.cellHInnerMargin + CGFloat(AvatarBuilder.smallAvatarSizePoints) + ContactCellView.avatarTextHSpacing

        updateGroupThreadsAsync()
    }

    private var groupThreads = [TSGroupThread]() {
        didSet {
            DispatchQueue.main.async { [weak self] in
                self?.updateTableContents()
            }
        }
    }

    private func updateGroupThreadsAsync() {
        DispatchQueue.sharedUserInitiated.async { [weak self] in
            self?.groupThreads = Self.fetchGroupThreads()
        }
    }

    private class func fetchGroupThreads() -> [TSGroupThread] {
        databaseStorage.read { transaction in
            var result = [TSGroupThread]()

            do {
                try AnyThreadFinder().enumerateGroupThreads(transaction: transaction) { thread in
                    guard thread.groupModel.groupsVersion == .V2 else { return }

                    let threadViewModel = ThreadViewModel(
                        thread: thread,
                        forChatList: false,
                        transaction: transaction
                    )
                    let groupViewHelper = GroupViewHelper(threadViewModel: threadViewModel)
                    guard groupViewHelper.canEditConversationMembership else { return }

                    result.append(thread)
                }
            } catch {
                owsFailDebug("Failed to fetch group threads: \(error). Returning an empty array")
            }

            return result
        }
    }

    private func updateTableContents() {
        AssertIsOnMainThread()
        let groupsSection = OWSTableSection(items: groupThreads.map(item(forGroupThread:)))
        self.contents = OWSTableContents(sections: [groupsSection])
    }

    // MARK: Helpers

    public override func applyTheme() {
        super.applyTheme()
        self.tableView.sectionIndexColor = Theme.primaryTextColor
    }

    public override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    @objc
    private func didPressCloseButton(sender: UIButton) {
        Logger.info("")

        self.dismiss(animated: true)
    }

    private func didSelectGroup(_ groupThread: TSGroupThread) {
        let shortName = databaseStorage.read { transaction in
            return Self.contactsManager.shortDisplayName(for: self.address, transaction: transaction)
        }

        guard !groupThread.groupModel.groupMembership.isMemberOfAnyKind(address) else {
            let toastFormat = NSLocalizedString(
                "ADD_TO_GROUP_ALREADY_MEMBER_TOAST_FORMAT",
                comment: "A toast on the 'add to group' view indicating the user is already a member. Embeds {contact name} and {group name}"
            )
            let toastText = String(format: toastFormat, shortName, groupThread.groupNameOrDefault)
            presentToast(text: toastText)
            return
        }

        let messageFormat = NSLocalizedString("ADD_TO_GROUP_ACTION_SHEET_MESSAGE_FORMAT",
                                            comment: "The title on the 'add to group' confirmation action sheet. Embeds {contact name, group name}")

        OWSActionSheets.showConfirmationAlert(
            title: NSLocalizedString(
                "ADD_TO_GROUP_ACTION_SHEET_TITLE",
                comment: "The title on the 'add to group' confirmation action sheet."
            ),
            message: String(format: messageFormat, shortName, groupThread.groupNameOrDefault),
            proceedTitle: NSLocalizedString("ADD_TO_GROUP_ACTION_PROCEED_BUTTON",
                                            comment: "The button on the 'add to group' confirmation to add the user to the group."),
            proceedStyle: .default) { _ in
                self.addToGroupStep1(groupThread, shortName: shortName)
        }
    }

    private func addToGroupStep1(_ groupThread: TSGroupThread, shortName: String) {
        AssertIsOnMainThread()
        guard groupThread.isGroupV2Thread else {
            addToGroupStep2(groupThread, shortName: shortName)
            return
        }
        let doesUserSupportGroupsV2 = GroupManager.doesUserSupportGroupsV2(address: self.address)
        guard doesUserSupportGroupsV2 else {
            GroupViewUtils.showInvalidGroupMemberAlert(fromViewController: self)
            return
        }
        addToGroupStep2(groupThread, shortName: shortName)
    }

    private func addToGroupStep2(_ groupThread: TSGroupThread, shortName: String) {
        let oldGroupModel = groupThread.groupModel

        guard !oldGroupModel.groupMembership.isMemberOfAnyKind(self.address) else {
            let error = OWSAssertionError("Receipient is already in group")
            GroupViewUtils.showUpdateErrorUI(error: error)
            return
        }

        guard let uuid = self.address.uuid else {
            let error = OWSAssertionError("Address missing UUID")
            GroupViewUtils.showUpdateErrorUI(error: error)
            return
        }

        GroupViewUtils.updateGroupWithActivityIndicator(
            fromViewController: self,
            withGroupModel: oldGroupModel,
            updateDescription: self.logTag,
            updateBlock: {
                GroupManager.addOrInvite(
                    aciOrPniUuids: [uuid],
                    toExistingGroup: oldGroupModel
                )
            },
            completion: { [weak self] _ in
                self?.notifyOfAddedAndDismiss(groupThread: groupThread, shortName: shortName)
            }
        )
    }

    private func notifyOfAddedAndDismiss(groupThread: TSGroupThread, shortName: String) {
        dismiss(animated: true) { [presentingViewController] in
            let toastFormat = NSLocalizedString(
                "ADD_TO_GROUP_SUCCESS_TOAST_FORMAT",
                comment: "A toast on the 'add to group' view indicating the user was added. Embeds {contact name} and {group name}"
            )
            let toastText = String(format: toastFormat, shortName, groupThread.groupNameOrDefault)
            presentingViewController?.presentToast(text: toastText)
        }
    }

    // MARK: -

    private func item(forGroupThread  groupThread: TSGroupThread) -> OWSTableItem {
        let alreadyAMemberText = NSLocalizedString(
            "ADD_TO_GROUP_ALREADY_A_MEMBER",
            comment: "Text indicating your contact is already a member of the group on the 'add to group' view."
        )
        let isAlreadyAMember = groupThread.groupMembership.isFullMember(address)

        return OWSTableItem(
            customCellBlock: {
                let cell = GroupTableViewCell()
                cell.configure(
                    thread: groupThread,
                    customSubtitle: isAlreadyAMember ? alreadyAMemberText : nil,
                    customTextColor: isAlreadyAMember ? Theme.ternaryTextColor : nil
                )
                cell.isUserInteractionEnabled = !isAlreadyAMember
                return cell
            },
            actionBlock: { [weak self] in
                self?.didSelectGroup(groupThread)
            }
        )
    }
}
