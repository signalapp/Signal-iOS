//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalServiceKit
import SignalUI

class StoryGroupRepliesAndViewsSheet: InteractiveSheetViewController, StoryGroupReplier {
    override var interactiveScrollViews: [UIScrollView] { [groupReplyViewController.tableView, viewsViewController.tableView] }

    override var sheetBackgroundColor: UIColor { .ows_gray90 }

    weak var interactiveTransitionCoordinator: StoryInteractiveTransitionCoordinator?
    private let groupReplyViewController: StoryGroupReplyViewController
    private let viewsViewController: StoryViewsViewController
    private let pagingScrollView = UIScrollView()

    var storyMessage: StoryMessage { groupReplyViewController.storyMessage }
    var threadUniqueId: String? { groupReplyViewController.thread?.uniqueId }

    private lazy var viewsButton = createToggleButton(
        title: NSLocalizedString("STORIES_VIEWS_TAB", comment: "Title text for the 'views' tab on the stories views & replies sheet")
    ) { [weak self] in
        self?.switchToViewsTab(animated: true)
    }

    private lazy var repliesButton = createToggleButton(
        title: NSLocalizedString("STORIES_REPLIES_TAB", comment: "Title text for the 'replies' tab on the stories views & replies sheet")
    ) { [weak self] in
        self?.switchToRepliesTab(animated: true)
    }

    var dismissHandler: (() -> Void)?

    enum Tab: Int {
        case views = 0
        case replies = 1
    }
    var focusedTab: Tab = .views

    init(storyMessage: StoryMessage) {
        self.groupReplyViewController = StoryGroupReplyViewController(storyMessage: storyMessage)
        self.viewsViewController = StoryViewsViewController(storyMessage: storyMessage)

        super.init()
    }

    public required init() {
        fatalError("init() has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        switch focusedTab {
        case .views: minimizedHeight = CurrentAppContext().frame.height * 0.6
        case .replies: minimizedHeight = super.maximizedHeight
        }

        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.alignment = .center
        vStack.spacing = 20
        contentView.addSubview(vStack)
        vStack.autoPinEdgesToSuperviewEdges()

        let hStack = UIStackView(arrangedSubviews: [viewsButton, repliesButton])
        hStack.axis = .horizontal
        hStack.spacing = 12
        vStack.addArrangedSubview(hStack)

        pagingScrollView.isPagingEnabled = true
        pagingScrollView.showsHorizontalScrollIndicator = false
        pagingScrollView.isDirectionalLockEnabled = true
        pagingScrollView.delegate = self
        vStack.addArrangedSubview(pagingScrollView)
        pagingScrollView.autoPinEdge(toSuperviewSafeArea: .left)
        pagingScrollView.autoPinEdge(toSuperviewSafeArea: .right)

        let pagesContainer = UIView()
        pagingScrollView.addSubview(pagesContainer)
        pagesContainer.autoPinEdgesToSuperviewEdges()
        pagesContainer.autoMatch(.height, to: .height, of: pagingScrollView)
        pagesContainer.autoMatch(.width, to: .width, of: pagingScrollView, withMultiplier: 2)

        addChild(viewsViewController)
        pagesContainer.addSubview(viewsViewController.view)
        viewsViewController.view.autoMatch(.width, to: .width, of: pagesContainer, withMultiplier: 0.5)
        viewsViewController.view.autoPinHeightToSuperview()
        viewsViewController.view.autoPinEdge(toSuperviewEdge: .leading)

        groupReplyViewController.delegate = self
        addChild(groupReplyViewController)
        pagesContainer.addSubview(groupReplyViewController.view)
        groupReplyViewController.view.autoMatch(.width, to: .width, of: pagesContainer, withMultiplier: 0.5)
        groupReplyViewController.view.autoPinHeightToSuperview()
        groupReplyViewController.view.autoPinEdge(.leading, to: .trailing, of: viewsViewController.view)
        groupReplyViewController.view.autoPinEdge(toSuperviewEdge: .trailing)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        switch focusedTab {
        case .views: break
        case .replies:
            groupReplyViewController.inputToolbar.becomeFirstResponder()
        }
    }

    private var hasCompletedInitialLayout = false
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        guard !hasCompletedInitialLayout, view.frame != .zero else { return }
        hasCompletedInitialLayout = true

        // Once we have a frame, we need to re-switch to the tab
        switch focusedTab {
        case .views: switchToViewsTab(animated: false)
        case .replies: switchToRepliesTab(animated: false)
        }
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        super.dismiss(animated: flag) { [dismissHandler] in
            completion?()
            dismissHandler?()
        }
    }

    private var isManuallySwitchingTabs = false
    func switchToRepliesTab(animated: Bool) {
        isManuallySwitchingTabs = true
        focusedTab = .replies
        repliesButton.isSelected = true
        viewsButton.isSelected = false
        view.layoutIfNeeded()
        pagingScrollView.setContentOffset(CGPoint(x: pagingScrollView.width, y: 0), animated: animated)
        isManuallySwitchingTabs = false
    }

    func switchToViewsTab(animated: Bool) {
        isManuallySwitchingTabs = true
        focusedTab = .views
        repliesButton.isSelected = false
        viewsButton.isSelected = true
        pagingScrollView.setContentOffset(.zero, animated: animated)
        isManuallySwitchingTabs = false
    }

    func createToggleButton(title: String, block: @escaping () -> Void) -> UIButton {
        let button = OWSButton()
        button.block = { [unowned button] in
            guard !button.isSelected else { return }
            block()
        }
        button.autoSetDimension(.height, toSize: 28)
        button.layer.cornerRadius = 14
        button.clipsToBounds = true
        button.titleLabel?.font = UIFont.ows_semiboldFont(withSize: 15)
        button.contentEdgeInsets = UIEdgeInsets(hMargin: 12, vMargin: 4)
        button.setTitle(title, for: .normal)
        button.setTitleColor(Theme.darkThemePrimaryColor, for: .normal)
        button.setBackgroundImage(UIImage(color: .ows_gray65), for: .selected)
        return button
    }
}

extension StoryGroupRepliesAndViewsSheet: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        groupReplyViewController.inputToolbar.resignFirstResponder()

        guard !isManuallySwitchingTabs else { return }

        if scrollView.contentOffset.x < scrollView.width / 2 {
            repliesButton.isSelected = false
            viewsButton.isSelected = true
            focusedTab = .views
        } else {
            repliesButton.isSelected = true
            viewsButton.isSelected = false
            focusedTab = .replies
        }
    }
}

extension StoryGroupRepliesAndViewsSheet: StoryGroupReplyDelegate {
    func storyGroupReplyViewControllerDidBeginEditing(_ storyGroupReplyViewController: StoryGroupReplyViewController) {
        maximizeHeight()
    }
}

extension StoryGroupRepliesAndViewsSheet {
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
