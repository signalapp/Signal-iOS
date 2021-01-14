//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// Represents a _playable_ audio attachment.
@objc
public class AudioAttachment: NSObject {
    public enum State {
        case attachmentStream(attachmentStream: TSAttachmentStream, audioDurationSeconds: TimeInterval)
        case attachmentPointer(attachmentPointer: TSAttachmentPointer)
    }
    public let state: State

    @objc
    public var attachment: TSAttachment {
        switch state {
        case .attachmentStream(let attachmentStream, _):
            return attachmentStream
        case .attachmentPointer(let attachmentPointer):
            return attachmentPointer
        }
    }

    @objc
    public var attachmentStream: TSAttachmentStream? {
        switch state {
        case .attachmentStream(let attachmentStream, _):
            return attachmentStream
        case .attachmentPointer:
            return nil
        }
    }

    @objc
    public var attachmentPointer: TSAttachmentPointer? {
        switch state {
        case .attachmentStream:
            return nil
        case .attachmentPointer(let attachmentPointer):
            return attachmentPointer
        }
    }

    @objc
    public var durationSeconds: TimeInterval {
        switch state {
        case .attachmentStream(_, let audioDurationSeconds):
            return audioDurationSeconds
        case .attachmentPointer:
            return 0
        }
    }

    @objc
    public required init?(attachment: TSAttachment) {
        if let attachmentStream = attachment as? TSAttachmentStream {
            let audioDurationSeconds = attachmentStream.audioDurationSeconds()
            guard audioDurationSeconds > 0 else {
                return nil
            }
            state = .attachmentStream(attachmentStream: attachmentStream, audioDurationSeconds: audioDurationSeconds)
        } else if let attachmentPointer = attachment as? TSAttachmentPointer {
            state = .attachmentPointer(attachmentPointer: attachmentPointer)
        } else {
            owsFailDebug("Invalid attachment.")
            return nil
        }
    }
}
