//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Combine
import SignalServiceKit

/// An interactive sheet view controller with stack view content. Automatically
/// resizes the sheet and enables/disables scrolling based on content size.
///
/// To use, set `contentStackView`'s `spacing` and `alignment`, and add your
/// content as arranged subviews. Optionally override `stackViewInsets` and/or
/// `minimumBottomInsetIncludingSafeArea`.
///
/// To use as the content of a ``SheetNavigationController`` instead, use
/// ``NavStackSheetViewController``.
///
///  - Backed by a native content-sized sheet on iOS 16+
///  - Backed by ``InteractiveSheetViewController`` on iOS 15
open class StackSheetViewController: OWSViewController {

    // MARK: - Inherited from InteractiveSheetViewController

    // Can be removed once iOS 15 is dropped in favor of editing these
    // properties on the view controller or presentation controller directly

    open var sheetBackgroundColor: UIColor {
        UIColor.Signal.groupedBackground
    }

    open var prefersGrabberVisible: Bool { true }

    open var placeOnGlassIfAvailable: Bool { true }

    open var canBeDismissed: Bool { true }

    // MARK: - Properties

    private var sizeChangeSubscription: AnyCancellable?
    private lazy var heightReloader = ContentSizedSheetHeightReloader(viewController: self)

    /// Margins for the content in the stack view. The safe area insets for the
    /// bottom will be added to the value specified here. To set a minimum
    /// bottom inset, see ``minimumBottomInsetIncludingSafeArea``.
    ///
    /// Default value is 24 on all sides.
    open var stackViewInsets: UIEdgeInsets {
        .init(margin: 24)
    }

    /// The minimum inset for the bottom of the stack view, including the safe area.
    ///
    /// For example, if `stackViewInsets.bottom` is set to 20 and
    /// `minimumBottomInsetIncludingSafeArea` is set to 32, a device with a
    /// 40-pt bottom safe area inset will have a total bottom margin of
    /// 40+20 = 60, which is over the minimum. A device with no bottom safe area
    /// inset will use the minimum-specified bottom inset of 32.
    ///
    /// Default value is 0.
    open var minimumBottomInsetIncludingSafeArea: CGFloat { 0 }

    public weak var dismissalDelegate: (any SheetDismissalDelegate)?

    fileprivate let contentScrollView = UIScrollView()

    /// The stack view to add your main content to.
    /// Recommended to set a custom `spacing` and `alignment`.
    public lazy var stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.isLayoutMarginsRelativeArrangement = true
        return stackView
    }()

    /// Add content to this which shouldn't scroll with the stack
    public var contentView: UIView { legacySheet?.contentView ?? view }

    private let legacySheet: LegacyStackSheetViewController?

    override public init() {
        if #available(iOS 16, *) {
            self.legacySheet = nil
        } else {
            self.legacySheet = LegacyStackSheetViewController()
        }

        super.init()

        if let legacySheet {
            legacySheet.owner = self
            addChild(legacySheet)
            modalPresentationStyle = .custom
            transitioningDelegate = legacySheet
        } else {
            modalPresentationStyle = .formSheet
        }
    }

    // MARK: - Layout

    override open func viewDidLoad() {
        super.viewDidLoad()

        let contentContainer: UIView
        if let legacySheet {
            view.backgroundColor = .clear
            view.addSubview(legacySheet.view)
            legacySheet.view.autoPinEdgesToSuperviewEdges()
            legacySheet.didMove(toParent: self)
            contentContainer = legacySheet.contentView
        } else {
            view.backgroundColor = isOnGlass ? nil : sheetBackgroundColor
            isModalInPresentation = !canBeDismissed
            contentContainer = view

            if let sheet = sheetPresentationController {
                sheet.prefersGrabberVisible = prefersGrabberVisible
                sheet.prefersEdgeAttachedInCompactHeight = true
            }
            sheetPresentationController?.setUpContentSizedDetent { [weak self] in
                self?.customSheetHeight()
            }
        }

        if navigationController != nil {
            owsFailDebug("doesn't support being in a nav controller. use NavStackSheetViewController")
        }

        contentContainer.addSubview(contentScrollView)
        contentScrollView.autoPinEdgesToSuperviewEdges()
        contentScrollView.contentInsetAdjustmentBehavior = .never

        contentScrollView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()
        stackView.autoPinWidth(toWidthOf: contentContainer)

        updateStackViewLayoutMargins()

        sizeChangeSubscription = stackView
            .publisher(for: \.bounds)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.reloadSheetHeight()
            }
    }

    override open func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        guard legacySheet == nil else { return }
        if #unavailable(iOS 26) {
            DispatchQueue.main.async { [weak self] in
                self?.sheetPresentationController?.reloadContentSizedHeight(animated: false)
            }
        }
    }

    override open func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateStackViewLayoutMargins()
    }

    override open func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if isBeingDismissed {
            dismissalDelegate?.didDismissPresentedSheet()
        }
    }

    override open func accessibilityPerformEscape() -> Bool {
        if canBeDismissed, presentingViewController != nil {
            dismiss(animated: true)
            return true
        }
        return super.accessibilityPerformEscape()
    }

    private var isOnGlass: Bool {
        if #available(iOS 26, *) {
            placeOnGlassIfAvailable
        } else {
            false
        }
    }

    private func updateStackViewLayoutMargins() {
        let desiredInsets = self.stackViewInsets

        // Dragging the sheet up changes the stack view's safe area,
        // so add it in manually instead of inheriting it.
        let bottomMargin = max(
            self.view.safeAreaInsets.bottom + desiredInsets.bottom,
            minimumBottomInsetIncludingSafeArea,
        )

        stackView.preservesSuperviewLayoutMargins = false
        stackView.insetsLayoutMarginsFromSafeArea = false

        let grabberInset: CGFloat = if legacySheet != nil {
            // InteractiveSheetViewController itself already adds grabber height
            0
        } else {
            InteractiveSheetViewController.Constants.handleHeight
        }
        stackView.layoutMargins = .init(
            top: desiredInsets.top + grabberInset,
            leading: desiredInsets.leading,
            bottom: bottomMargin,
            trailing: desiredInsets.trailing,
        )
    }

    // MARK: - Sheet height

    open func customSheetHeight() -> CGFloat {
        contentHeight - view.safeAreaInsets.bottom
    }

    public func reloadSheetHeight() {
        if let legacySheet {
            legacySheet.reloadHeight()
        } else {
            heightReloader.reload()
        }
    }

    fileprivate var contentHeight: CGFloat {
        // Opposite of grabberInset
        stackView.bounds.height + (legacySheet == nil ? 0 : InteractiveSheetViewController.Constants.handleHeight)
    }
}

// MARK: - LegacyStackSheetViewController

@available(
    iOS,
    introduced: 15.0,
    deprecated: 16.0,
    message: "Once this is removed, many `open` StackSheetViewController can be removed too"
)
private class LegacyStackSheetViewController: InteractiveSheetViewController {
    weak var owner: StackSheetViewController?

    override var interactiveScrollViews: [UIScrollView] {
        owner.map { [$0.contentScrollView] } ?? []
    }

    override var sheetBackgroundColor: UIColor {
        owner?.sheetBackgroundColor ?? super.sheetBackgroundColor
    }

    override var handleBackgroundColor: UIColor {
        (owner?.prefersGrabberVisible ?? true) ? super.handleBackgroundColor : .clear
    }

    override var placeOnGlassIfAvailable: Bool {
        owner?.placeOnGlassIfAvailable ?? super.placeOnGlassIfAvailable
    }

    override var canBeDismissed: Bool {
        owner?.canBeDismissed ?? super.canBeDismissed
    }

    private lazy var preferredHeight: CGFloat = self.maximumAllowedHeight()

    override func maximumPreferredHeight() -> CGFloat {
        min(self.preferredHeight, self.maximumAllowedHeight())
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        allowsExpansion = false
        animationsShouldBeInterruptible = true
    }

    func reloadHeight() {
        guard let owner else { return }
        let desiredHeight = owner.contentHeight
        self.preferredHeight = desiredHeight
        self.minimizedHeight = desiredHeight
        owner.contentScrollView.isScrollEnabled = self.maxHeight < desiredHeight
    }
}
