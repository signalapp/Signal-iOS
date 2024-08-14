//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

// MARK: - Convenience initializers

public extension TSInfoMessage {
    convenience init(
        thread: TSThread,
        messageType: TSInfoMessageType,
        timestamp: UInt64 = MessageTimestampGenerator.sharedInstance.generateTimestamp(),
        infoMessageUserInfo: [InfoMessageUserInfoKey: Any]? = nil
    ) {
        self.init(
            thread: thread,
            timestamp: timestamp,
            serverGuid: nil,
            messageType: messageType,
            infoMessageUserInfo: infoMessageUserInfo
        )
    }
}

// MARK: - InfoMessageUserInfo

extension TSInfoMessage {
    func infoMessageValue<T>(forKey key: InfoMessageUserInfoKey) -> T? {
        guard let value = infoMessageUserInfo?[key] as? T else {
            return nil
        }

        return value
    }

    func setInfoMessageValue(_ value: Any, forKey key: InfoMessageUserInfoKey) {
        if self.infoMessageUserInfo != nil {
            self.infoMessageUserInfo![key] = value
        } else {
            self.infoMessageUserInfo = [key: value]
        }
    }
}
