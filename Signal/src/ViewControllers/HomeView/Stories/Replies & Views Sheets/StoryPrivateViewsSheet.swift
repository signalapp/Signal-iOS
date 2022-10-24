//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI

class StoryPrivateViewsSheet: InteractiveSheetViewController {
    override var interactiveScrollViews: [UIScrollView] { [viewsViewController.tableView] }
    override var sheetBackgroundColor: UIColor { .ows_gray90 }

    var dismissHandler: (() -> Void)?

    let viewsViewController: StoryViewsViewController

    init(storyMessage: StoryMessage, context: StoryContext) {
        viewsViewController = StoryViewsViewController(storyMessage: storyMessage, context: context)
        super.init()
    }

    required init() {
        fatalError("init() has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        minimizedHeight = CurrentAppContext().frame.height * 0.6

        addChild(viewsViewController)
        contentView.addSubview(viewsViewController.view)
        viewsViewController.view.autoPinEdgesToSuperviewEdges()
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        super.dismiss(animated: flag) { [dismissHandler] in
            completion?()
            dismissHandler?()
        }
    }
}
