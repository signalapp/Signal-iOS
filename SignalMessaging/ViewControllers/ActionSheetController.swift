//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class ActionSheetController: OWSViewController {

    private let contentView = UIView()
    private let stackView = UIStackView()
    private let scrollView = UIScrollView()

    @objc
    private(set) public var actions = [ActionSheetAction]() {
        didSet {
            isCancelable = firstCancelAction != nil
        }
    }

    @objc
    public var contentAlignment: ContentAlignment = .center {
        didSet {
            guard oldValue != contentAlignment else { return }
            actions.forEach { $0.button.contentAlignment = contentAlignment }
        }
    }
    @objc(ActionSheetContentAlignment)
    public enum ContentAlignment: Int {
        case center
        case leading
        case trailing
    }

    @objc
    public var customHeader: UIView? {
        didSet {
            oldValue?.removeFromSuperview()
            guard let customHeader = customHeader else { return }
            stackView.insertArrangedSubview(customHeader, at: 0)
        }
    }

    @objc
    public var isCancelable = false

    fileprivate static let minimumRowHeight: CGFloat = 60

    /// The height of the entire action sheet, including any portion
    /// that extends off screen / is in the scrollable region
    var height: CGFloat {
        return stackView.height + bottomLayoutGuide.length
    }

    @objc
    public override init() {
        super.init()

        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    @objc
    public convenience init(title: String? = nil, message: String? = nil) {
        self.init()
        createHeader(title: title, message: message)
    }

    var firstCancelAction: ActionSheetAction? {
        return actions.first(where: { $0.style == .cancel })
    }

    @objc
    public func addAction(_ action: ActionSheetAction) {
        if action.style == .cancel && firstCancelAction != nil {
            owsFailDebug("Only one cancel button permitted per action sheet.")
        }

        // If we've already added a cancel action, any non-cancel actions should come before it
        // This matches how UIAlertController handles cancel actions.
        if action.style != .cancel,
            let firstCancelAction = firstCancelAction,
            let index = stackView.arrangedSubviews.firstIndex(of: firstCancelAction.button) {
            stackView.insertArrangedSubview(action.button, at: index)
        } else {
            stackView.addArrangedSubview(action.button)
        }
        action.button.contentAlignment = contentAlignment
        action.button.releaseAction = { [weak self, weak action] in
            guard let self = self, let action = action else { return }
            self.dismiss(animated: true) { action.handler?(action) }
        }
        actions.append(action)
    }

    // MARK: -

    public override var canBecomeFirstResponder: Bool {
        return true
    }

    override public var preferredStatusBarStyle: UIStatusBarStyle {
        return Theme.isDarkThemeEnabled ? .lightContent : .default
    }

    override public func loadView() {
        view = UIView()
        view.backgroundColor = .clear

        // Depending on the number of actions, the sheet may need
        // to scroll to allow access to all options.
        view.addSubview(scrollView)
        scrollView.clipsToBounds = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.autoPinEdge(toSuperviewEdge: .bottom)
        scrollView.autoHCenterInSuperview()
        scrollView.autoMatch(.height, to: .height, of: view, withOffset: 0, relation: .lessThanOrEqual)

        // Prefer to be full width, but don't exceed the maximum width
        scrollView.autoSetDimension(.width, toSize: 414, relation: .lessThanOrEqual)
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            scrollView.autoPinWidthToSuperview()
        }

        let topMargin: CGFloat = 18

        scrollView.addSubview(contentView)
        contentView.backgroundColor = Theme.actionSheetBackgroundColor
        contentView.autoPinWidthToSuperview()
        contentView.autoPinEdge(toSuperviewEdge: .top, withInset: topMargin)
        contentView.autoPinEdge(toSuperviewEdge: .bottom)
        contentView.autoMatch(.width, to: .width, of: scrollView)

        // If possible, the scrollview should be as tall as the content (no scrolling)
        // but if it doesn't fit on screen, it's okay to be greater than the scroll view.
        contentView.autoMatch(.height, to: .height, of: scrollView, withOffset: -topMargin, relation: .greaterThanOrEqual)
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            contentView.autoMatch(.height, to: .height, of: scrollView, withOffset: -topMargin)
        }

        stackView.addBackgroundView(withBackgroundColor: Theme.actionSheetHairlineColor)
        stackView.axis = .vertical
        stackView.spacing = 1

        contentView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewSafeArea()

        // Add an extra view behind to:
        // a) cover the safe area – the scroll view automatically insures
        //    that the stack view can scroll above that range.
        // b) avoid a gap at the bottom of the screen when bouncing vertically
        let safeAreaBackdrop = UIView()
        safeAreaBackdrop.backgroundColor = Theme.actionSheetBackgroundColor
        view.insertSubview(safeAreaBackdrop, belowSubview: scrollView)
        safeAreaBackdrop.autoHCenterInSuperview()
        safeAreaBackdrop.autoPinEdge(toSuperviewEdge: .bottom)
        safeAreaBackdrop.autoMatch(.height, to: .height, of: scrollView, withMultiplier: 0.5)
        safeAreaBackdrop.autoMatch(.width, to: .width, of: scrollView)

        // Support tapping the backdrop to cancel the action sheet.
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapBackdrop(_:)))
        view.addGestureRecognizer(tapGestureRecognizer)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Ensure the scrollView's layout has completed
        // as we're about to use its bounds to calculate
        // the masking view and contentOffset.
        scrollView.layoutIfNeeded()

        let cornerRadius: CGFloat = 16
        let path = UIBezierPath(
            roundedRect: contentView.bounds,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(square: cornerRadius)
        )
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath
        contentView.layer.mask = shapeLayer

        let bottomInset = scrollView.adjustedContentInset.bottom

        // Always scroll to the bottom initially, so it's clear to the
        // user that there's more to scroll to if it goes offscreen.
        scrollView.contentOffset = CGPoint(x: 0, y: scrollView.contentSize.height - scrollView.height + bottomInset)
    }

    @objc func didTapBackdrop(_ sender: UITapGestureRecognizer) {
        guard isCancelable else { return }
        // If we have a cancel action, treat tapping the background
        // as tapping the cancel button.

        let point = sender.location(in: self.scrollView)
        guard !contentView.frame.contains(point) else { return }

        dismiss(animated: true) { [firstCancelAction] in
            guard let firstCancelAction = firstCancelAction else { return }
            firstCancelAction.handler?(firstCancelAction)
        }
    }

    func createHeader(title: String? = nil, message: String? = nil) {
        guard title != nil || message != nil else { return }

        let headerStack = UIStackView()
        headerStack.addBackgroundView(withBackgroundColor: Theme.actionSheetBackgroundColor)
        headerStack.axis = .vertical
        headerStack.isLayoutMarginsRelativeArrangement = true
        headerStack.layoutMargins = UIEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        headerStack.spacing = 2
        headerStack.autoSetDimension(.height, toSize: ActionSheetController.minimumRowHeight, relation: .greaterThanOrEqual)
        stackView.addArrangedSubview(headerStack)

        let topSpacer = UIView.vStretchingSpacer()
        headerStack.addArrangedSubview(topSpacer)

        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            topSpacer.autoSetDimension(.height, toSize: 0)
        }

        // Title
        if let title = title {
            let titleLabel = UILabel()
            titleLabel.textColor = Theme.primaryTextColor
            titleLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold()
            titleLabel.numberOfLines = 0
            titleLabel.lineBreakMode = .byWordWrapping
            titleLabel.textAlignment = .center
            titleLabel.text = title
            titleLabel.setCompressionResistanceVerticalHigh()

            headerStack.addArrangedSubview(titleLabel)
        }

        // Message
        if let message = message {
            let messageLabel = UILabel()
            messageLabel.numberOfLines = 0
            messageLabel.textAlignment = .center
            messageLabel.lineBreakMode = .byWordWrapping
            messageLabel.textColor = Theme.primaryTextColor
            messageLabel.font = .ows_dynamicTypeSubheadlineClamped
            messageLabel.text = message
            messageLabel.setCompressionResistanceVerticalHigh()

            headerStack.addArrangedSubview(messageLabel)
        }

        let bottomSpacer = UIView.vStretchingSpacer()
        headerStack.addArrangedSubview(bottomSpacer)
        bottomSpacer.autoMatch(.height, to: .height, of: topSpacer)
    }
}

// MARK: -

@objc
public class ActionSheetAction: NSObject {
    @objc
    public let title: String
    @objc
    public var accessibilityIdentifier: String? {
        didSet {
            button.accessibilityIdentifier = accessibilityIdentifier
        }
    }

    @objc
    public let style: Style
    @objc(ActionSheetActionStyle)
    public enum Style: Int {
        case `default`
        case cancel
        case destructive
    }

    fileprivate let handler: Handler?
    public typealias Handler = (ActionSheetAction) -> Void

    @objc
    @available(swift, obsoleted: 1.0)
    public func setTrailingIcon(_ icon: ThemeIcon) {
        trailingIcon = icon
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func clearTrailingIcon() {
        trailingIcon = nil
    }

    public var trailingIcon: ThemeIcon? {
        set {
            button.trailingIcon = newValue
        }
        get {
            return button.trailingIcon
        }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setLeadingIcon(_ icon: ThemeIcon) {
        leadingIcon = icon
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func clearLeadingIcon() {
        leadingIcon = nil
    }

    public var leadingIcon: ThemeIcon? {
        set {
            button.leadingIcon = newValue
        }
        get {
            return button.leadingIcon
        }
    }

    fileprivate(set) public lazy var button = Button(action: self)

    @objc
    public convenience init(title: String, style: Style = .default, handler: Handler? = nil) {
        self.init(title: title, accessibilityIdentifier: nil, style: style, handler: handler)
    }

    @objc
    public init(title: String, accessibilityIdentifier: String?, style: Style = .default, handler: Handler? = nil) {
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.style = style
        self.handler = handler
    }

    public class Button: UIButton {
        public var releaseAction: (() -> Void)?

        var trailingIcon: ThemeIcon? {
            didSet {
                trailingIconView.isHidden = trailingIcon == nil

                if let trailingIcon = trailingIcon {
                    trailingIconView.setTemplateImage(
                        Theme.iconImage(trailingIcon),
                        tintColor: Theme.primaryTextColor
                    )
                }

                updateEdgeInsets()
            }
        }

        var leadingIcon: ThemeIcon? {
            didSet {
                leadingIconView.isHidden = leadingIcon == nil

                if let leadingIcon = leadingIcon {
                    leadingIconView.setTemplateImage(
                        Theme.iconImage(leadingIcon),
                        tintColor: Theme.primaryTextColor
                    )
                }

                updateEdgeInsets()
            }
        }

        private let leadingIconView = UIImageView()
        private let trailingIconView = UIImageView()

        var contentAlignment: ActionSheetController.ContentAlignment = .center {
            didSet {
                switch contentAlignment {
                case .center:
                    contentHorizontalAlignment = .center
                case .leading:
                    contentHorizontalAlignment = CurrentAppContext().isRTL ? .right : .left
                case .trailing:
                    contentHorizontalAlignment = CurrentAppContext().isRTL ? .left : .right
                }

                updateEdgeInsets()
            }
        }

        init(action: ActionSheetAction) {
            super.init(frame: .zero)

            setBackgroundImage(UIImage(color: Theme.actionSheetBackgroundColor), for: .init())
            setBackgroundImage(UIImage(color: Theme.cellSelectedColor), for: .highlighted)

            [leadingIconView, trailingIconView].forEach { iconView in
                addSubview(iconView)
                iconView.isHidden = true
                iconView.autoSetDimensions(to: CGSize(square: 24))
                iconView.autoVCenterInSuperview()
                iconView.autoPinEdge(
                    toSuperviewEdge: iconView == leadingIconView ? .leading : .trailing,
                    withInset: 16
                )
            }

            updateEdgeInsets()

            setTitle(action.title, for: .init())

            switch action.style {
            case .default:
                titleLabel?.font = .ows_dynamicTypeBodyClamped
                setTitleColor(Theme.primaryTextColor, for: .init())
            case .cancel:
                titleLabel?.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold()
                setTitleColor(Theme.primaryTextColor, for: .init())
            case .destructive:
                titleLabel?.font = .ows_dynamicTypeBodyClamped
                setTitleColor(.ows_accentRed, for: .init())
            }

            autoSetDimension(.height, toSize: ActionSheetController.minimumRowHeight, relation: .greaterThanOrEqual)

            addTarget(self, action: #selector(didTouchUpInside), for: .touchUpInside)

            accessibilityIdentifier = action.accessibilityIdentifier
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func updateEdgeInsets() {
            if !leadingIconView.isHidden || !trailingIconView.isHidden || contentAlignment != .center {
                contentEdgeInsets = UIEdgeInsets(top: 16, leading: 56, bottom: 16, trailing: 56)
            } else {
                contentEdgeInsets = UIEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
            }
        }

        @objc func didTouchUpInside() {
            releaseAction?()
        }
    }
}

// MARK: -

private class ActionSheetPresentationController: UIPresentationController {
    let backdropView = UIView()

    override init(presentedViewController: UIViewController, presenting presentingViewController: UIViewController?) {
        super.init(presentedViewController: presentedViewController, presenting: presentingViewController)
        backdropView.backgroundColor = Theme.backdropColor
    }

    override func presentationTransitionWillBegin() {
        guard let containerView = containerView, let presentedVC = presentedViewController as? ActionSheetController else { return }
        backdropView.alpha = 0
        containerView.addSubview(backdropView)
        backdropView.autoPinEdgesToSuperviewEdges()
        containerView.layoutIfNeeded()

        var startFrame = containerView.frame
        startFrame.origin.y = presentedVC.height
        presentedVC.view.frame = startFrame

        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            presentedVC.view.frame = containerView.frame
            self.backdropView.alpha = 1
        }, completion: nil)
    }

    override func dismissalTransitionWillBegin() {
        guard let containerView = containerView, let presentedVC = presentedViewController as? ActionSheetController else { return }

        var endFrame = containerView.frame
        endFrame.origin.y = presentedVC.height
        presentedVC.view.frame = containerView.frame

        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            presentedVC.view.frame = endFrame
            self.backdropView.alpha = 0
        }, completion: { _ in
            self.backdropView.removeFromSuperview()
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

extension ActionSheetController: UIViewControllerTransitioningDelegate {
    public func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return ActionSheetPresentationController(presentedViewController: presented, presenting: presenting)
    }
}
