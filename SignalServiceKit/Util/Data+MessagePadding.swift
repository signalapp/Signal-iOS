//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Data {
    public var paddedMessageBody: Data {
        let paddingLength: Int = {
            // We have our own padding scheme, but so does the cipher.
            // The +2 here is to ensure the cipher has room for a padding byte, plus the separator byte.
            // The -2 at the end of this undoes that.
            let messageLengthWithTerminator = self.count + 2
            var messagePartCount = messageLengthWithTerminator / 80
            if !messageLengthWithTerminator.isMultiple(of: 80) {
                messagePartCount += 1
            }
            let resultLength = messagePartCount * 80
            return resultLength - 2 - self.count
        }()
        return self + [0x80] + Data(count: paddingLength)
    }

    public func withoutPadding() -> Data {
        guard
            let lastNonZeroByteIndex = self.lastIndex(where: { $0 != 0 }),
            self[lastNonZeroByteIndex] == 0x80
        else {
            Logger.warn("Failed to find padding byte, returning unstripped data")
            return self
        }
        return self[..<lastNonZeroByteIndex]
    }
}
