//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class ReactionsDetailSheet: UIViewController {
    @objc
    let messageId: String

    private var reactionState: InteractionReactionState
    private let reactionFinder: ReactionFinder

    let stackView = UIStackView()
    let contentView = UIView()
    let handle = UIView()
    let backdropView = UIView()
    let emojiCountsCollectionView = EmojiCountsCollectionView()

    private var emojiCounts: [(emoji: String, count: Int)] {
        return reactionState.emojiCounts
    }

    private var allEmoji: [Emoji] {
        return emojiCounts.compactMap { Emoji($0.emoji) }
    }

    @objc
    init(reactionState: InteractionReactionState, message: TSMessage) {
        self.reactionState = reactionState
        self.messageId = message.uniqueId
        self.reactionFinder = ReactionFinder(uniqueMessageId: message.uniqueId)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    override public func loadView() {
        view = UIView()
        view.backgroundColor = .clear

        view.addSubview(contentView)
        contentView.autoPinEdge(toSuperviewEdge: .bottom)
        contentView.autoHCenterInSuperview()
        contentView.autoMatch(.height, to: .height, of: view, withOffset: 0, relation: .lessThanOrEqual)
        contentView.backgroundColor = Theme.actionSheetBackgroundColor

        // Prefer to be full width, but don't exceed the maximum width
        contentView.autoSetDimension(.width, toSize: maxWidth, relation: .lessThanOrEqual)
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            contentView.autoPinWidthToSuperview()
        }

        stackView.axis = .vertical
        stackView.spacing = 0

        contentView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()

        // Support tapping the backdrop to cancel the action sheet.
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapBackdrop(_:)))
        tapGestureRecognizer.delegate = self
        view.addGestureRecognizer(tapGestureRecognizer)

        // Prepare top view with emoji counts
        stackView.addArrangedSubview(emojiCountsCollectionView)
        buildEmojiCountItems()

        // Prepare paging between emoji reactors
        setupPaging()
        // Select the "all" reaction page by setting selected emoji to nil
        setSelectedEmoji(nil)

        // Setup handle for interactive dismissal / resizing
        setupInteractiveSizing()
    }

    private var hasPreparedInitialLayout = false
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        // Once we have a frame defined, we need to update the
        // page constraints. If we don't do this, the contentOffset
        // gets reset after the pagingScrollView layout occurs.
        guard !hasPreparedInitialLayout else { return }
        hasPreparedInitialLayout = true
        emojiPagingScrollView.superview?.layoutIfNeeded()
        updatePageConstraints(ignoreScrollingState: true)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Ensure the scrollView's layout has completed
        // as we're about to use its bounds to calculate
        // the masking view and contentOffset.
        contentView.layoutIfNeeded()

        let cornerRadius: CGFloat = 16
        let path = UIBezierPath(
            roundedRect: contentView.bounds,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(square: cornerRadius)
        )
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath
        contentView.layer.mask = shapeLayer
    }

    // MARK: -

    @objc
    func setReactionState(_ reactionState: InteractionReactionState, transaction: SDSAnyReadTransaction) {
        self.reactionState = reactionState

        buildEmojiCountItems()

        // If the currently selected emoji still exists, keep it selected.
        // Otherwise, select the "all" page by setting selected emoji to nil.
        let newSelectedEmoji: Emoji?
        if let selectedEmoji = selectedEmoji, allEmoji.contains(selectedEmoji) {
            newSelectedEmoji = selectedEmoji
        } else {
            newSelectedEmoji = nil
        }

        setSelectedEmoji(newSelectedEmoji, transaction: transaction)
    }

    func buildEmojiCountItems() {
        let allReactionsItem = EmojiItem(emoji: nil, count: emojiCounts.lazy.map { $0.count }.reduce(0, +)) { [weak self] in
            self?.setSelectedEmoji(nil)
        }

        emojiCountsCollectionView.items = [allReactionsItem] + emojiCounts.map { (emoji, count) in
            EmojiItem(emoji: emoji, count: count) { [weak self] in
                self?.setSelectedEmoji(Emoji(emoji))
            }
        }
    }

    @objc func didTapBackdrop(_ sender: UITapGestureRecognizer) {
        dismiss(animated: true)
    }

    // MARK: - Emoji Selection

    private var selectedEmoji: Emoji?

    func setSelectedEmoji(_ emoji: Emoji?) {
        SDSDatabaseStorage.shared.uiRead { self.setSelectedEmoji(emoji, transaction: $0) }
    }

    func setSelectedEmoji(_ emoji: Emoji?, transaction: SDSAnyReadTransaction) {
        let oldValue = selectedEmoji
        selectedEmoji = emoji
        selectedEmojiChanged(oldSelectedEmoji: oldValue, transaction: transaction)
    }

    // MARK: - Resize / Interactive Dismiss

    var heightConstraint: NSLayoutConstraint?
    let maxWidth: CGFloat = 414
    var minimizedHeight: CGFloat {
        return min(maximizedHeight, 346)
    }
    var maximizedHeight: CGFloat {
        return CurrentAppContext().frame.height - topLayoutGuide.length - 32
    }

    let maxAnimationDuration: TimeInterval = 0.2
    var startingHeight: CGFloat?
    var startingTranslation: CGFloat?

    func setupInteractiveSizing() {
        heightConstraint = contentView.autoSetDimension(.height, toSize: minimizedHeight)

        // Create a pan gesture to handle when the user interacts with the
        // view outside of the reactor table views.
        let panGestureRecognizer = DirectionalPanGestureRecognizer(direction: .vertical, target: self, action: #selector(handlePan))
        view.addGestureRecognizer(panGestureRecognizer)
        panGestureRecognizer.delegate = self

        // We also want to handle the pan gesture for all of the table
        // views, so we can do a nice scroll to dismiss gesture, and
        // so we can transfer any initial scrolling into maximizing
        // the view.
        emojiReactorsViews.forEach { $0.panGestureRecognizer.addTarget(self, action: #selector(handlePan)) }

        handle.backgroundColor = .ows_whiteAlpha80
        handle.autoSetDimensions(to: CGSize(width: 56, height: 5))
        handle.layer.cornerRadius = 5 / 2
        view.addSubview(handle)
        handle.autoHCenterInSuperview()
        handle.autoPinEdge(.bottom, to: .top, of: contentView, withOffset: -8)
    }

    @objc func handlePan(_ sender: UIPanGestureRecognizer) {
        let isTableViewPanGesture = currentPageReactorsView.panGestureRecognizer == sender

        switch sender.state {
        case .began, .changed:
            guard beginInteractiveTransitionIfNecessary(sender),
                let startingHeight = startingHeight,
                let startingTranslation = startingTranslation else {
                    return resetInteractiveTransition()
            }

            // We're in an interactive transition, so don't let the scrollView scroll.
            if isTableViewPanGesture {
                currentPageReactorsView.contentOffset.y = 0
                currentPageReactorsView.showsVerticalScrollIndicator = false
            }

            // We may have panned some distance if we were scrolling before we started
            // this interactive transition. Offset the translation we use to move the
            // view by whatever the translation was when we started the interactive
            // portion of the gesture.
            let translation = sender.translation(in: view).y - startingTranslation

            var newHeight = startingHeight - translation
            if newHeight > maximizedHeight {
                newHeight = maximizedHeight
            }

            // If the height is decreasing, adjust the relevant view's proporitionally
            if newHeight < startingHeight {
                backdropView.alpha = 1 - (startingHeight - newHeight) / startingHeight
            }

            // Update our height to reflect the new position
            heightConstraint?.constant = newHeight
            view.layoutIfNeeded()
        case .ended, .cancelled, .failed:
            guard let startingHeight = startingHeight else { break }

            let dismissThreshold = startingHeight * 0.5
            let growThreshold = startingHeight * 1.5
            let velocityThreshold: CGFloat = 500

            let currentHeight = contentView.height
            let currentVelocity = sender.velocity(in: view).y

            enum CompletionState { case growing, dismissing, cancelling }
            let completionState: CompletionState

            if abs(currentVelocity) >= velocityThreshold {
                completionState = currentVelocity < 0 ? .growing : .dismissing
            } else if currentHeight >= growThreshold {
                completionState = .growing
            } else if currentHeight <= dismissThreshold {
                completionState = .dismissing
            } else {
                completionState = .cancelling
            }

            let finalHeight: CGFloat
            switch completionState {
            case .dismissing:
                finalHeight = 0
            case .growing:
                finalHeight = maximizedHeight
            case .cancelling:
                finalHeight = startingHeight
            }

            let remainingDistance = finalHeight - currentHeight

            // Calculate the time to complete the animation if we want to preserve
            // the user's velocity. If this time is too slow (e.g. the user was scrolling
            // very slowly) we'll default to `maxAnimationDuration`
            let remainingTime = TimeInterval(abs(remainingDistance / currentVelocity))

            UIView.animate(withDuration: min(remainingTime, maxAnimationDuration), delay: 0, options: .curveEaseOut, animations: {
                if remainingDistance < 0 {
                    self.contentView.frame.origin.y -= remainingDistance
                    self.handle.frame.origin.y -= remainingDistance
                } else {
                    self.heightConstraint?.constant = finalHeight
                    self.view.layoutIfNeeded()
                }

                self.backdropView.alpha = completionState == .dismissing ? 0 : 1
            }) { _ in
                self.heightConstraint?.constant = finalHeight
                self.view.layoutIfNeeded()

                if completionState == .dismissing { self.dismiss(animated: true, completion: nil) }
            }

            resetInteractiveTransition()
        default:
            resetInteractiveTransition()

            backdropView.alpha = 1

            guard let startingHeight = startingHeight else { break }
            heightConstraint?.constant = startingHeight
        }
    }

    func beginInteractiveTransitionIfNecessary(_ sender: UIPanGestureRecognizer) -> Bool {
        // If we're at the top of the scrollView, the the view is not
        // currently maximized, or we're panning outside of the table
        // view we want to do an interactive transition.
        guard currentPageReactorsView.contentOffset.y <= 0
            || contentView.height < maximizedHeight
            || sender != currentPageReactorsView.panGestureRecognizer else { return false }

        if startingTranslation == nil {
            startingTranslation = sender.translation(in: view).y
        }

        if startingHeight == nil {
            startingHeight = contentView.height
        }

        return true
    }

    func resetInteractiveTransition() {
        startingTranslation = nil
        startingHeight = nil
        currentPageReactorsView.showsVerticalScrollIndicator = true
    }

    // MARK: - Paging

    /// This array always includes three reactors views, where the indices represent:
    /// 0 - Previous Page
    /// 1 - Current Page
    /// 2 - Next Page
    private lazy var emojiReactorsViews = [
        EmojiReactorsTableView(),
        EmojiReactorsTableView(),
        EmojiReactorsTableView()
    ]
    private var emojiReactorsViewConstraints = [NSLayoutConstraint]()

    private var currentPageReactorsView: EmojiReactorsTableView {
        return emojiReactorsViews[1]
    }

    private var nextPageReactorsView: EmojiReactorsTableView {
        return emojiReactorsViews[2]
    }

    private var previousPageReactorsView: EmojiReactorsTableView {
        return emojiReactorsViews[0]
    }

    private let emojiPagingScrollView = UIScrollView()

    private var nextPageEmoji: Emoji? {
        // If we don't have an emoji defined, the first emoji is always up next
        guard let emoji = selectedEmoji else { return allEmoji.first }

        // If we don't have an index, or we're at the end of the array, "all" is up next
        guard let index = allEmoji.firstIndex(of: emoji), index < (allEmoji.count - 1) else { return nil }

        // Otherwise, use the next emoji in the array
        return allEmoji[index + 1]
    }

    private var previousPageEmoji: Emoji? {
        // If we don't have an emoji defined, the last emoji is always previous
        guard let emoji = selectedEmoji else { return allEmoji.last }

        // If we don't have an index, or we're at the start of the array, "all" is previous
        guard let index = allEmoji.firstIndex(of: emoji), index > 0 else { return nil }

        // Otherwise, use the previous emoji in the array
        return allEmoji[index - 1]
    }

    private var pageWidth: CGFloat { return min(CurrentAppContext().frame.width, maxWidth) }
    private var numberOfPages: CGFloat { return CGFloat(emojiReactorsViews.count) }

    // These thresholds indicate the offset at which we update the next / previous page.
    // They're not exactly half way through the transition, to avoid us continously
    // bouncing back and forth between pages.
    private var previousPageThreshold: CGFloat { return pageWidth * 0.45 }
    private var nextPageThreshold: CGFloat { return pageWidth + previousPageThreshold }

    private func setupPaging() {
        emojiPagingScrollView.isPagingEnabled = true
        emojiPagingScrollView.showsHorizontalScrollIndicator = false
        emojiPagingScrollView.isDirectionalLockEnabled = true
        emojiPagingScrollView.delegate = self
        stackView.addArrangedSubview(emojiPagingScrollView)
        emojiPagingScrollView.autoPinEdge(toSuperviewSafeArea: .left)
        emojiPagingScrollView.autoPinEdge(toSuperviewSafeArea: .right)

        let reactorsPagesContainer = UIView()
        emojiPagingScrollView.addSubview(reactorsPagesContainer)
        reactorsPagesContainer.autoPinEdgesToSuperviewEdges()
        reactorsPagesContainer.autoMatch(.height, to: .height, of: emojiPagingScrollView)
        reactorsPagesContainer.autoMatch(.width, to: .width, of: emojiPagingScrollView, withMultiplier: numberOfPages)

        for (index, reactorsView) in emojiReactorsViews.enumerated() {
            reactorsView.isDirectionalLockEnabled = true

            // We want the current page on top, to prevent weird
            // animations when we initially calculate our frame.
            if reactorsView == currentPageReactorsView {
                reactorsPagesContainer.addSubview(reactorsView)
            } else {
                reactorsPagesContainer.insertSubview(reactorsView, at: 0)
            }

            reactorsView.autoMatch(.width, to: .width, of: emojiPagingScrollView)
            reactorsView.autoMatch(.height, to: .height, of: emojiPagingScrollView)

            reactorsView.autoPinEdge(toSuperviewEdge: .top)
            reactorsView.autoPinEdge(toSuperviewEdge: .bottom)

            emojiReactorsViewConstraints.append(
                reactorsView.autoPinEdge(toSuperviewEdge: .left, withInset: CGFloat(index) * pageWidth)
            )
        }
    }

    private func reactions(for emoji: Emoji?, transaction: SDSAnyReadTransaction) -> [OWSReaction] {
        guard let emoji = emoji else {
            return reactionFinder.allReactions(transaction: transaction.unwrapGrdbRead)
        }

        guard let reactions = reactionState.reactionsByEmoji[emoji] else {
            owsFailDebug("missing reactions for emoji \(emoji)")
            return []
        }

        return reactions
    }

    private func selectedEmojiChanged(oldSelectedEmoji: Emoji?, transaction: SDSAnyReadTransaction) {
        AssertIsOnMainThread()

        // We're paging backwards!
        if oldSelectedEmoji == nextPageEmoji, oldSelectedEmoji != selectedEmoji {
            // The previous page becomes the current page and the current page becomes
            // the next page. We have to load the new previous.

            emojiReactorsViews.insert(emojiReactorsViews.removeLast(), at: 0)
            emojiReactorsViewConstraints.insert(emojiReactorsViewConstraints.removeLast(), at: 0)

            let previousPageReactions = reactions(for: previousPageEmoji, transaction: transaction)
            previousPageReactorsView.configure(for: previousPageReactions, transaction: transaction)

        // We're paging forwards!
        } else if oldSelectedEmoji == previousPageEmoji, oldSelectedEmoji != selectedEmoji {
            // The next page becomes the current page and the current page becomes
            // the previous page. We have to load the new next.

            emojiReactorsViews.append(emojiReactorsViews.removeFirst())
            emojiReactorsViewConstraints.append(emojiReactorsViewConstraints.removeFirst())

            let nextPageReactions = reactions(for: nextPageEmoji, transaction: transaction)
            nextPageReactorsView.configure(for: nextPageReactions, transaction: transaction)

        // We didn't get here through paging, stuff probably changed. Reload all the things.
        } else {
            let currentPageReactions = reactions(for: selectedEmoji, transaction: transaction)
            currentPageReactorsView.configure(for: currentPageReactions, transaction: transaction)

            let previousPageReactions = reactions(for: previousPageEmoji, transaction: transaction)
            previousPageReactorsView.configure(for: previousPageReactions, transaction: transaction)

            let nextPageReactions = reactions(for: nextPageEmoji, transaction: transaction)
            nextPageReactorsView.configure(for: nextPageReactions, transaction: transaction)
        }

        updatePageConstraints()

        // Update selection on the counts view to reflect our new selected emoji
        if let selectedEmoji = selectedEmoji, let index = allEmoji.firstIndex(of: selectedEmoji) {
            emojiCountsCollectionView.setSelectedIndex(index + 1)
        } else {
            emojiCountsCollectionView.setSelectedIndex(0)
        }
    }

    private func updatePageConstraints(ignoreScrollingState: Bool = false) {
        // Setup the collection views in their page positions
        for (index, constraint) in emojiReactorsViewConstraints.enumerated() {
            constraint.constant = CGFloat(index) * pageWidth
        }

        // Scrolling backwards
        if !ignoreScrollingState && emojiPagingScrollView.contentOffset.x <= previousPageThreshold {
            emojiPagingScrollView.contentOffset.x += pageWidth

        // Scrolling forward
        } else if !ignoreScrollingState && emojiPagingScrollView.contentOffset.x >= nextPageThreshold {
            emojiPagingScrollView.contentOffset.x -= pageWidth

        // Not moving forward or back, just scroll back to center so we can go forward and back again
        } else {
            emojiPagingScrollView.contentOffset.x = pageWidth
        }
    }

    // MARK: - Scroll state management

    /// Indicates that the user stopped actively scrolling, but
    /// we still haven't reached their final destination.
    private var isWaitingForDeceleration = false

    /// Indicates that the user started scrolling and we've yet
    /// to reach their final destination.
    private var isUserScrolling = false

    /// Indicates that we're currently changing pages due to a
    /// user initiated scroll action.
    private var isScrollingChange = false

    private func userStartedScrolling() {
        isWaitingForDeceleration = false
        isUserScrolling = true
    }

    private func userStoppedScrolling(waitingForDeceleration: Bool = false) {
        guard isUserScrolling else { return }

        if waitingForDeceleration {
            isWaitingForDeceleration = true
        } else {
            isWaitingForDeceleration = false
            isUserScrolling = false
        }
    }

    private func checkForPageChange() {
        // Ignore any page changes unless the user is triggering them.
        guard isUserScrolling else { return }

        isScrollingChange = true

        let offsetX = emojiPagingScrollView.contentOffset.x

        // Scrolled left a page
        if offsetX <= previousPageThreshold {
            setSelectedEmoji(previousPageEmoji)

        // Scrolled right a page
        } else if offsetX >= nextPageThreshold {
            setSelectedEmoji(nextPageEmoji)

        }

        isScrollingChange = false
    }
}

// MARK: -

extension ReactionsDetailSheet: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        checkForPageChange()
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        userStartedScrolling()
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        userStoppedScrolling(waitingForDeceleration: decelerate)
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        userStoppedScrolling()
    }
}

// MARK: -
extension ReactionsDetailSheet: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        switch gestureRecognizer {
        case is UITapGestureRecognizer:
            let point = gestureRecognizer.location(in: view)
            guard !contentView.frame.contains(point) else { return false }
            return true
        default:
            return true
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        switch gestureRecognizer {
        case is UIPanGestureRecognizer:
            return currentPageReactorsView.panGestureRecognizer == otherGestureRecognizer
        default:
            return false
        }
    }
}

// MARK: -

private class ReactionsDetailAnimationController: UIPresentationController {

    var backdropView: UIView? {
        guard let vc = presentedViewController as? ReactionsDetailSheet else { return nil }
        return vc.backdropView
    }

    override init(presentedViewController: UIViewController, presenting presentingViewController: UIViewController?) {
        super.init(presentedViewController: presentedViewController, presenting: presentingViewController)
        backdropView?.backgroundColor = Theme.backdropColor
    }

    override func presentationTransitionWillBegin() {
        guard let containerView = containerView, let backdropView = backdropView else { return }
        backdropView.alpha = 0
        containerView.addSubview(backdropView)
        backdropView.autoPinEdgesToSuperviewEdges()
        containerView.layoutIfNeeded()

        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.backdropView?.alpha = 1
        }, completion: nil)
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.backdropView?.alpha = 0
        }, completion: { _ in
            self.backdropView?.removeFromSuperview()
        })
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard let presentedView = presentedView else { return }
        coordinator.animate(alongsideTransition: { _ in
            presentedView.frame = self.frameOfPresentedViewInContainerView
            presentedView.layoutIfNeeded()
        }, completion: nil)
    }
}

extension ReactionsDetailSheet: UIViewControllerTransitioningDelegate {
    public func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return ReactionsDetailAnimationController(presentedViewController: presented, presenting: presenting)
    }
}
