//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

extension ConversationViewController {
    @objc
    func ensureIndexPath(of interaction: TSMessage) -> IndexPath? {
        return databaseStorage.uiRead { transaction in
            self.conversationViewModel.ensureLoadWindowContainsInteractionId(interaction.uniqueId,
                                                                             transaction: transaction)
        }
    }
}

extension ConversationViewController: MessageActionsViewControllerDelegate {
    func messageActionsViewControllerRequestedDismissal(_ messageActionsViewController: MessageActionsViewController, withAction action: MessageAction?) {

        let sender: UIView? = {
            let interaction = messageActionsViewController.focusedInteraction
            guard let index = conversationViewModel.viewState.interactionIndexMap[interaction.uniqueId] else {
                return nil
            }

            let indexPath = IndexPath(item: index.intValue, section: 0)

            guard self.collectionView.indexPathsForVisibleItems.contains(indexPath),
                let cell = self.collectionView.cellForItem(at: indexPath) else {
                    return nil
            }

            switch cell {
            case let messageCell as OWSMessageCell:
                return messageCell.messageView
            default:
                return cell
            }
        }()

        dismissMessageActions(animated: true) {
            action?.block(sender)
        }
    }

    func messageActionsViewControllerRequestedDismissal(_ messageActionsViewController: MessageActionsViewController, withReaction reaction: String, isRemoving: Bool) {
        dismissMessageActions(animated: true) {
            guard let message = messageActionsViewController.focusedInteraction as? TSMessage else {
                owsFailDebug("Not sending reaction for unexpected interaction type")
                return
            }

            self.databaseStorage.asyncWrite { transaction in
                ReactionManager.localUserReacted(to: message,
                                                 emoji: reaction,
                                                 isRemoving: isRemoving,
                                                 transaction: transaction)

                // Mark the reactions experience upgrade complete if the user
                // sends a reaction, even if they didn't dismiss it directly.
                ExperienceUpgradeManager.clearReactionsExperienceUpgrade(transaction: transaction.unwrapGrdbWrite)
            }
        }
    }

    func messageActionsViewController(_ messageActionsViewController: MessageActionsViewController,
                                      shouldShowReactionPickerForInteraction: TSInteraction) -> Bool {
        guard FeatureFlags.reactionSend else { return false }

        guard !self.threadViewModel.hasPendingMessageRequest else { return false }

        switch messageActionsViewController.focusedInteraction {
        case let outgoingMessage as TSOutgoingMessage:
            switch outgoingMessage.messageState {
            case .failed, .sending:
                return false
            default:
                return true
            }
        case is TSIncomingMessage:
            return true
        default:
            return false
        }
    }
}

extension ConversationViewController: MediaPresentationContextProvider {
    func mediaPresentationContext(galleryItem: MediaGalleryItem, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
        guard let indexPath = ensureIndexPath(of: galleryItem.message) else {
            owsFailDebug("indexPath was unexpectedly nil")
            return nil
        }

        // `indexPath(of:)` can change the load window which requires re-laying out our view
        // in order to correctly determine:
        //  - `indexPathsForVisibleItems`
        //  - the correct presentation frame
        collectionView.layoutIfNeeded()

        guard let visibleIndex = collectionView.indexPathsForVisibleItems.firstIndex(of: indexPath) else {
            // This could happen if, after presenting media, you navigated within the gallery
            // to media not withing the collectionView's visible bounds.
            return nil
        }

        guard let messageCell = collectionView.visibleCells[safe: visibleIndex] as? OWSMessageCell else {
            owsFailDebug("messageCell was unexpectedly nil")
            return nil
        }

        guard let mediaView = messageCell.messageBubbleView.albumItemView(forAttachment: galleryItem.attachmentStream) else {
            owsFailDebug("itemView was unexpectedly nil")
            return nil
        }

        guard let mediaSuperview = mediaView.superview else {
            owsFailDebug("mediaSuperview was unexpectedly nil")
            return nil
        }

        let presentationFrame = coordinateSpace.convert(mediaView.frame, from: mediaSuperview)

        // TODO exactly match corner radius for collapsed cells - maybe requires passing a masking view?
        return MediaPresentationContext(mediaView: mediaView, presentationFrame: presentationFrame, cornerRadius: kOWSMessageCellCornerRadius_Small * 2)
    }

    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        return nil
    }

    func mediaWillDismiss(toContext: MediaPresentationContext) {
        guard let messageBubbleView = toContext.messageBubbleView else { return }

        // To avoid flicker when transition view is animated over the message bubble,
        // we initially hide the overlaying elements and fade them in.
        messageBubbleView.footerView.alpha = 0
        messageBubbleView.bodyMediaGradientView?.alpha = 0.0
    }

    func mediaDidDismiss(toContext: MediaPresentationContext) {
        guard let messageBubbleView = toContext.messageBubbleView else { return }

        // To avoid flicker when transition view is animated over the message bubble,
        // we initially hide the overlaying elements and fade them in.
        let duration: TimeInterval = kIsDebuggingMediaPresentationAnimations ? 1.5 : 0.2
        UIView.animate(
            withDuration: duration,
            animations: {
                messageBubbleView.footerView.alpha = 1.0
                messageBubbleView.bodyMediaGradientView?.alpha = 1.0
        })
    }
}

private extension MediaPresentationContext {
    var messageBubbleView: OWSMessageBubbleView? {
        guard let messageBubbleView = mediaView.firstAncestor(ofType: OWSMessageBubbleView.self) else {
            owsFailDebug("unexpected mediaView: \(mediaView)")
            return nil
        }

        return messageBubbleView
    }
}

extension OWSMessageBubbleView {
    func albumItemView(forAttachment attachment: TSAttachmentStream) -> UIView? {
        guard let mediaAlbumCellView = bodyMediaView as? MediaAlbumCellView else {
            owsFailDebug("mediaAlbumCellView was unexpectedly nil")
            return nil
        }

        guard let albumItemView = (mediaAlbumCellView.itemViews.first { $0.attachment == attachment }) else {
            assert(mediaAlbumCellView.moreItemsView != nil)
            return mediaAlbumCellView.moreItemsView
        }

        return albumItemView
    }
}
