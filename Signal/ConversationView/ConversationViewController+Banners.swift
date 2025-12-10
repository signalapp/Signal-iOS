//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import LibSignalClient

// MARK: - Banner Management

extension ConversationViewController {

    /// Checks if there are any banners that need to be displayed and shows them as necessary.
    public func ensureBannerState() {
        AssertIsOnMainThread()

        // This method should be called rarely, so it's simplest to discard and
        // rebuild the indicator view every time.
        if let bannerStackView {
            bannerStackView.removeFromSuperview()
            self.bannerStackView = nil
        }

        var banners = [UIView]()

        // Logic for whether or not should a certain banner be displayed is inside of each banner creation method.
        // If the banner should not be shown its "create..." method would return `nil`.

        // Most of these banners should hide themselves when the user scrolls
        if !userHasScrolled {
            // No Longer Verified
            if let banner = createNoLongerVerifiedStateBanner() {
                banners.append(banner)
            }
        }

        // Pending Member requests
        if let banner = createPendingJoinRequestBanner(viewState: viewState) {
            banners.append(banner)
        }

        // Name Collision Banners
        if let banner = createMessageRequestNameCollisionBanner(viewState: viewState) {
            banners.append(banner)
        }

        if let banner = createGroupMembershipCollisionBanner() {
            banners.append(banner)
        }

        // Pinned Messages
        if let banner = createPinnedMessageBannerIfNecessary() {
            banners.append(banner)
        }

        guard !banners.isEmpty else {
            if hasViewDidAppearEverBegun {
                updateContentInsets()
            }
            return
        }

        let topMargin: CGFloat = if #available(iOS 26, *) { 2 } else { 8 }
        let hMargin = OWSTableViewController2.cellHInnerMargin
        let bannersView = UIStackView(arrangedSubviews: banners)
        bannersView.axis = .vertical
        bannersView.alignment = .fill
        bannersView.spacing = 8
        bannersView.isLayoutMarginsRelativeArrangement = true
        bannersView.directionalLayoutMargins = .init(top: topMargin, leading: hMargin, bottom: 0, trailing: hMargin)
        bannersView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bannersView)
        NSLayoutConstraint.activate([
            bannersView.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            bannersView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            bannersView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])
        view.layoutSubviews()

        bannerStackView = bannersView
        if hasViewDidAppearEverBegun {
            updateContentInsets()
        }
    }
}

// MARK: - Single class for all banners

private class ConversationBannerView: UIView {
    internal var contentView: UIView & UIContentView

    /// Contains all the information necessary to construct any banner.
    struct ContentConfiguration: UIContentConfiguration {
        /// Text displayed on the top row of the banner.
        let title: String?

        /// Text displayed in the banner, under the title if it exists
        let body: NSAttributedString

        /// Thumbnail to show with pinned messages
        let thumbnail: UIImageView?

        /// Title for the button displayed at the trailing edge of the banner, typically something like "View".
        /// Both `viewButtonTitle` and `viewButtonAction` must be set in orded for "View" button to be displayed.
        let viewButtonTitle: String?

        /// Action to perform when user taps on "View" button.
        /// Both `viewButtonTitle` and `viewButtonAction` must be set in orded for "View" button to be displayed.
        let viewButtonAction: UIAction?

        /// Action to perform when user taps on Close (X) button.
        /// Close button will not be displayed if this is `nil`.
        let dismissButtonAction: UIAction?

        /// Small view displayed at the leading edge of the banner.
        let leadingAccessoryView: UIView?

        /// Small view displayed at the trailing edge of the banner.
        let trailingAccessoryView: UIView?

        /// Action to perform when the entire banner is tapped.
        /// Banner will not be tappable if this is nil.
        var bannerTapAction: (() -> Void)?

        let isPinnedMessagesBanner: Bool

        func makeContentView() -> any UIView & UIContentView {
            return ConversationBannerContentView(configuration: self)
        }

        func updated(for state: any UIConfigurationState) -> ConversationBannerView.ContentConfiguration {
            return self
        }
    }

    private class ConversationBannerContentView: UIStackView, UIContentView {

        var configuration: any UIContentConfiguration {
            get { _configuration }
            set {
                guard let configuration = newValue as? ContentConfiguration else { return }
                _configuration = configuration
                rebuildContent()
            }
        }

        private var _configuration: ContentConfiguration

        // Required stored labels for banner animations.
        var textStackView = UIStackView()
        var titleLabel = UILabel()
        var bodyLabel = UILabel()
        var thumbnail: UIImageView?

        init(configuration: ContentConfiguration) {
            _configuration = configuration

            super.init(frame: .zero)

            axis = .horizontal
            isLayoutMarginsRelativeArrangement = true
            spacing = 12

            rebuildContent()
        }

        private func rebuildContent() {
            directionalLayoutMargins = NSDirectionalEdgeInsets(hMargin: 16, vMargin: 10)

            removeAllSubviews()

            guard let configuration = self.configuration as? ContentConfiguration else { return }

            if let leadingAccessoryView = configuration.leadingAccessoryView {
                let leadingAccessoryContainerView = UIView.container()
                leadingAccessoryContainerView.addSubview(leadingAccessoryView)
                leadingAccessoryView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    leadingAccessoryView.topAnchor.constraint(greaterThanOrEqualTo: leadingAccessoryContainerView.topAnchor),
                    leadingAccessoryView.centerYAnchor.constraint(equalTo: leadingAccessoryContainerView.centerYAnchor),
                    leadingAccessoryView.leadingAnchor.constraint(equalTo: leadingAccessoryContainerView.leadingAnchor),
                    leadingAccessoryView.trailingAnchor.constraint(equalTo: leadingAccessoryContainerView.trailingAnchor),
                ])
                addArrangedSubview(leadingAccessoryContainerView)
            }

            if let _thumbnail = configuration.thumbnail {
                thumbnail = _thumbnail
                addArrangedSubview(_thumbnail)
            }

            // If this is a pinned message and its not first load (no previous title), animate.
            if configuration.isPinnedMessagesBanner,
               let title = configuration.title,
               !titleLabel.text.isEmptyOrNil
            {
                animatePinnedMessageTransition(
                    newTitle: title,
                    newBody: configuration.body.string,
                    newThumbnail: configuration.thumbnail
                )
            } else {
                bodyLabel.numberOfLines = 0
                bodyLabel.font = UIFont.dynamicTypeSubheadlineClamped
                bodyLabel.textColor = .Signal.label
                bodyLabel.attributedText = configuration.body

                if let title = configuration.title {
                    titleLabel.numberOfLines = 0
                    titleLabel.font = UIFont.dynamicTypeFootnote.semibold()
                    titleLabel.textColor = .Signal.label
                    titleLabel.text = title

                    textStackView.addArrangedSubviews([titleLabel, bodyLabel])
                    textStackView.axis = .vertical
                    textStackView.spacing = 2

                    addArrangedSubview(textStackView)
                } else {
                    addArrangedSubview(bodyLabel)
                }
            }

            if let viewButtonTitle = configuration.viewButtonTitle,
               let viewButtonAction = configuration.viewButtonAction
            {
                let button = UIButton(configuration: .gray(), primaryAction: viewButtonAction)
                button.configuration?.title = viewButtonTitle
                button.configuration?.titleTextAttributesTransformer = .defaultFont(.dynamicTypeSubheadlineClamped.medium())
                button.configuration?.cornerStyle = .capsule
                button.configuration?.contentInsets = .init(hMargin: 15, vMargin: 7)
                button.configuration?.baseForegroundColor = .Signal.label
                button.configuration?.baseBackgroundColor = .Signal.secondaryFill
                button.setCompressionResistanceHigh()
                button.setContentHuggingHigh()

                let buttonContainer = UIView.container()
                buttonContainer.addSubview(button)
                button.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    button.topAnchor.constraint(greaterThanOrEqualTo: buttonContainer.topAnchor),
                    button.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
                    button.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
                    button.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor),
                ])
                addArrangedSubview(buttonContainer)

                setCustomSpacing(8, after: buttonContainer)
                directionalLayoutMargins.trailing = 10 // match top and bottom margins
            }

            if let dismissButtonAction = configuration.dismissButtonAction {
                let button = UIButton(configuration: .plain(), primaryAction: dismissButtonAction)
                button.tintColor = .Signal.label
                button.configuration?.image = UIImage(named: "x-20")
                button.configuration?.cornerStyle = .capsule
                button.configuration?.contentInsets = .init(margin: 6)
                button.configuration?.baseBackgroundColor = .Signal.secondaryFill
                button.accessibilityLabel = OWSLocalizedString(
                    "BANNER_CLOSE_ACCESSIBILITY_LABEL",
                    comment: "Accessibility label for banner close button"
                )
                button.setCompressionResistanceHigh()
                button.setContentHuggingHigh()

                let buttonContainer = UIView.container()
                buttonContainer.addSubview(button)
                button.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    button.topAnchor.constraint(greaterThanOrEqualTo: buttonContainer.topAnchor),
                    button.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
                    button.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
                    button.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor),
                ])
                addArrangedSubview(buttonContainer)

                directionalLayoutMargins.trailing = 4 // 10 total with button's content padding
            }

            if let trailingAccessoryView = configuration.trailingAccessoryView {
                let trailingAccessoryContainerView = UIView.container()
                trailingAccessoryContainerView.addSubview(trailingAccessoryView)
                trailingAccessoryView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    trailingAccessoryView.topAnchor.constraint(greaterThanOrEqualTo: trailingAccessoryContainerView.topAnchor),
                    trailingAccessoryView.centerYAnchor.constraint(equalTo: trailingAccessoryContainerView.centerYAnchor),
                    trailingAccessoryView.leadingAnchor.constraint(equalTo: trailingAccessoryContainerView.leadingAnchor),
                    trailingAccessoryView.trailingAnchor.constraint(equalTo: trailingAccessoryContainerView.trailingAnchor),
                ])
                addArrangedSubview(trailingAccessoryContainerView)
            }

            if configuration.bannerTapAction != nil {
                addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapBanner)))
            }
        }

        private func animatePinnedMessageTransition(newTitle: String, newBody: String, newThumbnail: UIImageView?) {
            func makeAnimatedStack(title: String?, body: String?, thumbnailImageView: UIImageView?) -> (UIStackView) {
                let hStack = UIStackView()
                hStack.axis = .horizontal
                hStack.spacing = 12

                let _titleLabel = UILabel()
                _titleLabel.text = title
                _titleLabel.font = titleLabel.font

                let _bodyLabel = UILabel()
                _bodyLabel.text = body
                _bodyLabel.font = bodyLabel.font

                let newTextStack = UIStackView(arrangedSubviews: [_titleLabel, _bodyLabel])
                newTextStack.axis = .vertical
                newTextStack.spacing = 2

                if let _thumbnail = thumbnailImageView {
                    hStack.addArrangedSubview(_thumbnail)
                }
                hStack.addArrangedSubview(newTextStack)
                return hStack
            }

            let oldAnimatedStack = makeAnimatedStack(
                title: titleLabel.text,
                body: bodyLabel.text,
                thumbnailImageView: thumbnail
            )
            let newAnimatedStack = makeAnimatedStack(
                title: newTitle,
                body: newBody,
                thumbnailImageView: newThumbnail
            )

            // Create a stack with:
            // [old]
            // [new]
            // and insert it into a fixed-height wrapper (so the label thats sliding in/out gets cut off).
            // Constrain the top of the stack (old pin) to the top of the wrapper and start it at (0,0),
            // then animate it upwards off screen by a y value equal to its size, leaving the new pin in view.
            let animatedStack = UIStackView(arrangedSubviews: [
                oldAnimatedStack,
                newAnimatedStack
            ])
            animatedStack.axis = .vertical

            let fixedHeightAnimationView = UIView()
            fixedHeightAnimationView.clipsToBounds = true
            fixedHeightAnimationView.addSubview(animatedStack)

            animatedStack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                animatedStack.leadingAnchor.constraint(equalTo: fixedHeightAnimationView.leadingAnchor),
                animatedStack.trailingAnchor.constraint(equalTo: fixedHeightAnimationView.trailingAnchor),
                animatedStack.topAnchor.constraint(equalTo: fixedHeightAnimationView.topAnchor),
            ])

            let textHeight = textStackView.bounds.height
            addArrangedSubview(fixedHeightAnimationView)

            fixedHeightAnimationView.heightAnchor.constraint(equalToConstant: textHeight).isActive = true

            let pinAnimator = UIViewPropertyAnimator(
                duration: 0.3,
                springDamping: 1,
                springResponse: 0.3
            )
            pinAnimator.addAnimations {
                animatedStack.transform = CGAffineTransform(translationX: 0, y: -textHeight)
            }

            pinAnimator.addCompletion { [self] _ in
                fixedHeightAnimationView.removeFromSuperview()

                self.titleLabel.text = newTitle
                self.bodyLabel.text = newBody
                self.thumbnail = newThumbnail

                let textStackIndex: Int
                if let _thumbnail = self.thumbnail {
                    insertArrangedSubview(_thumbnail, at: 1)
                    textStackIndex = 2
                } else {
                    textStackIndex = 1
                }
                insertArrangedSubview(textStackView, at: textStackIndex)
            }
            pinAnimator.startAnimation()
        }

        @objc
        private func didTapBanner() {
            guard let configuration = self.configuration as? ContentConfiguration, let bannerTapAction = configuration.bannerTapAction else { return }
            bannerTapAction()
        }

        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func supports(_ configuration: any UIContentConfiguration) -> Bool {
            return configuration is ContentConfiguration
        }
    }

    init(configuration: ContentConfiguration) {
        contentView = configuration.makeContentView()

        super.init(frame: .zero)

        let backgroundView: UIView
        if #available(iOS 26, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.tintColor = UIColor { traitCollection in
                if traitCollection.userInterfaceStyle == .dark {
                    return UIColor(white: 0, alpha: 0.2)
                }
                return UIColor(white: 1, alpha: 0.12)
            }
            backgroundView = UIVisualEffectView(effect: glassEffect)
            backgroundView.cornerConfiguration = .capsule()
            backgroundView.clipsToBounds = true
        } else {
            if UIAccessibility.isReduceTransparencyEnabled {
                backgroundView = UIView()
                backgroundView.backgroundColor = Theme.secondaryBackgroundColor
            } else {
                backgroundView = UIVisualEffectView(effect: Theme.barBlurEffect)
            }
            backgroundView.layer.masksToBounds = true
            backgroundView.layer.cornerRadius = 16

            if Theme.isDarkThemeEnabled {
                layer.shadowColor = UIColor.white.cgColor
                layer.shadowOpacity = 0.16
            } else {
                layer.shadowColor = UIColor.black.cgColor
                layer.shadowOpacity = 0.08
            }
            layer.shadowRadius = 24
            layer.shadowOffset = .init(width: 0, height: 4)
        }
        addSubview(backgroundView)

        if let visualEffectView = backgroundView as? UIVisualEffectView {
            visualEffectView.contentView.addSubview(contentView)
        } else {
            addSubview(contentView)
        }

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            // Background view.
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Content view.
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Name Collision Banners

private extension ConversationViewController {

    func createMessageRequestNameCollisionBanner(viewState: CVViewState) -> ConversationBannerView? {
        guard let contactThread = thread as? TSContactThread else { return nil }

        let collisionFinder = ContactThreadNameCollisionFinder
            .makeToCheckMessageRequestNameCollisions(forContactThread: contactThread)

        guard let (avatar1, avatar2) = SSKEnvironment.shared.databaseStorageRef.read(block: { tx -> (UIImage?, UIImage?)? in
            guard
                viewState.shouldShowMessageRequestNameCollisionBanner(transaction: tx),
                let collision = collisionFinder.findCollisions(transaction: tx).first
            else { return nil }

            return (
                fetchAvatar(for: collision.elements[0].address, tx: tx),
                fetchAvatar(for: collision.elements[1].address, tx: tx)
            )
        }) else { return nil }

        let bannerConfiguration = ConversationBannerView.ContentConfiguration(
            title: nil,
            body: OWSLocalizedString(
                "MESSAGE_REQUEST_NAME_COLLISION_BANNER_LABEL",
                comment: "Banner label notifying user that a new message is from a user with the same name as an existing contact"
            ).attributedString(),
            thumbnail: nil,
            viewButtonTitle: CommonStrings.viewButton,
            viewButtonAction: UIAction { [weak self] _ in
                guard let self else { return }
                let vc = NameCollisionResolutionViewController(collisionFinder: collisionFinder, collisionDelegate: self)
                vc.present(fromViewController: self)
            },
            dismissButtonAction: UIAction { [weak self] _ in
                guard let self else { return }
                SSKEnvironment.shared.databaseStorageRef.write {
                    viewState.hideMessageRequestNameCollisionBanner(transaction: $0)
                }
                self.ensureBannerState()
            },
            leadingAccessoryView: DoubleProfileImageView(primaryImage: avatar1, secondaryImage: avatar2),
            trailingAccessoryView: nil,
            isPinnedMessagesBanner: false
        )

        return ConversationBannerView(configuration: bannerConfiguration)
    }

    func createGroupMembershipCollisionBanner() -> ConversationBannerView? {
        guard let groupThread = thread as? TSGroupThread else { return nil }

        // Collision discovery can be expensive, so we only build our banner if
        // we've already done the expensive bit
        guard let collisionFinder = viewState.groupNameCollisionFinder else {
            let collisionFinder = GroupMembershipNameCollisionFinder(thread: groupThread)
            viewState.groupNameCollisionFinder = collisionFinder

            Task.detached(priority: .userInitiated) {
                SSKEnvironment.shared.databaseStorageRef.read { readTx in
                    // Prewarm our collision finder off the main thread
                    _ = collisionFinder.findCollisions(transaction: readTx)
                }
                await self.ensureBannerState()
            }

            return nil
        }

        guard collisionFinder.hasFetchedProfileUpdateMessages else {
            // We already have a collision finder. It just hasn't finished fetching.
            return nil
        }

        // Fetch the necessary info to build the banner
        guard let (title, avatar1, avatar2) = SSKEnvironment.shared.databaseStorageRef.read(block: { readTx -> (String, UIImage?, UIImage?)? in
            let collisionSets = collisionFinder.findCollisions(transaction: readTx)
            guard !collisionSets.isEmpty else { return nil }

            let totalCollisionElementCount = collisionSets.reduce(0) { $0 + $1.elements.count }

            let title: String

            if collisionSets.count > 1 {
                let titleFormat = OWSLocalizedString(
                    "GROUP_MEMBERSHIP_MULTIPLE_COLLISIONS_BANNER_TITLE_%d",
                    tableName: "PluralAware",
                    comment: "Banner title alerting user to a name collision set ub the group membership. Embeds {{ total number of colliding members }}"
                )
                title = String.localizedStringWithFormat(titleFormat, collisionSets.count)
            } else {
                let titleFormat = OWSLocalizedString(
                    "GROUP_MEMBERSHIP_COLLISIONS_BANNER_TITLE_%d",
                    tableName: "PluralAware",
                    comment: "Banner title alerting user about multiple name collisions in group membership. Embeds {{ number of sets of colliding members }}"
                )
                title = String.localizedStringWithFormat(titleFormat, totalCollisionElementCount)
            }

            let avatar1 = fetchAvatar(
                for: collisionSets[0].elements[0].address,
                tx: readTx
            )
            let avatar2 = fetchAvatar(
                for: collisionSets[0].elements[1].address,
                tx: readTx
            )
            return (title, avatar1, avatar2)

        }) else { return nil }

        let bannerConfiguration = ConversationBannerView.ContentConfiguration(
            title: nil,
            body: title.attributedString(),
            thumbnail: nil,
            viewButtonTitle: CommonStrings.viewButton,
            viewButtonAction: UIAction { [weak self] _ in
                guard let self else { return }
                let vc = NameCollisionResolutionViewController(
                    collisionFinder: collisionFinder,
                    collisionDelegate: self
                )
                vc.present(fromViewController: self)
            },
            dismissButtonAction: UIAction { [weak self] _ in
                guard let self else { return }
                SSKEnvironment.shared.databaseStorageRef.asyncWrite(
                    block: { writeTx in
                        collisionFinder.markCollisionsAsResolved(transaction: writeTx)
                    },
                    completion: {
                        self.ensureBannerState()
                    }
                )
            },
            leadingAccessoryView: DoubleProfileImageView(primaryImage: avatar1, secondaryImage: avatar2),
            trailingAccessoryView: nil,
            isPinnedMessagesBanner: false
        )

        return ConversationBannerView(configuration: bannerConfiguration)
    }

    private func fetchAvatar(for address: SignalServiceAddress, tx: DBReadTransaction) -> UIImage? {
        return SSKEnvironment.shared.avatarBuilderRef.avatarImage(
            forAddress: address,
            diameterPoints: 24,
            localUserDisplayMode: .asUser,
            transaction: tx
        )
    }

    private class DoubleProfileImageView: UIView {

        init(primaryImage: UIImage?, secondaryImage: UIImage?) {
            super.init(frame: .zero)

            addSubview(secondaryImageView)
            addSubview(primaryImageView)

            if let primaryImage {
                primaryImageView.image = primaryImage
            }
            if let secondaryImage {
                secondaryImageView.image = secondaryImage
            }

            primaryImageView.translatesAutoresizingMaskIntoConstraints = false
            secondaryImageView.translatesAutoresizingMaskIntoConstraints = false

            let hasSecondaryImage = (secondaryImage != nil)
            let top = primaryImageView.topAnchor.constraint(
                equalTo: topAnchor,
                constant: hasSecondaryImage ? 12 : 0
            )
            let leading = primaryImageView.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: hasSecondaryImage ? 16 : 4
            )
            NSLayoutConstraint.activate([
                // Image sizes.
                primaryImageView.widthAnchor.constraint(equalToConstant: Constants.avatarSize.width),
                primaryImageView.heightAnchor.constraint(equalToConstant: Constants.avatarSize.height),
                secondaryImageView.widthAnchor.constraint(equalToConstant: Constants.avatarSize.width),
                secondaryImageView.heightAnchor.constraint(equalToConstant: Constants.avatarSize.height),

                // Position of the primary image.
                top,
                leading,
                primaryImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
                primaryImageView.bottomAnchor.constraint(equalTo: bottomAnchor),

                // Secondary image is always offset to the top left of the primary image
                secondaryImageView.topAnchor.constraint(equalTo: primaryImageView.topAnchor, constant: -12),
                secondaryImageView.leadingAnchor.constraint(equalTo: primaryImageView.leadingAnchor, constant: -12),
            ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private enum Constants {
            static let avatarSize = CGSize(square: 24)
            static let avatarBorderSize: CGFloat = 2
        }

        private let primaryImageView: UIImageView = {
            let imageView = UIImageView.withTemplateImageName("info", tintColor: .Signal.secondaryLabel)
            imageView.layer.cornerRadius = Constants.avatarSize.smallerAxis / 2
            imageView.layer.masksToBounds = true
            return imageView
        }()

        private let secondaryImageView: UIImageView = {
            let imageView = SecondaryImageView()
            imageView.layer.cornerRadius = Constants.avatarSize.smallerAxis / 2
            imageView.layer.masksToBounds = true
            return imageView
        }()

        private class SecondaryImageView: UIImageView {
            override func layoutSubviews() {
                // Mask out a border around the primary avatar.
                // The background is a UIVisualEffect, so we can't just rely
                // on adding a border around the primary avatar itself.
                let borderSize = Constants.avatarBorderSize
                let circlePath = UIBezierPath(
                    ovalIn: CGRect(
                        origin: CGPoint(
                            x: bounds.center.x - borderSize,
                            y: bounds.center.y - borderSize
                        ),
                        size: bounds.size.plus(.square(borderSize * 2))
                    )
                )

                let maskPath = UIBezierPath(rect: bounds)
                maskPath.append(circlePath)

                let maskLayer = CAShapeLayer()
                maskLayer.path = maskPath.cgPath
                // Mask the inverse of the circle path
                maskLayer.fillRule = .evenOdd

                layer.mask = maskLayer
            }
        }
    }
}

// MARK: - Pending Group Join Requests

private extension ConversationViewController {

    func createPendingJoinRequestBanner(viewState: CVViewState) -> ConversationBannerView? {
        guard let pendingMemberRequests = pendingMemberRequests,
              !pendingMemberRequests.isEmpty,
              canApprovePendingMemberRequests
        else {
            return nil
        }

        // We will skip this read if the above checks fail, which will be most of the time.
        guard SSKEnvironment.shared.databaseStorageRef.read(block: { tx in
            viewState.shouldShowPendingMemberRequestsBanner(
                currentPendingMembers: pendingMemberRequests,
                transaction: tx
            )
        }) else {
            return nil
        }

        let format = OWSLocalizedString(
            "PENDING_GROUP_MEMBERS_REQUEST_BANNER_%d",
            tableName: "PluralAware",
            comment: "Format for banner indicating that there are pending member requests to join the group. Embeds {{ the number of pending member requests }}."
        )

        let bannerConfiguration = ConversationBannerView.ContentConfiguration(
            title: nil,
            body: String.localizedStringWithFormat(format, pendingMemberRequests.count).attributedString(),
            thumbnail: nil,
            viewButtonTitle: CommonStrings.viewButton,
            viewButtonAction: UIAction { [weak self] _ in
                self?.showConversationSettingsAndShowMemberRequests()
            },
            dismissButtonAction: UIAction { [weak self] _ in
                SSKEnvironment.shared.databaseStorageRef.write { transaction in
                    viewState.hidePendingMemberRequestsBanner(
                        currentPendingMembers: pendingMemberRequests,
                        transaction: transaction
                    )
                }

                self?.ensureBannerState()
            },
            leadingAccessoryView: {
                let imageView = UIImageView(image: UIImage(named: "group"))
                imageView.tintColor = .Signal.label
                imageView.setContentHuggingHigh()
                imageView.setCompressionResistanceHigh()
                return imageView
            }(),
            trailingAccessoryView: nil,
            isPinnedMessagesBanner: false
        )
        return ConversationBannerView(configuration: bannerConfiguration)
    }

    private var pendingMemberRequests: Set<SignalServiceAddress>? {
        guard let groupThread = thread as? TSGroupThread else { return nil }
        return groupThread.groupMembership.requestingMembers
    }

    private var canApprovePendingMemberRequests: Bool {
        guard let groupThread = thread as? TSGroupThread else { return false }
        return groupThread.groupModel.groupMembership.isLocalUserFullMemberAndAdministrator
    }
}

// MARK: - No Longer Verified

private extension ConversationViewController {

    func createNoLongerVerifiedStateBanner() -> ConversationBannerView? {
        let noLongerVerifiedIdentityKeys = SSKEnvironment.shared.databaseStorageRef.read { tx in
            self.noLongerVerifiedIdentityKeys(tx: tx)
        }
        guard !noLongerVerifiedIdentityKeys.isEmpty else { return nil }

        let title: String
        switch noLongerVerifiedIdentityKeys.count {
        case 1:
            let address = noLongerVerifiedIdentityKeys.first!.key
            let displayName = SSKEnvironment.shared.databaseStorageRef.read {
                tx in SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: tx).resolvedValue()
            }
            let format = isGroupConversation
            ? OWSLocalizedString("MESSAGES_VIEW_1_MEMBER_NO_LONGER_VERIFIED_FORMAT",
                                 comment: "Indicates that one member of this group conversation is no longer verified. Embeds {{user's name or phone number}}.")
            : OWSLocalizedString("MESSAGES_VIEW_CONTACT_NO_LONGER_VERIFIED_FORMAT",
                                 comment: "Indicates that this 1:1 conversation is no longer verified. Embeds {{user's name or phone number}}.")
            title = String(format: format, displayName)

        default:
            title = OWSLocalizedString(
                "MESSAGES_VIEW_N_MEMBERS_NO_LONGER_VERIFIED",
                comment: "Indicates that more than one member of this group conversation is no longer verified."
            )
        }

        let bannerConfiguration = ConversationBannerView.ContentConfiguration(
            title: nil,
            body: title.attributedString(),
            thumbnail: nil,
            viewButtonTitle: CommonStrings.viewButton,
            viewButtonAction: UIAction { [weak self] _ in
                self?.noLongerVerifiedBannerViewWasTapped(noLongerVerifiedIdentityKeys: noLongerVerifiedIdentityKeys)
            },
            dismissButtonAction: UIAction { [weak self] _ in
                self?.resetVerificationStateToDefault(noLongerVerifiedIdentityKeys: noLongerVerifiedIdentityKeys)
            },
            leadingAccessoryView: {
                let imageView = UIImageView(image: UIImage(named: "safety-number"))
                imageView.tintColor = .Signal.label
                imageView.setContentHuggingHigh()
                imageView.setCompressionResistanceHigh()
                return imageView
            }(),
            trailingAccessoryView: nil,
            isPinnedMessagesBanner: false
        )

        return ConversationBannerView(configuration: bannerConfiguration)
    }

    private func noLongerVerifiedBannerViewWasTapped(noLongerVerifiedIdentityKeys: [SignalServiceAddress: Data]) {
        AssertIsOnMainThread()

        guard !noLongerVerifiedIdentityKeys.isEmpty else { return }

        let title: String
        switch noLongerVerifiedIdentityKeys.count {
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

        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.dismissButton,
            style: .cancel
        ) { [weak self] _ in
            self?.resetVerificationStateToDefault(noLongerVerifiedIdentityKeys: noLongerVerifiedIdentityKeys)
        })

        dismissKeyBoard()
        presentActionSheet(actionSheet)
    }
}

// MARK: - Pinned Messages

internal extension ConversationViewController {
    func animateToNextPinnedMessage() {
        guard let nextPinnedMessage = createPinnedMessageBannerIfNecessary(),
        let priorPinnedMessage = bannerStackView?.arrangedSubviews.last as? ConversationBannerView else {
            return
        }
        priorPinnedMessage.contentView.configuration = nextPinnedMessage.contentView.configuration
    }

    /// Displays the first pinned message, sorted by most recently pinned.
    /// When tapped, it cycles to the next pinned message if one exists.
    fileprivate func createPinnedMessageBannerIfNecessary() -> ConversationBannerView? {
        guard threadViewModel.pinnedMessages.indices.contains(pinnedMessageIndex),
              let pinnedMessageData = pinnedMessageData(for: threadViewModel.pinnedMessages[pinnedMessageIndex]) else {
            return nil
        }

        let bannerConfiguration = ConversationBannerView.ContentConfiguration(
            title: pinnedMessageData.authorName,
            body: pinnedMessageData.previewText,
            thumbnail: pinnedMessageData.thumbnail,
            viewButtonTitle: nil,
            viewButtonAction: nil,
            dismissButtonAction: nil,
            leadingAccessoryView: pinnedMessageLeadingAccessoryView(),
            trailingAccessoryView: {
                let imageView = UIImageView(image: UIImage(named: "pin"))
                imageView.tintColor = .Signal.label
                imageView.setContentHuggingHigh()
                imageView.setCompressionResistanceHigh()
                return imageView
            }(),
            bannerTapAction: threadViewModel.pinnedMessages.count == 1 ? nil : { [weak self] in
                self?.handleTappedPinnedMessage()
            },
            isPinnedMessagesBanner: true
        )

        let banner = ConversationBannerView(configuration: bannerConfiguration)
        let longPressInteraction = UIContextMenuInteraction(delegate: self)
        banner.addInteraction(longPressInteraction)

        return banner
    }
}
