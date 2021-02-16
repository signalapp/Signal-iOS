import CoreServices

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
        if let thread = thread as? TSContactThread {
            let publicKey = thread.contactIdentifier()
            guard !OWSBlockingManager.shared().isRecipientIdBlocked(publicKey) else {
                let blockedModal = BlockedModal(publicKey: publicKey)
                blockedModal.modalPresentationStyle = .overFullScreen
                blockedModal.modalTransitionStyle = .crossDissolve
                return present(blockedModal, animated: true, completion: nil)
            }
        }
        // TODO: Attachments
        let text = snInputView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let thread = self.thread
        guard !text.isEmpty else { return }
        let message = VisibleMessage()
        message.sentTimestamp = NSDate.millisecondTimestamp()
        message.text = text
        message.quote = VisibleMessage.Quote.from(snInputView.quoteDraftInfo?.model)
        let linkPreviewDraft = snInputView.linkPreviewInfo?.draft
        let tsMessage = TSOutgoingMessage.from(message, associatedWith: thread)
        viewModel.appendUnsavedOutgoingTextMessage(tsMessage)
        Storage.write(with: { transaction in
            message.linkPreview = VisibleMessage.LinkPreview.from(linkPreviewDraft, using: transaction)
        }, completion: { [weak self] in
            tsMessage.linkPreview = OWSLinkPreview.from(message.linkPreview)
            Storage.shared.write { transaction in
                tsMessage.save(with: transaction as! YapDatabaseReadWriteTransaction)
            }
            Storage.shared.write { transaction in
                MessageSender.send(message, with: [], in: thread, using: transaction as! YapDatabaseReadWriteTransaction)
            }
            guard let self = self else { return }
            self.snInputView.text = ""
            self.snInputView.quoteDraftInfo = nil
            self.markAllAsRead()
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
        if let message = viewItem.interaction as? TSOutgoingMessage, message.messageState == .failed {
            showFailedMessageSheet(for: message)
        } else {
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
            case .textOnlyMessage:
                guard let preview = viewItem.linkPreview, let urlAsString = preview.urlString, let url = URL(string: urlAsString) else { return }
                openURL(url)
            default: break
            }
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
    
    func openURL(_ url: URL) {
        let urlModal = URLModal(url: url)
        urlModal.modalPresentationStyle = .overFullScreen
        urlModal.modalTransitionStyle = .crossDissolve
        present(urlModal, animated: true, completion: nil)
    }
    
    func handleReplyButtonTapped(for viewItem: ConversationViewItem) {
        reply(viewItem)
    }
    
    @objc func unblock() {
        guard let thread = thread as? TSContactThread else { return }
        let publicKey = thread.contactIdentifier()
        UIView.animate(withDuration: 0.25, animations: {
            self.blockedBanner.alpha = 0
        }, completion: { _ in
            OWSBlockingManager.shared().removeBlockedPhoneNumber(publicKey)
        })
    }

    func requestMicrophonePermissionIfNeeded() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: break
        case .denied:
            cancelVoiceMessageRecording()
            let modal = PermissionMissingModal(permission: "microphone") { [weak self] in
                self?.cancelVoiceMessageRecording()
            }
            modal.modalPresentationStyle = .overFullScreen
            modal.modalTransitionStyle = .crossDissolve
            present(modal, animated: true, completion: nil)
        case .undetermined:
            cancelVoiceMessageRecording()
            AVAudioSession.sharedInstance().requestRecordPermission { _ in }
        default: break
        }
    }

    func startVoiceMessageRecording() {
        // Request permission if needed
        requestMicrophonePermissionIfNeeded()
        guard AVAudioSession.sharedInstance().recordPermission == .granted else { return }
        // Cancel any current audio playback
        audioPlayer?.stop()
        audioPlayer = nil
        // Create URL
        let directory = OWSTemporaryDirectory()
        let fileName = "\(NSDate.millisecondTimestamp()).m4a"
        let path = (directory as NSString).appendingPathComponent(fileName)
        let url = URL(fileURLWithPath: path)
        // Set up audio session
        let isConfigured = audioSession.startAudioActivity(recordVoiceMessageActivity)
        guard isConfigured else {
            return cancelVoiceMessageRecording()
        }
        // Set up audio recorder
        let settings: [String:NSNumber] = [
            AVFormatIDKey : NSNumber(value: kAudioFormatMPEG4AAC),
            AVSampleRateKey : NSNumber(value: 44100),
            AVNumberOfChannelsKey : NSNumber(value: 2),
            AVEncoderBitRateKey : NSNumber(value: 128 * 1024)
        ]
        let audioRecorder: AVAudioRecorder
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder.isMeteringEnabled = true
            self.audioRecorder = audioRecorder
        } catch {
            SNLog("Couldn't start audio recording due to error: \(error).")
            return cancelVoiceMessageRecording()
        }
        // Limit voice messages to a minute
        audioTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false, block: { [weak self] _ in
            self?.snInputView.hideVoiceMessageUI()
            self?.endVoiceMessageRecording()
        })
        // Prepare audio recorder
        guard audioRecorder.prepareToRecord() else {
            SNLog("Couldn't prepare audio recorder.")
            return cancelVoiceMessageRecording()
        }
        // Start recording
        guard audioRecorder.record() else {
            SNLog("Couldn't record audio.")
            return cancelVoiceMessageRecording()
        }
    }

    func endVoiceMessageRecording() {
        // Hide the UI
        snInputView.hideVoiceMessageUI()
        // Cancel the timer
        audioTimer?.invalidate()
        // Check preconditions
        guard let audioRecorder = audioRecorder else { return }
        // Get duration
        let duration = audioRecorder.currentTime
        // Stop the recording
        stopVoiceMessageRecording()
        // Check for user misunderstanding
        guard duration > 1 else {
            self.audioRecorder = nil
            let title = NSLocalizedString("VOICE_MESSAGE_TOO_SHORT_ALERT_TITLE", comment: "")
            let message = NSLocalizedString("VOICE_MESSAGE_TOO_SHORT_ALERT_MESSAGE", comment: "")
            return OWSAlerts.showAlert(title: title, message: message)
        }
        // Get data
        let dataSourceOrNil = DataSourcePath.dataSource(with: audioRecorder.url, shouldDeleteOnDeallocation: true)
        self.audioRecorder = nil
        guard let dataSource = dataSourceOrNil else { return SNLog("Couldn't load recorded data.") }
        // Create attachment
        let fileName = (NSLocalizedString("VOICE_MESSAGE_FILE_NAME", comment: "") as NSString).appendingPathExtension("m4a")
        dataSource.sourceFilename = fileName
        let attachment = SignalAttachment.voiceMessageAttachment(dataSource: dataSource, dataUTI: kUTTypeMPEG4Audio as String)
        guard !attachment.hasError else {
            let alert = UIAlertController(title: "Session", message: "An error occurred.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            return present(alert, animated: true, completion: nil)
        }
        // Send attachment
        // TODO: Send the attachment
    }

    func cancelVoiceMessageRecording() {
        snInputView.hideVoiceMessageUI()
        audioTimer?.invalidate()
        stopVoiceMessageRecording()
        audioRecorder = nil
    }

    func stopVoiceMessageRecording() {
        audioRecorder?.stop()
        audioSession.endAudioActivity(recordVoiceMessageActivity)
    }
}
