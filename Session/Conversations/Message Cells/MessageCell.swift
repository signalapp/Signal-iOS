// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionMessagingKit

public enum SwipeState {
    case began
    case ended
    case cancelled
}

public class MessageCell: UITableViewCell {
    var viewModel: MessageViewModel?
    weak var delegate: MessageCellDelegate?
    open var contextSnapshotView: UIView? { return nil }

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
        themeBackgroundColor = .clear
        
        let selectedBackgroundView = UIView()
        selectedBackgroundView.themeBackgroundColor = .clear
        self.selectedBackgroundView = selectedBackgroundView
    }

    func setUpGestureRecognizers() {
        // To be overridden by subclasses
    }

    // MARK: - Updating
    
    func update(
        with cellViewModel: MessageViewModel,
        mediaCache: NSCache<NSString, AnyObject>,
        playbackInfo: ConversationViewModel.PlaybackInfo?,
        showExpandedReactions: Bool,
        lastSearchText: String?
    ) {
        preconditionFailure("Must be overridden by subclasses.")
    }
    
    /// This is a cut-down version of the 'update' function which doesn't re-create the UI (it should be used for dynamically-updating content
    /// like playing inline audio/video)
    func dynamicUpdate(with cellViewModel: MessageViewModel, playbackInfo: ConversationViewModel.PlaybackInfo?) {
        preconditionFailure("Must be overridden by subclasses.")
    }

    // MARK: - Convenience
    
    static func cellType(for viewModel: MessageViewModel) -> MessageCell.Type {
        guard viewModel.cellType != .typingIndicator else { return TypingIndicatorCell.self }
        guard viewModel.cellType != .dateHeader else { return DateHeaderCell.self }
        
        switch viewModel.variant {
            case .standardOutgoing, .standardIncoming, .standardIncomingDeleted:
                return VisibleMessageCell.self
                
            case .infoClosedGroupCreated, .infoClosedGroupUpdated, .infoClosedGroupCurrentUserLeft,
                .infoDisappearingMessagesUpdate, .infoScreenshotNotification, .infoMediaSavedNotification,
                .infoMessageRequestAccepted:
                return InfoMessageCell.self
                
            case .infoCall:
                return CallMessageCell.self
        }
    }
}

// MARK: - MessageCellDelegate

protocol MessageCellDelegate: ReactionDelegate {
    func handleItemLongPressed(_ cellViewModel: MessageViewModel)
    func handleItemTapped(_ cellViewModel: MessageViewModel, gestureRecognizer: UITapGestureRecognizer)
    func handleItemDoubleTapped(_ cellViewModel: MessageViewModel)
    func handleItemSwiped(_ cellViewModel: MessageViewModel, state: SwipeState)
    func openUrl(_ urlString: String)
    func handleReplyButtonTapped(for cellViewModel: MessageViewModel)
    func startThread(with sessionId: String, openGroupServer: String?, openGroupPublicKey: String?)
    func showReactionList(_ cellViewModel: MessageViewModel, selectedReaction: EmojiWithSkinTones?)
    func needsLayout(for cellViewModel: MessageViewModel, expandingReactions: Bool)
}
