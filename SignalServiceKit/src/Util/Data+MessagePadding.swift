//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

// This code is ported from Android.
// See <https://github.com/signalapp/Signal-Android/blob/cdcb1de3d4c0a6c7ff7f80eed37b490743c311e5/libsignal/service/src/main/java/org/whispersystems/signalservice/internal/push/PushTransportDetails.java#L12-L57>.
extension Data {
    public var paddedMessageBody: Data {
        let paddingLength: Int = {
            // We have our own padding scheme, but so does the cipher.
            // The +2 here is to ensure the cipher has room for a padding byte, plus the separator byte.
            // The -2 at the end of this undoes that.
            let messageLengthWithTerminator = self.count + 2
            var messagePartCount = messageLengthWithTerminator / 160
            if !messageLengthWithTerminator.isMultiple(of: 160) {
                messagePartCount += 1
            }
            let resultLength = messagePartCount * 160
            return resultLength - 2 - self.count
        }()
        return self + [0x80] + Data(count: paddingLength)
    }

    public func withoutPadding() -> Data {
        guard
            let lastNonZeroByteIndex = self.lastIndex(where: { $0 != 0 }),
            self[lastNonZeroByteIndex] == 0x80 else {
            Logger.warn("Failed to find padding byte, returning unstripped data")
            return self
        }
        return self[..<lastNonZeroByteIndex]
    }
}
