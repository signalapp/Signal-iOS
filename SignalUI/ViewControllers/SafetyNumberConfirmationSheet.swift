//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalServiceKit

@objc
public class SafetyNumberConfirmationSheet: UIViewController {
    let stackView = UIStackView()
    let contentView = UIView()
    let handle = UIView()
    let backdropView = UIView()
    let tableView = UITableView()

    struct Item {
        let address: SignalServiceAddress
        let displayName: String
        let verificationState: OWSVerificationState
    }

    private var confirmationItems: [Item]

    let confirmAction: ActionSheetAction
    let cancelAction: ActionSheetAction
    let completionHandler: (Bool) -> Void
    public var allowsDismissal: Bool = true

    public let theme: Theme.ActionSheet

    @objc
    @available(swift, obsoleted: 1.0)
    public convenience init(addressesToConfirm addresses: [SignalServiceAddress], confirmationText: String, completionHandler: @escaping (Bool) -> Void) {
        self.init(addressesToConfirm: addresses, confirmationText: confirmationText, completionHandler: completionHandler)
    }

    public init(
        addressesToConfirm: [SignalServiceAddress],
        confirmationText: String,
        cancelText: String = CommonStrings.cancelButton,
        theme: Theme.ActionSheet = .translucentDark,
        completionHandler: @escaping (Bool) -> Void
    ) {
        assert(!addressesToConfirm.isEmpty)

        self.confirmationItems = Self.databaseStorage.read { transaction in
            Self.buildConfirmationItems(
                addressesToConfirm: addressesToConfirm,
                transaction: transaction
            )
        }

        self.confirmAction = ActionSheetAction(title: confirmationText, style: .default)
        self.cancelAction = ActionSheetAction(title: cancelText, style: .cancel)
        self.completionHandler = completionHandler
        self.theme = theme

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
        transaction: SDSAnyReadTransaction
    ) -> [Item] {
        addressesToConfirm.map { address in
            return Item(
                address: address,
                displayName: contactsManager.displayName(for: address, transaction: transaction),
                verificationState: identityManager.verificationState(for: address, transaction: transaction)
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
        databaseStorage.read { transaction in
            let addressesToConfirm = confirmationItems.map { $0.address }

            confirmationItems = Self.buildConfirmationItems(
                addressesToConfirm: addressesToConfirm,
                transaction: transaction
            )
        }

        tableView.reloadData()
    }

    // MARK: - Present if necessary

    @objc
    public class func presentIfNecessary(address: SignalServiceAddress, confirmationText: String, completion: @escaping (Bool) -> Void) -> Bool {
        return presentIfNecessary(addresses: [address], confirmationText: confirmationText, completion: completion)
    }

    /**
     * Shows confirmation dialog if at least one of the recipient id's is not confirmed.
     *
     * @returns true  if an alert was shown
     *          false if there were no unconfirmed identities
     */
    @objc
    public class func presentIfNecessary(
        addresses: [SignalServiceAddress],
        confirmationText: String,
        untrustedThreshold: TimeInterval = OWSIdentityManager.minimumUntrustedThreshold,
        completion: @escaping (Bool) -> Void
    ) -> Bool {

        let untrustedAddresses = databaseStorage.read { transaction in
            addresses.filter { address in
                identityManager.untrustedIdentityForSending(to: address, untrustedThreshold: untrustedThreshold, transaction: transaction) != nil
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

        CurrentAppContext().frontmostViewController()?.present(sheet, animated: true)
        return true
    }

    // MARK: -

    override public func loadView() {
        view = UIView()
        let backgroundView = theme.createBackgroundView()

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
            subview.layer.cornerRadius = 16
            subview.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            subview.layer.masksToBounds = true
        }

        stackView.axis = .vertical
        contentView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewSafeArea()

        // Support tapping the backdrop to cancel the action sheet.
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapBackdrop(_:)))
        tapGestureRecognizer.delegate = self
        view.addGestureRecognizer(tapGestureRecognizer)

        // Setup header

        let titleLabel = UILabel()
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.font = UIFont.dynamicTypeBody2.semibold()
        titleLabel.textColor = theme.headerTitleColor
        titleLabel.text = OWSLocalizedString("SAFETY_NUMBER_CONFIRMATION_TITLE",
                                             comment: "Title for the 'safety number confirmation' view")

        let messageLabel = UILabel()
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.font = .dynamicTypeBody2
        messageLabel.textColor = theme.headerMessageColor
        messageLabel.text = OWSLocalizedString("SAFETY_NUMBER_CONFIRMATION_MESSAGE",
                                               comment: "Message for the 'safety number confirmation' view")

        let headerStack = UIStackView(arrangedSubviews: [
            titleLabel,
            messageLabel
        ])
        headerStack.axis = .vertical
        headerStack.spacing = 2
        headerStack.isLayoutMarginsRelativeArrangement = true
        headerStack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stackView.addArrangedSubview(headerStack)
        stackView.addHairline(with: theme.hairlineColor)

        stackView.addArrangedSubview(tableView)
        stackView.addHairline(with: theme.hairlineColor)
        tableView.alwaysBounceVertical = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.register(SafetyNumberCell.self, forCellReuseIdentifier: SafetyNumberCell.reuseIdentifier)
        tableView.setContentHuggingHigh()
        tableView.setCompressionResistanceLow()

        confirmAction.button.applyActionSheetTheme(theme)
        stackView.addArrangedSubview(confirmAction.button)
        stackView.addHairline(with: theme.hairlineColor)
        confirmAction.button.releaseAction = { [weak self] in
            guard let self = self else { return }
            let identityManager = self.identityManager
            let unconfirmedAddresses = self.confirmationItems.map { $0.address }

            self.databaseStorage.asyncWrite(block: { writeTx in
                for address in unconfirmedAddresses {
                    guard let identityKey = identityManager.identityKey(for: address, transaction: writeTx) else { return }
                    let currentState = identityManager.verificationState(for: address, transaction: writeTx)

                    // Promote any unverified verification states to default, but otherwise leave
                    // the state intact. We don't want to overwrite any addresses that have
                    // been verified since we last checked.
                    let newState = (currentState == .noLongerVerified) ? .default : currentState
                    identityManager.setVerificationState(
                        newState,
                        identityKey: identityKey,
                        address: address,
                        isUserInitiatedChange: true,
                        transaction: writeTx
                    )
                }
            }, completionQueue: .main) {
                self.completionHandler(true)
                self.dismiss(animated: true)
            }
        }

        cancelAction.button.applyActionSheetTheme(theme)
        stackView.addArrangedSubview(cancelAction.button)
        cancelAction.button.releaseAction = { [weak self] in
            self?.completionHandler(false)
            self?.dismiss(animated: true)
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

    @objc
    func didTapBackdrop(_ sender: UITapGestureRecognizer) {
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

        handle.backgroundColor = .ows_whiteAlpha80
        handle.autoSetDimensions(to: CGSize(width: 56, height: 5))
        handle.layer.cornerRadius = 5 / 2
        view.addSubview(handle)
        handle.autoHCenterInSuperview()
        handle.autoPinEdge(.bottom, to: .top, of: contentView, withOffset: -8)
    }

    @objc
    func handlePan(_ sender: UIPanGestureRecognizer) {
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
            contactCell.configure(item: item, theme: theme, viewController: self)
        }

        return contactCell
    }
}

// MARK: -

private class SafetyNumberCell: ContactTableViewCell {

    open override class var reuseIdentifier: String { "SafetyNumberCell" }

    let button = OWSFlatButton()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        button.setTitle(
            title: OWSLocalizedString("SAFETY_NUMBER_CONFIRMATION_VIEW_ACTION",
                                      comment: "View safety number action for the 'safety number confirmation' view"),
            font: UIFont.dynamicTypeBody2.semibold(),
            titleColor: Theme.ActionSheet.default.safetyNumberChangeButtonTextColor
        )
        button.useDefaultCornerRadius()
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: SafetyNumberConfirmationSheet.Item, theme: Theme.ActionSheet, viewController: UIViewController) {
        button.setPressedBlock {
            FingerprintViewController.present(from: viewController, address: item.address)
        }

        Self.databaseStorage.read { transaction in
            let configuration = ContactCellConfiguration(address: item.address, localUserDisplayMode: .asUser)
            configuration.allowUserInteraction = true

            configuration.forceDarkAppearance = (theme == .translucentDark)

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
            case .`default`:
                if let phoneNumber = item.address.phoneNumber {
                    let formattedPhoneNumber = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: phoneNumber)

                    if item.displayName != formattedPhoneNumber {
                        configuration.attributedSubtitle = NSAttributedString(string: formattedPhoneNumber)
                    }
                }
            }

            self.configure(configuration: configuration, transaction: transaction)
        }
    }

    override func configure(configuration: ContactCellConfiguration, transaction: SDSAnyReadTransaction) {
        super.configure(configuration: configuration, transaction: transaction)
        let theme: Theme.ActionSheet = (configuration.forceDarkAppearance) ? .translucentDark : .default

        backgroundColor = theme.backgroundColor
        button.setBackgroundColors(upColor: theme.safetyNumberChangeButtonBackgroundColor)
        button.setTitleColor(theme.safetyNumberChangeButtonTextColor)
    }
}

private extension NSAttributedString {
    static func prefixedWithCheck(
        text: String
    ) -> NSAttributedString {
        let string = NSMutableAttributedString()

        string.appendTemplatedImage(named: "check-12", font: UIFont.regularFont(ofSize: 11))
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

private class SafetyNumberConfirmationAnimationController: UIPresentationController {

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
