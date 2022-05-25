// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionMessagingKit

public enum SwipeState {
    case began
    case ended
    case cancelled
}

public class MessageCell: UITableViewCell {
    weak var delegate: MessageCellDelegate?
    var viewModel: MessageCell.ViewModel?

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
    
    func update(with cellViewModel: MessageCell.ViewModel, mediaCache: NSCache<NSString, AnyObject>, playbackInfo: ConversationViewModel.PlaybackInfo?, lastSearchText: String?) {
        preconditionFailure("Must be overridden by subclasses.")
    }
    
    /// This is a cut-down version of the 'update' function which doesn't re-create the UI (it should be used for dynamically-updating content
    /// like playing inline audio/video)
    func dynamicUpdate(with cellViewModel: MessageCell.ViewModel, playbackInfo: ConversationViewModel.PlaybackInfo?) {
        preconditionFailure("Must be overridden by subclasses.")
    }

    // MARK: - Convenience
    
    static func cellType(for viewModel: MessageCell.ViewModel) -> MessageCell.Type {
        guard viewModel.cellType != .typingIndicator else { return TypingIndicatorCell.self }
        
        switch viewModel.variant {
            case .standardOutgoing, .standardIncoming, .standardIncomingDeleted:
                return VisibleMessageCell.self
                
            case .infoClosedGroupCreated, .infoClosedGroupUpdated, .infoClosedGroupCurrentUserLeft,
                .infoDisappearingMessagesUpdate, .infoScreenshotNotification, .infoMediaSavedNotification,
                .infoMessageRequestAccepted:
                return InfoMessageCell.self
        }
    }
}

// MARK: - MessageCellDelegate

protocol MessageCellDelegate: AnyObject {
    func handleItemLongPressed(_ cellViewModel: MessageCell.ViewModel)
    func handleItemTapped(_ cellViewModel: MessageCell.ViewModel, gestureRecognizer: UITapGestureRecognizer)
    func handleItemDoubleTapped(_ cellViewModel: MessageCell.ViewModel)
    func handleItemSwiped(_ cellViewModel: MessageCell.ViewModel, state: SwipeState)
    func openUrl(_ urlString: String)
    func handleReplyButtonTapped(for cellViewModel: MessageCell.ViewModel)
    func showUserDetails(for profile: Profile)
}
