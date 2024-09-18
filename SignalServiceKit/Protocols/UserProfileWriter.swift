//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// This enum is serialized.
public enum UserProfileWriter: UInt {
    case localUser = 0
    case profileFetch = 1
    case storageService = 2
    case syncMessage = 3
    case registration = 4
    case linking = 5
    case groupState = 6
    case reupload = 7
    case avatarDownload = 8
    case metadataUpdate = 9
    case debugging = 10
    case tests = 11
    case unknown = 12
    case systemContactsFetch = 13
    case changePhoneNumber = 14
    case messageBackupRestore = 15
}
