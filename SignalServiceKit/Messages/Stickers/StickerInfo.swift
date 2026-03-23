//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(StickerInfo)
public final class StickerInfo: NSObject, NSSecureCoding {

    public let packId: Data
    let packKey: Data
    public let stickerId: UInt32

    init(packId: Data, packKey: Data, stickerId: UInt32) {
        self.packId = packId
        self.packKey = packKey
        self.stickerId = stickerId
        super.init()
        owsAssertDebug(self.isValid())
    }

    public static var supportsSecureCoding: Bool { true }

    public func encode(with coder: NSCoder) {
        coder.encode(self.packId, forKey: "packId")
        coder.encode(self.packKey, forKey: "packKey")
        coder.encode(NSNumber(value: self.stickerId), forKey: "stickerId")
    }

    public init?(coder: NSCoder) {
        self.packId = coder.decodeObject(of: NSData.self, forKey: "packId") as Data? ?? Data()
        self.packKey = coder.decodeObject(of: NSData.self, forKey: "packKey") as Data? ?? Data()
        self.stickerId = coder.decodeObject(of: NSNumber.self, forKey: "stickerId")?.uint32Value ?? 0
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(self.packId)
        hasher.combine(self.packKey)
        hasher.combine(self.stickerId)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard self.packId == object.packId else { return false }
        guard self.packKey == object.packKey else { return false }
        guard self.stickerId == object.stickerId else { return false }
        return true
    }

    public func asKey() -> String {
        return StickerInfo.key(packId: self.packId, stickerId: self.stickerId)
    }

    static func key(packId: Data, stickerId: UInt32) -> String {
        return "\(packId.hexadecimalString).\(stickerId)"
    }

    static var defaultValue: StickerInfo {
        return StickerInfo(
            packId: Randomness.generateRandomBytes(16),
            packKey: Randomness.generateRandomBytes(StickerManager.packKeyLength),
            stickerId: 0,
        )
    }

    public var packInfo: StickerPackInfo {
        return StickerPackInfo(packId: self.packId, packKey: self.packKey)
    }

    func isValid() -> Bool {
        return !self.packId.isEmpty && self.packKey.count == StickerManager.packKeyLength
    }

    override public var debugDescription: String {
        return asKey()
    }
}
