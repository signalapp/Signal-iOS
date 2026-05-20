//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class StoryGroupRepliesAndViewsViewController: OWSViewController, StoryGroupReplier, StoryGroupReplyDelegate,
    UIAdaptivePresentationControllerDelegate, UIScrollViewDelegate
{
    private let groupReplyViewController: StoryGroupReplyViewController
    private let viewsViewController: StoryViewsViewController
    private lazy var pagingScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.isDirectionalLockEnabled = true
        scrollView.delegate = self
        return scrollView
    }()

    var storyMessage: StoryMessage { groupReplyViewController.storyMessage }
    var threadUniqueId: String? { groupReplyViewController.thread?.uniqueId }

    private lazy var viewsAndRepliesControl: UISegmentedControl = {
        let control = UISegmentedControl(items: [
            OWSLocalizedString(
                "STORIES_VIEWS_TAB",
                comment: "Title text for the 'views' tab on the stories views & replies sheet",
            ),
            OWSLocalizedString(
                "STORIES_REPLIES_TAB",
                comment: "Title text for the 'replies' tab on the stories views & replies sheet",
            ),
        ])
        control.addAction(
            UIAction { [weak self] _ in
                self?.switchBetweenRepliesAndViews()
            },
            for: .primaryActionTriggered,
        )
        return control
    }()

    var dismissHandler: (() -> Void)?

    init(storyMessage: StoryMessage, context: StoryContext, spoilerState: SpoilerRenderState) {
        self.groupReplyViewController = StoryGroupReplyViewController(
            storyMessage: storyMessage,
            spoilerState: spoilerState,
            isStandaloneVC: false,
        )
        self.viewsViewController = StoryViewsViewController(
            storyMessage: storyMessage,
            context: context,
            isStandaloneVC: false,
        )

        super.init()

        groupReplyViewController.delegate = self

        overrideUserInterfaceStyle = .dark
        modalPresentationStyle = .pageSheet
        presentationController?.delegate = self

        if let sheetPresentationController {
            if #available(iOS 17.0, *) {
                sheetPresentationController.traitOverrides.userInterfaceStyle = .dark
            } else {
                sheetPresentationController.overrideTraitCollection = UITraitCollection(userInterfaceStyle: .dark)
            }
            sheetPresentationController.detents = [.medium(), .large()]
            sheetPresentationController.prefersGrabberVisible = true
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.preservesSuperviewLayoutMargins = true

        let segmentedControlContainer = UIView()
        segmentedControlContainer.addSubview(viewsAndRepliesControl)
        viewsAndRepliesControl.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            viewsAndRepliesControl.topAnchor.constraint(equalTo: segmentedControlContainer.topAnchor, constant: 8),
            viewsAndRepliesControl.leadingAnchor.constraint(greaterThanOrEqualTo: segmentedControlContainer.leadingAnchor),
            viewsAndRepliesControl.centerXAnchor.constraint(equalTo: segmentedControlContainer.centerXAnchor),
            viewsAndRepliesControl.bottomAnchor.constraint(equalTo: segmentedControlContainer.bottomAnchor),
        ])

        let vStack = UIStackView(arrangedSubviews: [segmentedControlContainer, pagingScrollView])
        vStack.axis = .vertical
        vStack.alignment = .fill
        vStack.spacing = 20
        view.addSubview(vStack)
        vStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            vStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            vStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Page container: same height as scroll view, twice the width (two full pages of content).
        let pageContainer = UIView()
        pagingScrollView.addSubview(pageContainer)
        pageContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageContainer.topAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.topAnchor),
            pageContainer.leadingAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.leadingAnchor),
            pageContainer.trailingAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.trailingAnchor),
            pageContainer.bottomAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.bottomAnchor),

            pageContainer.heightAnchor.constraint(equalTo: pagingScrollView.frameLayoutGuide.heightAnchor),
            pageContainer.widthAnchor.constraint(equalTo: pagingScrollView.frameLayoutGuide.widthAnchor, multiplier: 2),
        ])

        // Page 1: "Views"
        addChild(viewsViewController)
        pageContainer.addSubview(viewsViewController.view)
        viewsViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            viewsViewController.view.topAnchor.constraint(equalTo: pageContainer.topAnchor),
            viewsViewController.view.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
            viewsViewController.view.widthAnchor.constraint(equalTo: pageContainer.widthAnchor, multiplier: 0.5),
            viewsViewController.view.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor),
        ])

        // Page 2: "Replies"
        addChild(groupReplyViewController)
        pageContainer.addSubview(groupReplyViewController.view)
        groupReplyViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            groupReplyViewController.view.topAnchor.constraint(equalTo: pageContainer.topAnchor),
            groupReplyViewController.view.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
            groupReplyViewController.view.widthAnchor.constraint(equalTo: pageContainer.widthAnchor, multiplier: 0.5),
            groupReplyViewController.view.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor),
        ])

        pagingScrollViewObservation = pagingScrollView.observe(\.contentSize, changeHandler: { [weak self] _, _ in
            self?.didUpdatePagingScrollViewContentSize()
        })
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if case .replies = focusedTab {
            sheetPresentationController?.animateChanges {
                sheetPresentationController?.selectedDetentIdentifier = .large
            }
        }
    }

    private var pagingScrollViewObservation: NSKeyValueObservation?

    private func didUpdatePagingScrollViewContentSize() {
        guard view.frame != .zero, pagingScrollView.contentSize.width > 0 else { return }

        // Only need to trigger once.
        pagingScrollViewObservation = nil

        // Once we have a frame, we need to re-switch to the tab
        switch focusedTab {
        case .views:
            switchToTab(.views, animated: false)

        case .replies:
            switchToTab(.replies, animated: false)
            groupReplyViewController.inputToolbar.becomeFirstResponder()
        }
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        super.dismiss(animated: flag) { [dismissHandler] in
            completion?()
            dismissHandler?()
        }
    }

    // MARK: - Tabs

    private var ignoreScrollViewDidScroll = false

    enum Tab: Int {
        case views = 0
        case replies = 1
    }

    var focusedTab: Tab = .views

    private func switchBetweenRepliesAndViews() {
        guard let newTab = Tab(rawValue: viewsAndRepliesControl.selectedSegmentIndex) else { return }
        switchToTab(newTab, animated: true)
    }

    private func switchToTab(_ tab: Tab, animated: Bool) {
        if animated {
            ignoreScrollViewDidScroll = true
        }
        focusedTab = tab
        viewsAndRepliesControl.selectedSegmentIndex = tab.rawValue

        let xOffset: CGFloat = switch tab {
        case .views: 0
        case .replies: pagingScrollView.width
        }
        pagingScrollView.setContentOffset(CGPoint(x: xOffset, y: 0), animated: animated)
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        groupReplyViewController.inputToolbar.resignFirstResponder()

        guard ignoreScrollViewDidScroll == false else { return }

        let newTab: Tab = if scrollView.contentOffset.x < scrollView.width / 2 { .views } else { .replies }
        guard focusedTab != newTab else { return }

        focusedTab = newTab
        viewsAndRepliesControl.selectedSegmentIndex = focusedTab.rawValue
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        ignoreScrollViewDidScroll = false
    }

    // MARK: - StoryGroupReplyDelegate

    func storyGroupReplyViewControllerDidBeginEditing(_ storyGroupReplyViewController: StoryGroupReplyViewController) {
        sheetPresentationController?.animateChanges {
            sheetPresentationController?.selectedDetentIdentifier = .large
        }
    }

    // MARK: - UIAdaptivePresentationControllerDelegate

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        dismissHandler?()
    }
}
