//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

private let kCoderPreKeyId = "kCoderPreKeyId"
private let kCoderPreKeyPair = "kCoderPreKeyPair"
private let kCoderPreKeyDate = "kCoderPreKeyDate"
private let kCoderPreKeySignature = "kCoderPreKeySignature"

@objc(SignedPreKeyRecord)
public class SignedPreKeyRecord: PreKeyRecord {
    public class override var supportsSecureCoding: Bool { true }

    public let signature: Data
    public let generatedAt: Date

    public init(id: Int32, keyPair: ECKeyPair, signature: Data, generatedAt: Date) {
        self.signature = signature
        self.generatedAt = generatedAt
        super.init(id: id, keyPair: keyPair, createdAt: generatedAt)
    }

    public required convenience init?(coder: NSCoder) {
        let id = coder.decodeInt32(forKey: kCoderPreKeyId)
        guard let keyPair = coder.decodeObject(of: ECKeyPair.self, forKey: kCoderPreKeyPair),
              let signature = coder.decodeObject(of: NSData.self, forKey: kCoderPreKeySignature) as Data?,
              let generatedAt = coder.decodeObject(of: NSDate.self, forKey: kCoderPreKeyDate) as Date? else {
            return nil
        }
        self.init(id: id, keyPair: keyPair, signature: signature, generatedAt: generatedAt)
    }

    public override func encode(with coder: NSCoder) {
        coder.encode(id, forKey: kCoderPreKeyId)
        coder.encode(keyPair, forKey: kCoderPreKeyPair)
        coder.encode(signature, forKey: kCoderPreKeySignature)
        coder.encode(generatedAt, forKey: kCoderPreKeyDate)
    }
}
