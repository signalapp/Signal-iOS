//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class ReactionsDetailSheet: InteractiveSheetViewController {
    let messageId: String

    private var reactionState: InteractionReactionState
    private let reactionFinder: ReactionFinder

    let stickerImageCache = StickerReactionImageCache()
    let stackView = UIStackView()
    lazy var emojiCountsCollectionView = EmojiCountsCollectionView(stickerImageCache: stickerImageCache)

    override var interactiveScrollViews: [UIScrollView] { emojiReactorsViews }

    override var placeOnGlassIfAvailable: Bool { true }

    private var emojiCounts: [InteractionReactionState.EmojiCount] {
        reactionState.emojiCounts
    }

    private var allGroupKeys: [ReactionGroupKey] {
        return emojiCounts.map { $0.groupKey }
    }

    init(reactionState: InteractionReactionState, message: TSMessage) {
        self.reactionState = reactionState
        self.messageId = message.uniqueId
        self.reactionFinder = ReactionFinder(uniqueMessageId: message.uniqueId)
        super.init()
        self.animationsShouldBeInterruptible = true
    }

    // MARK: -

    override func viewDidLoad() {
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
        // Select the "all" reaction page by setting selected group key to nil
        setSelectedGroupKey(nil)
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        // pageWidth needs to have an accurate value
        DispatchQueue.main.async {
            self.updatePageConstraints(ignoreScrollingState: true)
        }
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
    }

    // MARK: -

    func setReactionState(_ reactionState: InteractionReactionState, transaction: DBReadTransaction) {
        self.reactionState = reactionState

        buildEmojiCountItems()

        // If the currently selected group key still exists, keep it selected.
        // Otherwise, select the "all" page by setting selected group key to nil.
        let newSelectedGroupKey: ReactionGroupKey?
        if let selectedGroupKey, allGroupKeys.contains(selectedGroupKey) {
            newSelectedGroupKey = selectedGroupKey
        } else {
            newSelectedGroupKey = nil
        }

        setSelectedGroupKey(newSelectedGroupKey, transaction: transaction)
    }

    func buildEmojiCountItems() {
        let allReactionsItem = EmojiItem(emoji: nil, count: emojiCounts.lazy.map { $0.count }.reduce(0, +)) { [weak self] in
            self?.setSelectedGroupKey(nil)
        }

        emojiCountsCollectionView.items = [allReactionsItem] + emojiCounts.map { emojiCount in
            return EmojiItem(
                emoji: emojiCount.stickerAttachment != nil ? nil : emojiCount.emoji,
                count: emojiCount.count,
                sticker: emojiCount.stickerAttachment,
            ) { [weak self] in
                self?.setSelectedGroupKey(emojiCount.groupKey)
            }
        }
    }

    // MARK: - Group Key Selection

    private var selectedGroupKey: ReactionGroupKey?

    func setSelectedGroupKey(_ groupKey: ReactionGroupKey?) {
        SSKEnvironment.shared.databaseStorageRef.read { self.setSelectedGroupKey(groupKey, transaction: $0) }
    }

    func setSelectedGroupKey(_ groupKey: ReactionGroupKey?, transaction: DBReadTransaction) {
        let oldValue = selectedGroupKey
        selectedGroupKey = groupKey
        selectedGroupKeyChanged(oldSelectedGroupKey: oldValue, transaction: transaction)
    }

    // MARK: - Paging

    /// This array always includes three reactors views, where the indices represent:
    /// 0 - Previous Page
    /// 1 - Current Page
    /// 2 - Next Page
    private lazy var emojiReactorsViews: [EmojiReactorsTableView] = {
        let views = [
            EmojiReactorsTableView(stickerImageCache: stickerImageCache),
            EmojiReactorsTableView(stickerImageCache: stickerImageCache),
            EmojiReactorsTableView(stickerImageCache: stickerImageCache)
        ]
        views.forEach { $0.reactorDelegate = self }
        return views
    }()
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

    private var nextPageGroupKey: ReactionGroupKey? {
        // If we don't have a group key defined, the first group is always up next
        guard let key = selectedGroupKey else { return allGroupKeys.first }

        // If we don't have an index, or we're at the end of the array, "all" is up next
        guard let index = allGroupKeys.firstIndex(of: key), index < (allGroupKeys.count - 1) else { return nil }

        // Otherwise, use the next group key in the array
        return allGroupKeys[index + 1]
    }

    private var previousPageGroupKey: ReactionGroupKey? {
        // If we don't have a group key defined, the last group is always previous
        guard let key = selectedGroupKey else { return allGroupKeys.last }

        // If we don't have an index, or we're at the start of the array, "all" is previous
        guard let index = allGroupKeys.firstIndex(of: key), index > 0 else { return nil }

        // Otherwise, use the previous group key in the array
        return allGroupKeys[index - 1]
    }

    private var pageWidth: CGFloat { return min(contentView.frame.width, maxWidth) }
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
                reactorsView.autoPinEdge(toSuperviewEdge: .left, withInset: CGFloat(index) * pageWidth),
            )
        }
    }

    private func reactions(for groupKey: ReactionGroupKey?, transaction: DBReadTransaction) -> [OWSReaction] {
        guard let groupKey else {
            return reactionFinder.allReactions(transaction: transaction)
        }

        guard let reactions = reactionState.reactionsByGroupKey[groupKey] else {
            owsFailDebug("missing reactions for group key")
            return []
        }

        return reactions
    }

    private func selectedGroupKeyChanged(oldSelectedGroupKey: ReactionGroupKey?, transaction: DBReadTransaction) {
        AssertIsOnMainThread()

        // We're paging backwards!
        if oldSelectedGroupKey == nextPageGroupKey, oldSelectedGroupKey != selectedGroupKey {
            // The previous page becomes the current page and the current page becomes
            // the next page. We have to load the new previous.

            emojiReactorsViews.insert(emojiReactorsViews.removeLast(), at: 0)
            emojiReactorsViewConstraints.insert(emojiReactorsViewConstraints.removeLast(), at: 0)

            let previousPageReactions = reactions(for: previousPageGroupKey, transaction: transaction)
            previousPageReactorsView.configure(for: previousPageReactions, stickerAttachmentByReactionId: reactionState.stickerAttachmentByReactionId, transaction: transaction)

            // We're paging forwards!
        } else if oldSelectedGroupKey == previousPageGroupKey, oldSelectedGroupKey != selectedGroupKey {
            // The next page becomes the current page and the current page becomes
            // the previous page. We have to load the new next.

            emojiReactorsViews.append(emojiReactorsViews.removeFirst())
            emojiReactorsViewConstraints.append(emojiReactorsViewConstraints.removeFirst())

            let nextPageReactions = reactions(for: nextPageGroupKey, transaction: transaction)
            nextPageReactorsView.configure(for: nextPageReactions, stickerAttachmentByReactionId: reactionState.stickerAttachmentByReactionId, transaction: transaction)

            // We didn't get here through paging, stuff probably changed. Reload all the things.
        } else {
            let currentPageReactions = reactions(for: selectedGroupKey, transaction: transaction)
            currentPageReactorsView.configure(for: currentPageReactions, stickerAttachmentByReactionId: reactionState.stickerAttachmentByReactionId, transaction: transaction)

            let previousPageReactions = reactions(for: previousPageGroupKey, transaction: transaction)
            previousPageReactorsView.configure(for: previousPageReactions, stickerAttachmentByReactionId: reactionState.stickerAttachmentByReactionId, transaction: transaction)

            let nextPageReactions = reactions(for: nextPageGroupKey, transaction: transaction)
            nextPageReactorsView.configure(for: nextPageReactions, stickerAttachmentByReactionId: reactionState.stickerAttachmentByReactionId, transaction: transaction)
        }

        updatePageConstraints()

        // Update selection on the counts view to reflect our new selected group key
        if let selectedGroupKey, let index = allGroupKeys.firstIndex(of: selectedGroupKey) {
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
        if !ignoreScrollingState, emojiPagingScrollView.contentOffset.x <= previousPageThreshold {
            emojiPagingScrollView.contentOffset.x += pageWidth

            // Scrolling forward
        } else if !ignoreScrollingState, emojiPagingScrollView.contentOffset.x >= nextPageThreshold {
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
            setSelectedGroupKey(previousPageGroupKey)

            // Scrolled right a page
        } else if offsetX >= nextPageThreshold {
            setSelectedGroupKey(nextPageGroupKey)

        }

        isScrollingChange = false
    }
}

// MARK: - EmojiReactorsTableViewDelegate

extension ReactionsDetailSheet: EmojiReactorsTableViewDelegate {
    func emojiReactorsTableView(_ tableView: EmojiReactorsTableView, didTapSticker stickerInfo: StickerInfo) {
        let packView = StickerPackViewController(stickerPackInfo: stickerInfo.packInfo)
        packView.present(from: self, animated: true)
    }
}

// MARK: - UIScrollViewDelegate

extension ReactionsDetailSheet: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        checkForPageChange()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        userStartedScrolling()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        userStoppedScrolling(waitingForDeceleration: decelerate)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        userStoppedScrolling()
    }
}
