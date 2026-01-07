//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

// MARK: - Banner Management

extension ConversationViewController {

    /// Checks if there are any banners that need to be displayed and shows them as necessary.
    public func ensureBannerState() {
        AssertIsOnMainThread()

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
        var didAddPinnedMessage = false
        if let banner = createPinnedMessageBannerIfNecessary() {
            banners.append(banner)
            didAddPinnedMessage = true
        }

        let hasPriorPinnedMessages: Bool
        if let bannerStackView {
            hasPriorPinnedMessages = bannerStackView.arrangedSubviews.contains(where: { pinnedMessageBanner(view: $0) != nil })
        } else {
            hasPriorPinnedMessages = false
        }

        if hasPriorPinnedMessages, !didAddPinnedMessage, let bannerStackView {
            for banner in bannerStackView.arrangedSubviews {
                if let pinnedMessageBanner = pinnedMessageBanner(view: banner) {
                    pinnedMessageBanner.animateBannerFadeOut(completion: { _ in
                        bannerStackView.removeFromSuperview()
                        self.bannerStackView = nil
                    })
                    return
                }
            }
        }

        // This method should be called rarely, so it's simplest to discard and
        // rebuild the indicator view every time.
        if let bannerStackView {
            bannerStackView.removeFromSuperview()
            self.bannerStackView = nil
        }

        guard !banners.isEmpty else {
            if hasViewDidAppearEverBegun {
                updateContentInsets()
            }
            return
        }

        let topMargin: CGFloat = if #available(iOS 26, *) { 0 } else { 8 }
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

        if !hasPriorPinnedMessages, didAddPinnedMessage {
            for banner in bannersView.arrangedSubviews {
                if let pinnedMessageBanner = pinnedMessageBanner(view: banner) {
                    pinnedMessageBanner.animateBannerFadeIn()
                }
            }
        }

        bannerStackView = bannersView
        if hasViewDidAppearEverBegun {
            updateContentInsets()
        }
    }

    private func pinnedMessageBanner(view: UIView) -> ConversationBannerView? {
        guard
            let banner = view as? ConversationBannerView,
            let config = banner.contentView.configuration as? ConversationBannerView.ContentConfiguration,
            config.isPinnedMessagesBanner
        else {
            return nil
        }
        return banner
    }
}

// MARK: - Single class for all banners

private class ConversationBannerView: UIView {
    var contentView: UIView & UIContentView
    var blurBackgroundView: UIVisualEffectView?

    static func fadeInAnimator() -> UIViewPropertyAnimator {
        return UIViewPropertyAnimator(
            duration: 0.35,
            springDamping: 1,
            springResponse: 0.35,
        )
    }

    var pinnedMessageDelegate: PinnedMessageInteractionManagerDelegate? {
        get {
            guard let _contentView = contentView as? ConversationBannerContentView else {
                return nil
            }
            return _contentView.pinnedMessageInteractionDelegate
        }
        set {
            guard let _contentView = contentView as? ConversationBannerContentView else {
                return
            }
            _contentView.pinnedMessageInteractionDelegate = newValue
        }
    }

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
        private enum PinnedMessageConstants {
            static let bannerHeight = 50.0
            static let thumbnailSize = 30.0
            static let spacing = 8.0
            static let leadingPadding = 16.0

            // Image is 30 px, total banner is 50, which leaves 10 on top&bottom
            static let thumbnailPadding = 10.0

            // The leading scroll accessory adds 10 px to the total size when present.
            static let leadingAccessoryPadding = 10.0

            // Buffer so the text doesn't overlap with the trailing pin button.
            static let pinButtonTrailingPadding = 48.0
        }

        weak var pinnedMessageInteractionDelegate: PinnedMessageInteractionManagerDelegate?

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
        var isAnimating: Bool = false

        init(configuration: ContentConfiguration) {
            _configuration = configuration

            super.init(frame: .zero)

            axis = .horizontal
            isLayoutMarginsRelativeArrangement = true
            spacing = 12

            rebuildContent()
        }

        private func buildTitleLabel(text: String) -> UILabel {
            let _titleLabel = UILabel()
            _titleLabel.font = UIFont.dynamicTypeFootnoteClamped.semibold()
            _titleLabel.textColor = .Signal.label
            _titleLabel.numberOfLines = 1
            _titleLabel.text = text
            return _titleLabel
        }

        private func buildBodyLabel(text: NSAttributedString) -> UILabel {
            let _bodyLabel = UILabel()
            _bodyLabel.font = UIFont.dynamicTypeSubheadlineClamped
            _bodyLabel.textColor = .Signal.label
            _bodyLabel.numberOfLines = 1
            _bodyLabel.attributedText = text
            return _bodyLabel
        }

        func makeTextStackThumbnailContainer(
            thumbnail: UIImageView?,
            title: String,
            body: NSAttributedString,
            hasLeadingAccessory: Bool,
        ) -> UIView {
            let container = UIView()
            let accessoryPadding = hasLeadingAccessory ? PinnedMessageConstants.leadingAccessoryPadding : 0.0
            let textStackLeadingPadding: CGFloat
            if let thumbnail {
                container.addSubview(thumbnail)
                thumbnail.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    thumbnail.topAnchor.constraint(equalTo: container.topAnchor, constant: PinnedMessageConstants.thumbnailPadding),
                    thumbnail.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: PinnedMessageConstants.leadingPadding + accessoryPadding),
                    thumbnail.widthAnchor.constraint(equalToConstant: PinnedMessageConstants.thumbnailSize),
                ])
                textStackLeadingPadding = PinnedMessageConstants.leadingPadding +
                    accessoryPadding +
                    PinnedMessageConstants.thumbnailSize +
                    PinnedMessageConstants.spacing
            } else {
                textStackLeadingPadding = PinnedMessageConstants.leadingPadding + accessoryPadding
            }

            let _titleLabel = buildTitleLabel(text: title)
            let _bodyLabel = buildBodyLabel(text: body)

            let textStack = UIStackView(arrangedSubviews: [_titleLabel, _bodyLabel])
            textStack.axis = .vertical
            container.addSubview(textStack)

            textStack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                textStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: textStackLeadingPadding),
                textStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -PinnedMessageConstants.pinButtonTrailingPadding),
            ])
            textStack.isAccessibilityElement = true
            let axLabelPrefix = OWSLocalizedString(
                "PINNED_MESSAGE_BANNER_AX_LABEL",
                comment: "Accessibility label prefix for banner showing a pinned message",
            )
            textStack.accessibilityLabel = axLabelPrefix + title + "," + body.string
            textStack.accessibilityTraits = .button
            return container
        }

        private func rebuildContent() {
            directionalLayoutMargins = NSDirectionalEdgeInsets(hMargin: 16, vMargin: 6)

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

            if configuration.isPinnedMessagesBanner, let title = configuration.title {
                // If this is a pinned message and its not first load (no previous title), animate the existing banner off screen.
                if !titleLabel.text.isEmptyOrNil {
                    animatePinnedMessageTransition(
                        newTitle: title,
                        newBody: configuration.body,
                        newThumbnail: configuration.thumbnail,
                    )
                } else {
                    // Otherwise build from scratch.
                    let container = makeTextStackThumbnailContainer(
                        thumbnail: configuration.thumbnail,
                        title: title,
                        body: configuration.body,
                        hasLeadingAccessory: configuration.leadingAccessoryView != nil,
                    )

                    // Store copies of old banner strings for the next animation.
                    titleLabel = buildTitleLabel(text: title)
                    bodyLabel = buildBodyLabel(text: configuration.body)

                    addSubview(container)
                    container.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        container.leadingAnchor.constraint(equalTo: leadingAnchor),
                        container.trailingAnchor.constraint(equalTo: trailingAnchor),
                        container.topAnchor.constraint(equalTo: topAnchor),
                        container.heightAnchor.constraint(equalToConstant: PinnedMessageConstants.bannerHeight),
                    ])
                }
            } else {
                bodyLabel = UILabel()
                bodyLabel.font = UIFont.dynamicTypeSubheadlineClamped
                bodyLabel.textColor = .Signal.label
                bodyLabel.numberOfLines = 0
                bodyLabel.attributedText = configuration.body
                addArrangedSubview(bodyLabel)
            }

            if
                let viewButtonTitle = configuration.viewButtonTitle,
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
                    comment: "Accessibility label for banner close button",
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

            if configuration.isPinnedMessagesBanner {
                let button: UIButton
                if #available(iOS 26.0, *) {
                    button = UIButton(configuration: .clearGlass())
                } else {
                    button = UIButton(configuration: .plain())
                }
                button.configuration?.image = .pin
                button.configuration?.cornerStyle = .capsule
                button.configuration?.contentInsets = .init(margin: 6)
                button.accessibilityLabel = OWSLocalizedString(
                    "PINNED_MESSAGE_MENU_ACCESSIBILITY_LABEL",
                    comment: "Accessibility label for pin message button",
                )
                button.setCompressionResistanceHigh()
                button.setContentHuggingHigh()

                button.menu = pinMessageMenu()
                button.showsMenuAsPrimaryAction = true
                button.tintColor = .Signal.label

                let buttonContainer = UIView.container()
                buttonContainer.addSubview(button)
                button.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    button.topAnchor.constraint(greaterThanOrEqualTo: buttonContainer.topAnchor),
                    button.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
                    button.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
                    button.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor),
                ])
                addSubview(buttonContainer)
                buttonContainer.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    buttonContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
                    buttonContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                ])

                // Total banner height should always be 50 for pinned messages.
                NSLayoutConstraint.activate([
                    heightAnchor.constraint(equalToConstant: PinnedMessageConstants.bannerHeight),
                ])
            }

            if configuration.bannerTapAction != nil {
                addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapBanner)))
            }
        }

        private func pinMessageMenu() -> UIMenu {
            var actions: [UIAction] = []
            if BuildFlags.PinnedMessages.send {
                actions.append(
                    UIAction(
                        title: OWSLocalizedString(
                            "PINNED_MESSAGES_UNPIN",
                            comment: "Action menu item to unpin a message",
                        ),
                        image: .pinSlash,
                    ) { [weak self] _ in
                        self?.pinnedMessageInteractionDelegate?.unpinMessage(message: nil, modalDelegate: nil)
                    },
                )
            }
            actions.append(
                contentsOf: [
                    UIAction(
                        title: OWSLocalizedString(
                            "PINNED_MESSAGES_GO_TO_MESSAGE",
                            comment: "Action menu item to go to a message in the conversation view",
                        ),
                        image: .chatArrow,
                    ) { [weak self] _ in
                        self?.pinnedMessageInteractionDelegate?.goToMessage(message: nil)
                    },
                    UIAction(title: OWSLocalizedString(
                        "PINNED_MESSAGES_SEE_ALL_MESSAGES",
                        comment: "Action menu item to see all pinned messages",
                    ), image: .listBullet) { [weak self] _ in
                        self?.pinnedMessageInteractionDelegate?.presentSeeAllMessages()
                    },
                ])
            return UIMenu(children: actions)
        }

        private func animatePinnedMessageTransition(
            newTitle: String,
            newBody: NSAttributedString,
            newThumbnail: UIImageView?,
        ) {
            guard
                let titleText = titleLabel.text,
                let bodyText = bodyLabel.attributedText
            else {
                return
            }

            // Make container for old textStack
            let oldContainer = makeTextStackThumbnailContainer(
                thumbnail: thumbnail,
                title: titleText,
                body: bodyText,
                hasLeadingAccessory: true,
            )
            addSubview(oldContainer)

            oldContainer.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                oldContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
                oldContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
                oldContainer.topAnchor.constraint(equalTo: topAnchor),
                oldContainer.heightAnchor.constraint(equalToConstant: PinnedMessageConstants.bannerHeight),
            ])

            // Build container for new textStack
            let newContainer = makeTextStackThumbnailContainer(
                thumbnail: newThumbnail,
                title: newTitle,
                body: newBody,
                hasLeadingAccessory: true,
            )
            addSubview(newContainer)

            newContainer.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                newContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
                newContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
                newContainer.topAnchor.constraint(equalTo: topAnchor),
                newContainer.heightAnchor.constraint(equalToConstant: PinnedMessageConstants.bannerHeight),
            ])

            // Initial positions
            oldContainer.transform = .identity
            newContainer.transform = CGAffineTransform(translationX: 0, y: PinnedMessageConstants.bannerHeight)

            let pinAnimator = UIViewPropertyAnimator(
                duration: 0.3,
                springDamping: 1,
                springResponse: 0.3,
            )

            pinAnimator.addAnimations {
                oldContainer.transform = CGAffineTransform(translationX: 0, y: -PinnedMessageConstants.bannerHeight)
                newContainer.transform = .identity
            }

            pinAnimator.addCompletion { _ in
                self.isAnimating = false
                oldContainer.removeFromSuperview()

                // Store the new text & thumbnails so we can reference them
                // as the "old" ones next time we animate.
                self.titleLabel = self.buildTitleLabel(text: newTitle)
                self.bodyLabel = self.buildBodyLabel(text: newBody)
                self.thumbnail = newThumbnail
            }

            isAnimating = true
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
            blurBackgroundView = visualEffectView
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

    func isAnimating() -> Bool {
        guard let bannerContentView = contentView as? ConversationBannerContentView else {
            return false
        }
        return bannerContentView.isAnimating
    }

    func animateBannerFadeIn() {
        guard let contentView = contentView as? ConversationBannerContentView else {
            return
        }
        let animator = ConversationBannerView.fadeInAnimator()
        UIView.performWithoutAnimation {
            blurBackgroundView?.effect = nil
            contentView.bodyLabel.alpha = 0
            contentView.titleLabel.alpha = 0
            contentView.thumbnail?.alpha = 0
        }

        animator.addAnimations {
            if let backgroundViewEffect = self.backgroundViewVisualEffect() {
                self.blurBackgroundView?.effect = backgroundViewEffect
            }
            contentView.bodyLabel.alpha = 1
            contentView.titleLabel.alpha = 1
            contentView.thumbnail?.alpha = 1
        }

        animator.startAnimation()
    }

    func animateBannerFadeOut(completion: @escaping (UIViewAnimatingPosition) -> Void) {
        guard let contentView = contentView as? ConversationBannerContentView else {
            return
        }
        let animator = ConversationBannerView.fadeInAnimator()
        UIView.performWithoutAnimation {
            if let backgroundViewEffect = self.backgroundViewVisualEffect() {
                self.blurBackgroundView?.effect = backgroundViewEffect
            }
            contentView.bodyLabel.alpha = 1
            contentView.titleLabel.alpha = 1
            contentView.thumbnail?.alpha = 1
        }

        animator.addAnimations {
            self.blurBackgroundView?.effect = nil
            contentView.bodyLabel.alpha = 0
            contentView.titleLabel.alpha = 0
            contentView.thumbnail?.alpha = 0
        }

        animator.addCompletion(completion)

        animator.startAnimation()
    }

    private func backgroundViewVisualEffect() -> UIVisualEffect? {
        if #available(iOS 26, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.tintColor = UIColor { traitCollection in
                if traitCollection.userInterfaceStyle == .dark {
                    return UIColor(white: 0, alpha: 0.2)
                }
                return UIColor(white: 1, alpha: 0.12)
            }
            return glassEffect
        }

        guard !UIAccessibility.isReduceTransparencyEnabled else { return nil }

        let blurEffect = Theme.barBlurEffect
        return blurEffect
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

        guard
            let (avatar1, avatar2) = SSKEnvironment.shared.databaseStorageRef.read(block: { tx -> (UIImage?, UIImage?)? in
                guard
                    viewState.shouldShowMessageRequestNameCollisionBanner(transaction: tx),
                    let collision = collisionFinder.findCollisions(transaction: tx).first
                else { return nil }

                return (
                    fetchAvatar(for: collision.elements[0].address, tx: tx),
                    fetchAvatar(for: collision.elements[1].address, tx: tx),
                )
            }) else { return nil }

        let bannerConfiguration = ConversationBannerView.ContentConfiguration(
            title: nil,
            body: OWSLocalizedString(
                "MESSAGE_REQUEST_NAME_COLLISION_BANNER_LABEL",
                comment: "Banner label notifying user that a new message is from a user with the same name as an existing contact",
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
            isPinnedMessagesBanner: false,
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
        guard
            let (title, avatar1, avatar2) = SSKEnvironment.shared.databaseStorageRef.read(block: { readTx -> (String, UIImage?, UIImage?)? in
                let collisionSets = collisionFinder.findCollisions(transaction: readTx)
                guard !collisionSets.isEmpty else { return nil }

                let totalCollisionElementCount = collisionSets.reduce(0) { $0 + $1.elements.count }

                let title: String

                if collisionSets.count > 1 {
                    let titleFormat = OWSLocalizedString(
                        "GROUP_MEMBERSHIP_MULTIPLE_COLLISIONS_BANNER_TITLE_%d",
                        tableName: "PluralAware",
                        comment: "Banner title alerting user to a name collision set ub the group membership. Embeds {{ total number of colliding members }}",
                    )
                    title = String.localizedStringWithFormat(titleFormat, collisionSets.count)
                } else {
                    let titleFormat = OWSLocalizedString(
                        "GROUP_MEMBERSHIP_COLLISIONS_BANNER_TITLE_%d",
                        tableName: "PluralAware",
                        comment: "Banner title alerting user about multiple name collisions in group membership. Embeds {{ number of sets of colliding members }}",
                    )
                    title = String.localizedStringWithFormat(titleFormat, totalCollisionElementCount)
                }

                let avatar1 = fetchAvatar(
                    for: collisionSets[0].elements[0].address,
                    tx: readTx,
                )
                let avatar2 = fetchAvatar(
                    for: collisionSets[0].elements[1].address,
                    tx: readTx,
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
                    collisionDelegate: self,
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
                    },
                )
            },
            leadingAccessoryView: DoubleProfileImageView(primaryImage: avatar1, secondaryImage: avatar2),
            isPinnedMessagesBanner: false,
        )

        return ConversationBannerView(configuration: bannerConfiguration)
    }

    private func fetchAvatar(for address: SignalServiceAddress, tx: DBReadTransaction) -> UIImage? {
        return SSKEnvironment.shared.avatarBuilderRef.avatarImage(
            forAddress: address,
            diameterPoints: 24,
            localUserDisplayMode: .asUser,
            transaction: tx,
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
                constant: hasSecondaryImage ? 12 : 0,
            )
            let leading = primaryImageView.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: hasSecondaryImage ? 16 : 4,
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
                            y: bounds.center.y - borderSize,
                        ),
                        size: bounds.size.plus(.square(borderSize * 2)),
                    ),
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
        guard
            let pendingMemberRequests,
            !pendingMemberRequests.isEmpty,
            canApprovePendingMemberRequests
        else {
            return nil
        }

        // We will skip this read if the above checks fail, which will be most of the time.
        guard
            SSKEnvironment.shared.databaseStorageRef.read(block: { tx in
                viewState.shouldShowPendingMemberRequestsBanner(
                    currentPendingMembers: pendingMemberRequests,
                    transaction: tx,
                )
            })
        else {
            return nil
        }

        let format = OWSLocalizedString(
            "PENDING_GROUP_MEMBERS_REQUEST_BANNER_%d",
            tableName: "PluralAware",
            comment: "Format for banner indicating that there are pending member requests to join the group. Embeds {{ the number of pending member requests }}.",
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
                        transaction: transaction,
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
            isPinnedMessagesBanner: false,
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
                ? OWSLocalizedString(
                    "MESSAGES_VIEW_1_MEMBER_NO_LONGER_VERIFIED_FORMAT",
                    comment: "Indicates that one member of this group conversation is no longer verified. Embeds {{user's name or phone number}}.",
                )
                : OWSLocalizedString(
                    "MESSAGES_VIEW_CONTACT_NO_LONGER_VERIFIED_FORMAT",
                    comment: "Indicates that this 1:1 conversation is no longer verified. Embeds {{user's name or phone number}}.",
                )
            title = String(format: format, displayName)

        default:
            title = OWSLocalizedString(
                "MESSAGES_VIEW_N_MEMBERS_NO_LONGER_VERIFIED",
                comment: "Indicates that more than one member of this group conversation is no longer verified.",
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
            isPinnedMessagesBanner: false,
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
                comment: "Label for button or row which allows users to verify the safety number of another user.",
            )
        default:
            title = OWSLocalizedString(
                "VERIFY_PRIVACY_MULTIPLE",
                comment: "Label for button or row which allows users to verify the safety numbers of multiple users.",
            )
        }

        let actionSheet = ActionSheetController()

        actionSheet.addAction(ActionSheetAction(title: title, style: .default) { [weak self] _ in
            self?.showNoLongerVerifiedUI(noLongerVerifiedIdentityKeys: noLongerVerifiedIdentityKeys)
        })

        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.dismissButton,
            style: .cancel,
        ) { [weak self] _ in
            self?.resetVerificationStateToDefault(noLongerVerifiedIdentityKeys: noLongerVerifiedIdentityKeys)
        })

        dismissKeyBoard()
        presentActionSheet(actionSheet)
    }
}

// MARK: - Pinned Messages

extension ConversationViewController {
    func animateToNextPinnedMessage() {
        guard
            let nextPinnedMessage = createPinnedMessageBannerIfNecessary(),
            let priorPinnedMessage = bannerStackView?.arrangedSubviews.last as? ConversationBannerView
        else {
            return
        }
        priorPinnedMessage.contentView.configuration = nextPinnedMessage.contentView.configuration
    }

    /// Displays the first pinned message, sorted by most recently pinned.
    /// When tapped, it cycles to the next pinned message if one exists.
    private func createPinnedMessageBannerIfNecessary() -> ConversationBannerView? {
        guard
            threadViewModel.pinnedMessages.indices.contains(pinnedMessageIndex),
            let pinnedMessageData = pinnedMessageData(for: threadViewModel.pinnedMessages[pinnedMessageIndex])
        else {
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
            bannerTapAction: { [weak self] in
                guard let priorPinnedMessage = self?.bannerStackView?.arrangedSubviews.last as? ConversationBannerView else {
                    return
                }

                if !priorPinnedMessage.isAnimating() {
                    self?.handleTappedPinnedMessage()
                }
            },
            isPinnedMessagesBanner: true,
        )

        let banner = ConversationBannerView(configuration: bannerConfiguration)

        let longPressInteraction = UIContextMenuInteraction(delegate: self)
        banner.blurBackgroundView?.addInteraction(longPressInteraction)

        // Set up interaction delegate for pin icon menu
        banner.pinnedMessageDelegate = self

        return banner
    }
}
