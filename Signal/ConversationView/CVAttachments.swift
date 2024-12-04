//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import Foundation
public import SignalServiceKit

// Represents a _playable_ audio attachment.
public class AudioAttachment {
    public enum State: Equatable {
        case attachmentStream(
            attachmentStream: ReferencedAttachmentStream,
            audioDurationSeconds: TimeInterval
        )
        case attachmentPointer(
            attachmentPointer: ReferencedAttachmentTransitPointer,
            transitTierDownloadState: AttachmentDownloadState
        )

        public static func == (lhs: AudioAttachment.State, rhs: AudioAttachment.State) -> Bool {
            switch (lhs, rhs) {
            case let (
                .attachmentStream(lhsStream, lhsDuration),
                .attachmentStream(rhsStream, rhsDuration)
            ):
                return lhsStream.attachmentStream.id == rhsStream.attachmentStream.id
                    && lhsStream.reference.hasSameOwner(as: rhsStream.reference)
                    && lhsDuration == rhsDuration
            case let (
                .attachmentPointer(lhsPointer, lhsState),
                .attachmentPointer(rhsPointer, rhsState)
            ):
                return lhsPointer.attachment.id == rhsPointer.attachment.id
                    && lhsPointer.reference.hasSameOwner(as: rhsPointer.reference)
                    && lhsState == rhsState
            case (.attachmentStream, _), (.attachmentPointer, _):
                return false
            }
        }
    }
    public let state: State

    public var sourceFilename: String? {
        switch state {
        case .attachmentStream(let attachmentStream, _):
            return attachmentStream.reference.sourceFilename
        case .attachmentPointer(let attachmentPointer, _):
            return attachmentPointer.reference.sourceFilename
        }
    }

    public let receivedAtDate: Date
    public let owningMessage: TSMessage?

    // Set at time of init. Value doesn't change even after download completes
    // to ensure that conversation view diffing catches the need to redraw the cell
    public let isDownloading: Bool

    public init?(
        attachmentStream: ReferencedAttachmentStream,
        owningMessage: TSMessage?,
        metadata: MediaMetadata?,
        receivedAtDate: Date
    ) {
        let audioDurationSeconds: TimeInterval
        switch attachmentStream.attachmentStream.contentType {
        case .audio(var duration, _):
            // TODO: Remove & replace with a full fix to recompute the duration for invalid files.
            if duration <= 0 {
                duration = Self.cachedAudioDuration(forAttachment: attachmentStream.attachmentStream)
            }
            if duration <= 0 {
                fallthrough
            }
            audioDurationSeconds = duration
        default:
            return nil
        }
        self.state = .attachmentStream(
            attachmentStream: attachmentStream,
            audioDurationSeconds: audioDurationSeconds
        )
        self.isDownloading = false
        self.receivedAtDate = receivedAtDate
        self.owningMessage = owningMessage
    }

    public init(
        attachmentPointer: ReferencedAttachmentTransitPointer,
        owningMessage: TSMessage?,
        metadata: MediaMetadata?,
        receivedAtDate: Date,
        transitTierDownloadState: AttachmentDownloadState
    ) {
        state = .attachmentPointer(
            attachmentPointer: attachmentPointer,
            transitTierDownloadState: transitTierDownloadState
        )

        switch transitTierDownloadState {
        case .failed, .none:
            isDownloading = false
        case .enqueuedOrDownloading:
            isDownloading = true
        }
        self.receivedAtDate = receivedAtDate
        self.owningMessage = owningMessage
    }

    private static let cachedAttachmentDurations = AtomicDictionary<Int64, TimeInterval>([:], lock: .init())
    private static func cachedAudioDuration(forAttachment attachmentStream: AttachmentStream) -> TimeInterval {
        let attachmentId = attachmentStream.attachment.id
        if let cachedDuration = cachedAttachmentDurations[attachmentId] {
            return cachedDuration
        }
        let computedDuration: TimeInterval
        do {
            let asset = try attachmentStream.decryptedAVAsset()
            computedDuration = asset.duration.seconds
        } catch {
            Logger.warn("Couldn't compute fallback duration: \(error)")
            computedDuration = 0
        }
        cachedAttachmentDurations[attachmentId] = computedDuration
        return computedDuration
    }
}

extension AudioAttachment {
    var isDownloaded: Bool { attachmentStream != nil }

    public var attachment: Attachment {
        switch state {
        case .attachmentStream(let attachmentStream, _):
            return attachmentStream.attachment
        case .attachmentPointer(let attachmentPointer, _):
            return attachmentPointer.attachment
        }
    }

    public var attachmentStream: ReferencedAttachmentStream? {
        switch state {
        case .attachmentStream(let attachmentStream, _):
            return attachmentStream
        case .attachmentPointer:
            return nil
        }
    }

    public var attachmentPointer: ReferencedAttachmentTransitPointer? {
        switch state {
        case .attachmentStream:
            return nil
        case .attachmentPointer(let attachmentPointer, _):
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

    public var isVoiceMessage: Bool {
        { () -> AttachmentReference.RenderingFlag in
            switch state {
            case .attachmentStream(let attachmentStream, _):
                return attachmentStream.reference.renderingFlag
            case .attachmentPointer(let attachmentPointer, _):
                return attachmentPointer.reference.renderingFlag
            }
        }() == .voiceMessage
    }

    public func markOwningMessageAsViewed() -> Bool {
        AssertIsOnMainThread()
        guard let incomingMessage = owningMessage as? TSIncomingMessage, !incomingMessage.wasViewed else { return false }
        SSKEnvironment.shared.databaseStorageRef.asyncWrite { tx in
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
