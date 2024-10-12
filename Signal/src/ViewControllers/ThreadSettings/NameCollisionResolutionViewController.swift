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
                SSKEnvironment.shared.databaseStorageRef.asyncWrite { writeTx in
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

        SUIEnvironment.shared.contactsViewHelperRef.addObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateModel()
        tableView.separatorStyle = .none
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationItem.leftBarButtonItem = .doneButton { [weak self] in
            self?.donePressed()
        }
        navigationItem.rightBarButtonItem = nil
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
        cellModels = SSKEnvironment.shared.databaseStorageRef.read { readTx -> [[NameCollisionCellModel]] in
            if self.groupViewHelper == nil, self.thread.isGroupThread {
                let threadViewModel = ThreadViewModel(thread: self.thread, forChatList: false, transaction: readTx)
                self.groupViewHelper = GroupViewHelper(threadViewModel: threadViewModel)
                self.groupViewHelper?.delegate = self
            }

            let collisions = self.collisionFinder.findCollisions(transaction: readTx)
            if collisions.isEmpty {
                return []
            }

            return collisions.map { $0.collisionCellModels(
                thread: self.thread,
                identityManager: DependenciesBridge.shared.identityManager,
                profileManager: SSKEnvironment.shared.profileManagerRef,
                blockingManager: SSKEnvironment.shared.blockingManagerRef,
                contactsManager: SSKEnvironment.shared.contactManagerRef,
                viewControllerForPresentation: self,
                tx: readTx
            ) }
        }
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

        let shouldShowSectionHeaders = cellModels.count > 1

        contents = OWSTableContents(
            title: titleString,
            sections: [
                createHeaderSection()
            ] + cellModels
                .map { model in
                    createSections(
                        for: model,
                        shouldShowHeader: shouldShowSectionHeaders
                    )
                }
                .flatMap { $0 }
        )
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
                    comment: "A header string informing the user about a name collision in group membership. Embeds {{ number of sets of colliding members }}")
                label.text = String.localizedStringWithFormat(format, cellModels.count)
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
            label.autoPinEdgesToSuperviewEdges(with: .init(hMargin: 32, vMargin: 12))
            return view
        })
    }

    private func createSections(
        for models: [NameCollisionCellModel],
        shouldShowHeader: Bool
    ) -> [OWSTableSection] {
        owsAssertDebug(models.count > 1)

        let title: String?
        if shouldShowHeader {
            let format = OWSLocalizedString(
                "GROUP_MEMBERSHIP_NAME_COLLISION_MEMBER_COUNT_%d",
                tableName: "PluralAware",
                comment: "A header string above a section of group members whose names conflict."
            )
            title = String.localizedStringWithFormat(format, models.count)
        } else {
            title = nil
        }

        return models.enumerated().map { index, model in
            OWSTableSection(
                title: index == 0 ? title : nil,
                items: [createCell(for: model)]
            )
        }
    }

    private func createCell(for model: NameCollisionCellModel) -> OWSTableItem {
        let action: NameCollisionCell.Action? = {
            switch (thread: thread, address: model.address, isBlocked: model.isBlocked) {
            case (thread: is TSContactThread, address: flattenedCellModels.first?.address, isBlocked: false):
                return .block { [weak self] in self?.blockThread() }

            case (thread: is TSContactThread, address: flattenedCellModels.first?.address, isBlocked: true):
                return .unblock { [weak self] in self?.unblock(address: model.address) }

            case (_, let address, _) where shouldShowContactUpdateAction(for: address):
                return .updateContact { [weak self] in self?.presentUpdateContactViewController(for: address) }

            case (thread: is TSGroupThread, let address, _) where
                    !address.isLocalAddress && groupViewHelper?.canRemoveFromGroup(address: model.address) == true:
                return .removeFromGroup { [weak self] in self?.removeFromGroup(model.address) }

            case (thread: is TSGroupThread, let address, isBlocked: false) where !address.isLocalAddress:
                return .block {[weak self] in self?.blockAddress(model.address) }

            default:
                return nil
            }
        }()

        return  OWSTableItem(
            customCellBlock: {
                NameCollisionCell.createWithModel(model, action: action)
            }, actionBlock: { [weak self] in
                guard let self = self else { return }
                ProfileSheetSheetCoordinator(
                    address: model.address,
                    groupViewHelper: self.groupViewHelper,
                    spoilerState: SpoilerRenderState() // no need to share
                ).presentAppropriateSheet(from: self)
            }
        )
    }

    // MARK: - Resolution Actions

    private func blockThread() {
        guard let collisionDelegate = collisionDelegate else { return }

        presentActionSheet(collisionDelegate.createBlockThreadActionSheet { [weak self] shouldDismiss in
            if shouldDismiss {
                guard let self = self else { return }
                collisionDelegate.nameCollisionControllerDidComplete(self, dismissConversationView: true)
            }
        })
    }

    private func unblock(address: SignalServiceAddress) {
        BlockListUIUtils.showUnblockThreadActionSheet(thread, from: self) { [weak self] didUnblock in
            guard let self, didUnblock else { return }
            self.updateModel()
        }
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
        SUIEnvironment.shared.contactsViewHelperRef.presentSystemContactsFlow(
            CreateOrEditContactFlow(address: address),
            from: self
        )
        // We observe contact updates and will automatically update our model in response
    }

    private func donePressed() {
        // When the user presses done, implicitly mark the remaining collisions as resolved (if the finder supports it)
        // Note: We only do this for dismissal via "Done". If the user uses interactive sheet dismissal, leave the
        // collisions as-is.
        SSKEnvironment.shared.databaseStorageRef.write { writeTx in
            self.collisionFinder.markCollisionsAsResolved(transaction: writeTx)
        }
        collisionDelegate?.nameCollisionControllerDidComplete(self, dismissConversationView: false)
    }
}

// MARK: - Contacts

extension NameCollisionResolutionViewController: ContactsViewHelperObserver {

    func shouldShowContactUpdateAction(for address: SignalServiceAddress) -> Bool {
        guard SSKEnvironment.shared.contactManagerImplRef.isEditingAllowed else {
            return false
        }
        return SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return SSKEnvironment.shared.contactManagerRef.fetchSignalAccount(for: address, transaction: transaction) != nil
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
