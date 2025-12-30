//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import BonMot
import SafariServices
import SignalServiceKit

public protocol SheetDismissalDelegate: AnyObject {
    func didDismissPresentedSheet()
}

private final class OnDismissHandler: SheetDismissalDelegate {
    var handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func didDismissPresentedSheet() {
        handler()
    }
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

    private var onDismissHandler: OnDismissHandler?

    /// Set this property to register a closure to be run when the sheet is
    /// dismissed.
    ///
    /// After dismissal, `ActionSheetController` sets the value of this property
    /// to `nil`.
    ///
    /// - Note: Setting an `onDismiss` handler discards the previous value of
    ///   the `dismissalDelegate` property.
    public var onDismiss: (() -> Void)? {
        get {
            onDismissHandler?.handler
        }
        set {
            onDismissHandler = newValue.map(OnDismissHandler.init)
            dismissalDelegate = onDismissHandler
        }
    }

    /// Set this property to register a delegate object to be notified when the
    /// sheet is dismissed.
    ///
    /// After dismissal, `ActionSheetController` sets the value of this property
    /// to `nil`.
    ///
    /// - Note: Setting `dismissalDelegate` causes `onDismiss` to be set to `nil`.
    public weak var dismissalDelegate: (any SheetDismissalDelegate)? {
        didSet {
            if let dismissalDelegate, dismissalDelegate !== onDismissHandler {
                onDismissHandler = nil
            }
        }
    }

    public private(set) var actions = [ActionSheetAction]() {
        didSet {
            isCancelable = firstCancelAction != nil
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
            guard let customHeader else { return }
            stackView.insertArrangedSubview(customHeader, at: 0)
        }
    }

    /// Keep a reference in case we need to remove/replace it.
    private var defaultHeader: UIView?

    public func setTitle(_ title: String? = nil, message: String? = nil) {
        createHeader(title: title, message: { if let message { .text(message) } else { nil } }())
    }

    public func setTitle(_ title: String? = nil, message: NSAttributedString) {
        createHeader(title: title, message: .attributedText(message))
    }

    public var isCancelable = false

    /// The height of the entire action sheet, including any portion
    /// that extends off screen / is in the scrollable region
    var height: CGFloat {
        return stackView.height + view.safeAreaInsets.bottom
    }

    public static var messageLabelFont: UIFont { .dynamicTypeSubheadlineClamped }

    public static var messageBaseStyle: BonMot.StringStyle {
        return BonMot.StringStyle(.font(messageLabelFont), .alignment(.center))
    }

    override public init() {
        super.init()
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    public convenience init(title: String? = nil, message: String? = nil) {
        self.init()
        setTitle(title, message: message)
    }

    public convenience init(title: String? = nil, message: NSAttributedString) {
        self.init()
        setTitle(title, message: message)
    }

    var firstCancelAction: ActionSheetAction? {
        return actions.first(where: { $0.style == .cancel })
    }

    @objc
    public func addAction(_ action: ActionSheetAction) {
        if action.style == .cancel, firstCancelAction != nil {
            owsFailDebug("Only one cancel button permitted per action sheet.")
        }

        // If we've already added a cancel action, any non-cancel actions should come before it
        // This matches how UIAlertController handles cancel actions.
        if
            action.style != .cancel,
            let firstCancelAction,
            let index = stackView.arrangedSubviews.firstIndex(of: firstCancelAction.button)
        {
            stackView.insertArrangedSubview(action.button, at: index)
        } else {
            stackView.addArrangedSubview(action.button)
        }
        action.button.releaseAction = { [weak self, weak action] in
            guard let self, let action else { return }
            self.dismiss(animated: true) { action.handler?(action) }
        }
        actions.append(action)
    }

    // MARK: -

    override public var canBecomeFirstResponder: Bool {
        return true
    }

    private var widthLimitConstraint: NSLayoutConstraint?
    private var pinWidthConstraints: [NSLayoutConstraint]?
    private var backgroundView: UIView?

    let maxPreferredWidth: CGFloat = 414
    /// Add some wiggle room to the max width so the rounded corners don't look
    /// strange when there's only slightly more space on the sides than below.
    let maxWidthWiggleRoom: CGFloat = 40

    override open func viewDidLoad() {
        super.viewDidLoad()

        // Depending on the number of actions, the sheet may need
        // to scroll to allow access to all options.
        view.addSubview(scrollView)
        scrollView.clipsToBounds = false
        scrollView.showsVerticalScrollIndicator = false

        let insetFromScreenEdge: CGFloat = if
            #available(iOS 26, *),
            BuildFlags.iOS26SDKIsAvailable
        {
            8
        } else {
            0
        }

        widthLimitConstraint = scrollView.autoSetDimension(.width, toSize: maxPreferredWidth)
        widthLimitConstraint?.isActive = false

        scrollView.autoPinEdge(toSuperviewEdge: .bottom, withInset: insetFromScreenEdge)
        pinWidthConstraints = scrollView.autoPinWidthToSuperview(withMargin: insetFromScreenEdge)
        scrollView.autoHCenterInSuperview()

        scrollView.autoMatch(.height, to: .height, of: view, withOffset: 0, relation: .lessThanOrEqual)

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
        let backgroundView = createBackgroundView()
        self.backgroundView = backgroundView
        contentView.addSubview(backgroundView)
        backgroundView.autoPinWidthToSuperview()
        backgroundView.autoPinEdge(.top, to: .top, of: contentView)
        scrollView.frameLayoutGuide.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor).isActive = true

        contentView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = .init(margin: 16)
        stackView.insetsLayoutMarginsFromSafeArea = false

        // We can't mask the content view because the backdrop intentionally extends outside of the content
        // view's bounds. But its two subviews are pinned at same top edge. We can just apply corner
        // radii to each layer individually to get a similar effect.
        if #available(iOS 26, *), BuildFlags.iOS26SDKIsAvailable {
            // Background container sets corner radius itself
        } else {
            let cornerRadius: CGFloat = 24
            [backgroundView, stackView].forEach { subview in
                subview.layer.cornerRadius = cornerRadius
                subview.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
                subview.layer.masksToBounds = true
            }
        }

        // Support tapping the backdrop to cancel the action sheet.
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapBackdrop(_:)))
        view.addGestureRecognizer(tapGestureRecognizer)
    }

    private func createBackgroundView() -> UIView {
#if compiler(>=6.2)
        if #available(iOS 26, *), BuildFlags.iOS26SDKIsAvailable {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.tintColor = UIColor.Signal.background.withAlphaComponent(2 / 3)
            let background = UIVisualEffectView(effect: glassEffect)
            return background
        } else {
            return UIVisualEffectView(effect: UIBlurEffect(style: .prominent))
        }
#else
        return UIVisualEffectView(effect: UIBlurEffect(style: .prominent))
#endif
    }

    private func updateWidthConstraints() {
        if view.width > maxPreferredWidth + maxWidthWiggleRoom {
            pinWidthConstraints?.forEach { $0.isActive = false }
            widthLimitConstraint?.isActive = true
#if compiler(>=6.2)
            if #available(iOS 26.0, *), BuildFlags.iOS26SDKIsAvailable {
                backgroundView?.cornerConfiguration = .corners(radius: .fixed(24))
            }
#endif
        } else {
            widthLimitConstraint?.isActive = false
            pinWidthConstraints?.forEach { $0.isActive = true }
#if compiler(>=6.2)
            if #available(iOS 26.0, *), BuildFlags.iOS26SDKIsAvailable {
                let topRadius: CGFloat = if UIDevice.current.hasIPhoneXNotch {
                    40
                } else {
                    20
                }
                backgroundView?.cornerConfiguration = .uniformEdges(
                    topRadius: .fixed(topRadius),
                    bottomRadius: .containerConcentric(minimum: 20),
                )
            }
#endif
        }
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateWidthConstraints()

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

    override open func viewSafeAreaInsetsDidChange() {
        stackView.layoutMargins.bottom = max(20, view.safeAreaInsets.bottom)
        super.viewSafeAreaInsetsDidChange()
    }

    override open func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        dismissalDelegate?.didDismissPresentedSheet()
        onDismissHandler = nil
    }

    @objc
    private func didTapBackdrop(_ sender: UITapGestureRecognizer) {
        guard isCancelable else { return }
        // If we have a cancel action, treat tapping the background
        // as tapping the cancel button.

        let point = sender.location(in: self.scrollView)
        guard !contentView.frame.contains(point) else { return }

        dismiss(animated: true) { [firstCancelAction] in
            guard let firstCancelAction else { return }
            firstCancelAction.handler?(firstCancelAction)
        }
    }

    private func createHeader(title: String? = nil, message: Message? = nil) {
        if let defaultHeader {
            stackView.removeArrangedSubview(defaultHeader)
            defaultHeader.removeFromSuperview()
            self.defaultHeader = nil
        }

        guard title != nil || message != nil else { return }

        let headerStack = UIStackView()
        headerStack.axis = .vertical
        headerStack.alignment = .leading
        headerStack.isLayoutMarginsRelativeArrangement = true
        headerStack.layoutMargins = UIEdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12)
        headerStack.spacing = 4

        stackView.insertArrangedSubview(headerStack, at: 0)
        stackView.setCustomSpacing(20, after: headerStack)
        self.defaultHeader = headerStack

        // Title
        if let title {
            let titleLabel = UILabel()
            titleLabel.textColor = UIColor.Signal.label
            titleLabel.font = .dynamicTypeHeadline.semibold()
            titleLabel.numberOfLines = 0
            titleLabel.lineBreakMode = .byWordWrapping
            titleLabel.textAlignment = .natural
            titleLabel.text = title
            titleLabel.setCompressionResistanceVerticalHigh()

            headerStack.addArrangedSubview(titleLabel)
        }

        // Message
        if let message {
            let messageView: UIView = {
                switch message {
                case let .text(text):
                    let result = UILabel()
                    result.numberOfLines = 0
                    result.lineBreakMode = .byWordWrapping
                    result.textAlignment = .natural
                    result.textColor = UIColor.Signal.label
                    result.font = .dynamicTypeBody
                    result.text = text
                    return result
                case let .attributedText(attributedText):
                    let result = LinkingTextView()
                    result.textContainer.lineBreakMode = .byWordWrapping
                    result.textColor = UIColor.Signal.label
                    result.font = .dynamicTypeBody
                    result.attributedText = attributedText
                    result.textAlignment = .natural
                    result.delegate = self
                    return result
                }
            }()

            messageView.setCompressionResistanceVerticalHigh()

            headerStack.addArrangedSubview(messageView)
        }
    }
}

// MARK: -

public class ActionSheetAction: NSObject {

    private let title: String

    fileprivate let style: Style

    public enum Style: Int {
        case `default`
        case cancel
        case destructive

        fileprivate var textColor: UIColor {
            switch self {
            case .default, .cancel:
                UIColor.Signal.label
            case .destructive:
                UIColor.Signal.red
            }
        }
    }

    fileprivate let handler: Handler?
    public typealias Handler = @MainActor (ActionSheetAction) -> Void

    public private(set) lazy var button = Button(action: self)

    public init(title: String, style: Style = .default, handler: Handler? = nil) {
        self.title = title
        self.style = style
        self.handler = handler
    }

    public static let buttonBackgroundColor = UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark: .black
        default: .white
        }
    }

    public class Button: UIButton {
        let style: Style
        public var releaseAction: (() -> Void)?

        init(action: ActionSheetAction) {
            style = action.style
            super.init(frame: .zero)

            var config = UIButton.Configuration.filled()
            config.baseBackgroundColor = UIColor.Signal.secondaryFill
            config.cornerStyle = .capsule
            config.title = action.title
            config.baseForegroundColor = style.textColor
            config.titleTextAttributesTransformer = .defaultFont(.dynamicTypeBody.medium())
            config.contentInsets = .init(margin: 14)
            self.configuration = config

            addTarget(self, action: #selector(didTouchUpInside), for: .touchUpInside)
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        @objc
        private func didTouchUpInside() {
            releaseAction?()
        }
    }
}

// MARK: Common Actions

extension ActionSheetAction {
    public static var acknowledge: ActionSheetAction {
        ActionSheetAction(
            title: CommonStrings.acknowledgeButton,
            style: .default,
        )
    }

    public static var okay: ActionSheetAction {
        ActionSheetAction(
            title: CommonStrings.okayButton,
            style: .default,
        )
    }

    public static var cancel: ActionSheetAction {
        ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel,
        )
    }
}

// MARK: -

private class ActionSheetPresentationController: UIPresentationController {
    let backdropView = UIView()

    override init(presentedViewController: UIViewController, presenting presentingViewController: UIViewController?) {
        super.init(presentedViewController: presentedViewController, presenting: presentingViewController)
        backdropView.backgroundColor = .Signal.backdrop
    }

    override func presentationTransitionWillBegin() {
        guard let containerView, let presentedVC = presentedViewController as? ActionSheetController else { return }
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
        guard let containerView, let presentedVC = presentedViewController as? ActionSheetController else { return }

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
        guard let presentedView else { return }
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
        interaction: UITextItemInteraction,
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
        return "\(displayName.prefix(maxLength))…"
    }
}

// MARK: -

#if DEBUG

private func buildPreview(
    title: String?,
    message: String?,
    cancelButton: String?,
    destructiveButton: String?,
    customButtons: [String],
) -> UIViewController {
    let actionSheet = ActionSheetController(title: title, message: message)
    if let cancelButton {
        actionSheet.addAction(ActionSheetAction(title: cancelButton, style: .cancel))
    }
    if let destructiveButton {
        actionSheet.addAction(ActionSheetAction(title: destructiveButton, style: .destructive))
    }
    for customButton in customButtons {
        actionSheet.addAction(ActionSheetAction(title: customButton))
    }

    // Wrap in a nav controller for better contrast in the preview.
    let navController = UINavigationController(rootViewController: actionSheet)
    navController.view.backgroundColor = .Signal.groupedBackground

    return navController
}

@available(iOS 17.0, *)
#Preview {
    buildPreview(
        title: "Action Sheet Title",
        message: "This is an action sheet message.",
        cancelButton: "Cancel",
        destructiveButton: "Delete",
        customButtons: ["Action1", "Action2"],
    )
}

#endif
