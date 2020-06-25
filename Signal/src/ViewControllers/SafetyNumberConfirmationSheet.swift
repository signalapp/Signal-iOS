//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

@objc
class SafetyNumberConfirmationSheet: UIViewController {
    let stackView = UIStackView()
    let contentView = UIView()
    let handle = UIView()
    let backdropView = UIView()
    let tableView = UITableView()

    struct Item {
        let address: SignalServiceAddress
        let displayName: String?
        let verificationState: OWSVerificationState?
    }
    var items = [Item]()
    let confirmationText: String
    let completionHandler: (Bool) -> Void

    @objc
    init(addressesToConfirm addresses: [SignalServiceAddress], confirmationText: String, completionHandler: @escaping (Bool) -> Void) {
        assert(!addresses.isEmpty)
        self.confirmationText = confirmationText
        self.completionHandler = completionHandler
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
        transitioningDelegate = self

        SDSDatabaseStorage.shared.uiRead { transaction in
            self.items = addresses.map {
                return Item(
                    address: $0,
                    displayName: Environment.shared.contactsManager.displayName(for: $0, transaction: transaction),
                    verificationState: OWSIdentityManager.shared().verificationState(for: $0, transaction: transaction)
                )
            }
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    class func presentIfNecessary(address: SignalServiceAddress, confirmationText: String, completion: @escaping (Bool) -> Void) -> Bool {
        return presentIfNecessary(addresses: [address], confirmationText: confirmationText, completion: completion)
    }

    /**
     * Shows confirmation dialog if at least one of the recipient id's is not confirmed.
     *
     * @returns true  if an alert was shown
     *          false if there were no unconfirmed identities
     */
    @objc
    class func presentIfNecessary(addresses: [SignalServiceAddress], confirmationText: String, completion: @escaping (Bool) -> Void) -> Bool {

        let untrustedAddresses = untrustedIdentitiesForSending(addresses: addresses)

        guard !untrustedAddresses.isEmpty else {
            // No identities to confirm, no alert to present.
            return false
        }

        let sheet = SafetyNumberConfirmationSheet(
            addressesToConfirm: untrustedAddresses,
            confirmationText: confirmationText,
            completionHandler: completion
        )

        UIApplication.shared.frontmostViewController?.present(sheet, animated: true)
        return true
    }

    private class func untrustedIdentitiesForSending(addresses: [SignalServiceAddress]) -> [SignalServiceAddress] {
        return addresses.filter { OWSIdentityManager.shared().untrustedIdentityForSending(to: $0) != nil }
    }

    // MARK: -

    override public func loadView() {
        view = UIView()
        view.backgroundColor = .clear

        view.addSubview(contentView)
        contentView.autoPinEdge(toSuperviewEdge: .bottom)
        contentView.autoHCenterInSuperview()
        contentView.autoMatch(.height, to: .height, of: view, withOffset: 0, relation: .lessThanOrEqual)
        contentView.backgroundColor = Theme.actionSheetBackgroundColor

        // Prefer to be full width, but don't exceed the maximum width
        contentView.autoSetDimension(.width, toSize: maxWidth, relation: .lessThanOrEqual)
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            contentView.autoPinWidthToSuperview()
        }

        stackView.axis = .vertical
        stackView.spacing = 1
        stackView.addBackgroundView(withBackgroundColor: Theme.actionSheetHairlineColor)

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
        titleLabel.font = UIFont.ows_dynamicTypeBody2.ows_semibold()
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.text = NSLocalizedString("SAFETY_NUMBER_CONFIRMATION_TITLE",
                                            comment: "Title for the 'safety number confirmation' view")

        let messageLabel = UILabel()
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.font = .ows_dynamicTypeBody2
        messageLabel.textColor = Theme.secondaryTextAndIconColor
        messageLabel.text = NSLocalizedString("SAFETY_NUMBER_CONFIRMATION_MESSAGE",
                                              comment: "Message for the 'safety number confirmation' view")

        let headerStack = UIStackView(arrangedSubviews: [
            titleLabel,
            messageLabel
        ])
        headerStack.addBackgroundView(withBackgroundColor: Theme.actionSheetBackgroundColor)
        headerStack.axis = .vertical
        headerStack.spacing = 2
        headerStack.isLayoutMarginsRelativeArrangement = true
        headerStack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stackView.addArrangedSubview(headerStack)

        stackView.addArrangedSubview(tableView)
        tableView.alwaysBounceVertical = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = Theme.actionSheetBackgroundColor
        tableView.register(SafetyNumberCell.self, forCellReuseIdentifier: SafetyNumberCell.reuseIdentifier())
        tableView.setContentHuggingHigh()
        tableView.setCompressionResistanceLow()

        let sendAction = ActionSheetAction(title: confirmationText)
        stackView.addArrangedSubview(sendAction.button)
        sendAction.button.releaseAction = { [weak self] in
            self?.completionHandler(true)
            self?.dismiss(animated: true)
        }

        let cancelAction = OWSActionSheets.cancelAction
        stackView.addArrangedSubview(cancelAction.button)
        cancelAction.button.releaseAction = { [weak self] in
            self?.completionHandler(false)
            self?.dismiss(animated: true)
        }
    }

    private var hasPreparedInitialLayout = false
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        guard !hasPreparedInitialLayout else { return }
        hasPreparedInitialLayout = true

        // Setup handle for interactive dismissal / resizing
        setupInteractiveSizing()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Ensure the scrollView's layout has completed
        // as we're about to use its bounds to calculate
        // the masking view and contentOffset.
        contentView.layoutIfNeeded()

        let cornerRadius: CGFloat = 16
        let path = UIBezierPath(
            roundedRect: contentView.bounds,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(square: cornerRadius)
        )
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath
        contentView.layer.mask = shapeLayer
    }

    @objc func didTapBackdrop(_ sender: UITapGestureRecognizer) {
        dismiss(animated: true)
    }

    // MARK: - Resize / Interactive Dismiss

    var heightConstraint: NSLayoutConstraint?
    let maxWidth: CGFloat = 414
    lazy var baseContentViewHeight: CGFloat = {
        view.layoutIfNeeded()
        return contentView.height
    }()

    lazy var cellHeight = tableView.cellForRow(at: IndexPath(row: 0, section: 0))?.height ?? 72

    lazy var minimizedHeight: CGFloat = {
        // We want to show, at most, 3.5 rows when minimized. When we have
        // less than 4 rows, we will match our size to the number of rows.
        return min(maximizedHeight, baseContentViewHeight + min(CGFloat(items.count), 3.5) * cellHeight)
    }()
    var maximizedHeight: CGFloat {
        return min(
            CurrentAppContext().frame.height - topLayoutGuide.length - 16,
            baseContentViewHeight + CGFloat(items.count) * cellHeight
        )
    }

    let maxAnimationDuration: TimeInterval = 0.2
    var startingHeight: CGFloat?
    var startingTranslation: CGFloat?

    func setupInteractiveSizing() {
        heightConstraint = contentView.autoSetDimension(.height, toSize: minimizedHeight)

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

    @objc func handlePan(_ sender: UIPanGestureRecognizer) {
        switch sender.state {
        case .began, .changed:
            guard beginInteractiveTransitionIfNecessary(sender),
                let startingHeight = startingHeight,
                let startingTranslation = startingTranslation else {
                    return resetInteractiveTransition()
            }

            // We're in an interactive transition, so don't let the scrollView scroll.
            tableView.contentOffset.y = 0
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
            heightConstraint?.constant = newHeight
            view.layoutIfNeeded()
        case .ended, .cancelled, .failed:
            guard let startingHeight = startingHeight else { break }

            let dismissThreshold = startingHeight * 0.5
            let growThreshold = (maximizedHeight - startingHeight) * 0.5
            let velocityThreshold: CGFloat = 500

            let currentHeight = contentView.height
            let currentVelocity = sender.velocity(in: view).y

            enum CompletionState { case growing, dismissing, cancelling }
            let completionState: CompletionState

            if abs(currentVelocity) >= velocityThreshold {
                completionState = currentVelocity < 0 ? .growing : .dismissing
            } else if currentHeight - startingHeight >= growThreshold {
                completionState = .growing
            } else if currentHeight <= dismissThreshold {
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

            let remainingDistance = finalHeight - currentHeight

            // Calculate the time to complete the animation if we want to preserve
            // the user's velocity. If this time is too slow (e.g. the user was scrolling
            // very slowly) we'll default to `maxAnimationDuration`
            let remainingTime = TimeInterval(abs(remainingDistance / currentVelocity))

            UIView.animate(withDuration: min(remainingTime, maxAnimationDuration), delay: 0, options: .curveEaseOut, animations: {
                if remainingDistance < 0 {
                    self.contentView.frame.origin.y -= remainingDistance
                    self.handle.frame.origin.y -= remainingDistance
                } else {
                    self.heightConstraint?.constant = finalHeight
                    self.view.layoutIfNeeded()
                }

                self.backdropView.alpha = completionState == .dismissing ? 0 : 1
            }) { _ in
                self.heightConstraint?.constant = finalHeight
                self.view.layoutIfNeeded()

                if completionState == .dismissing { self.dismiss(animated: true, completion: nil) }
            }

            resetInteractiveTransition()
        default:
            resetInteractiveTransition()

            backdropView.alpha = 1

            guard let startingHeight = startingHeight else { break }
            heightConstraint?.constant = startingHeight
        }
    }

    func beginInteractiveTransitionIfNecessary(_ sender: UIPanGestureRecognizer) -> Bool {
        let tryingToDismiss = tableView.contentOffset.y <= 0
        let tryingToMaximize = contentView.height < maximizedHeight && tableView.height < tableView.contentSize.height

        // If we're at the top of the scrollView, or the view is not
        // currently maximized, we want to do an interactive transition.
        guard tryingToDismiss || tryingToMaximize else { return false }

        if startingTranslation == nil {
            startingTranslation = sender.translation(in: view).y
        }

        if startingHeight == nil {
            startingHeight = contentView.height
        }

        return true
    }

    func resetInteractiveTransition() {
        startingTranslation = nil
        startingHeight = nil
        tableView.showsVerticalScrollIndicator = true
    }
}

extension SafetyNumberConfirmationSheet: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SafetyNumberCell.reuseIdentifier(), for: indexPath)

        guard let contactCell = cell as? SafetyNumberCell else {
            return cell
        }

        guard let item = items[safe: indexPath.row] else {
            return cell
        }

        contactCell.configure(item: item, viewController: self)

        return contactCell
    }
}

private class SafetyNumberCell: ContactTableViewCell {
    let button = OWSFlatButton()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        button.setBackgroundColors(upColor: Theme.conversationButtonBackgroundColor)
        button.setTitle(
            title: NSLocalizedString("SAFETY_NUMBER_CONFIRMATION_VIEW_ACTION",
                                     comment: "View safety number action for the 'safety number confirmation' view"),
            font: UIFont.ows_dynamicTypeBody2.ows_semibold(),
            titleColor: Theme.conversationButtonTextColor
        )
        button.useDefaultCornerRadius()
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: SafetyNumberConfirmationSheet.Item, viewController: UIViewController) {
        configure(withRecipientAddress: item.address)

        ows_setAccessoryView(button)

        backgroundColor = Theme.actionSheetBackgroundColor

        if let verificationState = item.verificationState, verificationState == .noLongerVerified {
            let previouslyVerified = NSMutableAttributedString()
            // "checkmark"
            previouslyVerified.append(
                "\u{f00c} ",
                attributes: [
                    .font: UIFont.ows_fontAwesomeFont(12)
                ]
            )
            previouslyVerified.append(
                NSLocalizedString("SAFETY_NUMBER_CONFIRMATION_PREVIOUSLY_VERIFIED",
                                  comment: "Text explaining that the given contact previously had their safety number verified.")
            )

            setAttributedSubtitle(previouslyVerified)
        } else if let displayName = item.displayName {
            if let phoneNumber = item.address.phoneNumber {
                let formattedPhoneNumber = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: phoneNumber)
                if displayName != formattedPhoneNumber {
                    setAttributedSubtitle(NSAttributedString(string: formattedPhoneNumber))
                }
            }
        }

        button.setPressedBlock {
            FingerprintViewController.present(from: viewController, address: item.address)
        }
    }

    override func allowUserInteraction() -> Bool { true }
}

// MARK: -
extension SafetyNumberConfirmationSheet: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        switch gestureRecognizer {
        case is UITapGestureRecognizer:
            let point = gestureRecognizer.location(in: view)
            guard !contentView.frame.contains(point) else { return false }
            return true
        default:
            return true
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
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
