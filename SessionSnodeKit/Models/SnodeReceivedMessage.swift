// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

public struct SnodeReceivedMessage: CustomDebugStringConvertible {
    public let info: SnodeReceivedMessageInfo
    public let data: Data
    
    init?(snode: Snode, publicKey: String, rawMessage: JSON) {
        guard let hash: String = rawMessage["hash"] as? String else { return nil }

        guard
            let base64EncodedString: String = rawMessage["data"] as? String,
            let data: Data = Data(base64Encoded: base64EncodedString)
        else {
            SNLog("Failed to decode data for message: \(rawMessage).")
            return nil
        }
        
        self.info = SnodeReceivedMessageInfo(
            snode: snode,
            publicKey: publicKey,
            hash: hash,
            expirationDateMs: rawMessage["expiration"] as? Int64
        )
        self.data = data
    }
    
    public var debugDescription: String {
        return "{\"hash\":\(info.hash),\"expiration\":\(info.expirationDateMs),\"data\":\"\(data.base64EncodedString())\"}"
    }
}
