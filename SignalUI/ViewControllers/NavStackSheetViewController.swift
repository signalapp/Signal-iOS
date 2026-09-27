//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Combine
import SignalServiceKit

/// Equivalent of ``StackSheetViewController`` for navigation content
///
///  - Note: On iOS 15, the sheet falls back to medium and large detents
///    rather than sizing to its content.
open class NavStackSheetViewController: OWSViewController {

    // MARK: - Properties

    private var sizeChangeSubscription: AnyCancellable?
    private lazy var heightReloader = ContentSizedSheetHeightReloader(viewController: self)

    /// Margins for the content in the stack view. The navigation bar and the
    /// bottom safe area inset are added outside of the value specified here.
    /// To set a minimum bottom inset, see ``minimumBottomInsetIncludingSafeArea``.
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

    /// The stack view to add your main content to.
    /// Recommended to set a custom `spacing` and `alignment`.
    public let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.isLayoutMarginsRelativeArrangement = true
        return stackView
    }()

    private let contentScrollView = UIScrollView()

    // MARK: - Layout

    override open func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(contentScrollView)
        contentScrollView.autoPinEdgesToSuperviewEdges()
        contentScrollView.contentInsetAdjustmentBehavior = .never

        contentScrollView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()
        stackView.autoPinWidth(toWidthOf: view)

        updateInsets()

        sizeChangeSubscription = stackView
            .publisher(for: \.bounds)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.reloadSheetHeight()
            }
    }

    override open func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        // The detent is computed before this view's content has been laid out.
        // Reload after the current layout pass has completed.
        reloadSheetHeight()
    }

    override open func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateInsets()
        // The top safe area inset contributes to `customSheetHeight()` but
        // doesn't alter the stack view's bounds, so reload here too.
        reloadSheetHeight()
    }

    // MARK: - Sheet height

    /// The height of the sheet's content, used to size the sheet.
    open func customSheetHeight() -> CGFloat {
        // The top safe area is the navigation bar, which the scroll view
        // extends under. The bottom safe area is added below the detent.
        view.safeAreaInsets.top + stackView.bounds.height
    }

    public func reloadSheetHeight() {
        heightReloader.reload()
    }

    private func updateInsets() {
        let desiredInsets = self.stackViewInsets
        let safeAreaInsets = self.view.safeAreaInsets

        // The scroll view extends under the navigation bar and into the
        // bottom safe area. Inset its content for those rather than the
        // stack view's margins, so that the stack view's height doesn't
        // depend on the sheet's frame and the sheet can be sized from it
        // as soon as the safe area is known.
        contentScrollView.contentInset = .init(
            top: safeAreaInsets.top,
            leading: 0,
            bottom: safeAreaInsets.bottom,
            trailing: 0,
        )

        stackView.preservesSuperviewLayoutMargins = false
        stackView.insetsLayoutMarginsFromSafeArea = false
        stackView.layoutMargins = .init(
            top: desiredInsets.top,
            leading: desiredInsets.leading,
            bottom: max(
                desiredInsets.bottom,
                minimumBottomInsetIncludingSafeArea - safeAreaInsets.bottom,
            ),
            trailing: desiredInsets.trailing,
        )
    }
}
