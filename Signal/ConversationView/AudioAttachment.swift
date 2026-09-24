//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import Foundation
public import SignalServiceKit

// Represents a _playable_ audio attachment.
public class AudioAttachment: Equatable {
    public enum State: Equatable {
        case attachmentStream(attachmentStream: ReferencedAttachmentStream)
        case attachmentPointer(
            attachmentPointer: ReferencedAttachmentPointer,
            downloadState: AttachmentDownloadState,
        )

        public static func ==(lhs: AudioAttachment.State, rhs: AudioAttachment.State) -> Bool {
            switch (lhs, rhs) {
            case let (
                .attachmentStream(lhsStream),
                .attachmentStream(rhsStream),
            ):
                return lhsStream.attachmentStream.id == rhsStream.attachmentStream.id
                    && lhsStream.reference.hasSameOwner(as: rhsStream.reference)
            case let (
                .attachmentPointer(lhsPointer, lhsState),
                .attachmentPointer(rhsPointer, rhsState),
            ):
                return lhsPointer.attachment.id == rhsPointer.attachment.id
                    && lhsPointer.reference.hasSameOwner(as: rhsPointer.reference)
                    && lhsState == rhsState
            case
                (.attachmentStream, _),
                (.attachmentPointer, _):
                return false
            }
        }
    }

    public let state: State

    /// The duration and waveform for this audio, if we know them.
    public let audioDetails: Attachment.AudioDetails?

    public let receivedAtDate: Date
    public let owningMessage: TSMessage

    // Set at time of init. Value doesn't change even after download completes
    // to ensure that conversation view diffing catches the need to redraw the cell
    public let isDownloading: Bool

    public init?(
        attachmentStream referencedAttachmentStream: ReferencedAttachmentStream,
        owningMessage: TSMessage,
        metadata: MediaMetadata?,
        receivedAtDate: Date,
    ) {
        switch referencedAttachmentStream.attachmentStream.contentType {
        case .audio:
            break
        default:
            return nil
        }

        self.state = .attachmentStream(attachmentStream: referencedAttachmentStream)
        self.audioDetails = referencedAttachmentStream.attachmentStream.audioDetails
        self.isDownloading = false
        self.receivedAtDate = receivedAtDate
        self.owningMessage = owningMessage
    }

    public init?(
        attachmentPointer: ReferencedAttachmentPointer,
        owningMessage: TSMessage,
        metadata: MediaMetadata?,
        receivedAtDate: Date,
        downloadState: AttachmentDownloadState,
    ) {
        switch attachmentPointer.attachment.contentType {
        case .audio:
            break
        default:
            return nil
        }

        state = .attachmentPointer(
            attachmentPointer: attachmentPointer,
            downloadState: downloadState,
        )

        self.audioDetails = attachmentPointer.attachment.audioDetails

        switch downloadState {
        case .failed, .none:
            isDownloading = false
        case .enqueuedOrDownloading:
            isDownloading = true
        }
        self.receivedAtDate = receivedAtDate
        self.owningMessage = owningMessage
    }

    public var attachment: Attachment {
        switch state {
        case .attachmentStream(let attachmentStream):
            return attachmentStream.attachment
        case .attachmentPointer(let attachmentPointer, _):
            return attachmentPointer.attachment
        }
    }

    public var attachmentStream: ReferencedAttachmentStream? {
        switch state {
        case .attachmentStream(let attachmentStream):
            return attachmentStream
        case .attachmentPointer:
            return nil
        }
    }

    public var attachmentPointer: ReferencedAttachmentPointer? {
        switch state {
        case .attachmentStream:
            return nil
        case .attachmentPointer(let attachmentPointer, _):
            return attachmentPointer
        }
    }

    public var durationSeconds: TimeInterval? {
        if
            let duration = audioDetails?.duration,
            duration.isFinite,
            duration > 0
        {
            return duration
        }

        // Audio that doesn't know its own duration still has one once it's
        // been played.
        let cvAudioPlayer = AppEnvironment.shared.cvAudioPlayerRef
        return cvAudioPlayer.playbackDuration(
            playbackID: CVAudioPlaybackID(audioAttachment: self),
        )
    }

    public var isVoiceMessage: Bool {
        let renderingFlag: AttachmentReference.RenderingFlag = switch state {
        case .attachmentStream(let attachmentStream):
            attachmentStream.reference.renderingFlag
        case .attachmentPointer(let attachmentPointer, _):
            attachmentPointer.reference.renderingFlag
        }

        return renderingFlag == .voiceMessage
    }

    public var sourceFilename: String? {
        switch state {
        case .attachmentStream(let attachmentStream):
            return attachmentStream.reference.sourceFilename
        case .attachmentPointer(let attachmentPointer, _):
            return attachmentPointer.reference.sourceFilename
        }
    }

    public func markOwningMessageAsViewed() -> Bool {
        AssertIsOnMainThread()
        guard let incomingMessage = owningMessage as? TSIncomingMessage, !incomingMessage.wasViewed else { return false }
        SSKEnvironment.shared.databaseStorageRef.asyncWrite { tx in
            let uniqueId = incomingMessage.uniqueId
            guard
                let latestMessage = TSIncomingMessage.fetchIncomingMessageViaCache(uniqueId: uniqueId, transaction: tx),
                let latestThread = latestMessage.thread(tx: tx)
            else {
                return
            }
            let circumstance: OWSReceiptCircumstance = (
                latestThread.hasPendingMessageRequest(transaction: tx)
                    ? .onThisDeviceWhilePendingMessageRequest
                    : .onThisDevice,
            )
            latestMessage.markAsViewed(
                atTimestamp: Date.ows_millisecondTimestamp(),
                thread: latestThread,
                circumstance: circumstance,
                transaction: tx,
            )
        }
        return true
    }

    // MARK: - Equatable

    public static func ==(lhs: AudioAttachment, rhs: AudioAttachment) -> Bool {
        lhs.state == rhs.state &&
            lhs.audioDetails == rhs.audioDetails &&
            lhs.owningMessage == rhs.owningMessage &&
            lhs.isDownloading == rhs.isDownloading
    }
}
