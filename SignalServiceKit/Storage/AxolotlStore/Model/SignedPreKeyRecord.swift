//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

private let kCoderPreKeyId = "kCoderPreKeyId"
private let kCoderPreKeyPair = "kCoderPreKeyPair"
private let kCoderPreKeyDate = "kCoderPreKeyDate"
private let kCoderPreKeySignature = "kCoderPreKeySignature"
private let kCoderPreKeyReplacedAt = "kCoderReplacedAt"

// deprecated (see decodeDeprecatedPreKeys)
@objc(SignedPreKeyRecord)
public class SignedPreKeyRecord: PreKeyRecord {
    override public class var supportsSecureCoding: Bool { true }

    public let signature: Data
    public let generatedAt: Date

    public init(id: Int32, keyPair: ECKeyPair, signature: Data, generatedAt: Date, replacedAt: Date?) {
        self.signature = signature
        self.generatedAt = generatedAt
        super.init(id: id, keyPair: keyPair, createdAt: generatedAt, replacedAt: replacedAt)
    }

    public required convenience init?(coder: NSCoder) {
        let id = coder.decodeInt32(forKey: kCoderPreKeyId)
        guard
            let keyPair = coder.decodeObject(of: ECKeyPair.self, forKey: kCoderPreKeyPair),
            let signature = coder.decodeObject(of: NSData.self, forKey: kCoderPreKeySignature) as Data?,
            let generatedAt = coder.decodeObject(of: NSDate.self, forKey: kCoderPreKeyDate) as Date?
        else {
            return nil
        }
        let replacedAt = coder.decodeObject(of: NSDate.self, forKey: kCoderPreKeyReplacedAt) as Date?
        self.init(id: id, keyPair: keyPair, signature: signature, generatedAt: generatedAt, replacedAt: replacedAt)
    }

    override public func encode(with coder: NSCoder) {
        coder.encode(id, forKey: kCoderPreKeyId)
        coder.encode(keyPair, forKey: kCoderPreKeyPair)
        coder.encode(signature, forKey: kCoderPreKeySignature)
        coder.encode(generatedAt, forKey: kCoderPreKeyDate)
        if let replacedAt {
            coder.encode(replacedAt, forKey: kCoderPreKeyReplacedAt)
        }
    }
}
