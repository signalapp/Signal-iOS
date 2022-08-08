// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public enum AttachmentError: LocalizedError {
    case invalidStartState
    case noAttachment
    case notUploaded
    case invalidData
    case encryptionFailed

    public var errorDescription: String? {
        switch self {
            case .invalidStartState: return "Cannot upload an attachment in this state."
            case .noAttachment: return "No such attachment."
            case .notUploaded: return "Attachment not uploaded."
            case .invalidData: return "Invalid attachment data."
            case .encryptionFailed: return "Couldn't encrypt file."
        }
    }
}
