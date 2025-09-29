//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - MessageStickerDraft

final public class MessageStickerDraft {
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
final public class MessageSticker: MTLModel {
    // MTLModel requires default values.
    @objc
    public var info = StickerInfo.defaultValue

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

    @objc
    public var emoji: String?

    public init(info: StickerInfo, emoji: String?) {
        self.info = info
        self.emoji = emoji

        super.init()
    }

    @objc
    public override init() {
        super.init()
    }

    @objc
    public required init!(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc
    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
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
