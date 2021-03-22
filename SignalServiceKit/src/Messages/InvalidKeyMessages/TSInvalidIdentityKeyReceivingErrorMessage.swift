//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalClient

extension TSInvalidIdentityKeyReceivingErrorMessage {
    @objc(identityKeyFromEncodedPreKeySignalMessage:error:)
    private func identityKey(from encodedPreKeySignalMessage: Data) throws -> Data {
        return Data(try PreKeySignalMessage(bytes: encodedPreKeySignalMessage).identityKey.keyBytes)
    }
}
