//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit

open class OWSTableSheetViewController: InteractiveSheetViewController {
    open var tableViewController = OWSTableViewController2()
    override open var interactiveScrollViews: [UIScrollView] { [tableViewController.tableView] }

    override open var sheetBackgroundColor: UIColor {
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
            + (tableViewController.bottomFooter?.height ?? 0)
            + bottomSafeAreaContentPadding
    }

    override public init(visualEffect: UIVisualEffect? = nil) {
        super.init(visualEffect: visualEffect)

        tableViewController.shouldDeferInitialLoad = false

        super.allowsExpansion = false
    }

    public func updateMinimizedHeight() {
        self.minimizedHeight = self.contentSizeHeight
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        addChild(tableViewController)
        contentView.addSubview(tableViewController.view)
        tableViewController.didMove(toParent: self)

        tableViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableViewController.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            tableViewController.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tableViewController.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tableViewController.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        updateTableContents(shouldReload: true)
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // The table view might not have its final size when this method is called.
        // Run a layout pass so that we compute the correct height constraints.
        self.tableViewController.tableView.layoutIfNeeded()
        self.updateMinimizedHeight()
    }

    public func updateTableContents(shouldReload: Bool = true) {
        tableViewController.setContents(tableContents(), shouldReload: shouldReload)
        updateMinimizedHeight()
    }

    open func tableContents() -> OWSTableContents {
        return OWSTableContents()
    }
}
