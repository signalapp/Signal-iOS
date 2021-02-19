//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol ConversationSearchControllerDelegate: UISearchControllerDelegate {

    @objc
    func conversationSearchController(_ conversationSearchController: ConversationSearchController,
                                      didUpdateSearchResults resultSet: ConversationScreenSearchResultSet?)

    @objc
    func conversationSearchController(_ conversationSearchController: ConversationSearchController,
                                      didSelectMessageId: String)
}

@objc
public class ConversationSearchController : NSObject {

    @objc
    public static let kMinimumSearchTextLength: UInt = 2

    @objc
    public let uiSearchController =  UISearchController(searchResultsController: nil)

    @objc
    public weak var delegate: ConversationSearchControllerDelegate?

    let thread: TSThread

    @objc
    public let resultsBar: SearchResultsBar = SearchResultsBar()

    // MARK: Initializer

    @objc
    required public init(thread: TSThread) {
        self.thread = thread
        super.init()

        resultsBar.resultsBarDelegate = self
        uiSearchController.delegate = self
        uiSearchController.searchResultsUpdater = self

        uiSearchController.hidesNavigationBarDuringPresentation = false
        if #available(iOS 13, *) {
            // Do nothing
        } else {
            uiSearchController.dimsBackgroundDuringPresentation = false
        }
        uiSearchController.searchBar.inputAccessoryView = resultsBar
    }

    // MARK: Dependencies

    var dbReadConnection: YapDatabaseConnection {
        return OWSPrimaryStorage.shared().dbReadConnection
    }
}

extension ConversationSearchController : UISearchControllerDelegate {
    
    public func didPresentSearchController(_ searchController: UISearchController) {
        Logger.verbose("")
        delegate?.didPresentSearchController?(searchController)
    }

    public func didDismissSearchController(_ searchController: UISearchController) {
        Logger.verbose("")
        delegate?.didDismissSearchController?(searchController)
    }
}

extension ConversationSearchController : UISearchResultsUpdating {
    
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

        guard searchText.count >= ConversationSearchController.kMinimumSearchTextLength else {
            self.resultsBar.updateResults(resultSet: nil)
            self.delegate?.conversationSearchController(self, didUpdateSearchResults: nil)
            return
        }

        var resultSet: ConversationScreenSearchResultSet?
        self.dbReadConnection.asyncRead({ [weak self] transaction in
            guard let self = self else {
                return
            }
            resultSet = self.dbSearcher.searchWithinConversation(thread: self.thread, searchText: searchText, transaction: transaction)
        }, completionBlock: { [weak self] in
            guard let self = self else {
                return
            }
            self.resultsBar.updateResults(resultSet: resultSet)
            self.delegate?.conversationSearchController(self, didUpdateSearchResults: resultSet)
        })
    }
}

extension ConversationSearchController : SearchResultsBarDelegate {
    
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

protocol SearchResultsBarDelegate : AnyObject {
    
    func searchResultsBar(_ searchResultsBar: SearchResultsBar,
                          setCurrentIndex currentIndex: Int,
                          resultSet: ConversationScreenSearchResultSet)
}

public final class SearchResultsBar : UIView {
    private var resultSet: ConversationScreenSearchResultSet?
    var currentIndex: Int?
    weak var resultsBarDelegate: SearchResultsBarDelegate?
    
    public override var intrinsicContentSize: CGSize { CGSize.zero }
    
    private lazy var label: UILabel = {
        let result = UILabel()
        result.text = "Test"
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
        // Remaining constraints
        label.center(.horizontal, in: self)
    }
    
    @objc
    public func handleUpButtonTapped() {
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
    public func handleDownButtonTapped() {
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
            label.text = ""
            downButton.isEnabled = false
            upButton.isEnabled = false
            return
        }

        switch resultSet.messages.count {
        case 0:
            label.text = NSLocalizedString("CONVERSATION_SEARCH_NO_RESULTS", comment: "keyboard toolbar label when no messages match the search string")
        case 1:
            label.text = NSLocalizedString("CONVERSATION_SEARCH_ONE_RESULT", comment: "keyboard toolbar label when exactly 1 message matches the search string")
        default:
            let format = NSLocalizedString("CONVERSATION_SEARCH_RESULTS_FORMAT",
                                           comment: "keyboard toolbar label when more than 1 message matches the search string. Embeds {{number/position of the 'currently viewed' result}} and the {{total number of results}}")

            guard let currentIndex = currentIndex else {
                owsFailDebug("currentIndex was unexpectedly nil")
                return
            }
            label.text = String(format: format, currentIndex + 1, resultSet.messages.count)
        }

        if let currentIndex = currentIndex {
            downButton.isEnabled = currentIndex > 0
            upButton.isEnabled = currentIndex + 1 < resultSet.messages.count
        } else {
            downButton.isEnabled = false
            upButton.isEnabled = false
        }
    }
}
