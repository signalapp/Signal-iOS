//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit
public import SignalUI

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

        title = OWSLocalizedString("ADD_TO_GROUP_TITLE", comment: "Title of the 'add to group' view.")

        navigationItem.leftBarButtonItem = .cancelButton { [weak self] in
            self?.didPressCloseButton()
        }

        defaultSeparatorInsetLeading = Self.cellHInnerMargin + CGFloat(AvatarBuilder.smallAvatarSizePoints) + ContactCellView.avatarTextHSpacing

        updateGroupThreadsAsync()
    }

    private var groupThreads = [TSGroupThread]() {
        didSet {
            AssertIsOnMainThread()
            updateTableContents()
        }
    }

    private func updateGroupThreadsAsync() {
        DispatchQueue.sharedUserInitiated.async { [weak self] in
            let fetchedGroupThreads = Self.fetchGroupThreads()
            DispatchQueue.main.async {
                self?.groupThreads = fetchedGroupThreads
            }
        }
    }

    private class func fetchGroupThreads() -> [TSGroupThread] {
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            var result = [TSGroupThread]()

            do {
                try ThreadFinder().enumerateGroupThreads(transaction: transaction) { thread -> Bool in
                    if thread.isGroupV2Thread {
                        let groupViewHelper = GroupViewHelper(
                            threadViewModel: ThreadViewModel(
                                thread: thread,
                                forChatList: false,
                                transaction: transaction
                            )
                        )

                        if groupViewHelper.canEditConversationMembership {
                            result.append(thread)
                        }
                    }

                    return true
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

    public override func themeDidChange() {
        super.themeDidChange()
        self.tableView.sectionIndexColor = Theme.primaryTextColor
        updateTableContents()
    }

    private func didPressCloseButton() {
        Logger.info("")

        self.dismiss(animated: true)
    }

    private func didSelectGroup(_ groupThread: TSGroupThread) {
        let shortName = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return SSKEnvironment.shared.contactManagerRef.displayName(for: self.address, tx: transaction).resolvedValue(useShortNameIfAvailable: true)
        }

        guard !groupThread.groupModel.groupMembership.isMemberOfAnyKind(address) else {
            let toastFormat = OWSLocalizedString(
                "ADD_TO_GROUP_ALREADY_MEMBER_TOAST_FORMAT",
                comment: "A toast on the 'add to group' view indicating the user is already a member. Embeds {contact name} and {group name}"
            )
            let toastText = String(format: toastFormat, shortName, groupThread.groupNameOrDefault)
            presentToast(text: toastText)
            return
        }

        let messageFormat = OWSLocalizedString("ADD_TO_GROUP_ACTION_SHEET_MESSAGE_FORMAT",
                                            comment: "The title on the 'add to group' confirmation action sheet. Embeds {contact name, group name}")

        OWSActionSheets.showConfirmationAlert(
            title: OWSLocalizedString(
                "ADD_TO_GROUP_ACTION_SHEET_TITLE",
                comment: "The title on the 'add to group' confirmation action sheet."
            ),
            message: String(format: messageFormat, shortName, groupThread.groupNameOrDefault),
            proceedTitle: OWSLocalizedString("ADD_TO_GROUP_ACTION_PROCEED_BUTTON",
                                            comment: "The button on the 'add to group' confirmation to add the user to the group."),
            proceedStyle: .default) { _ in
                self.addToGroup(groupThread, shortName: shortName)
        }
    }

    private func addToGroup(_ groupThread: TSGroupThread, shortName: String) {
        AssertIsOnMainThread()
        owsPrecondition(groupThread.isGroupV2Thread)  // non-gv2 filtered above when fetching groups

        guard let serviceId = self.address.serviceId else {
            GroupViewUtils.showInvalidGroupMemberAlert(fromViewController: self)
            return
        }

        let oldGroupModel = groupThread.groupModel

        guard !oldGroupModel.groupMembership.isMemberOfAnyKind(serviceId) else {
            let error = OWSAssertionError("Receipient is already in group")
            GroupViewUtils.showUpdateErrorUI(error: error)
            return
        }

        GroupViewUtils.updateGroupWithActivityIndicator(
            fromViewController: self,
            updateDescription: self.logTag,
            updateBlock: {
                _ = try await GroupManager.addOrInvite(
                    serviceIds: [serviceId],
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
            let toastFormat = OWSLocalizedString(
                "ADD_TO_GROUP_SUCCESS_TOAST_FORMAT",
                comment: "A toast on the 'add to group' view indicating the user was added. Embeds {contact name} and {group name}"
            )
            let toastText = String(format: toastFormat, shortName, groupThread.groupNameOrDefault)
            presentingViewController?.presentToast(text: toastText)
        }
    }

    // MARK: -

    private func item(forGroupThread groupThread: TSGroupThread) -> OWSTableItem {
        let alreadyAMemberText = OWSLocalizedString(
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
