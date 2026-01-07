//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
public import SignalServiceKit

protocol PinnedMessageInteractionManagerDelegate: AnyObject {

    /// Scrolls to the message specified.
    /// If nil, scrolls to the message found at pinnedMessageIndex, the current one displayed in the UI banner.
    func goToMessage(message: TSMessage?)

    /// Unpins the message specified.
    /// If nil, unpins the message found at pinnedMessageIndex, the current one displayed in the UI banner.
    func unpinMessage(message: TSMessage?, modalDelegate: UIViewController?)

    /// Presents the "see all messages" details view.
    func presentSeeAllMessages()

    /// Unpins all messages
    func unpinAllMessages()
}

public struct PinnedMessageBannerData {
    let authorName: String
    let previewText: NSAttributedString
    let thumbnail: UIImageView?
}

public extension ConversationViewController {
    private enum PinnedMessageBarSizing {
        static let twoBarHeight = 12.0
        static let threeBarHeight = 8.0
        static let twoBarSpacing = 4.0
        static let threeBarSpacing = 2.0
    }

    func handleTappedPinnedMessage() {
        guard threadViewModel.pinnedMessages.indices.contains(pinnedMessageIndex) else {
            owsFailDebug("Invalid pinned message index")
            return
        }

        let currentPin = threadViewModel.pinnedMessages[pinnedMessageIndex]

        if threadViewModel.pinnedMessages.count > 1 {
            pinnedMessageIndex = (pinnedMessageIndex + 1) % threadViewModel.pinnedMessages.count
            animateToNextPinnedMessage()
        }

        ensureInteractionLoadedThenScrollToInteraction(
            currentPin.uniqueId,
            alignment: .centerIfNotEntirelyOnScreen,
            isAnimated: true,
        )
    }

    func pinnedMessageLeadingAccessoryView() -> UIView? {
        let pinnedMessages = threadViewModel.pinnedMessages

        guard pinnedMessages.count > 1 else {
            return nil
        }

        let accessoryViewContainer = UIStackView()
        accessoryViewContainer.axis = .vertical
        accessoryViewContainer.spacing = pinnedMessages.count == 2 ? PinnedMessageBarSizing.twoBarSpacing : PinnedMessageBarSizing.threeBarSpacing
        accessoryViewContainer.alignment = .leading
        accessoryViewContainer.translatesAutoresizingMaskIntoConstraints = false

        let singleBarSize = pinnedMessages.count == 2 ? PinnedMessageBarSizing.twoBarHeight : PinnedMessageBarSizing.threeBarHeight

        for (index, _) in pinnedMessages.enumerated().reversed() {
            let verticalBar = UIView()
            let color = index == pinnedMessageIndex ? UIColor.Signal.label : UIColor.Signal.tertiaryLabel
            verticalBar.backgroundColor = color
            verticalBar.layer.cornerRadius = 2
            verticalBar.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                verticalBar.widthAnchor.constraint(equalToConstant: 2),
                verticalBar.heightAnchor.constraint(equalToConstant: singleBarSize),
            ])
            accessoryViewContainer.addArrangedSubview(verticalBar)
        }
        accessoryViewContainer.widthAnchor.constraint(equalToConstant: 2).isActive = true
        return accessoryViewContainer
    }

    func pinnedMessageData(for message: TSMessage) -> PinnedMessageBannerData? {
        func needsThumbnail(mimeType: String, attachment: ReferencedAttachment) -> Bool {
            if MimeTypeUtil.isSupportedDefinitelyAnimatedMimeType(mimeType) || attachment.reference.renderingFlag == .shouldLoop {
                return false
            }
            return MimeTypeUtil.isSupportedImageMimeType(mimeType) || MimeTypeUtil.isSupportedVideoMimeType(mimeType)
        }

        guard let messageRowId = message.grdbId?.int64Value else {
            return nil
        }

        return DependenciesBridge.shared.db.read { tx in
            let attachment = DependenciesBridge.shared.attachmentStore
                .fetchAnyReferencedAttachment(for: .messageBodyAttachment(messageRowId: messageRowId), tx: tx)

            var authorAddress: SignalServiceAddress?
            if message.isOutgoing {
                authorAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aciAddress
            } else if let incomingMessage = message as? TSIncomingMessage {
                authorAddress = incomingMessage.authorAddress
            }

            guard
                let authorAddress,
                let previewText = pinnedMessagePreviewText(tx, message: message, mediaAttachment: attachment)
            else {
                return nil
            }
            let voteAuthorName = SSKEnvironment.shared.contactManagerRef.nameForAddress(
                authorAddress,
                localUserDisplayMode: .asLocalUser,
                short: false,
                transaction: tx,
            )

            var thumbnail: UIImageView?
            if let attachment, needsThumbnail(mimeType: attachment.attachment.mimeType, attachment: attachment) {
                thumbnail = mediaAttachmentThumbnail(messageRowId: messageRowId, tx: tx)
            }

            return PinnedMessageBannerData(
                authorName: voteAuthorName.string,
                previewText: previewText,
                thumbnail: thumbnail,
            )
        }
    }

    private func mediaSymbol(attachment: ReferencedAttachment?) -> NSAttributedString? {
        guard let attachment else {
            return nil
        }
        let mimeType = attachment.attachment.mimeType
        if MimeTypeUtil.isSupportedAudioMimeType(mimeType) {
            if attachment.reference.renderingFlag == .voiceMessage {
                return SignalSymbol.audio.attributedString(
                    dynamicTypeBaseSize: 15.0,
                )
            }
        }

        if MimeTypeUtil.isSupportedDefinitelyAnimatedMimeType(mimeType) || attachment.reference.renderingFlag == .shouldLoop {
            return SignalSymbol.gifRectangle.attributedString(
                dynamicTypeBaseSize: 15.0,
            )
        } else if MimeTypeUtil.isSupportedImageMimeType(mimeType) || MimeTypeUtil.isSupportedVideoMimeType(mimeType) {
            // These will show a thumbnail instead.
            return nil
        } else {
            return SignalSymbol.file.attributedString(
                dynamicTypeBaseSize: 15.0,
            )
        }
    }

    private func pinnedMessagePreviewText(
        _ tx: DBReadTransaction,
        message: TSMessage,
        mediaAttachment: ReferencedAttachment?,
    ) -> NSAttributedString? {
        // Payments
        if message is OWSPaymentMessage || message is OWSArchivedPaymentMessage {
            let paymentIcon = SignalSymbol.creditcard.attributedString(
                dynamicTypeBaseSize: 15.0,
            ) + " "
            return paymentIcon + NSAttributedString(string: message.body ?? "")
        }

        // View once
        if message.isViewOnceMessage {
            let viewOnceIcon = SignalSymbol.viewOnce.attributedString(
                dynamicTypeBaseSize: 15.0,
            ) + " "
            return viewOnceIcon + NSAttributedString(string: OWSLocalizedString(
                "PER_MESSAGE_EXPIRATION_NOT_VIEWABLE",
                comment: "inbox cell and notification text for an already viewed view-once media message.",
            ))
        }

        // Regular body text
        let bodyDescription = message.rawBody(transaction: tx)
        if let bodyDescription = bodyDescription?.nilIfEmpty {

            // Polls are a special case because the poll question is in the
            // message body.
            var pollPrefix: NSAttributedString = .init(string: "")
            if message.isPoll {
                let locPollString = OWSLocalizedString(
                    "POLL_PREFIX",
                    comment: "Prefix for a poll preview",
                ) + " "
                let pollIcon = SignalSymbol.poll.attributedString(
                    dynamicTypeBaseSize: 15.0,
                ) + " "
                pollPrefix = pollIcon + NSAttributedString(string: locPollString)
            }

            let hydrated = MessageBody(
                text: bodyDescription,
                ranges: message.bodyRanges ?? .empty,
            ).hydrating(mentionHydrator: ContactsMentionHydrator.mentionHydrator(transaction: tx))
            return pollPrefix + NSAttributedString(string: hydrated.asPlaintext())
        }

        // Attachments
        let attachmentIcon = mediaSymbol(attachment: mediaAttachment)
        let attachmentDescription = mediaAttachment?.previewText(includeEmoji: false)
        if let attachmentDescription = attachmentDescription?.nilIfEmpty {
            if let attachmentIcon {
                return attachmentIcon + " " + NSAttributedString(string: attachmentDescription)
            }
            return NSAttributedString(string: attachmentDescription)
        }

        // Contact share
        if let contactShare = message.contactShare {
            let contactIcon = SignalSymbol.personCircle.attributedString(
                dynamicTypeBaseSize: 15.0,
            ) + " "
            return contactIcon + NSAttributedString(string: contactShare.name.displayName)
        }

        // Sticker
        if message.messageSticker != nil {
            let stickerIcon = SignalSymbol.sticker.attributedString(
                dynamicTypeBaseSize: 15.0,
            ) + " "

            let stickerDescription = OWSLocalizedString(
                "STICKER_MESSAGE_PREVIEW",
                comment: "Preview text shown in notifications and conversation list for sticker messages.",
            )
            return stickerIcon + NSAttributedString(string: stickerDescription)
        }

        // Unknown
        return nil
    }

    private func mediaAttachmentThumbnail(messageRowId: Int64, tx: DBReadTransaction) -> UIImageView? {
        let attachment = DependenciesBridge.shared.attachmentStore.fetchAnyReferencedAttachment(
            for: .messageBodyAttachment(messageRowId: messageRowId),
            tx: tx,
        )
        guard let attachment, let attachmentStream = attachment.asReferencedStream else {
            return nil
        }

        let imageView = UIImageView()
        imageView.clipsToBounds = true
        if #available(iOS 26, *) {
            imageView.layer.cornerCurve = .continuous
            imageView.layer.cornerRadius = 11
        } else {
            imageView.layer.cornerRadius = 4
        }
        imageView.contentMode = .scaleAspectFill
        imageView.image = attachmentStream.attachmentStream.thumbnailImageSync(quality: .small)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 30),
            imageView.heightAnchor.constraint(equalToConstant: 30),
        ])
        return imageView
    }
}

extension ConversationViewController: UIContextMenuInteractionDelegate {
    public func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint,
    ) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            var actions: [UIAction] = []
            if BuildFlags.PinnedMessages.send {
                actions.append(
                    UIAction(
                        title: OWSLocalizedString(
                            "PINNED_MESSAGES_UNPIN",
                            comment: "Action menu item to unpin a message",
                        ),
                        image: .pinSlash,
                    ) { [weak self] _ in
                        guard let self else { return }
                        if threadViewModel.pinnedMessages.indices.contains(pinnedMessageIndex) {
                            handleActionUnpin(
                                message: threadViewModel.pinnedMessages[pinnedMessageIndex],
                                modalDelegate: self,
                            )
                        }
                    },
                )
            }

            actions.append(contentsOf: [
                UIAction(
                    title: OWSLocalizedString(
                        "PINNED_MESSAGES_GO_TO_MESSAGE",
                        comment: "Action menu item to go to a message in the conversation view",
                    ),
                    image: .chatArrow,
                ) { [weak self] _ in
                    guard let self else { return }
                    if threadViewModel.pinnedMessages.indices.contains(pinnedMessageIndex) {
                        goToMessage(message: threadViewModel.pinnedMessages[pinnedMessageIndex])
                    }
                },
                UIAction(title: OWSLocalizedString(
                    "PINNED_MESSAGES_SEE_ALL_MESSAGES",
                    comment: "Action menu item to see all pinned messages",
                ), image: .listBullet) { [weak self] _ in
                    self?.presentSeeAllMessages()
                },
            ])
            return UIMenu(children: actions)
        }
    }
}

extension ConversationViewController: PinnedMessageInteractionManagerDelegate {
    func goToMessage(message: TSMessage?) {
        let targetMessage: TSMessage
        if let message {
            targetMessage = message
        } else {
            guard threadViewModel.pinnedMessages.indices.contains(pinnedMessageIndex) else {
                return
            }
            targetMessage = threadViewModel.pinnedMessages[pinnedMessageIndex]
        }

        ensureInteractionLoadedThenScrollToInteraction(
            targetMessage.uniqueId,
            alignment: .centerIfNotEntirelyOnScreen,
            isAnimated: true,
        )
    }

    func unpinMessage(message: TSMessage?, modalDelegate: UIViewController?) {
        let messageToUnpin: TSMessage
        if let message {
            messageToUnpin = message
        } else {
            guard threadViewModel.pinnedMessages.indices.contains(pinnedMessageIndex) else {
                return
            }
            messageToUnpin = threadViewModel.pinnedMessages[pinnedMessageIndex]
        }

        handleActionUnpin(message: messageToUnpin, modalDelegate: modalDelegate ?? self)
    }

    func presentSeeAllMessages() {
        let pmDetailsController = UINavigationController(rootViewController: PinnedMessagesDetailsViewController(
            pinnedMessages: threadViewModel.pinnedMessages,
            threadViewModel: threadViewModel,
            database: DependenciesBridge.shared.db,
            delegate: self,
            databaseChangeObserver: DependenciesBridge.shared.databaseChangeObserver,
            pinnedMessageManager: DependenciesBridge.shared.pinnedMessageManager,
        ))
        pmDetailsController.modalPresentationStyle = .pageSheet
        present(pmDetailsController, animated: true)
    }

    func unpinAllMessages() {
        Task {
            for message in threadViewModel.pinnedMessages {
                await handleActionUnpinAsync(message: message)
            }
            presentToast(
                text: OWSLocalizedString(
                    "PINNED_MESSAGE_TOAST",
                    comment: "Text to show on a toast when someone unpins a message",
                ),
            )
        }
    }
}
