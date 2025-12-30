//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - MessageStickerDraft

public class MessageStickerDraft {
    public let info: StickerInfo

    public var packId: Data {
        return info.packId
    }

    public var packKey: Data {
        return info.packKey
    }

    public var stickerId: UInt32 {
        return info.stickerId
    }

    public let stickerData: Data

    public let stickerType: StickerType

    public let emoji: String?

    public init(info: StickerInfo, stickerData: Data, stickerType: StickerType, emoji: String?) {
        self.info = info
        self.stickerData = stickerData
        self.stickerType = stickerType
        self.emoji = emoji
    }
}

// MARK: - MessageSticker

@objc
public final class MessageSticker: NSObject, NSCoding, NSCopying {
    public init?(coder: NSCoder) {
        self.emoji = coder.decodeObject(of: NSString.self, forKey: "emoji") as String?
        self.info = coder.decodeObject(of: StickerInfo.self, forKey: "info") ?? .defaultValue
    }

    public func encode(with coder: NSCoder) {
        if let emoji {
            coder.encode(emoji, forKey: "emoji")
        }
        coder.encode(self.info, forKey: "info")
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(emoji)
        hasher.combine(info)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard type(of: self) == type(of: object) else { return false }
        guard self.emoji == object.emoji else { return false }
        guard self.info == object.info else { return false }
        return true
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return self
    }

    public let info: StickerInfo

    @objc
    public var packId: Data {
        return info.packId
    }

    @objc
    public var packKey: Data {
        return info.packKey
    }

    @objc
    public var stickerId: UInt32 {
        return info.stickerId
    }

    public let emoji: String?

    public init(info: StickerInfo, emoji: String?) {
        self.info = info
        self.emoji = emoji

        super.init()
    }

    @objc
    public var isValid: Bool {
        return info.isValid()
    }

    @objc
    public class func isNoStickerError(_ error: Error) -> Bool {
        guard let error = error as? StickerError else {
            return false
        }
        return error == .noSticker
    }
}
