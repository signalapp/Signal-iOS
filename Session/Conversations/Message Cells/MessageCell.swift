// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionMessagingKit

public enum SwipeState {
    case began
    case ended
    case cancelled
}

class MessageCell: UITableViewCell {
    weak var delegate: MessageCellDelegate?
    var item: ConversationViewModel.Item?

    // MARK: - Lifecycle
    
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

    // MARK: - Updating
    
    func update(with item: ConversationViewModel.Item, mediaCache: NSCache<NSString, AnyObject>, playbackInfo: ConversationViewModel.PlaybackInfo?, lastSearchText: String?) {
        preconditionFailure("Must be overridden by subclasses.")
    }
    
    /// This is a cut-down version of the 'update' function which doesn't re-create the UI (it should be used for dynamically-updating content
    /// like playing inline audio/video)
    func dynamicUpdate(with item: ConversationViewModel.Item, playbackInfo: ConversationViewModel.PlaybackInfo?) {
        preconditionFailure("Must be overridden by subclasses.")
    }

    // MARK: - Convenience
    
    static func cellType(for item: ConversationViewModel.Item) -> MessageCell.Type {
        guard item.cellType != .typingIndicator else { return TypingIndicatorCell.self }
        
        switch item.interactionVariant {
            case .standardOutgoing, .standardIncoming, .standardIncomingDeleted:
                return VisibleMessageCell.self
                
            case .infoClosedGroupCreated, .infoClosedGroupUpdated, .infoClosedGroupCurrentUserLeft,
                .infoDisappearingMessagesUpdate, .infoScreenshotNotification, .infoMediaSavedNotification,
                .infoMessageRequestAccepted:
                return InfoMessageCell.self
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
