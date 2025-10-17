//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit

open class OWSTableSheetViewController: InteractiveSheetViewController {
    open var tableViewController = OWSTableViewController2()
    open override var interactiveScrollViews: [UIScrollView] { [tableViewController.tableView] }

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
            + footerView.frame.height
            + bottomSafeAreaContentPadding
    }

    public init() {
        super.init()

        tableViewController.shouldDeferInitialLoad = false

        super.allowsExpansion = false
    }

    public func updateMinimizedHeight() {
        self.minimizedHeight = self.contentSizeHeight
    }

    private var footerView = UIView.container()
    private var footerViewConstraints = [NSLayoutConstraint]()

    public override func viewDidLoad() {
        super.viewDidLoad()

        addChild(tableViewController)
        contentView.addSubview(tableViewController.view)
        tableViewController.didMove(toParent: self)

        contentView.addSubview(footerView)

        tableViewController.view.translatesAutoresizingMaskIntoConstraints = false
        footerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableViewController.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            tableViewController.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tableViewController.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            footerView.topAnchor.constraint(equalTo: tableViewController.view.bottomAnchor),
            footerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        updateTableContents(shouldReload: true)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // The table view might not have its final size when this method is called.
        // Run a layout pass so that we compute the correct height constraints.
        self.tableViewController.tableView.layoutIfNeeded()
        self.updateMinimizedHeight()
    }

    public func updateTableContents(shouldReload: Bool = true) {
        // Update table view.
        tableViewController.setContents(tableContents(), shouldReload: shouldReload)

        // Update footer.
        footerView.removeAllSubviews()
        NSLayoutConstraint.deactivate(footerViewConstraints)
        if let footerContentView = tableFooterView() {
            footerView.addSubview(footerContentView)
            footerContentView.translatesAutoresizingMaskIntoConstraints = false
            footerViewConstraints = [
                footerContentView.topAnchor.constraint(equalTo: footerView.topAnchor),
                footerContentView.leadingAnchor.constraint(equalTo: footerView.leadingAnchor),
                footerContentView.trailingAnchor.constraint(equalTo: footerView.trailingAnchor),
                footerContentView.bottomAnchor.constraint(equalTo: footerView.bottomAnchor),
            ]
        } else {
            footerViewConstraints = [footerView.heightAnchor.constraint(equalToConstant: 0)]
        }
        NSLayoutConstraint.activate(footerViewConstraints)

        // Update height.
        updateMinimizedHeight()
    }

    open func tableContents() -> OWSTableContents {
        return OWSTableContents()
    }

    open func tableFooterView() -> UIView? {
        return nil
    }
}
