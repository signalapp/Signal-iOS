//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

// See:
// https://github.com/signalapp/libsignal-protocol-java/blob/87fae0f98332e98a32bbb82515428b4edeb4181f/java/src/main/java/org/whispersystems/libsignal/ecc/DjbECPublicKey.java
@objc public class ECPublicKey: NSObject {

    @objc
    public static let keyTypeDJB: UInt8 = 0x05

    @objc
    public let keyData: Data

    @objc
    public init(keyData: Data) throws {
        guard keyData.count == ECCKeyLength else {
            throw SMKError.assertionError(description: "\(ECPublicKey.logTag) key has invalid length")
        }

        self.keyData = keyData
    }

    // https://github.com/signalapp/libsignal-protocol-java/blob/master/java/src/main/java/org/whispersystems/libsignal/ecc/Curve.java#L30
    @objc
    public init(serializedKeyData: Data) throws {
        let parser = OWSDataParser(data: serializedKeyData)

        let typeByte = try parser.nextByte(name: "type byte")
        guard typeByte == ECPublicKey.keyTypeDJB else {
            throw SMKError.assertionError(description: "\(ECPublicKey.logTag) key data has invalid type byte")
        }

        let keyData = try parser.remainder(name: "key data")
        guard keyData.count == ECCKeyLength else {
            throw SMKError.assertionError(description: "\(ECPublicKey.logTag) key has invalid length")
        }

        self.keyData = keyData
    }

    @objc public var serialized: Data {
        let typeBytes = [ECPublicKey.keyTypeDJB]
        let typeData = Data(bytes: typeBytes)
        return NSData.join([typeData, keyData])
    }

    open override func isEqual(_ object: Any?) -> Bool {
        if let object = object as? ECPublicKey {
            return keyData == object.keyData
        } else {
            return false
        }
    }

    public override var hash: Int {
        return keyData.hashValue
    }
}
