//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

private let kCoderPreKeyId = "kCoderPreKeyId"
private let kCoderPreKeyPair = "kCoderPreKeyPair"
private let kCoderCreatedAt = "kCoderCreatedAt"

@objc(PreKeyRecord)
public class PreKeyRecord: NSObject, NSSecureCoding {
    public class var supportsSecureCoding: Bool { true }

    public let id: Int32
    public let keyPair: ECKeyPair
    public private(set) var createdAt: Date?

    public init(id: Int32, keyPair: ECKeyPair, createdAt: Date?) {
        self.id = id
        self.keyPair = keyPair
        self.createdAt = createdAt
    }

    public required convenience init?(coder: NSCoder) {
        let id = coder.decodeInt32(forKey: kCoderPreKeyId)
        guard let keyPair = coder.decodeObject(of: ECKeyPair.self, forKey: kCoderPreKeyPair) else {
            return nil
        }
        let createdAt = coder.decodeObject(of: NSDate.self, forKey: kCoderCreatedAt) as Date?
        self.init(id: id, keyPair: keyPair, createdAt: createdAt)
    }

    public func encode(with coder: NSCoder) {
        coder.encode(id, forKey: kCoderPreKeyId)
        coder.encode(keyPair, forKey: kCoderPreKeyPair)
        if let createdAt {
            coder.encode(createdAt, forKey: kCoderCreatedAt)
        }
    }

    public func setCreatedAtToNow() {
        createdAt = Date()
    }
}
