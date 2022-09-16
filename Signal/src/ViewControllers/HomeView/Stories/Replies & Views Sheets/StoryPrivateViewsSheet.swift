//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalUI

class StoryPrivateViewsSheet: InteractiveSheetViewController {
    override var interactiveScrollViews: [UIScrollView] { [viewsViewController.tableView] }
    override var minHeight: CGFloat { CurrentAppContext().frame.height * 0.6 }
    override var sheetBackgroundColor: UIColor { .ows_gray90 }

    var dismissHandler: (() -> Void)?

    let viewsViewController: StoryViewsViewController

    init(storyMessage: StoryMessage) {
        viewsViewController = StoryViewsViewController(storyMessage: storyMessage)
        super.init()
    }

    required init() {
        fatalError("init() has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

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
