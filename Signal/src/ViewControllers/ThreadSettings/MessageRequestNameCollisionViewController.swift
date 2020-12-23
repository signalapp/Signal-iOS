//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class MessageRequestNameCollisionViewController: OWSTableViewController {

    let thread: TSContactThread
    var requesterModel: NameCollisionModel?
    var collisionModels: [NameCollisionModel]?

    init(thread: TSContactThread) {
        self.thread = thread
        super.init()
        useThemeBackgroundColors = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateModel()
        updateTableContents()
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
                    NameCollisionModel.buildFromAddress(
                        address: address,
                        transaction: readTx)
                }
        }
    }

    func updateTableContents() {
        guard let requesterModel = requesterModel, let collisionModels = collisionModels else {
            return owsFailDebug("Models haven't been initialized")
        }
        owsAssertDebug(collisionModels.count > 0)

        let newContents = OWSTableContents()
        newContents.title = "Review Request"
        newContents.addSection(createHeaderSection())
        newContents.addSection(createRequesterSection(model: requesterModel))
        collisionModels.forEach {
            newContents.addSection(createCollisionSection(model: $0))
        }

        contents = newContents
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
        let actionCell = NameCollisionActionCell(
            actions: [
                (title: "Delete", action: {

                }),
                (title: "Block", action: {

                })
            ])

        return OWSTableSection(
            title: "Request",
            items: [
                OWSTableItem(
                    customCell: contactInfoCell,
                    customRowHeight: UITableView.automaticDimension,
                    actionBlock: nil),

                OWSTableItem(
                    customCell: actionCell,
                    customRowHeight: UITableView.automaticDimension,
                    actionBlock: nil)
            ])
    }

    func createCollisionSection(model: NameCollisionModel) -> OWSTableSection {
        let contactInfoCell = NameCollisionReviewContactCell.createWithModel(model)
        let section = OWSTableSection(
            title: "Your Contact",
            items: [
                OWSTableItem(
                    customCell: contactInfoCell,
                    customRowHeight: UITableView.automaticDimension,
                    actionBlock: nil)
            ])

        if contactsManager.isSystemContact(address: model.address) {
            contactInfoCell.isPairedWithActions = true
            section.add(OWSTableItem(customCell: NameCollisionActionCell(actions: [
                (title: "Update Contact", action: {

                })
            ]), customRowHeight: UITableView.automaticDimension, actionBlock: nil))

        } else {
            contactInfoCell.isPairedWithActions = false
        }

        return section
    }

    // MARK: - Banner

    static func collidingAddresses(
        for address: SignalServiceAddress,
        transaction readTx: SDSAnyReadTransaction
    ) -> [SignalServiceAddress] {

        let displayName = address.getDisplayName(transaction: readTx)
        let possibleMatches = self.contactsViewHelper.signalAccounts(
            matchingSearch: displayName,
            transaction: readTx)

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

        return NameCollisionModel(
            address: address,
            name: address.getDisplayName(transaction: readTx),
            commonGroupsString: commonGroupsString,
            avatar: avatar,
            oldName: nil)
    }
}




/* struct NameCollision {
    struct Member {
        let address: SignalServiceAddress
        let oldName: String?
        let name: String
    }

    let thread: TSThread
    let collidingMembers: [Member]

    static func createMatchingAnyKnownAccount(to thread: TSContactThread) -> Self {
        return .init(thread: thread, collidingMembers: [])
    }

    static func createMatchingNames(within groupThread: TSGroupThread) -> Self {
        return .init(thread: groupThread, collidingMembers: [])
    }
} */







 /*
struct NameCollision {
    struct Member {
        let address: SignalServiceAddress

        let oldName: String?
        let name: String
        let commonGroupNames: [String]
    }
    let thread: TSGroupThread
    let collidingMembers: [Member]

    static func findNameCollisionsInGroup(_ thread: TSGroupThread, readTx: SDSAnyReadTransaction) -> [NameCollision] {
        return thread.groupMembership.fullMembers.compactMap { address in
            guard !address.isLocalAddress else { return nil }

            let name = Environment.shared.contactsManager.displayName(for: address)
            let commonGroupNames = TSGroupThread
                .groupThreads(with: address, transaction: readTx)
                .map { $0.groupNameOrDefault }

            return NameCollision(thread: thread, collidingMembers: [
                Member(address: address, oldName: nil, name: name, commonGroupNames: commonGroupNames)
            ])

        }
    }
}








class GroupNameCollisionViewController: OWSTableViewController {

    let collisionModel: NameCollision
    var isLocalUserAdmin: Bool {
        collisionModel.thread.groupMembership.isLocalUserFullMemberAndAdministrator
    }

    init(collisionModel: NameCollision) {
        self.collisionModel = collisionModel
        super.init()
    }

    override func viewDidLoad() {
        rebuildContents()
    }

    func rebuildContents() {
        self.contents = OWSTableContents(
            title: "Review Members",
            sections: collisionModel.collidingMembers.map { member in
                OWSTableSection(title: "Member", items: [
                    createMemberCell(for: member),
                    createRemoveButtonCell()
                ])
            })
    }

    func createMemberCell(for member: NameCollision.Member) -> OWSTableItem {

        OWSTableItem { () -> UITableViewCell in
            let cell = OWSTableItem.newCell()
            cell.contentView.backgroundColor = .blue
            cell.textLabel?.text = member.name
            return cell

        } actionBlock: {
        }

    }

    func createRemoveButtonCell() -> OWSTableItem {
        OWSTableItem(text: "Remove From Cell", actionBlock: {

        }, accessoryType: .none)
    }

    

}
*/
