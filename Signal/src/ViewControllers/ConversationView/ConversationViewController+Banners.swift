//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension ConversationViewController {

    static func createBannerWithTitle(title: String,
                                      bannerColor: UIColor,
                                      tapBlock: @escaping () -> Void) -> UIView {
        owsAssertDebug(title.count > 0)

        let bannerView = GestureView()
        bannerView.addTap(block: tapBlock)
        bannerView.backgroundColor = bannerColor
        bannerView.accessibilityIdentifier = "banner_close"

        let label = buildBannerLabel(title: title)
        label.textAlignment = .center

        let closeIcon = UIImage(named: "banner_close")!
        let closeButton = UIImageView(image: closeIcon)
        bannerView.addSubview(closeButton)
        let kBannerCloseButtonPadding: CGFloat = 8
        closeButton.autoPinEdge(toSuperviewEdge: .top, withInset: kBannerCloseButtonPadding)
        closeButton.autoPinTrailingToSuperviewMargin(withInset: kBannerCloseButtonPadding)
        closeButton.autoSetDimensions(to: closeIcon.size)

        bannerView.addSubview(label)
        label.autoPinEdge(toSuperviewEdge: .top, withInset: 5)
        label.autoPinEdge(toSuperviewEdge: .bottom, withInset: 5)
        let kBannerHPadding: CGFloat = 15
        label.autoPinLeadingToSuperviewMargin(withInset: kBannerHPadding)
        let kBannerHSpacing: CGFloat = 10
        closeButton.autoPinTrailing(toEdgeOf: label, offset: kBannerHSpacing)

        return bannerView
    }

    // MARK: - Pending Join Requests Banner

    func createPendingJoinRequestBanner(viewState: CVCViewState,
                                        count pendingMemberRequestCount: UInt,
                                        viewMemberRequestsBlock: @escaping () -> Void) -> UIView {
        owsAssertDebug(pendingMemberRequestCount > 0)

        let format = NSLocalizedString("PENDING_GROUP_MEMBERS_REQUEST_BANNER_FORMAT",
                                       comment: "Format for banner indicating that there are pending member requests to join the group. Embeds {{ the number of pending member requests }}.")
        let title = String(format: format, OWSFormat.formatUInt(pendingMemberRequestCount))

        let dismissButton = OWSButton(title: CommonStrings.dismissButton) { [weak self] in
            AssertIsOnMainThread()
            viewState.isPendingMemberRequestsBannerHidden = true
            self?.ensureBannerState()
        }
        dismissButton.titleLabel?.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold
        let viewRequestsLabel = NSLocalizedString("PENDING_GROUP_MEMBERS_REQUEST_BANNER_VIEW_REQUESTS",
                                                  comment: "Label for the 'view requests' button in the pending member requests banner.")
        let viewRequestsButton = OWSButton(title: viewRequestsLabel, block: viewMemberRequestsBlock)
        viewRequestsButton.titleLabel?.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold

        return Self.createBanner(title: title,
                                 buttons: [dismissButton, viewRequestsButton],
                                 accessibilityIdentifier: "pending_group_request_banner")
    }

    // MARK: - Manual Migration Banner

    var manualMigrationInfoForGroup: GroupsV2MigrationInfo? {
        guard GroupManager.canManuallyMigrate else {
            return nil
        }
        guard let groupThread = thread as? TSGroupThread,
            groupThread.isGroupV1Thread else {
                return nil
        }
        guard groupThread.isLocalUserFullMember else {
            return nil
        }

        // migrationInfoForManualMigrationWithGroupThread uses
        // a transaction, so we try to avoid calling it.
        return GroupsV2Migration.migrationInfoForManualMigration(groupThread: groupThread)
    }

    func createMigrateGroupBanner(viewState: CVCViewState,
                                  migrationInfo: GroupsV2MigrationInfo) -> UIView {

        let title = NSLocalizedString("GROUPS_LEGACY_GROUP_MIGRATE_GROUP_OFFER_BANNER",
                                      comment: "Title for the the 'migrate group' banner.")

        let notNowButton = OWSButton(title: CommonStrings.notNowButton) { [weak self] in
            AssertIsOnMainThread()
            viewState.isMigrateGroupBannerHidden = true
            self?.ensureBannerState()
        }
        notNowButton.titleLabel?.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold

        let migrateButtonText = NSLocalizedString("GROUPS_LEGACY_GROUP_MIGRATE_GROUP_MIGRATE_BUTTON",
                                                  comment: "Label for the 'migrate' button in the 'migrate group' banner.")
        let migrateButton = OWSButton(title: migrateButtonText) { [weak self] in
            self?.migrateGroupPressed(migrationInfo: migrationInfo)
        }
        migrateButton.titleLabel?.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold

        return Self.createBanner(title: title,
                                 buttons: [notNowButton, migrateButton],
                                 accessibilityIdentifier: "migrate_group_banner")
    }

    private func migrateGroupPressed(migrationInfo: GroupsV2MigrationInfo) {
        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return
        }
        showManualMigrationAlert(groupThread: groupThread, migrationInfo: migrationInfo)
    }

    // MARK: - Dropped Group Members Banner

    func createDroppedGroupMembersBannerIfNecessary(viewState: CVCViewState) -> UIView? {
        guard let droppedMembersInfo = buildDroppedMembersInfo() else {
            return nil
        }
        return createDroppedGroupMembersBanner(viewState: viewState,
                                               droppedMembersInfo: droppedMembersInfo)
    }
}

// MARK: -

fileprivate extension ConversationViewController {

    struct DroppedMembersInfo {
        let groupThread: TSGroupThread
        let addableMembers: Set<SignalServiceAddress>
    }

    func buildDroppedMembersInfo() -> DroppedMembersInfo? {
        guard let groupThread = thread as? TSGroupThread else {
            return nil
        }
        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            return nil
        }
        guard groupThread.isLocalUserFullMember else {
            return nil
        }

        var addableMembers = Set<SignalServiceAddress>()
        Self.databaseStorage.read { transaction in
            for address in groupModel.droppedMembers {
                guard address.uuid != nil else {
                    continue
                }
                guard GroupsV2Migration.doesUserHaveBothCapabilities(address: address, transaction: transaction) else {
                    continue
                }
                addableMembers.insert(address)
            }
        }
        guard !addableMembers.isEmpty else {
            return nil
        }
        let droppedMembersInfo = DroppedMembersInfo(groupThread: groupThread,
                                                    addableMembers: addableMembers)
        return droppedMembersInfo
    }

    func createDroppedGroupMembersBanner(viewState: CVCViewState,
                                         droppedMembersInfo: DroppedMembersInfo) -> UIView {

        let title: String
        if droppedMembersInfo.addableMembers.count > 1 {
            let titleFormat = NSLocalizedString("GROUPS_LEGACY_GROUP_DROPPED_MEMBERS_BANNER_N_FORMAT",
                                                comment: "Format for the title for the the 'dropped group members' banner. Embeds: {{ the number of dropped group members }}.")
            title = String(format: titleFormat, OWSFormat.formatInt(droppedMembersInfo.addableMembers.count))
        } else {
            title = NSLocalizedString("GROUPS_LEGACY_GROUP_DROPPED_MEMBERS_BANNER_1",
                                      comment: "Title for the the 'dropped group member' banner.")
        }

        let notNowButton = OWSButton(title: CommonStrings.notNowButton) { [weak self] in
            AssertIsOnMainThread()
            viewState.isDroppedGroupMembersBannerHidden = true
            self?.ensureBannerState()
        }
        notNowButton.titleLabel?.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold

        let addMembersButtonText = NSLocalizedString("GROUPS_LEGACY_GROUP_RE_ADD_DROPPED_GROUP_MEMBERS_BUTTON",
                                                     comment: "Label for the 'add members' button in the 're-add dropped groups members' banner.")
        let addMembersButton = OWSButton(title: addMembersButtonText) { [weak self] in
            self?.reAddDroppedGroupMembers(droppedMembersInfo: droppedMembersInfo)
        }
        addMembersButton.titleLabel?.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold

        return Self.createBanner(title: title,
                                 buttons: [notNowButton, addMembersButton],
                                 accessibilityIdentifier: "dropped_group_members_banner")
    }

    func reAddDroppedGroupMembers(droppedMembersInfo: DroppedMembersInfo) {
        let mode = GroupMigrationActionSheet.Mode.reAddDroppedMembers(members: droppedMembersInfo.addableMembers)
        let view = GroupMigrationActionSheet(groupThread: droppedMembersInfo.groupThread, mode: mode)
        view.present(fromViewController: self)
    }

    // MARK: -

    static func buildBannerLabel(title: String) -> UILabel {
        let label = UILabel()
        label.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold
        label.text = title
        label.textColor = .white
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }

    static func createBanner(title: String,
                             buttons: [UIView],
                             accessibilityIdentifier: String) -> UIView {

        let titleLabel = buildBannerLabel(title: title)
        titleLabel.font = .ows_dynamicTypeSubheadlineClamped

        let buttonRow = UIStackView(arrangedSubviews: [UIView.hStretchingSpacer()] + buttons)
        buttonRow.axis = .horizontal
        buttonRow.spacing = 24

        let bannerView = UIStackView(arrangedSubviews: [ titleLabel, buttonRow ])
        bannerView.axis = .vertical
        bannerView.alignment = .fill
        bannerView.spacing = 10
        bannerView.layoutMargins = UIEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        bannerView.isLayoutMarginsRelativeArrangement = true
        bannerView.addBackgroundView(withBackgroundColor: .ows_accentBlue)
        bannerView.accessibilityIdentifier = accessibilityIdentifier
        return bannerView
    }
}

// MARK: -

// A convenience view that allows block-based gesture handling.
@objc
public class GestureView: UIView {
    @objc
    public required init() {
        super.init(frame: .zero)

        self.layoutMargins = .zero
    }

    @available(*, unavailable, message:"use other constructor instead.")
    @objc
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    public typealias BlockType = () -> Void

    private var tapBlock: BlockType?

    @objc
    public func addTap(block tapBlock: @escaping () -> Void) {
        owsAssertDebug(self.tapBlock == nil)

        self.tapBlock = tapBlock
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap(_:))))
    }

    // MARK: - Events

    @objc
    func didTap(_ sender: UITapGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        guard let tapBlock = tapBlock else {
            owsFailDebug("Missing tapBlock.")
            return
        }
        tapBlock()
    }
}
