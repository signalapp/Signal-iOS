// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SignalUtilitiesKit

public class ConversationSearchController: NSObject {
    public static let minimumSearchTextLength: UInt = 2

    private let threadId: String
    public weak var delegate: ConversationSearchControllerDelegate?
    public let uiSearchController: UISearchController = UISearchController(searchResultsController: nil)
    public let resultsBar: SearchResultsBar = SearchResultsBar()
    
    private var lastSearchText: String?

    // MARK: Initializer

    public init(threadId: String) {
        self.threadId = threadId
        
        super.init()
        
        self.resultsBar.resultsBarDelegate = self
        self.uiSearchController.delegate = self
        self.uiSearchController.searchResultsUpdater = self

        self.uiSearchController.hidesNavigationBarDuringPresentation = false
        self.uiSearchController.searchBar.inputAccessoryView = resultsBar
    }
}

// MARK: - UISearchControllerDelegate

extension ConversationSearchController: UISearchControllerDelegate {
    public func didPresentSearchController(_ searchController: UISearchController) {
        delegate?.didPresentSearchController?(searchController)
    }

    public func didDismissSearchController(_ searchController: UISearchController) {
        delegate?.didDismissSearchController?(searchController)
    }
}

// MARK: - UISearchResultsUpdating

extension ConversationSearchController: UISearchResultsUpdating {
    public func updateSearchResults(for searchController: UISearchController) {
        Logger.verbose("searchBar.text: \( searchController.searchBar.text ?? "<blank>")")

        guard
            let searchText: String = searchController.searchBar.text?.stripped,
            searchText.count >= ConversationSearchController.minimumSearchTextLength
        else {
            self.resultsBar.updateResults(results: nil)
            self.delegate?.conversationSearchController(self, didUpdateSearchResults: nil, searchText: nil)
            return
        }
        
        let threadId: String = self.threadId
        let results: [Int64] = Storage.shared.read { db -> [Int64] in
            try Interaction.idsForTermWithin(
                threadId: threadId,
                pattern: try SessionThreadViewModel.pattern(db, searchTerm: searchText)
            )
            .fetchAll(db)
        }
        .defaulting(to: [])
        
        self.resultsBar.updateResults(results: results)
        self.delegate?.conversationSearchController(self, didUpdateSearchResults: results, searchText: searchText)
    }
}

// MARK: - SearchResultsBarDelegate

extension ConversationSearchController: SearchResultsBarDelegate {
    func searchResultsBar(
        _ searchResultsBar: SearchResultsBar,
        setCurrentIndex currentIndex: Int,
        results: [Int64]
    ) {
        guard let interactionId: Int64 = results[safe: currentIndex] else { return }
        
        self.delegate?.conversationSearchController(self, didSelectInteractionId: interactionId)
    }
}

protocol SearchResultsBarDelegate: AnyObject {
    func searchResultsBar(
        _ searchResultsBar: SearchResultsBar,
        setCurrentIndex currentIndex: Int,
        results: [Int64]
    )
}

public final class SearchResultsBar: UIView {
    private var results: [Int64]?
    var currentIndex: Int?
    weak var resultsBarDelegate: SearchResultsBarDelegate?
    
    public override var intrinsicContentSize: CGSize { CGSize.zero }
    
    private lazy var label: UILabel = {
        let result = UILabel()
        result.font = .boldSystemFont(ofSize: Values.smallFontSize)
        result.textColor = Colors.text
        return result
    }()
    
    private lazy var upButton: UIButton = {
        let icon = #imageLiteral(resourceName: "ic_chevron_up").withRenderingMode(.alwaysTemplate)
        let result = UIButton()
        result.setImage(icon, for: UIControl.State.normal)
        result.tintColor = Colors.accent
        result.addTarget(self, action: #selector(handleUpButtonTapped), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    private lazy var downButton: UIButton = {
        let icon = #imageLiteral(resourceName: "ic_chevron_down").withRenderingMode(.alwaysTemplate)
        let result = UIButton()
        result.setImage(icon, for: UIControl.State.normal)
        result.tintColor = Colors.accent
        result.addTarget(self, action: #selector(handleDownButtonTapped), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let result = UIActivityIndicatorView(style: .medium)
        result.tintColor = Colors.text
        result.alpha = 0.5
        result.hidesWhenStopped = true
        return result
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpViewHierarchy()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpViewHierarchy()
    }
    
    private func setUpViewHierarchy() {
        autoresizingMask = .flexibleHeight
        
        // Background & blur
        let backgroundView = UIView()
        backgroundView.backgroundColor = isLightMode ? .white : .black
        backgroundView.alpha = Values.lowOpacity
        addSubview(backgroundView)
        backgroundView.pin(to: self)
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        addSubview(blurView)
        blurView.pin(to: self)
        
        // Separator
        let separator = UIView()
        separator.backgroundColor = Colors.text.withAlphaComponent(0.2)
        separator.set(.height, to: 1 / UIScreen.main.scale)
        addSubview(separator)
        separator.pin([ UIView.HorizontalEdge.leading, UIView.VerticalEdge.top, UIView.HorizontalEdge.trailing ], to: self)
        
        // Spacers
        let spacer1 = UIView.hStretchingSpacer()
        let spacer2 = UIView.hStretchingSpacer()
        
        // Button containers
        let upButtonContainer = UIView(wrapping: upButton, withInsets: UIEdgeInsets(top: 2, left: 0, bottom: 0, right: 0))
        let downButtonContainer = UIView(wrapping: downButton, withInsets: UIEdgeInsets(top: 0, left: 0, bottom: 2, right: 0))
        
        // Main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ upButtonContainer, downButtonContainer, spacer1, label, spacer2 ])
        mainStackView.axis = .horizontal
        mainStackView.spacing = Values.mediumSpacing
        mainStackView.isLayoutMarginsRelativeArrangement = true
        mainStackView.layoutMargins = UIEdgeInsets(top: Values.smallSpacing, leading: Values.largeSpacing, bottom: Values.smallSpacing, trailing: Values.largeSpacing)
        addSubview(mainStackView)
        
        mainStackView.pin(.top, to: .bottom, of: separator)
        mainStackView.pin([ UIView.HorizontalEdge.leading, UIView.HorizontalEdge.trailing ], to: self)
        mainStackView.pin(.bottom, to: .bottom, of: self, withInset: -2)
        
        addSubview(loadingIndicator)
        loadingIndicator.pin(.left, to: .right, of: label, withInset: 10)
        loadingIndicator.centerYAnchor.constraint(equalTo: label.centerYAnchor).isActive = true
        
        // Remaining constraints
        label.center(.horizontal, in: self)
    }
    
    // MARK: - Functions
    
    @objc
    public func handleUpButtonTapped() {
        guard let results: [Int64] = results else { return }
        guard let currentIndex: Int = currentIndex else { return }
        guard currentIndex + 1 < results.count else { return }

        let newIndex = currentIndex + 1
        self.currentIndex = newIndex
        updateBarItems()
        resultsBarDelegate?.searchResultsBar(self, setCurrentIndex: newIndex, results: results)
    }

    @objc
    public func handleDownButtonTapped() {
        Logger.debug("")
        guard let results: [Int64] = results else { return }
        guard let currentIndex: Int = currentIndex, currentIndex > 0 else { return }

        let newIndex = currentIndex - 1
        self.currentIndex = newIndex
        updateBarItems()
        resultsBarDelegate?.searchResultsBar(self, setCurrentIndex: newIndex, results: results)
    }

    func updateResults(results: [Int64]?) {
        currentIndex = {
            guard let results: [Int64] = results, !results.isEmpty else { return nil }
            
            if let currentIndex: Int = currentIndex {
                return max(0, min(currentIndex, results.count - 1))
            }
            
            return 0
        }()

        self.results = results

        updateBarItems()
        
        if let currentIndex = currentIndex, let results = results {
            resultsBarDelegate?.searchResultsBar(self, setCurrentIndex: currentIndex, results: results)
        }
    }

    func updateBarItems() {
        guard let results: [Int64] = results else {
            label.text = ""
            downButton.isEnabled = false
            upButton.isEnabled = false
            return
        }

        switch results.count {
            case 0:
                // Keyboard toolbar label when no messages match the search string
                label.text = "CONVERSATION_SEARCH_NO_RESULTS".localized()
            
            case 1:
                // Keyboard toolbar label when exactly 1 message matches the search string
                label.text = "CONVERSATION_SEARCH_ONE_RESULT".localized()
        
            default:
                // Keyboard toolbar label when more than 1 message matches the search string
                //
                // Embeds {{number/position of the 'currently viewed' result}} and
                // the {{total number of results}}
                let format = "CONVERSATION_SEARCH_RESULTS_FORMAT".localized()

                guard let currentIndex: Int = currentIndex else { return }
                
                label.text = String(format: format, currentIndex + 1, results.count)
            }

        if let currentIndex: Int = currentIndex {
            downButton.isEnabled = currentIndex > 0
            upButton.isEnabled = (currentIndex + 1 < results.count)
        }
        else {
            downButton.isEnabled = false
            upButton.isEnabled = false
        }
    }
    
    public func startLoading() {
        loadingIndicator.startAnimating()
    }
    
    public func stopLoading() {
        loadingIndicator.stopAnimating()
    }
}

// MARK: - ConversationSearchControllerDelegate

public protocol ConversationSearchControllerDelegate: UISearchControllerDelegate {
    func conversationSearchController(_ conversationSearchController: ConversationSearchController, didUpdateSearchResults results: [Int64]?, searchText: String?)
    func conversationSearchController(_ conversationSearchController: ConversationSearchController, didSelectInteractionId: Int64)
}
