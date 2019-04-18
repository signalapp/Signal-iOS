//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class StickerPackMetadata: MTLModel {
    // MTLModel requires default values.
    @objc
    public var packId = Data()

    // MTLModel requires default values.
    @objc
    public var packKey = Data()

    @objc
    public init(packId: Data, packKey: Data) {
        self.packId = packId
        self.packKey = packKey

        super.init()
    }

    private override init() {
        super.init()
    }

    @objc
    public required init!(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc
    public required init(dictionary dictionaryValue: [AnyHashable: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    // Returns a String that can be used as a key in caches, etc.
    @objc
    public func cacheKey() -> String {
        return packId.hexadecimalString
    }
}

// MARK: - StickerMetadata

@objc
public class StickerMetadata: MTLModel {
    // MTLModel requires default values.
    @objc
    public var packId = Data()

    // MTLModel requires default values.
    @objc
    public var packKey = Data()

    // MTLModel requires default values.
    @objc
    public var stickerId: UInt32 = 0

    public static var defaultValue: StickerMetadata {
        return StickerMetadata()
    }

    @objc
    public init(packId: Data, packKey: Data, stickerId: UInt32) {
        self.packId = packId
        self.packKey = packKey
        self.stickerId = stickerId

        super.init()
    }

    // This should only be used by defaultValue.
    private override init() {
        super.init()
    }

    @objc
    public required init!(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc
    public required init(dictionary dictionaryValue: [AnyHashable: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    // Returns a String that can be used as a key in caches, etc.
    @objc
    public func cacheKey() -> String {
        return "\(packId.hexadecimalString).\(stickerId)"
    }
}
