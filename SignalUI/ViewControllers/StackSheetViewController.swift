//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import Combine

/// An interactive sheet view controller with stack view content. Automatically
/// resizes the sheet and enables/disables scrolling based on content size.
///
/// To use, set `contentStackView`'s `spacing` and `alignment`, and add your
/// content as arranged subviews. Optionally override `stackViewInsets` and/or
/// `minimumBottomInsetIncludingSafeArea`.
open class StackSheetViewController: InteractiveSheetViewController {
    public override var interactiveScrollViews: [UIScrollView] { [contentScrollView] }

    private var sizeChangeSubscription: AnyCancellable?

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

    private let contentScrollView = UIScrollView()

    /// The stack view to add your main content to.
    /// Recommended to set a custom `spacing` and `alignment`.
    public lazy var stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.isLayoutMarginsRelativeArrangement = true
        return stackView
    }()

    open override func viewDidLoad() {
        super.viewDidLoad()

        allowsExpansion = false
        contentView.addSubview(contentScrollView)
        contentScrollView.autoPinEdgesToSuperviewEdges()

        contentScrollView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()
        stackView.autoPinWidth(toWidthOf: contentView)
        stackView.preservesSuperviewLayoutMargins = true

        sizeChangeSubscription = stackView
            .publisher(for: \.bounds)
            .removeDuplicates()
            .sink { [weak self] bounds in
                guard let self else { return }
                let totalHandleHeight = Constants.handleSize.height + Constants.handleInsideMargin * 2
                let desiredHeight = bounds.height + totalHandleHeight
                self.minimizedHeight = desiredHeight
                self.contentScrollView.isScrollEnabled = self.maxHeight < desiredHeight
            }
    }

    open override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        let desiredInsets = self.stackViewInsets

        let bottomMargin = max(
            contentScrollView.safeAreaInsets.bottom + desiredInsets.bottom, minimumBottomInsetIncludingSafeArea
        )

        contentScrollView.layoutMargins = .init(
            top: desiredInsets.top,
            leading: desiredInsets.leading,
            bottom: bottomMargin,
            trailing: desiredInsets.trailing
        )
    }
}
