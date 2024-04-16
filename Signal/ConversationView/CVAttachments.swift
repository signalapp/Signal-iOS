//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

// Represents a _playable_ audio attachment.
public class AudioAttachment {
    public enum State: Equatable {
        case attachmentStream(
            attachmentStream: TSResourceStream,
            isVoiceMessage: Bool,
            audioDurationSeconds: TimeInterval
        )
        case attachmentPointer(
            attachmentPointer: TSResourcePointer,
            isVoiceMessage: Bool,
            transitTierDownloadState: TSAttachmentPointerState?
        )

        public static func == (lhs: AudioAttachment.State, rhs: AudioAttachment.State) -> Bool {
            switch (lhs, rhs) {
            case let (
                .attachmentStream(lhsStream, lhsIsVoiceMessage, lhsDuration),
                .attachmentStream(rhsStream, rhsIsVoiceMessage, rhsDuration)
            ):
                return lhsStream.resourceId == rhsStream.resourceId
                    && lhsIsVoiceMessage == rhsIsVoiceMessage
                    && lhsDuration == rhsDuration
            case let (
                .attachmentPointer(lhsStream, lhsIsVoiceMessage, lhsState),
                .attachmentPointer(rhsStream, rhsIsVoiceMessage, rhsState)
            ):
                return lhsStream.resourceId == rhsStream.resourceId
                    && lhsIsVoiceMessage == rhsIsVoiceMessage
                    && lhsState == rhsState
            case (.attachmentStream, _), (.attachmentPointer, _):
                return false
            }
        }
    }
    public let state: State
    public let sourceFilename: String?
    public let receivedAtDate: Date
    public let owningMessage: TSMessage?

    // Set at time of init. Value doesn't change even after download completes
    // to ensure that conversation view diffing catches the need to redraw the cell
    public let isDownloading: Bool

    public init?(
        attachment: TSResource,
        owningMessage: TSMessage?,
        metadata: MediaMetadata?,
        isVoiceMessage: Bool,
        sourceFilename: String?,
        receivedAtDate: Date,
        transitTierDownloadState: TSAttachmentPointerState?
    ) {
        if let attachmentStream = attachment.asResourceStream() {
            let audioDurationSeconds: TimeInterval
            switch attachmentStream.computeContentType() {
            case .audio(let duration):
                let duration = duration.compute()
                guard duration > 0 else {
                    fallthrough
                }
                audioDurationSeconds = duration
            default:
                return nil
            }
            state = .attachmentStream(
                attachmentStream: attachmentStream,
                isVoiceMessage: isVoiceMessage,
                audioDurationSeconds: audioDurationSeconds
            )
            isDownloading = false
        } else if let attachmentPointer = attachment.asTransitTierPointer() {
            state = .attachmentPointer(
                attachmentPointer: attachmentPointer,
                isVoiceMessage: isVoiceMessage,
                transitTierDownloadState: transitTierDownloadState
            )

            switch transitTierDownloadState {
            case .none, .failed, .pendingMessageRequest, .pendingManualDownload:
                isDownloading = false
            case .enqueued, .downloading:
                isDownloading = true
            }
        } else {
            owsFailDebug("Invalid attachment.")
            return nil
        }
        self.sourceFilename = sourceFilename
        self.receivedAtDate = receivedAtDate
        self.owningMessage = owningMessage
    }
}

extension AudioAttachment: Dependencies {
    var isDownloaded: Bool { attachmentStream != nil }

    public var attachment: TSResource {
        switch state {
        case .attachmentStream(let attachmentStream, _, _):
            return attachmentStream
        case .attachmentPointer(let attachmentPointer, _, _):
            return attachmentPointer.resource
        }
    }

    public var attachmentStream: TSResourceStream? {
        switch state {
        case .attachmentStream(let attachmentStream, _, _):
            return attachmentStream
        case .attachmentPointer:
            return nil
        }
    }

    public var attachmentPointer: TSResourcePointer? {
        switch state {
        case .attachmentStream:
            return nil
        case .attachmentPointer(let attachmentPointer, _, _):
            return attachmentPointer
        }
    }

    public var transitTierDownloadState: TSAttachmentPointerState? {
        switch state {
        case .attachmentStream:
            return nil
        case .attachmentPointer(_, _, let state):
            return state
        }
    }

    public var durationSeconds: TimeInterval {
        switch state {
        case .attachmentStream(_, _, let audioDurationSeconds):
            return audioDurationSeconds
        case .attachmentPointer:
            return 0
        }
    }

    public var isVoiceMessage: Bool {
        switch state {
        case .attachmentStream(_, let isVoiceMessage, _):
            return isVoiceMessage
        case .attachmentPointer(_, let isVoiceMessage, _):
            return isVoiceMessage
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
                latestThread.hasPendingMessageRequest(transaction: tx)
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
