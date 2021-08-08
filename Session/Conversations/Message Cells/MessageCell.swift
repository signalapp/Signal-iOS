import UIKit

public enum SwipeState {
    case began
    case ended
    case cancelled
}

class MessageCell : UITableViewCell {
    weak var delegate: MessageCellDelegate?
    var viewItem: ConversationViewItem? { didSet { update() } }
    
    // MARK: Settings
    class var identifier: String { preconditionFailure("Must be overridden by subclasses.") }
    
    // MARK: Lifecycle
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setUpViewHierarchy()
        setUpGestureRecognizers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpViewHierarchy()
        setUpGestureRecognizers()
    }

    func setUpViewHierarchy() {
        backgroundColor = .clear
        let selectedBackgroundView = UIView()
        selectedBackgroundView.backgroundColor = .clear
        self.selectedBackgroundView = selectedBackgroundView
    }
    
    func setUpGestureRecognizers() {
        // To be overridden by subclasses
    }
    
    // MARK: Updating
    func update() {
        preconditionFailure("Must be overridden by subclasses.")
    }
    
    // MARK: Convenience
    static func getCellType(for viewItem: ConversationViewItem) -> MessageCell.Type {
        switch viewItem.interaction {
        case is TSIncomingMessage: fallthrough
        case is TSOutgoingMessage: return VisibleMessageCell.self
        case is TSInfoMessage: return InfoMessageCell.self
        case is TypingIndicatorInteraction: return TypingIndicatorCell.self
        default: preconditionFailure()
        }
    }
}

protocol MessageCellDelegate : AnyObject {
    var lastSearchedText: String? { get }
    
    func getMediaCache() -> NSCache<NSString, AnyObject>
    func handleViewItemLongPressed(_ viewItem: ConversationViewItem)
    func handleViewItemTapped(_ viewItem: ConversationViewItem, gestureRecognizer: UITapGestureRecognizer)
    func handleViewItemDoubleTapped(_ viewItem: ConversationViewItem)
    func handleViewItemSwiped(_ viewItem: ConversationViewItem, state: SwipeState)
    func showFullText(_ viewItem: ConversationViewItem)
    func openURL(_ url: URL)
    func handleReplyButtonTapped(for viewItem: ConversationViewItem)
    func showUserDetails(for sessionID: String)
}
