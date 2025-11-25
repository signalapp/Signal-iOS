//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Foundation
public import UIKit

public import SignalServiceKit
public import SignalUI

public protocol ConversationSearchControllerDelegate: UISearchControllerDelegate {

    func conversationSearchController(_ conversationSearchController: ConversationSearchController,
                                      didUpdateSearchResults resultSet: ConversationScreenSearchResultSet?)

    func conversationSearchController(_ conversationSearchController: ConversationSearchController,
                                      didSelectMessageId: String)
}

// MARK: -

public class ConversationSearchController: NSObject {

    public static let kMinimumSearchTextLength: UInt = 2

    public let uiSearchController =  UISearchController(searchResultsController: nil)

    public weak var delegate: ConversationSearchControllerDelegate?

    let thread: TSThread

    public let resultsBar: SearchResultsBar = SearchResultsBar(frame: .zero)

    private var lastSearchText: String?
    private var currentSearchTask: Task<Void, Never>?

    // MARK: Initializer

    public init(thread: TSThread) {
        self.thread = thread
        super.init()

        resultsBar.resultsBarDelegate = self
        uiSearchController.delegate = self
        uiSearchController.searchResultsUpdater = self

        uiSearchController.hidesNavigationBarDuringPresentation = true
        uiSearchController.obscuresBackgroundDuringPresentation = false

        applyTheme()
    }

    var searchBar: UISearchBar {
        return uiSearchController.searchBar
    }

    func applyTheme() {
        OWSSearchBar.applyTheme(to: uiSearchController.searchBar)
    }
}

extension ConversationSearchController: UISearchControllerDelegate {
    public func didPresentSearchController(_ searchController: UISearchController) {
        delegate?.didPresentSearchController?(searchController)
    }

    public func didDismissSearchController(_ searchController: UISearchController) {
        delegate?.didDismissSearchController?(searchController)
    }
}

extension ConversationSearchController: UISearchResultsUpdating {
    var dbSearcher: FullTextSearcher {
        return FullTextSearcher.shared
    }

    public func updateSearchResults(for searchController: UISearchController) {
        let searchText = FullTextSearchIndexer.normalizeText((searchController.searchBar.text ?? "").stripped)

        guard searchText.count >= ConversationSearchController.kMinimumSearchTextLength else {
            self.resultsBar.updateResults(resultSet: nil)
            self.delegate?.conversationSearchController(self, didUpdateSearchResults: nil)
            self.lastSearchText = nil
            self.currentSearchTask?.cancel()
            return
        }

        guard lastSearchText != searchText else {
            // Skip redundant search.
            return
        }
        lastSearchText = searchText

        self.currentSearchTask?.cancel()
        self.currentSearchTask = Task {
            let resultSet: ConversationScreenSearchResultSet
            do throws(CancellationError) {
                resultSet = try await performSearch(
                    searchText: searchText,
                    threadUniqueId: thread.uniqueId,
                    isGroupThread: thread is TSGroupThread,
                )
                if Task.isCancelled {
                    throw CancellationError()
                }
            } catch {
                // Discard obsolete search results.
                return
            }
            self.resultsBar.updateResults(resultSet: resultSet)
            self.delegate?.conversationSearchController(self, didUpdateSearchResults: resultSet)
        }
    }

    private nonisolated func performSearch(
        searchText: String,
        threadUniqueId: String,
        isGroupThread: Bool,
    ) async throws(CancellationError) -> ConversationScreenSearchResultSet {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        return try databaseStorage.read { tx throws(CancellationError) in
            return try dbSearcher.searchWithinConversation(
                threadUniqueId: threadUniqueId,
                isGroupThread: isGroupThread,
                searchText: searchText,
                transaction: tx,
            )
        }
    }
}

extension ConversationSearchController: SearchResultsBarDelegate {
    func searchResultsBar(_ searchResultsBar: SearchResultsBar,
                          setCurrentIndex currentIndex: Int,
                          resultSet: ConversationScreenSearchResultSet) {
        guard let searchResult = resultSet.messages[safe: currentIndex] else {
            owsFailDebug("messageId was unexpectedly nil")
            return
        }

        self.delegate?.conversationSearchController(self, didSelectMessageId: searchResult.messageId)
    }
}

protocol SearchResultsBarDelegate: AnyObject {
    func searchResultsBar(_ searchResultsBar: SearchResultsBar,
                          setCurrentIndex currentIndex: Int,
                          resultSet: ConversationScreenSearchResultSet)
}

public class SearchResultsBar: UIView {

    weak var resultsBarDelegate: SearchResultsBarDelegate?

    var showLessRecentButton: UIBarButtonItem!
    var showMoreRecentButton: UIBarButtonItem!

    let labelItem = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)
    let toolbar = UIToolbar.clear()

    var resultSet: ConversationScreenSearchResultSet?

    override init(frame: CGRect) {
        super.init(frame: frame)

        layoutMargins = .zero

        let isLegacyLayout: Bool = if #unavailable(iOS 26) { true } else { false }

        if isLegacyLayout {
            if UIAccessibility.isReduceTransparencyEnabled {
                backgroundColor = Theme.toolbarBackgroundColor

                let extendedBackground = UIView()
                extendedBackground.backgroundColor = Theme.toolbarBackgroundColor
                addSubview(extendedBackground)
                extendedBackground.autoPinEdgesToSuperviewEdges()
            } else {
                let alpha: CGFloat = OWSNavigationBar.backgroundBlurMutingFactor
                backgroundColor = Theme.toolbarBackgroundColor.withAlphaComponent(alpha)

                let blurEffectView = UIVisualEffectView(effect: Theme.barBlurEffect)
                blurEffectView.layer.zPosition = -1
                addSubview(blurEffectView)
                blurEffectView.autoPinEdgesToSuperviewEdges()
            }
        }

        addSubview(toolbar)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        let vMargin: CGFloat = isLegacyLayout ? 0 : 6
        let hMargin: CGFloat = 0
        addConstraints([
            toolbar.topAnchor.constraint(equalTo: topAnchor, constant: vMargin),
            toolbar.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: hMargin),
            toolbar.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -hMargin),
            toolbar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vMargin),
        ])

        let leftExteriorChevronMargin: CGFloat
        let leftInteriorChevronMargin: CGFloat
        if CurrentAppContext().isRTL {
            leftExteriorChevronMargin = 8
            leftInteriorChevronMargin = 0
        } else {
            leftExteriorChevronMargin = 0
            leftInteriorChevronMargin = 8
        }

        showLessRecentButton = UIBarButtonItem(
            image: Theme.iconImage(.chevronUp),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapShowLessRecent()
            }
        )
        showLessRecentButton.imageInsets = UIEdgeInsets(top: 2, left: leftExteriorChevronMargin, bottom: 2, right: leftInteriorChevronMargin)

        showMoreRecentButton = UIBarButtonItem(
            image: Theme.iconImage(.chevronDown),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapShowMoreRecent()
            }
        )
        showMoreRecentButton.imageInsets = UIEdgeInsets(top: 2, left: leftInteriorChevronMargin, bottom: 2, right: leftExteriorChevronMargin)

        if isLegacyLayout {
            showLessRecentButton.tintColor = .Signal.accent
            showMoreRecentButton.tintColor = .Signal.accent
        }

        toolbar.items = [showLessRecentButton, showMoreRecentButton, .flexibleSpace(), labelItem, .flexibleSpace()]

        updateBarItems()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func didTapShowLessRecent() {
        Logger.debug("")
        guard let resultSet = resultSet else {
            owsFailDebug("resultSet was unexpectedly nil")
            return
        }

        guard let currentIndex = currentIndex else {
            owsFailDebug("currentIndex was unexpectedly nil")
            return
        }

        guard currentIndex + 1 < resultSet.messages.count else {
            owsFailDebug("showLessRecent button should be disabled")
            return
        }

        let newIndex = currentIndex + 1
        self.currentIndex = newIndex
        updateBarItems()
        resultsBarDelegate?.searchResultsBar(self, setCurrentIndex: newIndex, resultSet: resultSet)
    }

    private func didTapShowMoreRecent() {
        Logger.debug("")
        guard let resultSet = resultSet else {
            owsFailDebug("resultSet was unexpectedly nil")
            return
        }

        guard let currentIndex = currentIndex else {
            owsFailDebug("currentIndex was unexpectedly nil")
            return
        }

        guard currentIndex > 0 else {
            owsFailDebug("showMoreRecent button should be disabled")
            return
        }

        let newIndex = currentIndex - 1
        self.currentIndex = newIndex
        updateBarItems()
        resultsBarDelegate?.searchResultsBar(self, setCurrentIndex: newIndex, resultSet: resultSet)
    }

    var currentIndex: Int?

    func updateResults(resultSet: ConversationScreenSearchResultSet?) {
        if let resultSet = resultSet {
            if resultSet.messages.count > 0 {
                currentIndex = min(currentIndex ?? 0, resultSet.messages.count - 1)
            } else {
                currentIndex = nil
            }
        } else {
            currentIndex = nil
        }

        self.resultSet = resultSet

        updateBarItems()
        if let currentIndex = currentIndex, let resultSet = resultSet {
            resultsBarDelegate?.searchResultsBar(self, setCurrentIndex: currentIndex, resultSet: resultSet)
        }
    }

    func updateBarItems() {
        defer {
            if #available(iOS 26, *) {
                if labelItem.title.isEmptyOrNil {
                    toolbar.items = [ showLessRecentButton, showMoreRecentButton, .flexibleSpace() ]
                } else {
                    toolbar.items = [ showLessRecentButton, showMoreRecentButton, .flexibleSpace(), labelItem, .flexibleSpace() ]
                }
            }
        }

        guard let resultSet else {
            labelItem.title = nil
            showMoreRecentButton.isEnabled = false
            showLessRecentButton.isEnabled = false
            return
        }

        if resultSet.messages.count == 0 {
            labelItem.title = OWSLocalizedString("CONVERSATION_SEARCH_NO_RESULTS", comment: "keyboard toolbar label when no messages match the search string")
        } else {
            let format = OWSLocalizedString("CONVERSATION_SEARCH_RESULTS_%d_%d", tableName: "PluralAware",
                                           comment: "keyboard toolbar label when more than one or more messages matches the search string. Embeds {{number/position of the 'currently viewed' result}} and the {{total number of results}}")

            guard let currentIndex else {
                owsFailDebug("currentIndex was unexpectedly nil")
                return
            }
            labelItem.title = String.localizedStringWithFormat(format, currentIndex + 1, resultSet.messages.count)
        }

        if let currentIndex = currentIndex {
            showMoreRecentButton.isEnabled = currentIndex > 0
            showLessRecentButton.isEnabled = currentIndex + 1 < resultSet.messages.count
        } else {
            showMoreRecentButton.isEnabled = false
            showLessRecentButton.isEnabled = false
        }
    }
}

extension SearchResultsBar: ConversationBottomBar {
    var shouldAttachToKeyboardLayoutGuide: Bool { true }
}
