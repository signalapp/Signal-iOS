//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import ContactsUI
import SignalServiceKit
import SignalUI

protocol NameCollisionResolutionDelegate: AnyObject {
    // For message requests, we should piggyback on the same action sheet that's presented
    // by the message request actions
    func createBlockThreadActionSheet(sheetCompletion: ((Bool) -> Void)?) -> ActionSheetController
    func createDeleteThreadActionSheet(sheetCompletion: ((Bool) -> Void)?) -> ActionSheetController

    // Invoked when the controller requests dismissal
    func nameCollisionControllerDidComplete(_ controller: NameCollisionResolutionViewController, dismissConversationView: Bool)
}

class NameCollisionResolutionViewController: OWSTableViewController2 {
    private let collisionFinder: NameCollisionFinder
    private var thread: TSThread { collisionFinder.thread }
    private var groupViewHelper: GroupViewHelper?
    private weak var collisionDelegate: NameCollisionResolutionDelegate?

    // The actual table UI doesn't section off one collision from the next
    // As a convenience, here's a flattened window of cell models
    private var flattenedCellModels: [NameCollisionCellModel] { cellModels.lazy.flatMap { $0 } }
    private var cellModels: [[NameCollisionCellModel]] = [] {
        didSet {
            if cellModels.count == 0 || cellModels.allSatisfy({ $0.count <= 1 }) {
                databaseStorage.asyncWrite { writeTx in
                    self.collisionFinder.markCollisionsAsResolved(transaction: writeTx)
                }
                collisionDelegate?.nameCollisionControllerDidComplete(self, dismissConversationView: false)
            } else {
                updateTableContents()
            }
        }
    }

    init(collisionFinder: NameCollisionFinder, collisionDelegate: NameCollisionResolutionDelegate) {
        self.collisionFinder = collisionFinder
        self.collisionDelegate = collisionDelegate
        super.init()

        contactsViewHelper.addObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateModel()
        tableView.separatorStyle = .none
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationItem.leftBarButtonItem = nil
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(donePressed))
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { _ in
            // Force tableview to recalculate self-sized cell height
            self.tableView.beginUpdates()
            self.tableView.endUpdates()
        }
    }

    func updateModel() {
        cellModels = databaseStorage.read(block: { readTx in
            if self.groupViewHelper == nil, self.thread.isGroupThread {
                let threadViewModel = ThreadViewModel(thread: self.thread, forChatList: false, transaction: readTx)
                self.groupViewHelper = GroupViewHelper(threadViewModel: threadViewModel)
                self.groupViewHelper?.delegate = self
            }

            let standardSort = self.collisionFinder.findCollisions(transaction: readTx).standardSort(readTx: readTx)
            guard standardSort.count > 0, standardSort.allSatisfy({ $0.elements.count >= 2 }) else { return [] }

            let sortedCollisions: [NameCollision]
            if let contactAddress = (self.thread as? TSContactThread)?.contactAddress,
               standardSort.count == 1,
               let requesterIndex = standardSort[0].elements.firstIndex(where: { $0.address == contactAddress }) {
                // If we're in a contact thread, the one exception to the standard sorting of collisions
                // is that the message requester should appear first
                var collidingElements = standardSort[0].elements
                let requesterElement = collidingElements.remove(at: requesterIndex)
                collidingElements.insert(requesterElement, at: 0)
                sortedCollisions = [NameCollision(collidingElements)]
            } else {
                sortedCollisions = standardSort
            }

            return sortedCollisions.map { $0.collisionCellModels(thread: self.thread, transaction: readTx) }
        })
    }

    func updateTableContents() {
        let titleString: String
        if thread.isGroupThread {
            titleString = OWSLocalizedString(
                "GROUP_MEMBERSHIP_NAME_COLLISION_TITLE",
                comment: "A title string for a view that allows a user to review name collisions in group membership")
        } else {
            titleString = OWSLocalizedString(
                "MESSAGE_REQUEST_NAME_COLLISON_TITLE",
                comment: "A title string for a view that allows a user to review name collisions for an incoming message request")
        }

        contents = OWSTableContents(
            title: titleString,
            sections: [
                createHeaderSection()
            ] + flattenedCellModels.map {
                createSection(for: $0)
            })
    }

    func createHeaderSection() -> OWSTableSection {
        OWSTableSection(header: {
            let view = UIView()
            let label = UILabel()

            label.textColor = Theme.secondaryTextAndIconColor
            label.font = UIFont.dynamicTypeFootnote
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 0

            if thread.isGroupThread, cellModels.count >= 2 {
                let format = OWSLocalizedString(
                    "GROUP_MEMBERSHIP_NAME_MULTIPLE_COLLISION_HEADER_%d", tableName: "PluralAware",
                    comment: "A header string informing the user about a name collision in group membership. Embeds {{ total number of colliding members }}")
                label.text = String.localizedStringWithFormat(format, flattenedCellModels.count)
            } else if thread.isGroupThread {
                let format = OWSLocalizedString(
                    "GROUP_MEMBERSHIP_NAME_SINGLE_COLLISION_HEADER_%d", tableName: "PluralAware",
                    comment: "A header string informing the user about a name collision in group membership. Embeds {{ total number of colliding members }}")
                label.text = String.localizedStringWithFormat(format, flattenedCellModels.count)
            } else {
                label.text = OWSLocalizedString(
                    "MESSAGE_REQUEST_NAME_COLLISON_HEADER",
                    comment: "A header string informing the user about name collisions in a message request")
            }

            view.addSubview(label)
            label.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 24, leading: 16, bottom: 16, trailing: 16))
            return view
        })
    }

    func createSection(for model: NameCollisionCellModel) -> OWSTableSection {
        let requesterHeader = OWSLocalizedString(
            "MESSAGE_REQUEST_NAME_COLLISON_REQUESTER_HEADER",
            comment: "A header string above the requester's contact info")
        let contactHeader = OWSLocalizedString(
            "MESSAGE_REQUEST_NAME_COLLISON_CONTACT_HEADER",
            comment: "A header string above a known contact's contact info")
        let groupMemberHeader = OWSLocalizedString(
            "GROUP_MEMBERSHIP_NAME_COLLISION_MEMBER_HEADER",
            comment: "A header string above a group member's contact info")
        let updateContactActionString = OWSLocalizedString(
            "MESSAGE_REQUEST_NAME_COLLISON_UPDATE_CONTACT_ACTION",
            comment: "A button that updates a known contact's information to resolve a name collision")
        let deleteActionString = OWSLocalizedString(
            "MESSAGE_REQUEST_VIEW_DELETE_BUTTON",
            comment: "incoming message request button text which deletes a conversation")
        let blockActionString = OWSLocalizedString(
            "MESSAGE_REQUEST_VIEW_BLOCK_BUTTON",
            comment: "A button used to block a user on an incoming message request.")
        let removeActionString = OWSLocalizedString(
            "CONVERSATION_SETTINGS_REMOVE_FROM_GROUP_BUTTON",
            comment: "Label for 'remove from group' button in conversation settings view.")

        let header: String = {
            switch (thread: thread, model: model) {
            case (thread: is TSContactThread, let model) where model.address == flattenedCellModels.first?.address:
                return requesterHeader
            case (thread: is TSContactThread, _):
                return contactHeader
            case (thread: is TSGroupThread, let model) where model.isSystemContact:
                return contactHeader
            case (thread: is TSGroupThread, _):
                return groupMemberHeader
            default:
                owsFailDebug("Unknown header type")
                return contactHeader
            }
        }()

        let actions: [NameCollisionCell.Action] = {
            switch (thread: thread, address: model.address, isBlocked: model.isBlocked) {
            case (thread: is TSContactThread, address: flattenedCellModels.first?.address, isBlocked: false):
                return [
                    (title: deleteActionString, action: { [weak self] in self?.deleteThread() }),
                    (title: blockActionString, action: { [weak self] in self?.blockThread() })
                ]
            case (thread: is TSContactThread, address: flattenedCellModels.first?.address, isBlocked: true):
                return [(title: deleteActionString, action: { [weak self] in self?.deleteThread() })]

            case (_, let address, _) where shouldShowContactUpdateAction(for: address):
                return [(title: updateContactActionString, action: { [weak self] in self?.presentUpdateContactViewController(for: address) })]

            case (thread: is TSGroupThread, let address, _) where
                    !address.isLocalAddress && groupViewHelper?.canRemoveFromGroup(address: model.address) == true:
                return [(title: removeActionString, action: { [weak self] in self?.removeFromGroup(model.address) })]

            case (thread: is TSGroupThread, let address, isBlocked: false) where !address.isLocalAddress:
                return [(title: blockActionString, action: { [weak self] in self?.blockAddress(model.address) })]

            default:
                return []
            }
        }()

        return OWSTableSection(title: header, items: [
            OWSTableItem(customCellBlock: {
                NameCollisionCell.createWithModel(model, actions: actions)
            },
            actionBlock: { [weak self] in
                guard let self = self else { return }
                MemberActionSheet(
                    address: model.address,
                    groupViewHelper: self.groupViewHelper,
                    spoilerState: SpoilerRenderState() // no need to share
                ).present(from: self)
            }
            )
        ])
    }

    // MARK: - Resolution Actions

    private func deleteThread() {
        guard let collisionDelegate = collisionDelegate else { return }

        presentActionSheet(collisionDelegate.createDeleteThreadActionSheet { [weak self] shouldDismiss in
            if shouldDismiss {
                guard let self = self else { return }
                collisionDelegate.nameCollisionControllerDidComplete(self, dismissConversationView: true)
            }
        })
    }

    private func blockThread() {
        guard let collisionDelegate = collisionDelegate else { return }

        presentActionSheet(collisionDelegate.createBlockThreadActionSheet { [weak self] shouldDismiss in
            if shouldDismiss {
                guard let self = self else { return }
                collisionDelegate.nameCollisionControllerDidComplete(self, dismissConversationView: true)
            }
        })
    }

    private func blockAddress(_ address: SignalServiceAddress) {
        BlockListUIUtils.showBlockAddressActionSheet(address, from: self) { [weak self] (didBlock) in
            if didBlock {
                self?.updateModel()
            }
        }
    }

    private func removeFromGroup(_ address: SignalServiceAddress) {
        groupViewHelper?.presentRemoveFromGroupActionSheet(address: address)
        // groupViewHelper will call out to its delegate (us) when the membership
    }

    private func presentUpdateContactViewController(for address: SignalServiceAddress) {
        contactsViewHelper.presentSystemContactsFlow(
            CreateOrEditContactFlow(address: address),
            from: self
        )
        // We observe contact updates and will automatically update our model in response
    }

    @objc
    private func donePressed(_ sender: UIBarButtonItem) {
        // When the user presses done, implicitly mark the remaining collisions as resolved (if the finder supports it)
        // Note: We only do this for dismissal via "Done". If the user uses interactive sheet dismissal, leave the
        // collisions as-is.
        databaseStorage.write { writeTx in
            self.collisionFinder.markCollisionsAsResolved(transaction: writeTx)
        }
        collisionDelegate?.nameCollisionControllerDidComplete(self, dismissConversationView: false)
    }
}

// MARK: - Contacts

extension NameCollisionResolutionViewController: ContactsViewHelperObserver {

    func shouldShowContactUpdateAction(for address: SignalServiceAddress) -> Bool {
        guard contactsManagerImpl.isEditingAllowed else {
            return false
        }
        return databaseStorage.read { transaction in
            contactsManager.isSystemContact(address: address, transaction: transaction)
        }
    }

    func contactsViewHelperDidUpdateContacts() {
        updateModel()
    }
}

extension NameCollisionResolutionViewController: GroupViewHelperDelegate {
    func groupViewHelperDidUpdateGroup() {
        updateModel()
    }

    var currentGroupModel: TSGroupModel? { (thread as? TSGroupThread)?.groupModel }

    var fromViewController: UIViewController? { self }
}
