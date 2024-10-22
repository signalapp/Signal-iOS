//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

extension ChatListViewController: OWSNavigationChildController {
    func focusSearch() {
        AssertIsOnMainThread()

        Logger.info("")

        // If we have presented a conversation list (the archive) search there instead.
        if let presentedChatListViewController {
            presentedChatListViewController.focusSearch()
            return
        }

        searchBar.becomeFirstResponder()
    }

    func cancelSearch() {
        guard viewState.searchController.isActive else { return }
        // Deactivating the search controller has a different animation if it's
        // scrolled to the top or not. It gets confused whether it's at the top
        // or not and has a buggy animation when this is activated while
        // scrolling, so force an offset to ensure it always uses the
        // not-at-the-top animation.
        tableView.contentOffset.y += 1
        viewState.searchController.isActive = false
    }

    private var searchText: String { (searchBar.text ?? "").stripped }
    var isSearching: Bool { !searchText.isEmpty }

    func scrollSearchBarToTop(animated: Bool) {
        let topInset = view.safeAreaInsets.top
        tableView.setContentOffset(CGPoint(x: 0, y: -topInset), animated: animated)
    }
}

extension ChatListViewController: UISearchResultsUpdating {
    public func updateSearchResults(for searchController: UISearchController) {
        AssertIsOnMainThread()
        guard isSearching else { return }
        viewState.searchResultsController.searchText = searchText
    }
}

extension ChatListViewController: ConversationSearchViewDelegate {

    public func conversationSearchViewWillBeginDragging() {
        AssertIsOnMainThread()
        searchBar.resignFirstResponder()
        owsAssertDebug(!searchBar.isFirstResponder)
    }

    public func conversationSearchDidSelectRow() {
        AssertIsOnMainThread()
        viewState.shouldFocusSearchOnAppear = searchBar.resignFirstResponder()
    }
}
