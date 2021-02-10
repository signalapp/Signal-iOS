
extension ConversationVC : InputViewDelegate, MessageCellDelegate, ContextMenuActionDelegate, ScrollToBottomButtonDelegate {
    
    @objc func openSettings() {
        let settingsVC = OWSConversationSettingsViewController()
        settingsVC.configure(with: thread, uiDatabaseConnection: OWSPrimaryStorage.shared().uiDatabaseConnection)
        navigationController!.pushViewController(settingsVC, animated: true, completion: nil)
    }
    
    func handleCameraButtonTapped() {
        // TODO: Implement
    }
    
    func handleLibraryButtonTapped() {
        // TODO: Implement
    }
    
    func handleGIFButtonTapped() {
        // TODO: Implement
    }
    
    func handleDocumentButtonTapped() {
        // TODO: Implement
    }
    
    func handleSendButtonTapped() {
        // TODO: Attachments
        let text = snInputView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let thread = self.thread
        // TODO: Blocking
        guard !text.isEmpty else { return }
        let message = VisibleMessage()
        message.sentTimestamp = NSDate.millisecondTimestamp()
        message.text = text
        message.quote = VisibleMessage.Quote.from(snInputView.quoteDraftInfo?.model)
        // TODO: Link previews
        let tsMessage = TSOutgoingMessage.from(message, associatedWith: thread)
        viewModel.appendUnsavedOutgoingTextMessage(tsMessage)
        Storage.shared.write(with: { transaction in
            // TODO: Link previews
        }, completion: { [weak self] in
            // TODO: Link previews
            Storage.shared.write { transaction in
                tsMessage.save(with: transaction as! YapDatabaseReadWriteTransaction)
            }
            Storage.shared.write { transaction in
                MessageSender.send(message, with: [], in: thread, using: transaction as! YapDatabaseReadWriteTransaction)
            }
            // TODO: Sent handling
            self?.snInputView.text = ""
            self?.snInputView.quoteDraftInfo = nil
            // TODO: Reset mentions
        })
    }

    func handleViewItemLongPressed(_ viewItem: ConversationViewItem) {
        guard let index = viewItems.firstIndex(where: { $0 === viewItem }),
            let cell = messagesTableView.cellForRow(at: IndexPath(row: index, section: 0)) as? VisibleMessageCell,
            let snapshot = cell.bubbleView.snapshotView(afterScreenUpdates: false), contextMenuWindow == nil,
            !ContextMenuVC.actions(for: viewItem, delegate: self).isEmpty else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        let frame = cell.convert(cell.bubbleView.frame, to: UIApplication.shared.keyWindow!)
        let window = ContextMenuWindow()
        let contextMenuVC = ContextMenuVC(snapshot: snapshot, viewItem: viewItem, frame: frame, delegate: self) {
            window.isHidden = true
            self.contextMenuVC = nil
            self.contextMenuWindow = nil
        }
        self.contextMenuVC = contextMenuVC
        contextMenuWindow = window
        window.rootViewController = contextMenuVC
        window.makeKeyAndVisible()
        window.backgroundColor = .clear
    }

    func handleViewItemTapped(_ viewItem: ConversationViewItem, gestureRecognizer: UITapGestureRecognizer) {
        switch viewItem.messageCellType {
        case .audio: playOrPauseAudio(for: viewItem)
        case .mediaMessage:
            guard let index = viewItems.firstIndex(where: { $0 === viewItem }),
                let cell = messagesTableView.cellForRow(at: IndexPath(row: index, section: 0)) as? VisibleMessageCell, let albumView = cell.albumView else { return }
            let locationInCell = gestureRecognizer.location(in: cell)
            if let overlayView = cell.mediaTextOverlayView {
                let locationInOverlayView = cell.convert(locationInCell, to: overlayView)
                if let readMoreButton = overlayView.readMoreButton, readMoreButton.frame.contains(locationInOverlayView) {
                    return showFullText(viewItem) // FIXME: Bit of a hack to do it this way
                }
            }
            let locationInAlbumView = cell.convert(locationInCell, to: albumView)
            guard let mediaView = albumView.mediaView(forLocation: locationInAlbumView) else { return }
            if albumView.isMoreItemsView(mediaView: mediaView) && viewItem.mediaAlbumHasFailedAttachment() {
                // TODO: Tapped a failed incoming attachment
            }
            let attachment = mediaView.attachment
            if let pointer = attachment as? TSAttachmentPointer {
                if pointer.state == .failed {
                    // TODO: Tapped a failed incoming attachment
                }
            }
            guard let stream = attachment as? TSAttachmentStream else { return }
            let gallery = MediaGallery(thread: thread, options: [ .sliderEnabled, .showAllMediaButton ])
            gallery.presentDetailView(fromViewController: self, mediaAttachment: stream, replacingView: mediaView)
        case .genericAttachment:
            guard let url = viewItem.attachmentStream?.originalMediaURL else { return }
            let shareVC = UIActivityViewController(activityItems: [ url ], applicationActivities: nil)
            navigationController!.present(shareVC, animated: true, completion: nil)
        default: break
        }
    }

    func handleViewItemDoubleTapped(_ viewItem: ConversationViewItem) {
        switch viewItem.messageCellType {
        case .audio: speedUpAudio(for: viewItem)
        default: break
        }
    }
    
    func showFullText(_ viewItem: ConversationViewItem) {
        let longMessageVC = LongTextViewController(viewItem: viewItem)
        navigationController!.pushViewController(longMessageVC, animated: true)
    }

    func playOrPauseAudio(for viewItem: ConversationViewItem) {
        guard let attachment = viewItem.attachmentStream else { return }
        let fileManager = FileManager.default
        guard let path = attachment.originalFilePath, fileManager.fileExists(atPath: path),
            let url = attachment.originalMediaURL else { return }
        if let audioPlayer = audioPlayer {
            if let owner = audioPlayer.owner as? ConversationViewItem, owner === viewItem {
                audioPlayer.playbackRate = 1
                audioPlayer.togglePlayState()
                return
            } else {
                audioPlayer.stop()
                self.audioPlayer = nil
            }
        }
        let audioPlayer = OWSAudioPlayer(mediaUrl: url, audioBehavior: .audioMessagePlayback, delegate: viewItem)
        self.audioPlayer = audioPlayer
        audioPlayer.owner = viewItem
        audioPlayer.play()
        audioPlayer.setCurrentTime(Double(viewItem.audioProgressSeconds))
    }

    func speedUpAudio(for viewItem: ConversationViewItem) {
        guard let audioPlayer = audioPlayer, let owner = audioPlayer.owner as? ConversationViewItem, owner === viewItem, audioPlayer.isPlaying else { return }
        audioPlayer.playbackRate = 1.5
        viewItem.lastAudioMessageView?.showSpeedUpLabel()
    }
    
    func reply(_ viewItem: ConversationViewItem) {
        var quoteDraftOrNil: OWSQuotedReplyModel?
        Storage.read { transaction in
            quoteDraftOrNil = OWSQuotedReplyModel.quotedReplyForSending(with: viewItem, threadId: viewItem.interaction.uniqueThreadId, transaction: transaction)
        }
        guard let quoteDraft = quoteDraftOrNil else { return }
        let isOutgoing = (viewItem.interaction.interactionType() == .outgoingMessage)
        snInputView.quoteDraftInfo = (model: quoteDraft, isOutgoing: isOutgoing)
        snInputView.becomeFirstResponder()
    }
    
    func copy(_ viewItem: ConversationViewItem) {
        if viewItem.canCopyMedia() {
            viewItem.copyMediaAction()
        } else {
            viewItem.copyTextAction()
        }
    }
    
    func copySessionID(_ viewItem: ConversationViewItem) {
        guard let message = viewItem.interaction as? TSIncomingMessage else { return }
        UIPasteboard.general.string = message.authorId
    }
    
    func delete(_ viewItem: ConversationViewItem) {
        viewItem.deleteAction()
    }
    
    func save(_ viewItem: ConversationViewItem) {
        guard viewItem.canSaveMedia() else { return }
        viewItem.saveMediaAction()
    }
    
    func ban(_ viewItem: ConversationViewItem) {
        guard let message = viewItem.interaction as? TSIncomingMessage, message.isOpenGroupMessage else { return }
        let alert = UIAlertController(title: "Ban This User?", message: nil, preferredStyle: .alert)
        let threadID = thread.uniqueId!
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            guard let openGroup = Storage.shared.getOpenGroup(for: threadID) else { return }
            let publicKey = message.authorId
            OpenGroupAPI.ban(publicKey, from: openGroup.server).retainUntilComplete()
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
    func handleScrollToBottomButtonTapped() {
        scrollToBottom(isAnimated: true)
    }

    func handleQuoteViewCancelButtonTapped() {
        snInputView.quoteDraftInfo = nil
    }
}
