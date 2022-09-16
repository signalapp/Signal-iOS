//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalServiceKit

class StoryGroupReplySheet: InteractiveSheetViewController, StoryGroupReplier {
    override var interactiveScrollViews: [UIScrollView] { [groupReplyViewController.tableView] }
    override var minHeight: CGFloat { maximizedHeight }
    override var sheetBackgroundColor: UIColor { .ows_gray90 }

    weak var interactiveTransitionCoordinator: StoryInteractiveTransitionCoordinator?
    private let groupReplyViewController: StoryGroupReplyViewController

    var dismissHandler: (() -> Void)?

    var storyMessage: StoryMessage { groupReplyViewController.storyMessage }
    var threadUniqueId: String? { groupReplyViewController.thread?.uniqueId }

    init(storyMessage: StoryMessage) {
        self.groupReplyViewController = StoryGroupReplyViewController(storyMessage: storyMessage)

        super.init()
    }

    public required init() {
        fatalError("init() has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(groupReplyViewController)
        contentView.addSubview(groupReplyViewController.view)
        groupReplyViewController.view.autoPinEdgesToSuperviewEdges()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        groupReplyViewController.inputToolbar.becomeFirstResponder()
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        super.dismiss(animated: flag) { [dismissHandler] in
            completion?()
            dismissHandler?()
        }
    }
}

extension StoryGroupReplySheet {
    override func presentationController(
        forPresented presented: UIViewController,
        presenting: UIViewController?,
        source: UIViewController
    ) -> UIPresentationController? {
        return nil
    }

    public func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        return StoryReplySheetAnimator(
            isPresenting: true,
            isInteractive: interactiveTransitionCoordinator != nil,
            backdropView: backdropView
        )
    }

    public func animationController(
        forDismissed dismissed: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        return StoryReplySheetAnimator(
            isPresenting: false,
            isInteractive: false,
            backdropView: backdropView
        )
    }

    public func interactionControllerForPresentation(
        using animator: UIViewControllerAnimatedTransitioning
    ) -> UIViewControllerInteractiveTransitioning? {
        interactiveTransitionCoordinator?.mode = .reply
        return interactiveTransitionCoordinator
    }
}
