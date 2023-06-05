//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

extension ChatListViewController: OWSNavigationChildController {

    private var shouldShowSearchBarCancelButton: Bool {
        searchBar.isFirstResponder || !(searchBar.text as String?).isEmptyOrNil
    }

    public var prefersNavigationBarHidden: Bool {
        shouldShowSearchBarCancelButton
    }

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

    func dismissSearchKeyboard() {
        AssertIsOnMainThread()

        searchBar.resignFirstResponder()
        owsAssertDebug(!searchBar.isFirstResponder)
    }

    func ensureSearchBarCancelButton() {
        let shouldShowCancelButton = shouldShowSearchBarCancelButton
        let shouldHideNavigationBar = shouldShowCancelButton

        if searchBar.showsCancelButton != shouldShowCancelButton {
            searchBar.setShowsCancelButton(shouldShowCancelButton, animated: isViewVisible)
        }

        if let owsNavigationController, shouldHideNavigationBar != owsNavigationController.isNavigationBarHidden {
            owsNavigationController.updateNavbarAppearance(animated: isViewVisible)
        }
    }

    func updateSearchResultsVisibility() {
        AssertIsOnMainThread()

        let searchText = (searchBar.text ?? "").stripped
        searchResultsController.searchText = searchText
        let isSearching = !searchText.isEmpty
        searchResultsController.view.isHidden = !isSearching

        if isSearching {
            scrollSearchBarToTop()
            tableView.isScrollEnabled = false
        } else {
            tableView.isScrollEnabled = true
        }
    }

    func scrollSearchBarToTop(animated: Bool = false) {
        let topInset = view.safeAreaInsets.top
        tableView.setContentOffset(CGPoint(x: 0, y: -topInset), animated: animated)
    }
}

extension ChatListViewController: UISearchBarDelegate {

    public func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        scrollSearchBarToTop()
        updateSearchResultsVisibility()
        ensureSearchBarCancelButton()
    }

    public func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        updateSearchResultsVisibility()
        ensureSearchBarCancelButton()
    }

    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        updateSearchResultsVisibility()
        ensureSearchBarCancelButton()
    }

    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        updateSearchResultsVisibility()
    }

    public func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = nil
        dismissSearchKeyboard()
        updateSearchResultsVisibility()
        ensureSearchBarCancelButton()
    }
}

extension ChatListViewController: ConversationSearchViewDelegate {

    public func conversationSearchViewWillBeginDragging() {
        dismissSearchKeyboard()
    }
}
