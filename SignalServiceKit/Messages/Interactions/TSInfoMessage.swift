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
        expireTimerVersion: UInt32? = nil,
        expiresInSeconds: UInt32? = nil,
        infoMessageUserInfo: [InfoMessageUserInfoKey: Any]? = nil,
    ) {
        self.init(
            thread: thread,
            timestamp: timestamp,
            serverGuid: nil,
            messageType: messageType,
            expireTimerVersion: expireTimerVersion as NSNumber?,
            expiresInSeconds: expiresInSeconds ?? 0,
            infoMessageUserInfo: infoMessageUserInfo,
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
