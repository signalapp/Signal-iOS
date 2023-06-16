//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

// Represents a _playable_ audio attachment.
public class AudioAttachment {
    public enum State: Equatable {
        case attachmentStream(attachmentStream: TSAttachmentStream, audioDurationSeconds: TimeInterval)
        case attachmentPointer(attachmentPointer: TSAttachmentPointer)
    }
    public let state: State
    public let owningMessage: TSMessage?

    // Set at time of init. Value doesn't change even after download completes
    // to ensure that conversation view diffing catches the need to redraw the cell
    public let isDownloading: Bool

    public required init?(attachment: TSAttachment, owningMessage: TSMessage?, metadata: MediaMetadata?) {
        if let attachmentStream = attachment as? TSAttachmentStream {
            let audioDurationSeconds = attachmentStream.audioDurationSeconds()
            guard audioDurationSeconds > 0 else {
                return nil
            }
            state = .attachmentStream(attachmentStream: attachmentStream, audioDurationSeconds: audioDurationSeconds)
            isDownloading = false
        } else if let attachmentPointer = attachment as? TSAttachmentPointer {
            state = .attachmentPointer(attachmentPointer: attachmentPointer)

            switch attachmentPointer.state {
            case .failed, .pendingMessageRequest, .pendingManualDownload:
                isDownloading = false
            case .enqueued, .downloading:
                isDownloading = true
            }
        } else {
            owsFailDebug("Invalid attachment.")
            return nil
        }

        self.owningMessage = owningMessage
    }
}

extension AudioAttachment: Dependencies {
    var isDownloaded: Bool { attachmentStream != nil }

    public var attachment: TSAttachment {
        switch state {
        case .attachmentStream(let attachmentStream, _):
            return attachmentStream
        case .attachmentPointer(let attachmentPointer):
            return attachmentPointer
        }
    }

    public var attachmentStream: TSAttachmentStream? {
        switch state {
        case .attachmentStream(let attachmentStream, _):
            return attachmentStream
        case .attachmentPointer:
            return nil
        }
    }

    public var attachmentPointer: TSAttachmentPointer? {
        switch state {
        case .attachmentStream:
            return nil
        case .attachmentPointer(let attachmentPointer):
            return attachmentPointer
        }
    }

    public var durationSeconds: TimeInterval {
        switch state {
        case .attachmentStream(_, let audioDurationSeconds):
            return audioDurationSeconds
        case .attachmentPointer:
            return 0
        }
    }

    public func markOwningMessageAsViewed() -> Bool {
        AssertIsOnMainThread()
        guard let incomingMessage = owningMessage as? TSIncomingMessage, !incomingMessage.wasViewed else { return false }
        databaseStorage.asyncWrite { tx in
            let uniqueId = incomingMessage.uniqueId
            guard
                let latestMessage = TSIncomingMessage.anyFetchIncomingMessage(uniqueId: uniqueId, transaction: tx),
                let latestThread = latestMessage.thread(tx: tx)
            else {
                return
            }
            let circumstance: OWSReceiptCircumstance = (
                latestThread.hasPendingMessageRequest(transaction: tx.unwrapGrdbWrite)
                ? .onThisDeviceWhilePendingMessageRequest
                : .onThisDevice
            )
            latestMessage.markAsViewed(
                atTimestamp: Date.ows_millisecondTimestamp(),
                thread: latestThread,
                circumstance: circumstance,
                transaction: tx
            )
        }
        return true
    }
}

extension AudioAttachment: Equatable {
    public static func == (lhs: AudioAttachment, rhs: AudioAttachment) -> Bool {
        lhs.state == rhs.state &&
        lhs.owningMessage == rhs.owningMessage &&
        lhs.isDownloading == rhs.isDownloading
    }
}
