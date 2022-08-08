// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public enum ProfileManagerError: LocalizedError {
    case avatarImageTooLarge
    case avatarWriteFailed
    case avatarEncryptionFailed
    case avatarUploadFailed
    case avatarUploadMaxFileSizeExceeded
    
    var localizedDescription: String {
        switch self {
            case .avatarImageTooLarge: return "Avatar image too large."
            case .avatarWriteFailed: return "Avatar write failed."
            case .avatarEncryptionFailed: return "Avatar encryption failed."
            case .avatarUploadFailed: return "Avatar upload failed."
            case .avatarUploadMaxFileSizeExceeded: return "Maximum file size exceeded."
        }
    }
}
