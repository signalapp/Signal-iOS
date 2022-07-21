//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

open class OWSTableSheetViewController: InteractiveSheetViewController {
    public let tableViewController = OWSTableViewController2()
    public override var interactiveScrollViews: [UIScrollView] { [tableViewController.tableView] }

    public override var sheetBackgroundColor: UIColor {
        OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)
    }

    open var contentSizeHeight: CGFloat {
        tableViewController.tableView.contentSize.height + tableViewController.tableView.adjustedContentInset.totalHeight
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
