//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

final public class SafetyNumberConfirmationSheet: UIViewController {
    let stackView = UIStackView()
    let contentView = UIView()
    let backdropView = UIView()
    let tableView = UITableView()

    struct Item {
        let address: SignalServiceAddress
        let displayName: String
        let verificationState: OWSVerificationState
        let identityKey: Data?
    }

    private var confirmationItems: [Item]

    let confirmAction: ActionSheetAction
    let cancelAction: ActionSheetAction
    let completionHandler: (Bool) -> Void
    public var allowsDismissal: Bool = true

    public init(
        addressesToConfirm: [SignalServiceAddress],
        confirmationText: String,
        cancelText: String = CommonStrings.cancelButton,
        completionHandler: @escaping (Bool) -> Void
    ) {
        assert(!addressesToConfirm.isEmpty)

        self.confirmationItems = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            Self.buildConfirmationItems(
                addressesToConfirm: addressesToConfirm,
                transaction: transaction
            )
        }

        self.confirmAction = ActionSheetAction(title: confirmationText, style: .default)
        self.cancelAction = ActionSheetAction(title: cancelText, style: .cancel)
        self.completionHandler = completionHandler

        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .custom
        transitioningDelegate = self

        observeIdentityChangeNotification()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    fileprivate static func buildConfirmationItems(
        addressesToConfirm: [SignalServiceAddress],
        transaction tx: DBReadTransaction
    ) -> [Item] {
        let identityManager = DependenciesBridge.shared.identityManager
        return addressesToConfirm.map { address in
            let recipientIdentity = identityManager.recipientIdentity(for: address, tx: tx)
            return Item(
                address: address,
                displayName: SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: tx).resolvedValue(),
                verificationState: recipientIdentity?.verificationState ?? .default,
                identityKey: recipientIdentity?.identityKey
            )
        }
    }

    // MARK: - Identity change notification

    private func observeIdentityChangeNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(identityStateDidChange),
            name: .identityStateDidChange,
            object: nil
        )
    }

    /// Rebuild our confirmation items and reload the table, to ensure we
    /// reflect the latest identity state after the user may have verified
    /// one of the addresses we presented.
    @objc
    private func identityStateDidChange() {
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            let addressesToConfirm = confirmationItems.map { $0.address }

            confirmationItems = Self.buildConfirmationItems(
                addressesToConfirm: addressesToConfirm,
                transaction: transaction
            )
        }

        tableView.reloadData()
    }

    // MARK: - Present if necessary

    public class func presentIfNecessary(
        address: SignalServiceAddress,
        confirmationText: String,
        forceDarkTheme: Bool = false,
        completion: @escaping (Bool) -> Void
    ) -> Bool {
        return presentIfNecessary(
            addresses: [address],
            confirmationText: confirmationText,
            forceDarkTheme: forceDarkTheme,
            completion: completion
        )
    }

    /**
     * Shows confirmation dialog if at least one of the recipient id's is not confirmed.
     *
     * @returns true  if an alert was shown
     *          false if there were no unconfirmed identities
     */
    public class func presentIfNecessary(
        addresses: [SignalServiceAddress],
        confirmationText: String,
        untrustedThreshold: Date? = nil,
        forceDarkTheme: Bool = false,
        completion: @escaping (Bool) -> Void
    ) -> Bool {
        return presentIfNecessary(
            for: addresses,
            from: CurrentAppContext().frontmostViewController(),
            confirmationText: confirmationText,
            untrustedThreshold: untrustedThreshold,
            forceDarkTheme: forceDarkTheme,
            completion: completion
        )
    }

    /// Presents the a `SafetyNumberConfirmationSheet` if needed.
    ///
    /// The sheet will be presented repeatedly to handle cases where Safety
    /// Numbers change while the sheet is visible.
    ///
    /// This method will recompute `addresses` before the initial sheet
    /// presentation as well as after each sheet presentation.
    ///
    /// - Returns: True if the user accepted all Safety Number changes OR if
    /// there weren't any that needed to be accepted.
    public class func presentRepeatedlyAsNecessary(
        for addresses: () -> [SignalServiceAddress],
        from viewController: UIViewController,
        confirmationText: String,
        untrustedThreshold: Date? = nil,
        forceDarkTheme: Bool = false,
        didPresent didPresentBlock: @MainActor () -> Void = {},
    ) async -> Bool {
        while true {
            var untrustedThreshold = untrustedThreshold
            let terminalResult: Bool? = await withCheckedContinuation { continuation in
                let newUntrustedThreshold = Date()
                defer { untrustedThreshold = newUntrustedThreshold }

                let didPresent = self.presentIfNecessary(
                    for: addresses(),
                    from: viewController,
                    confirmationText: confirmationText,
                    untrustedThreshold: untrustedThreshold,
                    forceDarkTheme: forceDarkTheme,
                    completion: { didConfirmIdentity in
                        if didConfirmIdentity {
                            // The user said it's fine -- loop and check for more mismatches.
                            continuation.resume(returning: nil)
                        } else {
                            continuation.resume(returning: false)
                        }
                    }
                )
                if didPresent {
                    didPresentBlock()
                } else {
                    continuation.resume(returning: true)
                }
            }
            if let terminalResult {
                return terminalResult
            }
        }
    }

    public class func presentIfNecessary(
        for addresses: [SignalServiceAddress],
        from viewController: UIViewController?,
        confirmationText: String,
        untrustedThreshold: Date?,
        forceDarkTheme: Bool = false,
        completion: @escaping (Bool) -> Void
    ) -> Bool {
        let identityManager = DependenciesBridge.shared.identityManager
        let untrustedAddresses = SSKEnvironment.shared.databaseStorageRef.read { tx in
            addresses.filter { address in
                identityManager.untrustedIdentityForSending(to: address, untrustedThreshold: untrustedThreshold, tx: tx) != nil
            }
        }

        guard !untrustedAddresses.isEmpty else {
            // No identities to confirm, no alert to present.
            return false
        }

        let sheet = SafetyNumberConfirmationSheet(
            addressesToConfirm: untrustedAddresses,
            confirmationText: confirmationText,
            completionHandler: completion
        )
        if forceDarkTheme {
            sheet.overrideUserInterfaceStyle = .dark
        }

        viewController?.present(sheet, animated: true)
        return true
    }

    // MARK: -

    override public func loadView() {
        view = UIView()
        let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .prominent))

        view.addSubview(backgroundView)
        view.addSubview(contentView)
        backgroundView.autoPinEdges(toEdgesOf: contentView)

        contentView.autoHCenterInSuperview()
        contentView.autoMatch(.height, to: .height, of: view, withOffset: 0, relation: .lessThanOrEqual)

        // Prefer to be full width, but don't exceed the maximum width
        contentView.autoSetDimension(.width, toSize: maxWidth, relation: .lessThanOrEqual)
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            contentView.autoPinWidthToSuperview()
        }

        [backgroundView, contentView].forEach { subview in
            subview.layer.cornerRadius = 24
            subview.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            subview.layer.masksToBounds = true
        }

        stackView.axis = .vertical
        stackView.alignment = .center
        contentView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewSafeArea()

        // Support tapping the backdrop to cancel the action sheet.
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapBackdrop(_:)))
        tapGestureRecognizer.delegate = self
        view.addGestureRecognizer(tapGestureRecognizer)

        // Setup header

        let titleLabel = UILabel()
        titleLabel.textAlignment = .natural
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.font = UIFont.dynamicTypeSubheadline.semibold()
        titleLabel.textColor = UIColor.Signal.label
        titleLabel.text = OWSLocalizedString("SAFETY_NUMBER_CONFIRMATION_TITLE",
                                             comment: "Title for the 'safety number confirmation' view")

        let messageLabel = UILabel()
        messageLabel.textAlignment = .natural
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.font = .dynamicTypeSubheadline
        messageLabel.textColor = UIColor.Signal.label
        messageLabel.text = OWSLocalizedString("SAFETY_NUMBER_CONFIRMATION_MESSAGE",
                                               comment: "Message for the 'safety number confirmation' view")

        let headerStack = UIStackView(arrangedSubviews: [
            titleLabel,
            messageLabel
        ])
        headerStack.axis = .vertical
        headerStack.spacing = 4
        headerStack.isLayoutMarginsRelativeArrangement = true
        headerStack.layoutMargins = UIEdgeInsets(top: 24, left: 28, bottom: 16, right: 28)
        stackView.addArrangedSubview(headerStack)
        headerStack.autoPinWidthToSuperview()

        stackView.addArrangedSubview(tableView)
        tableView.autoPinWidthToSuperview()
        tableView.alwaysBounceVertical = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.register(SafetyNumberCell.self, forCellReuseIdentifier: SafetyNumberCell.reuseIdentifier)
        tableView.setContentHuggingHigh()
        tableView.setCompressionResistanceLow()

        stackView.addArrangedSubview(confirmAction.button)
        stackView.setCustomSpacing(10, after: confirmAction.button)
        confirmAction.button.autoPinWidthToSuperview(withMargin: 16)
        confirmAction.button.releaseAction = { [weak self] in
            guard let self = self else { return }
            SSKEnvironment.shared.databaseStorageRef.asyncWrite(block: { tx in
                let identityManager = DependenciesBridge.shared.identityManager
                for item in self.confirmationItems {
                    guard let identityKey = item.identityKey else {
                        return
                    }
                    switch identityManager.verificationState(for: item.address, tx: tx) {
                    case .verified:
                        // We don't want to overwrite any addresses that have been verified since
                        // we last checked.
                        return
                    case .noLongerVerified, .implicit(isAcknowledged: _):
                        break
                    }
                    _ = identityManager.setVerificationState(
                        .implicit(isAcknowledged: true),
                        of: identityKey,
                        for: item.address,
                        isUserInitiatedChange: true,
                        tx: tx
                    )
                }
            }, completionQueue: .main) {
                self.dismiss(animated: true) { self.completionHandler(true) }
            }
        }

        stackView.addArrangedSubview(cancelAction.button)
        cancelAction.button.autoPinWidthToSuperview(withMargin: 16)
        cancelAction.button.releaseAction = { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true) { self.completionHandler(false) }
        }
    }

    private var hasPreparedInitialLayout = false
    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        guard !hasPreparedInitialLayout else { return }
        hasPreparedInitialLayout = true

        // Setup handle for interactive dismissal / resizing
        setupInteractiveSizing()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        let profileFetcher = SSKEnvironment.shared.profileFetcherRef

        // When the view appears, fetch profiles if it's been a while to ensure we
        // have the latest identity key.
        for confirmationItem in confirmationItems {
            guard let serviceId = confirmationItem.address.serviceId else {
                continue
            }
            Task {
                do {
                    _ = try await profileFetcher.fetchProfile(for: serviceId, context: .init(isOpportunistic: true))
                } catch {
                    Logger.warn("Didn't fetch profile for Safety Number change: \(error)")
                }
            }
        }
    }

    @objc
    private func didTapBackdrop(_ sender: UITapGestureRecognizer) {
        guard allowsDismissal else { return }
        dismiss(animated: true)
    }

    // MARK: - Resize / Interactive Dismiss

    var bottomConstraint: NSLayoutConstraint?
    var heightConstraint: NSLayoutConstraint?
    let maxWidth: CGFloat = 414

    lazy var baseStackViewHeight: CGFloat = {
        tableView.isHidden = true
        stackView.layoutIfNeeded()

        let baseStackViewHeight = stackView.height

        tableView.isHidden = false
        stackView.layoutIfNeeded()

        return baseStackViewHeight
    }()

    lazy var cellHeight = tableView.cellForRow(at: IndexPath(row: 0, section: 0))?.height ?? 72

    var minimizedHeight: CGFloat {
        // We want to show, at most, 3.5 rows when minimized. When we have
        // less than 4 rows, we will match our size to the number of rows.
        let compactTableViewHeight = min(CGFloat(confirmationItems.count), 3.5) * cellHeight
        let preferredMinimizedHeight = baseStackViewHeight + compactTableViewHeight + view.safeAreaInsets.bottom

        return min(maximizedHeight, preferredMinimizedHeight)
    }

    var maximizedHeight: CGFloat {
        let tableViewHeight = CGFloat(confirmationItems.count) * cellHeight
        let preferredMaximizedHeight = baseStackViewHeight + tableViewHeight + view.safeAreaInsets.bottom
        let maxPermittedHeight = CurrentAppContext().frame.height - view.safeAreaInsets.top - 16

        return min(preferredMaximizedHeight, maxPermittedHeight)
    }

    var desiredVisibleContentHeight: CGFloat = 0 {
        didSet {
            updateConstraints(withDesiredContentHeight: desiredVisibleContentHeight)
        }
    }

    func updateConstraints(withDesiredContentHeight height: CGFloat) {
        // To prevent views from getting compressed, if the desired appearance height is less than
        // the minimized height, we translate the content off the bottom edge
        let newHeightConstant = max(minimizedHeight, desiredVisibleContentHeight)
        let newBottomOffset = max((minimizedHeight - desiredVisibleContentHeight), 0)

        if let heightConstraint = heightConstraint {
            heightConstraint.constant = newHeightConstant
        } else {
            heightConstraint = contentView.autoSetDimension(.height, toSize: newHeightConstant)
        }

        if let bottomConstraint = bottomConstraint {
            bottomConstraint.constant = newBottomOffset
        } else {
            bottomConstraint = contentView.autoPinEdge(toSuperviewEdge: .bottom, withInset: -newBottomOffset)
        }
    }

    var visibleContentHeight: CGFloat {
        let contentRect = contentView.convert(contentView.bounds, to: view)
        return view.bounds.intersection(contentRect).height
    }

    let maxAnimationDuration: TimeInterval = 0.2
    var startingHeight: CGFloat?
    var startingTranslation: CGFloat?
    var pinnedContentOffset: CGPoint?

    func setupInteractiveSizing() {
        desiredVisibleContentHeight = minimizedHeight

        // Create a pan gesture to handle when the user interacts with the
        // view outside of the reactor table views.
        let panGestureRecognizer = DirectionalPanGestureRecognizer(direction: .vertical, target: self, action: #selector(handlePan))
        view.addGestureRecognizer(panGestureRecognizer)
        panGestureRecognizer.delegate = self

        // We also want to handle the pan gesture for the table
        // view, so we can do a nice scroll to dismiss gesture, and
        // so we can transfer any initial scrolling into maximizing
        // the view.
        tableView.panGestureRecognizer.addTarget(self, action: #selector(handlePan))
    }

    @objc
    private func handlePan(_ sender: UIPanGestureRecognizer) {
        switch sender.state {
        case .began, .changed:
            guard beginInteractiveTransitionIfNecessary(sender),
                let startingHeight = startingHeight,
                let startingTranslation = startingTranslation,
                let pinnedContentOffset = pinnedContentOffset else {
                    return resetInteractiveTransition()
            }

            // We're in an interactive transition, so don't let the scrollView scroll.
            tableView.contentOffset = pinnedContentOffset
            tableView.showsVerticalScrollIndicator = false

            // We may have panned some distance if we were scrolling before we started
            // this interactive transition. Offset the translation we use to move the
            // view by whatever the translation was when we started the interactive
            // portion of the gesture.
            let translation = sender.translation(in: view).y - startingTranslation

            var newHeight = startingHeight - translation
            if newHeight > maximizedHeight {
                newHeight = maximizedHeight
            }

            // If the height is decreasing, adjust the relevant view's proporitionally
            if newHeight < startingHeight {
                backdropView.alpha = 1 - (startingHeight - newHeight) / startingHeight
            }

            // Update our height to reflect the new position
            desiredVisibleContentHeight = newHeight
            view.layoutIfNeeded()
        case .ended, .cancelled, .failed:
            guard let startingHeight = startingHeight else { break }

            let dismissThreshold = startingHeight * 0.5
            let growThreshold = (maximizedHeight - startingHeight) * 0.5
            let velocityThreshold: CGFloat = 500

            let currentHeight = visibleContentHeight
            let currentVelocity = sender.velocity(in: view).y

            enum CompletionState { case growing, dismissing, cancelling }
            let completionState: CompletionState

            if abs(currentVelocity) >= velocityThreshold {
                if currentVelocity < 0 {
                    completionState = .growing
                } else {
                    completionState = allowsDismissal ? .dismissing : .cancelling
                }
            } else if currentHeight - startingHeight >= growThreshold {
                completionState = .growing
            } else if currentHeight <= dismissThreshold, allowsDismissal {
                completionState = .dismissing
            } else {
                completionState = .cancelling
            }

            let finalHeight: CGFloat
            switch completionState {
            case .dismissing:
                finalHeight = 0
            case .growing:
                finalHeight = maximizedHeight
            case .cancelling:
                finalHeight = startingHeight
            }

            let remainingDistance = finalHeight - visibleContentHeight

            // Calculate the time to complete the animation if we want to preserve
            // the user's velocity. If this time is too slow (e.g. the user was scrolling
            // very slowly) we'll default to `maxAnimationDuration`
            let remainingTime = TimeInterval(abs(remainingDistance / currentVelocity))

            UIView.animate(withDuration: min(remainingTime, maxAnimationDuration), delay: 0, options: .curveEaseOut, animations: {
                self.desiredVisibleContentHeight = finalHeight
                self.view.layoutIfNeeded()
                self.backdropView.alpha = completionState == .dismissing ? 0 : 1
            }) { _ in
                owsAssertDebug(completionState != .dismissing || self.allowsDismissal)
                self.desiredVisibleContentHeight = finalHeight
                if completionState == .dismissing { self.dismiss(animated: false, completion: nil) }
            }

            resetInteractiveTransition()
        default:
            resetInteractiveTransition()

            backdropView.alpha = 1

            guard let startingHeight = startingHeight else { break }
            desiredVisibleContentHeight = startingHeight
        }
    }

    func beginInteractiveTransitionIfNecessary(_ sender: UIPanGestureRecognizer) -> Bool {
        let tryingToDismiss = tableView.contentOffset.y <= 0 || tableView.panGestureRecognizer != sender
        let tryingToMaximize = visibleContentHeight < maximizedHeight && tableView.height < tableView.contentSize.height

        // If we're at the top of the scrollView, or the view is not
        // currently maximized, we want to do an interactive transition.
        guard tryingToDismiss || tryingToMaximize else { return false }

        if startingTranslation == nil {
            startingTranslation = sender.translation(in: view).y
        }

        if startingHeight == nil {
            startingHeight = visibleContentHeight
        }

        if pinnedContentOffset == nil {
            pinnedContentOffset = tableView.contentOffset.y < 0 ? .zero : tableView.contentOffset
        }

        return true
    }

    func resetInteractiveTransition() {
        startingTranslation = nil
        startingHeight = nil
        if let pinnedContentOffset = pinnedContentOffset {
            tableView.contentOffset = pinnedContentOffset
        }
        pinnedContentOffset = nil
        tableView.showsVerticalScrollIndicator = true
    }

    public override func viewSafeAreaInsetsDidChange() {
        // The minimized height is dependent on safe the current safe area insets
        // If they every change, reset the content height to the new minimized height
        super.viewSafeAreaInsetsDidChange()
        desiredVisibleContentHeight = minimizedHeight
    }
}

// MARK: -

extension SafetyNumberConfirmationSheet: UITableViewDelegate, UITableViewDataSource {
    public func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return confirmationItems.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SafetyNumberCell.reuseIdentifier,
                                                 for: indexPath)

        guard let contactCell = cell as? SafetyNumberCell else {
            return cell
        }

        guard let item = confirmationItems[safe: indexPath.row] else {
            return cell
        }

        UIView.performWithoutAnimation {
            contactCell.configure(item: item, viewController: self)
        }

        return contactCell
    }
}

// MARK: -

private class SafetyNumberCell: ContactTableViewCell {

    open override class var reuseIdentifier: String { "SafetyNumberCell" }

    let button = UIButton()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        var config = UIButton.Configuration.gray()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = UIColor.Signal.secondaryFill
        config.contentInsets = .init(hMargin: 16, vMargin: 6)
        config.title = OWSLocalizedString(
            "SAFETY_NUMBER_CONFIRMATION_VIEW_ACTION",
            comment: "View safety number action for the 'safety number confirmation' view"
        )
        config.titleTextAttributesTransformer = .defaultFont(.dynamicTypeSubheadline.semibold())
        button.configuration = config
        button.addTarget(self, action: #selector(performButtonActon), for: .touchUpInside)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: SafetyNumberConfirmationSheet.Item, viewController: UIViewController) {
        self.buttonAction = {
            FingerprintViewController.present(for: item.address.aci, from: viewController)
        }

        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            let configuration = ContactCellConfiguration(address: item.address, localUserDisplayMode: .asUser)
            configuration.allowUserInteraction = true

            configuration.forceDarkAppearance = traitCollection.userInterfaceStyle == .dark

            let buttonSize = button.intrinsicContentSize
            button.removeFromSuperview()
            let buttonWrapper = ManualLayoutView.wrapSubviewUsingIOSAutoLayout(button)
            configuration.accessoryView = ContactCellAccessoryView(accessoryView: buttonWrapper,
                                                                   size: buttonSize)

            switch item.verificationState {
            case .noLongerVerified:
                configuration.attributedSubtitle = .prefixedWithCheck(text: OWSLocalizedString(
                    "SAFETY_NUMBER_CONFIRMATION_PREVIOUSLY_VERIFIED",
                    comment: "Text explaining that the given contact previously had their safety number verified."
                ))
            case .verified:
                configuration.attributedSubtitle = .prefixedWithCheck(text: OWSLocalizedString(
                    "SAFETY_NUMBER_CONFIRMATION_VERIFIED",
                    comment: "Text explaining that the given contact has had their safety number verified."
                ))
            case .`default`, .defaultAcknowledged:
                if let phoneNumber = item.address.phoneNumber {
                    let formattedPhoneNumber = PhoneNumber.bestEffortLocalizedPhoneNumber(e164: phoneNumber)

                    if item.displayName != formattedPhoneNumber {
                        configuration.attributedSubtitle = NSAttributedString(string: formattedPhoneNumber)
                    }
                }
            }

            self.configure(configuration: configuration, transaction: transaction)
        }
    }

    override func configure(configuration: ContactCellConfiguration, transaction: DBReadTransaction) {
        super.configure(configuration: configuration, transaction: transaction)
        backgroundColor = nil
    }

    private var buttonAction: (() -> Void)?

    @objc
    private func performButtonActon() {
        buttonAction?()
    }
}

private extension NSAttributedString {
    static func prefixedWithCheck(
        text: String
    ) -> NSAttributedString {
        let string = NSMutableAttributedString()

        string.appendTemplatedImage(named: "check-extra-small", font: UIFont.regularFont(ofSize: 11))
        string.append(" ")
        string.append(text)

        return string
    }
}

// MARK: -
extension SafetyNumberConfirmationSheet: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        switch gestureRecognizer {
        case is UITapGestureRecognizer:
            let point = gestureRecognizer.location(in: view)
            guard !contentView.frame.contains(point) else { return false }
            return true
        default:
            return true
        }
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        switch gestureRecognizer {
        case is UIPanGestureRecognizer:
            return tableView.panGestureRecognizer == otherGestureRecognizer
        default:
            return false
        }
    }
}

// MARK: -

final private class SafetyNumberConfirmationAnimationController: UIPresentationController {

    var backdropView: UIView? {
        guard let vc = presentedViewController as? SafetyNumberConfirmationSheet else { return nil }
        return vc.backdropView
    }

    override init(presentedViewController: UIViewController, presenting presentingViewController: UIViewController?) {
        super.init(presentedViewController: presentedViewController, presenting: presentingViewController)
        backdropView?.backgroundColor = Theme.backdropColor
    }

    override func presentationTransitionWillBegin() {
        guard let containerView = containerView, let backdropView = backdropView else { return }
        backdropView.alpha = 0
        containerView.addSubview(backdropView)
        backdropView.autoPinEdgesToSuperviewEdges()
        containerView.layoutIfNeeded()

        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.backdropView?.alpha = 1
        }, completion: nil)
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.backdropView?.alpha = 0
        }, completion: { _ in
            self.backdropView?.removeFromSuperview()
        })
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard let presentedView = presentedView else { return }
        coordinator.animate(alongsideTransition: { _ in
            presentedView.frame = self.frameOfPresentedViewInContainerView
            presentedView.layoutIfNeeded()
        }, completion: nil)
    }
}

extension SafetyNumberConfirmationSheet: UIViewControllerTransitioningDelegate {
    public func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return SafetyNumberConfirmationAnimationController(presentedViewController: presented, presenting: presenting)
    }
}
