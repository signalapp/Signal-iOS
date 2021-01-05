//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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

    func createPendingJoinRequestBanner(viewState: CVViewState,
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

    func createMigrateGroupBanner(viewState: CVViewState,
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

    func createDroppedGroupMembersBannerIfNecessary(viewState: CVViewState) -> UIView? {
        guard let droppedMembersInfo = buildDroppedMembersInfo() else {
            return nil
        }
        return createDroppedGroupMembersBanner(viewState: viewState,
                                               droppedMembersInfo: droppedMembersInfo)
    }

    // MARK: - Name collision banners

    func createMessageRequestNameCollisionBannerIfNecessary(viewState: CVViewState) -> UIView? {
        guard !viewState.isMessageRequestNameCollisionBannerHidden else { return nil }
        guard viewState.threadViewModel.isContactThread else { return nil }

        guard databaseStorage.uiRead(block: { readTx in
            MessageRequestNameCollisionViewController.shouldShowBanner(
                for: viewState.threadViewModel.threadRecord,
                transaction: readTx)
        }) else { return nil }

        let banner = MessageRequestNameCollisionBanner()

        banner.closeAction = { [weak self] in
            viewState.isMessageRequestNameCollisionBannerHidden = true
            self?.ensureBannerState()
        }

        banner.reviewAction = { [weak self] in
            guard let self = self else { return }
            guard let contactThread = self.thread as? TSContactThread else {
                return owsFailDebug("Unexpected thread type")
            }

            let vc = MessageRequestNameCollisionViewController(thread: contactThread, collisionDelegate: self)
            vc.present(from: self)
        }

        return banner
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

    func createDroppedGroupMembersBanner(viewState: CVViewState,
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

private class MessageRequestNameCollisionBanner: UIView {

    var reviewAction: () -> Void {
        get { reviewButton.block }
        set { reviewButton.block = newValue }
    }

    var closeAction: () -> Void {
        get { closeButton.block }
        set { closeButton.block = newValue }
    }

    private let label: UILabel = {
        let labelText = NSLocalizedString(
            "MESSAGE_REQUEST_NAME_COLLISON_BANNER_LABEL",
            comment: "Banner label notifying user that a new message is from a user with the same name as an existing contact")

        let label = UILabel()
        label.text = labelText
        label.numberOfLines = 0
        label.font = UIFont.ows_dynamicTypeFootnote
        label.textColor = Theme.secondaryTextAndIconColor
        return label
    }()

    private let infoIcon: UIImageView = {
        let icon = UIImageView.withTemplateImageName(
            "info-outline-24",
            tintColor: Theme.secondaryTextAndIconColor)
        icon.setCompressionResistanceHigh()
        icon.setContentHuggingHigh()
        return icon
    }()

    private let closeButton: OWSButton = {
        let button = OWSButton(
            imageName: "x-circle-16",
            tintColor: Theme.secondaryTextAndIconColor)
        button.accessibilityLabel = NSLocalizedString("BANNER_CLOSE_ACCESSIBILITY_LABEL",
            comment: "Accessibility label for banner close button")
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setCompressionResistanceHigh()
        button.setContentHuggingHigh()
        return button
    }()

    private let reviewButton: OWSButton = {
        let buttonText = NSLocalizedString("MESSAGE_REQUEST_REVIEW_NAME_COLLISION",
            comment: "Button to allow user to review known name collisions with an incoming message request")

        let button = OWSButton(title: buttonText)
        button.setTitleColor(Theme.accentBlueColor, for: .normal)
        button.setTitleColor(Theme.accentBlueColor.withAlphaComponent(0.7), for: .highlighted)
        button.titleLabel?.font = UIFont.ows_dynamicTypeFootnote
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.secondaryBackgroundColor

        [infoIcon, label, closeButton, reviewButton]
            .forEach { addSubview($0) }

        // Note that UIButtons are being aligned based on their content subviews
        // UIButtons this small will have an intrinsic size larger than their content
        // That extra padding between the content and its frame messes up alignment
        label.autoPinEdge(toSuperviewEdge: .top, withInset: 12)
        infoIcon.autoPinEdge(.top, to: .top, of: label)
        closeButton.imageView?.autoPinEdge(.top, to: .top, of: label)
        reviewButton.titleLabel?.autoPinEdge(.top, to: .bottom, of: label, withOffset: 3)
        reviewButton.titleLabel?.autoPinEdge(.bottom, to: .bottom, of: self, withOffset: -12)

        // Aligning things this way is useful, because we can also increase the tap target
        // for the tiny close button without messing up the appearance.
        closeButton.contentEdgeInsets = UIEdgeInsets(hMargin: 8, vMargin: 8)

        infoIcon.autoPinLeading(toEdgeOf: self, offset: 16)
        label.autoPinLeading(toTrailingEdgeOf: infoIcon, offset: 16)
        closeButton.imageView?.autoPinLeading(toTrailingEdgeOf: label, offset: 16)
        closeButton.imageView?.autoPinTrailing(toEdgeOf: self, offset: -16)
        reviewButton.titleLabel?.autoPinLeading(toEdgeOf: label)

        accessibilityElements = [label, reviewButton, closeButton]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
