//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

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

    // MARK: Initializer

    required public init(thread: TSThread) {
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
        Logger.verbose("")
        delegate?.didPresentSearchController?(searchController)
    }

    public func didDismissSearchController(_ searchController: UISearchController) {
        Logger.verbose("")
        delegate?.didDismissSearchController?(searchController)
    }
}

extension ConversationSearchController: UISearchResultsUpdating {
    var dbSearcher: FullTextSearcher {
        return FullTextSearcher.shared
    }

    public func updateSearchResults(for searchController: UISearchController) {
        Logger.verbose("searchBar.text: \( searchController.searchBar.text ?? "<blank>")")

        guard let rawSearchText = searchController.searchBar.text?.stripped else {
            self.resultsBar.updateResults(resultSet: nil)
            self.delegate?.conversationSearchController(self, didUpdateSearchResults: nil)
            return
        }
        let searchText = FullTextSearchFinder.normalize(text: rawSearchText)
        BenchManager.startEvent(title: "Conversation Search", eventId: searchText)

        guard searchText.count >= ConversationSearchController.kMinimumSearchTextLength else {
            self.resultsBar.updateResults(resultSet: nil)
            self.delegate?.conversationSearchController(self, didUpdateSearchResults: nil)
            self.lastSearchText = nil
            return
        }

        guard lastSearchText != searchText else {
            // Skip redundant search.
            return
        }
        lastSearchText = searchText

        var resultSet: ConversationScreenSearchResultSet?
        databaseStorage.asyncRead(block: { [weak self] transaction in
            guard let self = self else {
                return
            }
            resultSet = self.dbSearcher.searchWithinConversation(thread: self.thread, searchText: searchText, transaction: transaction)
        }, completion: { [weak self] in
            guard let self = self else {
                return
            }
            guard self.lastSearchText == searchText else {
                // Discard obsolete search results.
                return
            }
            self.resultsBar.updateResults(resultSet: resultSet)
            self.delegate?.conversationSearchController(self, didUpdateSearchResults: resultSet)
        })
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

        BenchEventStart(title: "Conversation Search Nav", eventId: "Conversation Search Nav: \(searchResult.messageId)")
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

        self.layoutMargins = .zero

        // When presenting or dismissing the keyboard, there may be a slight
        // gap between the keyboard and the bottom of the input bar during
        // the animation. Extend the background below the toolbar's bounds
        // by this much to mask that extra space.
        let backgroundExtension: CGFloat = 100

        if UIAccessibility.isReduceTransparencyEnabled {
            self.backgroundColor = Theme.toolbarBackgroundColor

            let extendedBackground = UIView()
            extendedBackground.backgroundColor = Theme.toolbarBackgroundColor
            addSubview(extendedBackground)
            extendedBackground.autoPinWidthToSuperview()
            extendedBackground.autoPinEdge(.top, to: .bottom, of: self)
            extendedBackground.autoSetDimension(.height, toSize: backgroundExtension)
        } else {
            let alpha: CGFloat = OWSNavigationBar.backgroundBlurMutingFactor
            backgroundColor = Theme.toolbarBackgroundColor.withAlphaComponent(alpha)

            let blurEffectView = UIVisualEffectView(effect: Theme.barBlurEffect)
            blurEffectView.layer.zPosition = -1
            addSubview(blurEffectView)
            blurEffectView.autoPinWidthToSuperview()
            blurEffectView.autoPinEdge(toSuperviewEdge: .top)
            blurEffectView.autoPinEdge(toSuperviewEdge: .bottom, withInset: -backgroundExtension)
        }

        addSubview(toolbar)
        toolbar.autoPinEdgesToSuperviewMargins()

        let leftExteriorChevronMargin: CGFloat
        let leftInteriorChevronMargin: CGFloat
        if CurrentAppContext().isRTL {
            leftExteriorChevronMargin = 8
            leftInteriorChevronMargin = 0
        } else {
            leftExteriorChevronMargin = 0
            leftInteriorChevronMargin = 8
        }

        let upChevron = #imageLiteral(resourceName: "ic_chevron_up").withRenderingMode(.alwaysTemplate)
        showLessRecentButton = UIBarButtonItem(image: upChevron, style: .plain, target: self, action: #selector(didTapShowLessRecent))
        showLessRecentButton.imageInsets = UIEdgeInsets(top: 2, left: leftExteriorChevronMargin, bottom: 2, right: leftInteriorChevronMargin)
        showLessRecentButton.tintColor = Theme.accentBlueColor

        let downChevron = #imageLiteral(resourceName: "ic_chevron_down").withRenderingMode(.alwaysTemplate)
        showMoreRecentButton = UIBarButtonItem(image: downChevron, style: .plain, target: self, action: #selector(didTapShowMoreRecent))
        showMoreRecentButton.imageInsets = UIEdgeInsets(top: 2, left: leftInteriorChevronMargin, bottom: 2, right: leftExteriorChevronMargin)
        showMoreRecentButton.tintColor = Theme.accentBlueColor

        let spacer1 = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let spacer2 = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        toolbar.items = [showLessRecentButton, showMoreRecentButton, spacer1, labelItem, spacer2]

        self.autoresizingMask = .flexibleHeight
        self.translatesAutoresizingMaskIntoConstraints = false

        updateBarItems()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
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

    @objc
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

    // MARK: 

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
        guard let resultSet = resultSet else {
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

            guard let currentIndex = currentIndex else {
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
