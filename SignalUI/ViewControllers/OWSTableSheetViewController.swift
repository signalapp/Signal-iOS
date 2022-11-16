//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit

open class OWSTableSheetViewController: InteractiveSheetViewController {
    public let tableViewController = OWSTableViewController2()
    public override var interactiveScrollViews: [UIScrollView] { [tableViewController.tableView] }

    open override var sheetBackgroundColor: UIColor {
        OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true, forceDarkMode: tableViewController.forceDarkMode)
    }

    open var bottomSafeAreaContentPadding: CGFloat {
        var padding = view.safeAreaInsets.bottom
        if padding == 0 {
            // For home button devices, add generous bottom padding
            // so it isn't right up on the edge.
            padding = 36
        } else {
            // For other devices, just add a touch extra.
            padding += 12
        }
        return padding
    }

    private var contentSizeHeight: CGFloat {
        let tableView = tableViewController.tableView
        // The `adjustedContentInset` property diverges from its stable value during
        // interactive dismiss operations. This causes weird drag/height jump behavior.
        // Instead, compute the height using `view.safeAreaInsets`, which remains stable
        // during animations. (Note that `.top` isn't considered here since
        // `maximumHeight` prevents the view's height from extending into top safe area.)
        return tableView.contentSize.height
            + tableView.contentInset.totalHeight
            + footerStack.frame.height
            + bottomSafeAreaContentPadding
    }

    private var contentSizeObservation: NSKeyValueObservation?

    public required init() {
        super.init()

        tableViewController.shouldDeferInitialLoad = false

        super.allowsExpansion = false
        contentSizeObservation = tableViewController.tableView.observe(\.contentSize, changeHandler: { [weak self] (_, _) in
            guard let self = self else { return }
            self.minimizedHeight = self.contentSizeHeight
        })
    }

    deinit {
        contentSizeObservation?.invalidate()
    }

    open var footerStack: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.distribution = .fill
        view.alignment = .center
        view.preservesSuperviewLayoutMargins = true
        return view
    }()

    public override func viewDidLoad() {
        super.viewDidLoad()

        addChild(tableViewController)
        contentView.addSubview(tableViewController.view)
        contentView.addSubview(footerStack)

        tableViewController.view.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        footerStack.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .top)
        tableViewController.view.autoPinEdge(.bottom, to: .top, of: footerStack)

        minimizedHeight = contentSizeHeight

        updateViewState()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateViewState()
    }

    private var previousMinimizedHeight: CGFloat?
    private var previousSafeAreaInsets: UIEdgeInsets?
    public func updateViewState() {
        if previousSafeAreaInsets != tableViewController.view.safeAreaInsets {
            updateTableContents()
            previousSafeAreaInsets = tableViewController.view.safeAreaInsets
        }
        // The table view might not have its final size when this method is called.
        // Run a layout pass so that we compute the correct height constraints.
        self.tableViewController.tableView.layoutIfNeeded()
    }

    public override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    open func updateTableContents(shouldReload: Bool = true) {

    }
}
