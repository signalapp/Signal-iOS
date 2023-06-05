//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit
import SignalUI

class StoryGroupReplySheet: InteractiveSheetViewController, StoryGroupReplier {
    override var interactiveScrollViews: [UIScrollView] { [groupReplyViewController.tableView] }
    override var sheetBackgroundColor: UIColor { .ows_gray90 }

    private let groupReplyViewController: StoryGroupReplyViewController

    var dismissHandler: (() -> Void)?

    var storyMessage: StoryMessage { groupReplyViewController.storyMessage }
    var threadUniqueId: String? { groupReplyViewController.thread?.uniqueId }

    init(storyMessage: StoryMessage) {
        self.groupReplyViewController = StoryGroupReplyViewController(storyMessage: storyMessage)

        super.init()

        self.allowsExpansion = true
    }

    public required init() {
        fatalError("init() has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        minimizedHeight = super.maxHeight

        addChild(groupReplyViewController)
        contentView.addSubview(groupReplyViewController.view)
        groupReplyViewController.view.autoPinEdgesToSuperviewEdges()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        groupReplyViewController.inputToolbar.becomeFirstResponder()
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        super.dismiss(animated: flag) { [dismissHandler] in
            completion?()
            dismissHandler?()
        }
    }
}
