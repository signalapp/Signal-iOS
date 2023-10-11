//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

public extension ConversationViewController {

    static func createBanner(title: String,
                             bannerColor: UIColor,
                             tapBlock: @escaping () -> Void) -> UIView {
        owsAssertDebug(!title.isEmpty)

        let bannerView = GestureView()
        bannerView.addTap(block: tapBlock)
        bannerView.backgroundColor = bannerColor
        bannerView.accessibilityIdentifier = "banner_close"

        let label = buildBannerLabel(title: title)
        label.textAlignment = .center

        let closeIcon = UIImage(imageLiteralResourceName: "x-extra-small")
        let closeButton = UIImageView(image: closeIcon)
        closeButton.tintColor = .white
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

    func createPendingJoinRequestBanner(
        viewState: CVViewState,
        pendingMemberRequests: Set<SignalServiceAddress>,
        viewMemberRequestsBlock: @escaping () -> Void
    ) -> UIView {
        owsAssertDebug(!pendingMemberRequests.isEmpty)

        let format = OWSLocalizedString("PENDING_GROUP_MEMBERS_REQUEST_BANNER_%d", tableName: "PluralAware",
                                       comment: "Format for banner indicating that there are pending member requests to join the group. Embeds {{ the number of pending member requests }}.")
        let title = String.localizedStringWithFormat(format, pendingMemberRequests.count)

        let dismissButton = OWSButton(title: CommonStrings.dismissButton) { [weak self] in
            guard let self = self else { return }
            AssertIsOnMainThread()

            self.databaseStorage.write { transaction in
                viewState.hidePendingMemberRequestsBanner(
                    currentPendingMembers: pendingMemberRequests,
                    transaction: transaction
                )
            }

            self.ensureBannerState()
        }
        dismissButton.titleLabel?.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
        let viewRequestsLabel = OWSLocalizedString("PENDING_GROUP_MEMBERS_REQUEST_BANNER_VIEW_REQUESTS",
                                                  comment: "Label for the 'view requests' button in the pending member requests banner.")
        let viewRequestsButton = OWSButton(title: viewRequestsLabel, block: viewMemberRequestsBlock)
        viewRequestsButton.titleLabel?.font = UIFont.dynamicTypeSubheadlineClamped.semibold()

        return Self.createBanner(title: title,
                                 buttons: [dismissButton, viewRequestsButton],
                                 accessibilityIdentifier: "pending_group_request_banner")
    }

    // MARK: - Name collision banners

    func createMessageRequestNameCollisionBannerIfNecessary(viewState: CVViewState) -> UIView? {
        guard let contactThread = thread as? TSContactThread else { return nil }

        let collisionFinder = ContactThreadNameCollisionFinder
            .makeToCheckMessageRequestNameCollisions(forContactThread: contactThread)

        let collisionCount = databaseStorage.read { transaction -> Int in
            guard viewState.shouldShowMessageRequestNameCollisionBanner(transaction: transaction) else {
                // The banner should not be shown, so let's pretend we have no
                // collisions.
                return 0
            }

            return collisionFinder.findCollisions(transaction: transaction).count
        }

        guard collisionCount > 0 else {
            return nil
        }

        let banner = NameCollisionBanner()
        banner.labelText = OWSLocalizedString(
            "MESSAGE_REQUEST_NAME_COLLISON_BANNER_LABEL",
            comment: "Banner label notifying user that a new message is from a user with the same name as an existing contact")
        banner.reviewActionText = OWSLocalizedString(
            "MESSAGE_REQUEST_REVIEW_NAME_COLLISION",
            comment: "Button to allow user to review known name collisions with an incoming message request")

        banner.closeAction = { [weak self] in
            guard let self = self else { return }
            self.databaseStorage.write { viewState.hideMessageRequestNameCollisionBanner(transaction: $0) }
            self.ensureBannerState()
        }

        banner.reviewAction = { [weak self] in
            guard let self = self else { return }
            let vc = NameCollisionResolutionViewController(collisionFinder: collisionFinder, collisionDelegate: self)
            vc.present(fromViewController: self)
        }

        return banner
    }

    func createGroupMembershipCollisionBannerIfNecessary() -> UIView? {
        guard let groupThread = thread as? TSGroupThread else { return nil }

        // Collision discovery can be expensive, so we only build our banner if
        // we've already done the expensive bit
        guard let collisionFinder = viewState.groupNameCollisionFinder else {
            let collisionFinder = GroupMembershipNameCollisionFinder(thread: groupThread)
            viewState.groupNameCollisionFinder = collisionFinder

            firstly(on: DispatchQueue.sharedUserInitiated) {
                self.databaseStorage.read { readTx in
                    // Prewarm our collision finder off the main thread
                    _ = collisionFinder.findCollisions(transaction: readTx)
                }
            }.done(on: DispatchQueue.main) {
                self.ensureBannerState()
            }.catch { error in
                owsFailDebug("\(error)")
            }
            return nil
        }

        guard collisionFinder.hasFetchedProfileUpdateMessages else {
            // We already have a collision finder. It just hasn't finished fetching.
            return nil
        }

        // Fetch the necessary info to build the banner
        guard let (title, avatar1, avatar2) = databaseStorage.read(block: { readTx -> (String, UIImage?, UIImage?)? in
            let collisionSets = collisionFinder.findCollisions(transaction: readTx).standardSort(readTx: readTx)
            guard !collisionSets.isEmpty, collisionSets[0].elements.count >= 2 else { return nil }

            let totalCollisionElementCount = collisionSets.reduce(0) { $0 + $1.elements.count }

            let titleFormat = OWSLocalizedString("GROUP_MEMBERSHIP_COLLISIONS_BANNER_TITLE_%d", tableName: "PluralAware",
                                                comment: "Banner title alerting user to a name collision set ub the group membership. Embeds {{ total number of colliding members }}")
            let title = String.localizedStringWithFormat(titleFormat, totalCollisionElementCount)

            let fetchAvatarForAddress = { (address: SignalServiceAddress) -> UIImage? in
                if address.isLocalAddress, let profileAvatar = self.profileManager.localProfileAvatarImage() {
                    return profileAvatar.resizedImage(to: CGSize(square: 24))
                } else {
                    return Self.avatarBuilder.avatarImage(forAddress: address,
                                                          diameterPoints: 24,
                                                          localUserDisplayMode: .asUser,
                                                          transaction: readTx)
                }
            }

            let avatar1 = fetchAvatarForAddress(collisionSets[0].elements[0].address)
            let avatar2 = fetchAvatarForAddress(collisionSets[0].elements[1].address)
            return (title, avatar1, avatar2)

        }) else { return nil }

        let banner = NameCollisionBanner()
        banner.labelText = title
        banner.reviewActionText = OWSLocalizedString(
            "GROUP_MEMBERSHIP_NAME_COLLISION_BANNER_REVIEW_BUTTON",
            comment: "Button to allow user to review known name collisions in group membership")
        if let avatar1 = avatar1, let avatar2 = avatar2 {
            banner.primaryImage = avatar1
            banner.secondaryImage = avatar2
        }

        banner.closeAction = { [weak self] in
            self?.databaseStorage.asyncWrite(block: { writeTx in
                collisionFinder.markCollisionsAsResolved(transaction: writeTx)
            }, completion: {
                self?.ensureBannerState()
            })
        }

        banner.reviewAction = { [weak self] in
            guard let self = self else { return }
            let vc = NameCollisionResolutionViewController(collisionFinder: collisionFinder, collisionDelegate: self)
            vc.present(fromViewController: self)
        }

        return banner
    }
}

// MARK: -

fileprivate extension ConversationViewController {

    static func buildBannerLabel(title: String) -> UILabel {
        let label = UILabel()
        label.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
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
        titleLabel.font = .dynamicTypeSubheadlineClamped

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
public class GestureView: UIView {
    public required init() {
        super.init(frame: .zero)

        self.layoutMargins = .zero
    }

    @available(*, unavailable, message: "use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    public typealias BlockType = () -> Void

    private var tapBlock: BlockType?

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

private class NameCollisionBanner: UIView {

    var primaryImage: UIImage? {
        get { primaryImageView.image }
        set {
            primaryImageView.image = newValue
            setNeedsUpdateConstraints()
        }
    }

    var secondaryImage: UIImage? {
        get { secondaryImageView.image }
        set {
            secondaryImageView.image = newValue
            setNeedsUpdateConstraints()
        }
    }

    var labelText: String? {
        get { label.text }
        set { label.text = newValue }
    }

    var reviewActionText: String? {
        get { reviewButton.title(for: .normal) }
        set { reviewButton.setTitle(newValue, for: .normal) }
    }

    var reviewAction: () -> Void {
        get { reviewButton.block }
        set { reviewButton.block = newValue }
    }

    var closeAction: () -> Void {
        get { closeButton.block }
        set { closeButton.block = newValue }
    }

    private let label: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = UIFont.dynamicTypeFootnote
        label.textColor = Theme.secondaryTextAndIconColor
        return label
    }()

    private let primaryImageView: UIImageView = {
        let avatarSize = CGSize(square: 24)
        let borderWidth: CGFloat = 2
        let totalSize = avatarSize.plus(CGSize(square: borderWidth))

        let imageView = UIImageView.withTemplateImageName("info", tintColor: Theme.secondaryTextAndIconColor)
        imageView.contentMode = .center

        imageView.layer.borderColor = Theme.secondaryBackgroundColor.cgColor
        imageView.layer.borderWidth = borderWidth
        imageView.layer.cornerRadius = totalSize.smallerAxis / 2
        imageView.layer.masksToBounds = true

        imageView.autoSetDimensions(to: totalSize)
        imageView.setCompressionResistanceHigh()
        imageView.setContentHuggingHigh()
        return imageView
    }()

    private let secondaryImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.layer.cornerRadius = 12
        imageView.layer.masksToBounds = true

        imageView.autoSetDimensions(to: CGSize(square: 24))
        imageView.setCompressionResistanceHigh()
        imageView.setContentHuggingHigh()
        return imageView
    }()

    private let closeButton: OWSButton = {
        let button = OWSButton(
            imageName: "x-circle-compact",
            tintColor: Theme.secondaryTextAndIconColor)
        button.accessibilityLabel = OWSLocalizedString("BANNER_CLOSE_ACCESSIBILITY_LABEL",
                                                      comment: "Accessibility label for banner close button")
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setCompressionResistanceHigh()
        button.setContentHuggingHigh()
        return button
    }()

    private let reviewButton: OWSButton = {
        let button = OWSButton()
        button.setTitleColor(Theme.accentBlueColor, for: .normal)
        button.setTitleColor(Theme.accentBlueColor.withAlphaComponent(0.7), for: .highlighted)
        button.titleLabel?.font = UIFont.dynamicTypeFootnote
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.secondaryBackgroundColor

        [secondaryImageView, primaryImageView, label, closeButton, reviewButton]
            .forEach { addSubview($0) }

        // Offsets adjusted in updateConstraints() based on content
        primaryImageViewConstraints = (
            top: primaryImageView.autoPinEdge(.top, to: .top, of: self, withOffset: 18),
            leading: primaryImageView.autoPinEdge(.leading, to: .leading, of: self, withOffset: 16),
            trailing: label.autoPinEdge(.leading, to: .trailing, of: primaryImageView, withOffset: 16)
        )
        // Secondary image is always offset to the top left of the primary image
        secondaryImageView.autoPinEdge(.top, to: .top, of: primaryImageView, withOffset: -12)
        secondaryImageView.autoPinEdge(.leading, to: .leading, of: primaryImageView, withOffset: -12)

        // Note that UIButtons are being aligned based on their content subviews
        // UIButtons this small will have an intrinsic size larger than their content
        // That extra padding between the content and its frame messes up alignment
        label.autoPinEdge(toSuperviewEdge: .top, withInset: 12)
        closeButton.imageView?.autoPinEdge(.top, to: .top, of: label)
        reviewButton.titleLabel?.autoPinEdge(.top, to: .bottom, of: label, withOffset: 3)
        reviewButton.titleLabel?.autoPinEdge(.bottom, to: .bottom, of: self, withOffset: -12)

        // Aligning things this way is useful, because we can also increase the tap target
        // for the tiny close button without messing up the appearance.
        closeButton.contentEdgeInsets = UIEdgeInsets(hMargin: 8, vMargin: 8)
        closeButton.imageView?.autoPinLeading(toTrailingEdgeOf: label, offset: 16)
        closeButton.imageView?.autoPinTrailing(toEdgeOf: self, offset: -16)
        reviewButton.titleLabel?.autoPinLeading(toEdgeOf: label)

        accessibilityElements = [label, reviewButton, closeButton]
    }

    var primaryImageViewConstraints: (top: NSLayoutConstraint, leading: NSLayoutConstraint, trailing: NSLayoutConstraint)?

    override func updateConstraints() {
        super.updateConstraints()
        guard let topConstraint = primaryImageViewConstraints?.top,
              let leadingConstraint = primaryImageViewConstraints?.leading,
              let trailingConstraint = primaryImageViewConstraints?.trailing else { return }

        // If we have a secondary image, we want to adjust our constraints a bit
        let hasSecondaryImage = (secondaryImage != nil)
        topConstraint.constant = hasSecondaryImage ? 24 : 18
        leadingConstraint.constant = hasSecondaryImage ? 28 : 16
        trailingConstraint.constant = hasSecondaryImage ? 12 : 16
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: -

extension ConversationViewController {

    public func ensureBannerState() {
        AssertIsOnMainThread()

        // This method should be called rarely, so it's simplest to discard and
        // rebuild the indicator view every time.
        bannerView?.removeFromSuperview()
        self.bannerView = nil

        var banners = [UIView]()

        // Most of these banners should hide themselves when the user scrolls
        if !userHasScrolled {
            let message: String?
            let noLongerVerifiedIdentityKeys = databaseStorage.read { tx in self.noLongerVerifiedIdentityKeys(tx: tx) }
            switch noLongerVerifiedIdentityKeys.count {
            case 0:
                message = nil

            case 1:
                let address = noLongerVerifiedIdentityKeys.first!.key
                let displayName = contactsManager.displayName(for: address)
                let format = (isGroupConversation
                                ? OWSLocalizedString("MESSAGES_VIEW_1_MEMBER_NO_LONGER_VERIFIED_FORMAT",
                                                    comment: "Indicates that one member of this group conversation is no longer verified. Embeds {{user's name or phone number}}.")
                                : OWSLocalizedString("MESSAGES_VIEW_CONTACT_NO_LONGER_VERIFIED_FORMAT",
                                                    comment: "Indicates that this 1:1 conversation is no longer verified. Embeds {{user's name or phone number}}."))
                message = String(format: format, displayName)

            default:
                message = OWSLocalizedString("MESSAGES_VIEW_N_MEMBERS_NO_LONGER_VERIFIED",
                                            comment: "Indicates that more than one member of this group conversation is no longer verified.")
            }
            if let message {
                let banner = ConversationViewController.createBanner(
                    title: message,
                    bannerColor: .ows_accentRed,
                    tapBlock: { [weak self] in
                        self?.noLongerVerifiedBannerViewWasTapped(noLongerVerifiedIdentityKeys: noLongerVerifiedIdentityKeys)
                    }
                )
                banners.append(banner)
            }

            func buildBlockStateMessage() -> String? {
                guard isGroupConversation else {
                    return nil
                }
                let blockedGroupMemberCount = self.blockedGroupMemberCount
                if blockedGroupMemberCount > 0 {
                    return String.localizedStringWithFormat(
                        OWSLocalizedString("MESSAGES_VIEW_GROUP_N_MEMBERS_BLOCKED_%d", tableName: "PluralAware",
                                          comment: "Indicates that some members of this group has been blocked. Embeds {{the number of blocked users in this group}}."),
                        blockedGroupMemberCount)
                } else {
                    return nil
                }
            }
            if let blockStateMessage = buildBlockStateMessage() {
                let banner = ConversationViewController.createBanner(title: blockStateMessage,
                                                                     bannerColor: .ows_accentRed) { [weak self] in
                    self?.blockBannerViewWasTapped()
                }
                banners.append(banner)
            }

            let pendingMemberRequests = self.pendingMemberRequests
            if
                !pendingMemberRequests.isEmpty,
                self.canApprovePendingMemberRequests,
                databaseStorage.read(block: { transaction in
                    // We will skip this read if the above checks fail, which
                    // will be most of the time.
                    viewState.shouldShowPendingMemberRequestsBanner(
                        currentPendingMembers: pendingMemberRequests,
                        transaction: transaction
                    )
                }) {
                let banner = self.createPendingJoinRequestBanner(
                    viewState: viewState,
                    pendingMemberRequests: pendingMemberRequests
                ) { [weak self] in
                    self?.showConversationSettingsAndShowMemberRequests()
                }

                banners.append(banner)
            }
        }

        if let banner = createMessageRequestNameCollisionBannerIfNecessary(viewState: viewState) {
            banners.append(banner)
        }

        if let banner = createGroupMembershipCollisionBannerIfNecessary() {
            banners.append(banner)
        }

        if banners.isEmpty {
            if hasViewDidAppearEverBegun {
                updateContentInsets()
            }
            return
        }

        let bannerView = UIStackView(arrangedSubviews: banners)
        bannerView.axis = .vertical
        bannerView.alignment = .fill
        self.view.addSubview(bannerView)
        bannerView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        bannerView.autoPinEdge(toSuperviewEdge: .leading)
        bannerView.autoPinEdge(toSuperviewEdge: .trailing)
        self.view.layoutSubviews()

        self.bannerView = bannerView
        if hasViewDidAppearEverBegun {
            updateContentInsets()
        }
    }

    private var pendingMemberRequests: Set<SignalServiceAddress> {
        if let groupThread = thread as? TSGroupThread {
            return groupThread.groupMembership.requestingMembers
        } else {
            return []
        }
    }

    private var canApprovePendingMemberRequests: Bool {
        if let groupThread = thread as? TSGroupThread {
            return groupThread.isLocalUserFullMemberAndAdministrator
        } else {
            return false
        }
    }

    private func blockBannerViewWasTapped() {
        AssertIsOnMainThread()

        if isBlockedConversation() {
            // If this a blocked conversation, offer to unblock.
            showUnblockConversationUI(completion: nil)
        } else if isGroupConversation {
            // If this a group conversation with at least one blocked member,
            // Show the block list view.
            let blockedGroupMemberCount = self.blockedGroupMemberCount
            if blockedGroupMemberCount > 0 {
                let vc = BlockListViewController()
                navigationController?.pushViewController(vc, animated: true)
            }
        }
    }

    private func noLongerVerifiedBannerViewWasTapped(noLongerVerifiedIdentityKeys: [SignalServiceAddress: Data]) {
        AssertIsOnMainThread()

        let title: String
        switch noLongerVerifiedIdentityKeys.count {
        case 0:
            return
        case 1:
            title = OWSLocalizedString(
                "VERIFY_PRIVACY",
                comment: "Label for button or row which allows users to verify the safety number of another user."
            )
        default:
            title = OWSLocalizedString(
                "VERIFY_PRIVACY_MULTIPLE",
                comment: "Label for button or row which allows users to verify the safety numbers of multiple users."
            )
        }

        let actionSheet = ActionSheetController()

        actionSheet.addAction(ActionSheetAction(title: title, style: .default) { [weak self] _ in
            self?.showNoLongerVerifiedUI(noLongerVerifiedIdentityKeys: noLongerVerifiedIdentityKeys)
        })

        actionSheet.addAction(ActionSheetAction(title: CommonStrings.dismissButton,
                                                accessibilityIdentifier: "dismiss",
                                                style: .cancel) { [weak self] _ in
            self?.resetVerificationStateToDefault(noLongerVerifiedIdentityKeys: noLongerVerifiedIdentityKeys)
        })

        dismissKeyBoard()
        presentActionSheet(actionSheet)
    }

    private var blockedGroupMemberCount: Int {
        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return 0
        }

        let blockedMembers = databaseStorage.read { readTx in
            groupThread.groupModel.groupMembers.filter {
                blockingManager.isAddressBlocked($0, transaction: readTx)
            }
        }
        return blockedMembers.count
    }
}
