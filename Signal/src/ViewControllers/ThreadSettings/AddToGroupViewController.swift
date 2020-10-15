//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class AddToGroupViewController: OWSTableViewController {

    private let address: SignalServiceAddress
    private let collation = UILocalizedIndexedCollation.current()
    private let maxRecentGroups = 5

    private lazy var threadViewHelper: ThreadViewHelper = {
        let threadViewHelper = ThreadViewHelper()
        threadViewHelper.delegate = self
        return threadViewHelper
    }()

    init(address: SignalServiceAddress) {
        self.address = address

        super.init()

        tableViewStyle = .plain
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

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(didPressCloseButton))

        tableView.separatorStyle = .none
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()

        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: .ThemeDidChange, object: nil)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        NotificationCenter.default.removeObserver(self)
    }

    private func updateTableContents() {
        AssertIsOnMainThread()

        let groupThreads = databaseStorage.read { transaction in
            return self.threadViewHelper.threads.filter { thread -> Bool in
                guard let groupThread = thread as? TSGroupThread else { return false }
                let threadViewModel = ThreadViewModel(thread: groupThread, transaction: transaction)
                let groupViewHelper = GroupViewHelper(threadViewModel: threadViewModel)
                return groupViewHelper.canEditConversationMembership
            } as? [TSGroupThread] ?? []
        }

        let contents = OWSTableContents()

        let recentGroups = groupThreads.count > maxRecentGroups ? Array(groupThreads[0..<maxRecentGroups]) : groupThreads

        let recentsSection = OWSTableSection()
        recentsSection.customHeaderView = sectionHeader(
            title: NSLocalizedString("ADD_TO_GROUP_RECENTS_TITLE",
                                     comment: "The title for the 'add to group' view's recents section")
        )
        recentsSection.add(recentGroups.map(item(for:)))
        contents.addSection(recentsSection)

        if let additionalGroups = groupThreads.count > maxRecentGroups ? Array(groupThreads[maxRecentGroups..<groupThreads.count]) : nil {
            let collatedGroups = additionalGroups.reduce(into: [Int: [TSGroupThread]]()) { result, group in
                let section = collation.section(for: group, collationStringSelector: #selector(getter: TSGroupThread.groupNameOrDefault))
                var sectionGroups = result[section] ?? []
                sectionGroups.append(group)
                result[section] = sectionGroups
            }

            for (section, title) in collation.sectionTitles.enumerated() {
                guard let sectionGroups = collatedGroups[section] else { continue }

                let section = OWSTableSection()
                section.customHeaderView = sectionHeader(title: title)
                section.add(
                    sectionGroups
                        .sorted { $0.groupNameOrDefault.localizedCaseInsensitiveCompare($1.groupNameOrDefault) == .orderedAscending }
                        .map(item(for:))
                )

                contents.addSection(section)
            }

            let visibleTitles: [String] = collation.sectionTitles.enumerated().compactMap { (index, title) in
                guard collatedGroups[index] != nil else { return nil }
                return title
            }

            contents.sectionForSectionIndexTitleBlock = { $1 + 1 }
            contents.sectionIndexTitlesForTableViewBlock = { visibleTitles }

        }

        self.contents = contents
    }

    // MARK: Helpers

    @objc
    private func themeDidChange() {
        updateTableContents()
    }

    @objc
    private func didPressCloseButton(sender: UIButton) {
        Logger.info("")

        self.dismiss(animated: true)
    }

    private func didSelectGroup(_ groupThread: TSGroupThread) {
        let shortName = databaseStorage.uiRead { transaction in
            return Environment.shared.contactsManager.shortDisplayName(for: self.address, transaction: transaction)
        }

        guard !groupThread.groupModel.groupMembership.isMemberOfAnyKind(address) else {
            let toastFormat = NSLocalizedString(
                "ADD_TO_GROUP_ALREADY_MEMBER_TOAST_FORMAT",
                comment: "A toast on the 'add to group' view indicating the user is already a member. Embeds {contact name} and {group name}"
            )

            let toastController = ToastController(
                text: String(format: toastFormat, shortName, groupThread.groupNameOrDefault)
            )
            toastController.presentToastView(fromBottomOfView: view, inset: bottomLayoutGuide.length + 8)
            return
        }

        let titleFormat = NSLocalizedString("ADD_TO_GROUP_ACTION_SHEET_TITLE_FORMAT",
                                            comment: "The title on the 'add to group' confirmation action sheet. Embeds {group name}")
        let messageFormat = NSLocalizedString("ADD_TO_GROUP_ACTION_SHEET_MESSAGE_FORMAT",
                                            comment: "The title on the 'add to group' confirmation action sheet. Embeds {contact name}")

        OWSActionSheets.showConfirmationAlert(
            title: String(format: titleFormat, groupThread.groupNameOrDefault),
            message: String(format: messageFormat, shortName),
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
        let doesUserSupportGroupsV2 = databaseStorage.read { transaction in
            GroupManager.doesUserSupportGroupsV2(address: self.address, transaction: transaction)
        }
        guard doesUserSupportGroupsV2 else {
            GroupViewUtils.showInvalidGroupMemberAlert(fromViewController: self)
            return
        }
        addToGroupStep2(groupThread, shortName: shortName)
    }

    private func addToGroupStep2(_ groupThread: TSGroupThread, shortName: String) {
        let oldGroupModel = groupThread.groupModel
        guard let newGroupModel = buildNewGroupModel(oldGroupModel: oldGroupModel) else {
            let error = OWSAssertionError("Couldn't build group model.")
            GroupViewUtils.showUpdateErrorUI(error: error)
            return
        }

        GroupViewUtils.updateGroupWithActivityIndicator(
            fromViewController: self,
            updatePromiseBlock: {
                self.updateGroupThreadPromise(oldGroupModel: oldGroupModel,
                                              newGroupModel: newGroupModel)
            },
            completion: { [weak self] _ in
                self?.notifyOfAddedAndDismiss(groupThread: groupThread, shortName: shortName)
            }
        )
    }

    private func notifyOfAddedAndDismiss(groupThread: TSGroupThread, shortName: String) {
        let toastInset = bottomLayoutGuide.length + 8

        dismiss(animated: true) { [presentingViewController] in
            guard let presentingView = presentingViewController?.view else { return }

            let toastFormat = NSLocalizedString(
                "ADD_TO_GROUP_SUCCESS_TOAST_FORMAT",
                comment: "A toast on the 'add to group' view indicating the user was added. Embeds {contact name} and {group name}"
            )

            let toastController = ToastController(
                text: String(format: toastFormat, shortName, groupThread.groupNameOrDefault)
            )
            toastController.presentToastView(fromBottomOfView: presentingView, inset: toastInset)
        }
    }

    // MARK: -

    func buildNewGroupModel(oldGroupModel: TSGroupModel) -> TSGroupModel? {
        do {
            return try databaseStorage.read { transaction in
                var builder = oldGroupModel.asBuilder
                let oldGroupMembership = oldGroupModel.groupMembership
                var groupMembershipBuilder = oldGroupMembership.asBuilder

                guard !oldGroupMembership.isMemberOfAnyKind(self.address) else {
                    owsFailDebug("Recipient is already in group.")
                    return nil
                }
                // GroupManager will separate out members as pending if necessary.
                groupMembershipBuilder.addFullMember(self.address, role: .normal)

                builder.groupMembership = groupMembershipBuilder.build()
                return try builder.build(transaction: transaction)
            }
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    func updateGroupThreadPromise(oldGroupModel: TSGroupModel,
                                  newGroupModel: TSGroupModel) -> Promise<Void> {

        guard let localAddress = TSAccountManager.localAddress else {
            return Promise(error: OWSAssertionError("Missing localAddress."))
        }

        return firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: oldGroupModel,
                                                         description: self.logTag)
        }.then(on: .global()) { _ in
            // dmConfiguration: nil means don't change disappearing messages configuration.
            GroupManager.localUpdateExistingGroup(oldGroupModel: oldGroupModel,
                                                  newGroupModel: newGroupModel,
                                                  dmConfiguration: nil,
                                                  groupUpdateSourceAddress: localAddress)
        }.asVoid()
    }

    // MARK: -

    private func sectionHeader(title: String) -> UIView {
        let textView = UITextView()
        textView.isOpaque = false
        textView.isEditable = false
        textView.contentInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.textColor = Theme.primaryTextColor
        textView.font = UIFont.ows_dynamicTypeBody.ows_semibold
        textView.backgroundColor = Theme.washColor
        let tableEdgeInsets: CGFloat = UIDevice.current.isPlusSizePhone ? 20 : 16
        textView.textContainerInset = UIEdgeInsets(top: 5, left: tableEdgeInsets, bottom: 5, right: tableEdgeInsets)
        textView.text = title
        return textView
    }

    private func item(for groupThread: TSGroupThread) -> OWSTableItem {
        return OWSTableItem(
            customCellBlock: {
                let cell = GroupTableViewCell()
                cell.configure(thread: groupThread)
                return cell
            },
            actionBlock: { [weak self] in
                self?.didSelectGroup(groupThread)
            }
        )
    }
}

// MARK: -

extension AddToGroupViewController: ThreadViewHelperDelegate {
    public func threadListDidChange() {
        updateTableContents()
    }
}
