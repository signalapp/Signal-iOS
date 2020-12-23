//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import ContactsUI

protocol MessageRequestNameCollisionDelegate: class {
    func createBlockActionSheet(sheetCompletion: ((Bool) -> Void)?) -> ActionSheetController
    func createDeleteActionSheet(sheetCompletion: ((Bool) -> Void)?) -> ActionSheetController

    func nameCollisionController(_ controller: MessageRequestNameCollisionViewController, didResolveCollisions: Bool)
}

class MessageRequestNameCollisionViewController: OWSTableViewController {

    private let thread: TSContactThread
    private var requesterModel: NameCollisionModel?
    private var collisionModels: [NameCollisionModel]?
    private weak var collisionDelegate: MessageRequestNameCollisionDelegate?

    init(thread: TSContactThread, collisionDelegate: MessageRequestNameCollisionDelegate) {
        self.thread = thread
        self.collisionDelegate = collisionDelegate
        super.init()

        useThemeBackgroundColors = true
        contactsViewHelper.addObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateModel()
    }

    func updateModel() {
        databaseStorage.uiRead { readTx in
            self.requesterModel = NameCollisionModel.buildFromAddress(
                address: self.thread.contactAddress,
                transaction: readTx)

            self.collisionModels = Self.collidingAddresses(
                for: self.thread.contactAddress,
                transaction: readTx)
                .map { address in
                    NameCollisionModel.buildFromAddress(address: address, transaction: readTx)
                }
        }

        if collisionModels?.count == 0 {
            Logger.info("No collisions remaining")
            self.collisionDelegate?.nameCollisionController(self, didResolveCollisions: true)
        } else {
            updateTableContents()
        }
    }

    func updateTableContents() {
        guard let requesterModel = requesterModel, let collisionModels = collisionModels else {
            return owsFailDebug("Models haven't been initialized")
        }
        owsAssertDebug(collisionModels.count > 0)

        contents = OWSTableContents(
            title: "Review Request",
            sections: [
                createHeaderSection(),
                createRequesterSection(model: requesterModel)
            ] + collisionModels.map {
                createCollisionSection(model: $0)
            })
    }

    func createHeaderSection() -> OWSTableSection {
        OWSTableSection(header: {
            let view = UIView()
            let label = UILabel()

            label.textColor = Theme.secondaryTextAndIconColor
            label.font = UIFont.ows_dynamicTypeFootnote
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 0

            label.text = "If you’re not sure who the request is from, review the contacts below and take action."

            view.addSubview(label)
            label.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 24, leading: 16, bottom: 16, trailing: 16))
            return view
        })
    }

    func createRequesterSection(model: NameCollisionModel) -> OWSTableSection {
        let contactInfoCell = NameCollisionReviewContactCell.createWithModel(model)
        contactInfoCell.isPairedWithActions = true

        var actions: [NameCollisionActionCell.Action] = [
            (title: "Delete", action: { [weak self] in
                self?.delete()
            })
        ]
        if !model.isBlocked {
            actions.append((title: "Block", action: { [weak self] in
                self?.block()
            }))
        }

        return OWSTableSection(title: "Request", items: [
            OWSTableItem(customCell: contactInfoCell),
            OWSTableItem(customCell: NameCollisionActionCell(actions: actions))
        ])
    }

    func createCollisionSection(model: NameCollisionModel) -> OWSTableSection {
        let contactInfoCell = NameCollisionReviewContactCell.createWithModel(model)
        contactInfoCell.isPairedWithActions = false

        let section = OWSTableSection(title: "Your Contact", items: [
            OWSTableItem(customCell: contactInfoCell)
        ])

        guard shouldShowContactUpdateAction(for: model.address) else {
            return section
        }

        contactInfoCell.isPairedWithActions = true

        let actionCell = NameCollisionActionCell(actions: [
            (title: "Update Contact", action: { [weak self] in
                self?.presentContactUpdateSheet(for: model.address)
            })
        ])

        section.add(OWSTableItem(customCell: actionCell))
        contactInfoCell.isPairedWithActions = true
        return section
    }

    private func delete() {
        guard let collisionDelegate = collisionDelegate else { return }

        presentActionSheet(collisionDelegate.createDeleteActionSheet() { [weak self] shouldDismiss in
            if shouldDismiss {
                guard let self = self else { return }
                self.collisionDelegate?.nameCollisionController(self, didResolveCollisions: false)
            }
        })
    }

    private func block() {
        guard let collisionDelegate = collisionDelegate else { return }

        presentActionSheet(collisionDelegate.createBlockActionSheet() { [weak self] shouldDismiss in
            if shouldDismiss {
                guard let self = self else { return }
                self.collisionDelegate?.nameCollisionController(self, didResolveCollisions: false)
            }
        })
    }
}

// MARK: - Banner

extension MessageRequestNameCollisionViewController {

    static func collidingAddresses(
        for address: SignalServiceAddress,
        transaction readTx: SDSAnyReadTransaction
        ) -> [SignalServiceAddress] {

        let displayName = address.getDisplayName(transaction: readTx)
        let possibleMatches = self.contactsViewHelper.signalAccounts(
            matchingSearch: displayName,
            transaction: readTx)

        // TODO: Check with design. Should we consult...
        // -[ContactsViewHelper nonSignalContactsMatchingSearchString:]

        // ContactsViewHelper uses substring matching, so it might return false positives
        // Filter to just the matches that have identical names
        return possibleMatches
            .map { $0.recipientAddress }
            .filter { $0.getDisplayName(transaction: readTx) == displayName }
            .filter { !$0.isLocalAddress && $0 != address }
    }

    static func shouldShowBanner(for thread: TSThread, transaction readTx: SDSAnyReadTransaction) -> Bool {
        guard let contactThread = thread as? TSContactThread else { return false }
        guard contactThread.hasPendingMessageRequest(transaction: readTx.unwrapGrdbRead) else { return false }

        return collidingAddresses(for: contactThread.contactAddress, transaction: readTx).count > 0
    }
}

// MARK: - Contacts

extension MessageRequestNameCollisionViewController: CNContactViewControllerDelegate, ContactsViewHelperObserver {

    func shouldShowContactUpdateAction(for address: SignalServiceAddress) -> Bool {
        return contactsManager.isSystemContact(address: address) && contactsManager.supportsContactEditing
    }

    func presentContactUpdateSheet(for address: SignalServiceAddress) {
        owsAssertDebug(navigationController != nil)
        guard contactsManager.supportsContactEditing else {
            return owsFailDebug("Contact editing unsupported")
        }
        guard let contactVC = contactsViewHelper.contactViewController(for: address, editImmediately: true) else {
            return owsFailDebug("Failed to create contact view controller")
        }

        contactVC.delegate = self
        navigationController?.pushViewController(contactVC, animated: true)
    }

    func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        DispatchQueue.main.async {
            self.navigationController?.popToViewController(self, animated: true)
        }
    }

    func contactsViewHelperDidUpdateContacts() {
        updateModel()
    }
}

// MARK: - Helpers

fileprivate extension SignalServiceAddress {
    func getDisplayName(transaction readTx: SDSAnyReadTransaction) -> String {
        Environment.shared.contactsManager.displayName(for: self, transaction: readTx)
    }
}

fileprivate extension NameCollisionModel {
    static func buildFromAddress(
        address: SignalServiceAddress,
        transaction readTx: SDSAnyReadTransaction) -> NameCollisionModel {

        let commonGroups = TSGroupThread.groupThreads(with: address, transaction: readTx)
        let commonGroupsString: String
        switch commonGroups.count {
        case 0:
            commonGroupsString = "No groups in common"
        case 1:
            commonGroupsString = "Member of \(commonGroups[0].groupNameOrDefault)"
        case 2...:
            commonGroupsString = "\(commonGroups.count) groups in common"
        default:
            owsFailDebug("Invalid groups count")
            commonGroupsString = "No groups in common"
        }

        let avatar = OWSContactAvatarBuilder.buildImage(
            address: address,
            diameter: 64,
            transaction: readTx)

        let isBlocked = OWSBlockingManager.shared().isAddressBlocked(address)

        return NameCollisionModel(
            address: address,
            name: address.getDisplayName(transaction: readTx),
            commonGroupsString: commonGroupsString,
            avatar: avatar,
            oldName: nil,
            isBlocked: isBlocked)
    }
}
