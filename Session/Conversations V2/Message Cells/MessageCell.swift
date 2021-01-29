import UIKit

class MessageCell : UITableViewCell {
    var delegate: MessageCellDelegate?
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
        case is TypingIndicatorInteraction: return TypingIndicatorCellV2.self
        default: preconditionFailure()
        }
    }
}

protocol MessageCellDelegate {
    
    func getMediaCache() -> NSCache<NSString, AnyObject>
    func handleViewItemLongPressed(_ viewItem: ConversationViewItem)
    func handleViewItemTapped(_ viewItem: ConversationViewItem, gestureRecognizer: UITapGestureRecognizer)
    func handleViewItemDoubleTapped(_ viewItem: ConversationViewItem)
    func showFullText(_ viewItem: ConversationViewItem)
}
