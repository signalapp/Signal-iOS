//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

open class OWSTableSheetViewController: InteractiveSheetViewController {
    public let tableViewController = OWSTableViewController2()
    public override var interactiveScrollViews: [UIScrollView] { [tableViewController.tableView] }

    open override var sheetBackgroundColor: UIColor {
        OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)
    }

    private var contentSizeHeight: CGFloat {
        let tableView = tableViewController.tableView
        // The `adjustedContentInset` property diverges from its stable value during
        // interactive dismiss operations. This causes weird drag/height jump behavior.
        // Instead, compute the height using `view.safeAreaInsets`, which remains stable
        // during animations. (Note that `.top` isn't considered here since
        // `maximumHeight` prevents the view's height from extending into top safe area.)
        return tableView.contentSize.height + tableView.contentInset.totalHeight + view.safeAreaInsets.bottom
    }
    public override var minimizedHeight: CGFloat {
        return min(contentSizeHeight, maximizedHeight)
    }
    public override var maximizedHeight: CGFloat {
        min(contentSizeHeight, CurrentAppContext().frame.height - (view.safeAreaInsets.top + 32))
    }

    public required init() {
        super.init()

        tableViewController.shouldDeferInitialLoad = false
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        addChild(tableViewController)
        contentView.addSubview(tableViewController.view)
        tableViewController.view.autoPinEdgesToSuperviewEdges()

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
        // This comparison isn't redundant: assigning same value to `heightConstraint.constant`
        // triggers a layout cycle and therefore this method, where height being reset to a previous value,
        // killing interactive dismiss.
        let minimizedHeight = minimizedHeight
        if minimizedHeight != previousMinimizedHeight {
            heightConstraint.constant = minimizedHeight
            previousMinimizedHeight = minimizedHeight
        }
        maxHeightConstraint.constant = maximizedHeight
    }

    public override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    open func updateTableContents(shouldReload: Bool = true) {

    }
}
