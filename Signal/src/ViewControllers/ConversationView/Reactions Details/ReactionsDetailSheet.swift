//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

class ReactionsDetailSheet: InteractiveSheetViewController {
    let messageId: String

    private var reactionState: InteractionReactionState
    private let reactionFinder: ReactionFinder

    let stackView = UIStackView()
    let emojiCountsCollectionView = EmojiCountsCollectionView()

    override var interactiveScrollViews: [UIScrollView] { emojiReactorsViews }

    private var emojiCounts: [InteractionReactionState.EmojiCount] {
        reactionState.emojiCounts
    }

    private var allEmoji: [Emoji] {
        return emojiCounts.compactMap { Emoji($0.emoji) }
    }

    init(reactionState: InteractionReactionState, message: TSMessage) {
        self.reactionState = reactionState
        self.messageId = message.uniqueId
        self.reactionFinder = ReactionFinder(uniqueMessageId: message.uniqueId)
        super.init()
    }

    public required init() {
        fatalError("init() has not been implemented")
    }

    // MARK: -

    override public func viewDidLoad() {
        super.viewDidLoad()

        stackView.axis = .vertical
        stackView.spacing = 0

        contentView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()

        // Prepare top view with emoji counts
        stackView.addArrangedSubview(emojiCountsCollectionView)
        buildEmojiCountItems()

        // Prepare paging between emoji reactors
        setupPaging()
        // Select the "all" reaction page by setting selected emoji to nil
        setSelectedEmoji(nil)
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

    // MARK: -

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

        emojiCountsCollectionView.items = [allReactionsItem] + emojiCounts.map { (emojiCount) in
            EmojiItem(emoji: emojiCount.emoji,
                      count: emojiCount.count) { [weak self] in
                self?.setSelectedEmoji(Emoji(emojiCount.emoji))
            }
        }
    }

    // MARK: - Emoji Selection

    private var selectedEmoji: Emoji?

    func setSelectedEmoji(_ emoji: Emoji?) {
        SDSDatabaseStorage.shared.read { self.setSelectedEmoji(emoji, transaction: $0) }
    }

    func setSelectedEmoji(_ emoji: Emoji?, transaction: SDSAnyReadTransaction) {
        let oldValue = selectedEmoji
        selectedEmoji = emoji
        selectedEmojiChanged(oldSelectedEmoji: oldValue, transaction: transaction)
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
    // They're not exactly half way through the transition, to avoid us continuously
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
