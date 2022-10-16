// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

// MARK: - Decoding

extension Dependencies {
    static let userInfoKey: CodingUserInfoKey = CodingUserInfoKey(rawValue: "io.oxen.dependencies.codingOptions")!
}

public extension Data {
    func decoded<T: Decodable>(as type: T.Type, using dependencies: Dependencies = Dependencies()) throws -> T {
        do {
            let decoder: JSONDecoder = JSONDecoder()
            decoder.userInfo = [ Dependencies.userInfoKey: dependencies ]
            
            return try decoder.decode(type, from: self)
        }
        catch {
            throw HTTP.Error.parsingFailed
        }
    }
    
    func removePadding() -> Data {
        let bytes: [UInt8] = self.bytes
        var paddingStart: Int = self.count
        
        for i in 0..<(self.count - 1) {
            let targetIndex: Int = ((self.count - 1) - i)
            
            if bytes[targetIndex] == 0x80 {
                paddingStart = targetIndex
                break
            }
            else if bytes[targetIndex] != 0x00 {
                SNLog("Failed to remove padding, returning unstripped padding");
                return self
            }
        }
        
        return self.prefix(upTo: paddingStart)
    }
    
    func paddedMessageBody() -> Data {
        // From
        // https://github.com/signalapp/TextSecure/blob/master/libtextsecure/src/main/java/org/whispersystems/textsecure/internal/push/PushTransportDetails.java#L55
        // NOTE: This is dumb.  We have our own padding scheme, but so does the cipher.
        // The +1 -1 here is to make sure the Cipher has room to add one padding byte,
        // otherwise it'll add a full 16 extra bytes.
        let paddedMessageLength: Int = (self.paddedMessageLength(self.count + 1) - 1)
        var paddedMessage: Data = Data(count: paddedMessageLength)

        let paddingByte: UInt8 = 0x80
        paddedMessage[0..<self.count] = Data(self.bytes)
        paddedMessage[self.count..<(self.count + 1)] = Data([paddingByte])
        
        return paddedMessage
    }
    
    private func paddedMessageLength(_ unpaddedLength: Int) -> Int {
        let messageLengthWithTerminator: Int = (unpaddedLength + 1)
        var messagePartCount: Int = (messageLengthWithTerminator / 160)
        
        if CGFloat(messageLengthWithTerminator).truncatingRemainder(dividingBy: 160) != 0 {
            messagePartCount += 1
        }
        
        return (messagePartCount * 160)
    }
}
