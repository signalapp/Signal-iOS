//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BonMot
import SafariServices
import SignalServiceKit

public protocol SheetDismissalDelegate: AnyObject {
    func didDismissPresentedSheet()
}

@objc
open class ActionSheetController: OWSViewController {
    private enum Message {
        case text(String)
        case attributedText(NSAttributedString)
    }

    private let contentView = UIView()
    private let stackView = UIStackView()
    private let scrollView = UIScrollView()
    private var hasCompletedFirstLayout = false

    public weak var dismissalDelegate: (any SheetDismissalDelegate)?

    private(set) public var actions = [ActionSheetAction]() {
        didSet {
            isCancelable = firstCancelAction != nil
        }
    }

    public var contentAlignment: ContentAlignment = .center {
        didSet {
            guard oldValue != contentAlignment else { return }
            actions.forEach { $0.button.contentAlignment = contentAlignment }
        }
    }

    public enum ContentAlignment: Int {
        case center
        case leading
        case trailing
    }

    /// Adds a header view to the top of the action sheet stack
    /// Note: It's the caller's responsibility to ensure the header view matches the style of the action sheet
    /// See: theme.backgroundColor, theme.headerTitleColor, etc.
    public var customHeader: UIView? {
        didSet {
            oldValue?.removeFromSuperview()
            guard let customHeader = customHeader else { return }
            stackView.insertArrangedSubview(customHeader, at: 0)
        }
    }

    public var isCancelable = false

    // Currently the theme must be set during initialization to take effect
    // There's probably a future use case where we want to recolor everything
    // as the theme changes. But for now we have initializers.
    public let theme: Theme.ActionSheet

    fileprivate static let minimumRowHeight: CGFloat = 60

    /// The height of the entire action sheet, including any portion
    /// that extends off screen / is in the scrollable region
    var height: CGFloat {
        return stackView.height + view.safeAreaInsets.bottom
    }

    public static var messageLabelFont: UIFont { .dynamicTypeSubheadlineClamped }

    public static var messageBaseStyle: BonMot.StringStyle {
        return BonMot.StringStyle(.font(messageLabelFont), .alignment(.center))
    }

    public init(theme: Theme.ActionSheet = .default) {
        self.theme = theme
        super.init()
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    public override convenience init() {
        self.init(theme: .default)
    }

    @objc
    public convenience init(title: String? = nil, message: String? = nil) {
        self.init(title: title, message: message, theme: .default)
    }

    public convenience init(title: String? = nil, message: String? = nil, theme: Theme.ActionSheet = .default) {
        self.init(theme: theme)
        createHeader(title: title, message: {
            guard let message else { return nil }
            return .text(message)
        }())
    }

    public convenience init(
        title: String? = nil,
        message: NSAttributedString,
        theme: Theme.ActionSheet = .default
    ) {
        self.init(theme: theme)
        createHeader(title: title, message: .attributedText(message))
    }

    var firstCancelAction: ActionSheetAction? {
        return actions.first(where: { $0.style == .cancel })
    }

    @objc
    public func addAction(_ action: ActionSheetAction) {
        if action.style == .cancel && firstCancelAction != nil {
            owsFailDebug("Only one cancel button permitted per action sheet.")
        }
        action.button.applyActionSheetTheme(theme)

        // If we've already added a cancel action, any non-cancel actions should come before it
        // This matches how UIAlertController handles cancel actions.
        if action.style != .cancel,
            let firstCancelAction = firstCancelAction,
            let index = stackView.arrangedSubviews.firstIndex(of: firstCancelAction.button) {
            // The hairline we're inserting is the divider between the new button and the cancel button
            stackView.insertHairline(with: theme.hairlineColor, at: index)
            stackView.insertArrangedSubview(action.button, at: index)
        } else {
            stackView.addHairline(with: theme.hairlineColor)
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
        scrollView.autoMatch(.width, to: .width, of: view, withOffset: 0, relation: .lessThanOrEqual)
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            scrollView.autoPinWidthToSuperview()
        }

        let topMargin: CGFloat = 18

        scrollView.addSubview(contentView)
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

        // The backdrop view needs to extend from the top of the scroll view content to the bottom of the scroll view
        // If the backdrop was not pinned to the scroll view frame, we'd see empty space in the safe area as we bounce
        //
        // The backdrop has to be a subview of the scrollview's content because constraints that bridge from the inside
        // to outside of the scroll view cause the content to be pinned. Views outside the scrollview will not follow
        // the content offset.
        //
        // This means that the backdrop view will extend outside of the bounds of the content view as the user
        // scrolls the content out of the safe area
        let backgroundView = theme.createBackgroundView()
        contentView.addSubview(backgroundView)
        backgroundView.autoPinWidthToSuperview()
        backgroundView.autoPinEdge(.top, to: .top, of: contentView)
        scrollView.frameLayoutGuide.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor).isActive = true

        // Stack views don't support corner masking pre-iOS 14
        // Instead we add our stack view to a wrapper view with masksToBounds: true
        let stackViewContainer = UIView()
        contentView.addSubview(stackViewContainer)
        stackViewContainer.autoPinEdgesToSuperviewSafeArea()

        stackViewContainer.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()
        stackView.axis = .vertical

        // We can't mask the content view because the backdrop intentionally extends outside of the content
        // view's bounds. But its two subviews are pinned at same top edge. We can just apply corner
        // radii to each layer individually to get a similar effect.
        let cornerRadius: CGFloat = 16
        [backgroundView, stackViewContainer].forEach { subview in
            subview.layer.cornerRadius = cornerRadius
            subview.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            subview.layer.masksToBounds = true
        }

        // Support tapping the backdrop to cancel the action sheet.
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapBackdrop(_:)))
        view.addGestureRecognizer(tapGestureRecognizer)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Always scroll to the bottom initially, so it's clear to the
        // user that there's more to scroll to if it goes offscreen.
        // We only want to do this once after the first layout resulting in a nonzero frame
        guard !hasCompletedFirstLayout else { return }
        hasCompletedFirstLayout = (view.frame != .zero)

        // Ensure the scrollView's layout has completed
        // as we're about to use its bounds to calculate
        // the contentOffset.
        scrollView.layoutSubviews()

        let bottomInset = scrollView.adjustedContentInset.bottom
        scrollView.contentOffset = CGPoint(x: 0, y: scrollView.contentSize.height - scrollView.height + bottomInset)
    }

    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        dismissalDelegate?.didDismissPresentedSheet()
    }

    @objc
    private func didTapBackdrop(_ sender: UITapGestureRecognizer) {
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

    private func createHeader(title: String? = nil, message: Message? = nil) {
        guard title != nil || message != nil else { return }

        let headerStack = UIStackView()
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
            titleLabel.textColor = theme.headerTitleColor
            titleLabel.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
            titleLabel.numberOfLines = 0
            titleLabel.lineBreakMode = .byWordWrapping
            titleLabel.textAlignment = .center
            titleLabel.text = title
            titleLabel.setCompressionResistanceVerticalHigh()

            headerStack.addArrangedSubview(titleLabel)
        }

        // Message
        if let message = message {
            let messageView: UIView = {
                switch message {
                case let .text(text):
                    let result = UILabel()
                    result.numberOfLines = 0
                    result.lineBreakMode = .byWordWrapping
                    result.textAlignment = .center
                    result.textColor = theme.headerMessageColor
                    result.font = Self.messageLabelFont
                    result.text = text
                    return result
                case let .attributedText(attributedText):
                    let result = LinkingTextView()
                    result.textContainer.lineBreakMode = .byWordWrapping
                    result.textColor = theme.headerMessageColor
                    result.font = Self.messageLabelFont
                    result.attributedText = attributedText
                    result.textAlignment = .center
                    result.delegate = self
                    return result
                }
            }()

            messageView.setCompressionResistanceVerticalHigh()

            headerStack.addArrangedSubview(messageView)
        }

        let bottomSpacer = UIView.vStretchingSpacer()
        headerStack.addArrangedSubview(bottomSpacer)
        bottomSpacer.autoMatch(.height, to: .height, of: topSpacer)
    }
}

// MARK: -

@objc
public class ActionSheetAction: NSObject {

    public let title: String

    public var accessibilityIdentifier: String? {
        didSet {
            button.accessibilityIdentifier = accessibilityIdentifier
        }
    }

    public let style: Style

    @objc(ActionSheetActionStyle)
    public enum Style: Int {
        case `default`
        case cancel
        case destructive
    }

    fileprivate let handler: Handler?
    public typealias Handler = (ActionSheetAction) -> Void

    public var trailingIcon: ThemeIcon? {
        get {
            return button.trailingIcon
        }
        set {
            button.trailingIcon = newValue
        }
    }

    public var leadingIcon: ThemeIcon? {
        get {
            return button.leadingIcon
        }
        set {
            button.leadingIcon = newValue
        }
    }

    fileprivate(set) public lazy var button = Button(action: self)

    @objc
    public convenience init(title: String, style: Style = .default, handler: Handler? = nil) {
        self.init(title: title, accessibilityIdentifier: nil, style: style, handler: handler)
    }

    public init(title: String, accessibilityIdentifier: String?, style: Style = .default, handler: Handler? = nil) {
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.style = style
        self.handler = handler
    }

    public class Button: UIButton {
        let style: Style
        public var releaseAction: (() -> Void)?

        var trailingIcon: ThemeIcon? {
            didSet {
                trailingIconView.isHidden = trailingIcon == nil

                if let trailingIcon = trailingIcon {
                    trailingIconView.setTemplateImage(
                        Theme.iconImage(trailingIcon),
                        tintColor: Theme.ActionSheet.default.buttonTextColor
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
                        tintColor: Theme.ActionSheet.default.buttonTextColor
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
            style = action.style
            super.init(frame: .zero)

            setBackgroundImage(UIImage(color: Theme.ActionSheet.default.buttonHighlightColor), for: .highlighted)

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
                titleLabel?.font = .dynamicTypeBodyClamped
                setTitleColor(Theme.ActionSheet.default.buttonTextColor, for: .init())
            case .cancel:
                titleLabel?.font = UIFont.dynamicTypeBodyClamped.semibold()
                setTitleColor(Theme.ActionSheet.default.buttonTextColor, for: .init())
            case .destructive:
                titleLabel?.font = .dynamicTypeBodyClamped
                setTitleColor(Theme.ActionSheet.default.destructiveButtonTextColor, for: .init())
            }

            autoSetDimension(.height, toSize: ActionSheetController.minimumRowHeight, relation: .greaterThanOrEqual)

            addTarget(self, action: #selector(didTouchUpInside), for: .touchUpInside)

            accessibilityIdentifier = action.accessibilityIdentifier
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public func applyActionSheetTheme(_ theme: Theme.ActionSheet) {
            // Recolor everything based on the requested theme
            setBackgroundImage(UIImage(color: theme.buttonHighlightColor), for: .highlighted)

            leadingIconView.tintColor = theme.buttonTextColor
            trailingIconView.tintColor = theme.buttonTextColor

            switch style {
            case .default, .cancel:
                setTitleColor(theme.buttonTextColor, for: .normal)
            case .destructive:
                setTitleColor(theme.destructiveButtonTextColor, for: .normal)
            }
        }

        private func updateEdgeInsets() {
            if !leadingIconView.isHidden || !trailingIconView.isHidden || contentAlignment != .center {
                contentEdgeInsets = UIEdgeInsets(top: 16, leading: 56, bottom: 16, trailing: 56)
            } else {
                contentEdgeInsets = UIEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
            }
        }

        @objc
        private func didTouchUpInside() {
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

extension ActionSheetController: UITextViewDelegate {
    public func textView(
        _ textView: UITextView,
        shouldInteractWith url: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        // Because of our modal presentation style, we can't present another controller over this
        // one. We must dismiss it first.
        dismiss(animated: true) {
            let vc = SFSafariViewController(url: url)
            CurrentAppContext().frontmostViewController()?.present(vc, animated: true)
        }
        return false
    }
}

extension String {

    func formattedForActionSheetTitle() -> String {
        String.formattedDisplayName(self, maxLength: 20)
    }

    func formattedForActionSheetMessage() -> String {
        String.formattedDisplayName(self, maxLength: 127)
    }

    private static func formattedDisplayName(_ displayName: String, maxLength: Int) -> String {
        guard displayName.count > maxLength else { return displayName }
        return displayName.substring(to: maxLength).appending("…")
    }
}
