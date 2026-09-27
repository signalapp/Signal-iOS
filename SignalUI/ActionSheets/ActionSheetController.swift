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

open class ActionSheetController: OWSViewController {
    private enum Message {
        case text(String)
        case attributedText(NSAttributedString)
    }

    private let backgroundView = ActionSheetController.createBackgroundView()
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
            stackView.insertArrangedSubview(customHeader, at: headerInsertIndex)
        }
    }

    /// Keep a reference in case we need to remove/replace it.
    private var defaultHeader: UIView?

    private var imageHeaderView: UIImageView?

    // If there's an image, insert the header below that.
    private var headerInsertIndex: Int {
        imageHeaderView != nil ? 1 : 0
    }

    public func setTitle(_ title: String? = nil, message: String? = nil) {
        createHeader(title: title, message: { if let message { .text(message) } else { nil } }())
    }

    public func setTitle(_ title: String? = nil, message: NSAttributedString) {
        createHeader(title: title, message: .attributedText(message))
    }

    public func setImage(_ image: UIImage) {
        imageHeaderView?.removeFromSuperview()
        let imageView = UIImageView(image: image)
        imageView.contentMode = .center
        imageView.setCompressionResistanceVerticalHigh()
        stackView.insertArrangedSubview(imageView, at: 0)
        stackView.setCustomSpacing(16, after: imageView)
        self.imageHeaderView = imageView
    }

    public var isCancelable = false

    /// The height of the entire action sheet, including any portion
    /// that extends off screen / is in the scrollable region
    var height: CGFloat {
        return stackView.height + view.safeAreaInsets.bottom
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

    public convenience init(title: String? = nil, message: NSAttributedString, image: UIImage? = nil) {
        self.init()

        if let image {
            setImage(image)
        }

        setTitle(title, message: message)
    }

    var firstCancelAction: ActionSheetAction? {
        return actions.first(where: { $0.style == .cancel })
    }

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

    let maxPreferredWidth: CGFloat = 414
    /// Add some wiggle room to the max width so the rounded corners don't look
    /// strange when there's only slightly more space on the sides than below.
    let maxWidthWiggleRoom: CGFloat = 40

    override open func viewDidLoad() {
        super.viewDidLoad()

        // Depending on the number of actions, the sheet may need
        // to scroll to allow access to all options.
        view.addSubview(backgroundView)
        backgroundView.clipsToBounds = true

        backgroundView.contentView.addSubview(scrollView)
        scrollView.autoPinEdgesToSuperviewEdges()
        scrollView.showsVerticalScrollIndicator = false

        let insetFromScreenEdge: CGFloat = if #available(iOS 26, *) {
            8
        } else {
            0
        }

        widthLimitConstraint = backgroundView.autoSetDimension(.width, toSize: maxPreferredWidth)
        widthLimitConstraint?.isActive = false

        backgroundView.autoPinEdge(toSuperviewEdge: .bottom, withInset: insetFromScreenEdge)
        pinWidthConstraints = backgroundView.autoPinWidthToSuperview(withMargin: insetFromScreenEdge)
        backgroundView.autoHCenterInSuperview()

        let topMargin: CGFloat = 18
        backgroundView.topAnchor.constraint(
            greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor,
            constant: topMargin,
        ).isActive = true

        scrollView.addSubview(contentView)
        contentView.autoPinWidthToSuperview()
        contentView.autoPinEdge(toSuperviewEdge: .top)
        contentView.autoPinEdge(toSuperviewEdge: .bottom)
        contentView.autoMatch(.width, to: .width, of: scrollView)

        // If possible, the scrollview should be as tall as the content (no scrolling)
        // but if it doesn't fit on screen, it's okay to be greater than the scroll view.
        contentView.autoMatch(.height, to: .height, of: scrollView, withOffset: 0, relation: .greaterThanOrEqual)
        let contentHeightConstraint = contentView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        contentHeightConstraint.priority = .defaultLow
        contentHeightConstraint.isActive = true

        contentView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = .init(margin: 16)
        stackView.insetsLayoutMarginsFromSafeArea = false

        if #available(iOS 26, *) {
            // updateWidthConstraints sets corner radius
        } else {
            let cornerRadius: CGFloat = 24
            backgroundView.layer.cornerRadius = cornerRadius
            backgroundView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        }

        // Support tapping the backdrop to cancel the action sheet.
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapBackdrop(_:)))
        view.addGestureRecognizer(tapGestureRecognizer)
    }

    private static func createBackgroundView() -> UIVisualEffectView {
        if #available(iOS 26, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.tintColor = UIColor.Signal.background.withAlphaComponent(2 / 3)
            let background = UIVisualEffectView(effect: glassEffect)
            return background
        } else {
            return UIVisualEffectView(effect: UIBlurEffect(style: .prominent))
        }
    }

    private func updateWidthConstraints() {
        if view.width > maxPreferredWidth + maxWidthWiggleRoom {
            pinWidthConstraints?.forEach { $0.isActive = false }
            widthLimitConstraint?.isActive = true
            if #available(iOS 26.0, *) {
                backgroundView.cornerConfiguration = .corners(radius: .fixed(24))
            }
        } else {
            widthLimitConstraint?.isActive = false
            pinWidthConstraints?.forEach { $0.isActive = true }
            if #available(iOS 26.0, *) {
                let topRadius: CGFloat = if view.safeAreaInsets.bottom > 0 { 40 } else { 20 }
                backgroundView.cornerConfiguration = .uniformEdges(
                    topRadius: .fixed(topRadius),
                    bottomRadius: .containerConcentric(minimum: 20),
                )
            }
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

        stackView.insertArrangedSubview(headerStack, at: headerInsertIndex)
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
                .Signal.label
            case .destructive:
                .Signal.red
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

    public static let buttonBackgroundColor = UIColor(
        light: .white,
        dark: .black,
    )

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

            addAction(
                UIAction { [weak self] _ in
                    guard let buttonAction = self?.releaseAction else { return }
                    buttonAction()
                },
                for: .primaryActionTriggered,
            )
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
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

    public static var ok: ActionSheetAction {
        ActionSheetAction(
            title: CommonStrings.okButton,
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

@available(iOS 17.0, *)
#Preview("Super Long Title") {
    buildPreview(
        title: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nam pretium, arcu id dignissim iaculis, nulla ipsum pulvinar est, sed convallis tellus neque sit amet diam. Nunc sit amet ipsum vitae purus finibus varius. In ligula turpis, semper vitae faucibus eu, dapibus et nunc. Nam nec laoreet nunc. Nam et pulvinar mauris, vitae pulvinar ligula. In sapien dui, auctor commodo quam eu, luctus feugiat mauris. In gravida porttitor eros, nec elementum diam facilisis nec. Ut finibus erat at fermentum consectetur. Maecenas vitae consectetur sem. Proin dignissim enim molestie dignissim tincidunt. Pellentesque habitant morbi tristique senectus et netus et malesuada fames ac turpis egestas. Suspendisse tempor aliquam tortor eu dictum. Sed laoreet felis elit, ut bibendum ex feugiat eu. Morbi pulvinar maximus dolor, et aliquet ex fringilla sed. Nunc id tempor massa, at luctus nisi. Aenean pellentesque mattis finibus. Pellentesque tempor, quam ut ornare dignissim, purus ante cursus lorem, et convallis erat nunc vitae ligula. Nullam in laoreet nulla, id sagittis ipsum. Nam non purus lorem. Maecenas a aliquet tortor, ut pulvinar lorem. Praesent ex nisi, blandit sed metus quis, malesuada porta quam. Morbi in ligula scelerisque, volutpat lorem sit amet, mollis ex. Pellentesque facilisis venenatis metus. Ut ac porttitor neque. Fusce convallis dolor tortor, sit amet interdum urna suscipit et. Vivamus quis viverra velit, sed aliquam ex. Nam ligula ligula, ultrices at vehicula aliquet, aliquam sed orci. Morbi tortor elit, suscipit vel cursus at, accumsan nec leo. Quisque aliquet risus vitae massa suscipit, sit amet elementum lacus convallis. Nulla facilisi. Integer tempus tellus tellus, eu faucibus augue maximus facilisis. Quisque feugiat convallis magna, quis ornare orci efficitur quis. Suspendisse ac hendrerit tortor, sed rutrum massa. Quisque vehicula odio sed ultrices pharetra. Fusce ornare consectetur eros, non fermentum turpis consequat egestas. Integer tempus ac nulla at mattis. Praesent et iaculis eros. Duis vel ex non odio rhoncus dictum. Vestibulum dapibus lacus ac ipsum tempor bibendum. Integer at interdum libero. Curabitur non lacus tincidunt, semper leo vel, hendrerit ex. Curabitur vitae finibus mauris. Vestibulum auctor urna in consectetur lacinia. Nunc vehicula leo vitae magna auctor posuere. Mauris suscipit mauris nec tincidunt elementum. Nullam tincidunt sit amet ipsum quis porta. Aliquam laoreet felis ac porttitor lacinia. Sed et diam quis eros iaculis bibendum ut nec velit. Cras quis semper augue. Nullam in auctor sem, at efficitur turpis. Maecenas ornare felis ut cursus interdum. Curabitur sed congue velit, vitae condimentum mi. ",
        message: nil,
        cancelButton: "Cancel",
        destructiveButton: "Delete",
        customButtons: ["Action1", "Action2"],
    )
}

#endif
