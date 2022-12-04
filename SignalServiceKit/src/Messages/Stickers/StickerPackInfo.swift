//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(StickerPackInfo)
public class StickerPackInfo: MTLModel {
    // Exposed to Objective-C and made optional for MTLModel serialization.
    @objc
    public var packId: Data!
    @objc
    public var packKey: Data!

    @objc
    public init(packId: Data, packKey: Data) {
        owsAssert(!packId.isEmpty && packKey.count == StickerManager.packKeyLength)
        self.packId = packId
        self.packKey = packKey

        super.init()
    }

    @objc
    public var asKey: String { packId.hexadecimalString }

    @objc(parsePackIdHex:packKeyHex:)
    public class func parse(packIdHex: String?, packKeyHex: String?) -> StickerPackInfo? {
        guard let packIdHex, !packIdHex.isEmpty else {
            Logger.warn("Invalid packIdHex")
            Logger.debug("Invalid packIdHex: \(packIdHex ?? "nil")")
            return nil
        }
        guard let packKeyHex, !packKeyHex.isEmpty else {
            Logger.warn("Invalid packKeyHex")
            Logger.debug("Invalid packKeyHex: \(packKeyHex ?? "nil")")
            return nil
        }
        return parse(packId: Data.data(fromHex: packIdHex), packKey: Data.data(fromHex: packKeyHex))
    }

    public class func parse(packId: Data?, packKey: Data?) -> StickerPackInfo? {
        guard let packId, !packId.isEmpty else {
            Logger.warn("Invalid packId")
            Logger.debug("Invalid packId: \(String(describing: packId))")
            return nil
        }
        guard let packKey, packKey.count == StickerManager.packKeyLength else {
            Logger.warn("Invalid packKey")
            Logger.debug("Invalid packKey: \(String(describing: packKey))")
            return nil
        }
        return StickerPackInfo(packId: packId, packKey: packKey)
    }

    public func shareUrl() -> String {
        let packIdHex = packId.hexadecimalString
        let packKeyHex = packKey.hexadecimalString
        return "https://signal.art/addstickers/#pack_id=\(packIdHex)&pack_key=\(packKeyHex)"
    }

    @objc(isStickerPackShareUrl:)
    public class func isStickerPackShare(_ url: URL) -> Bool {
        url.scheme == "https" &&
        url.user == nil &&
        url.password == nil &&
        url.host == "signal.art" &&
        url.port == nil &&
        url.path == "/addstickers"
    }

    @objc(parseStickerPackShareUrl:)
    public class func parseStickerPackShare(_ url: URL) -> StickerPackInfo? {
        guard
            isStickerPackShare(url),
            let components = URLComponents(string: url.absoluteString)
        else {
            owsFail("Invalid URL.")
        }

        guard
            let fragment = components.fragment,
            let queryItems = parseAsQueryItems(string: fragment)
        else {
            Logger.warn("No fragment to parse as query items")
            return nil
        }

        var packIdHex: String?
        var packKeyHex: String?
        for queryItem in queryItems {
            switch queryItem.name {
            case "pack_id":
                if packIdHex != nil {
                    Logger.warn("Duplicate pack_id. Using the newest one")
                }
                packIdHex = queryItem.value
            case "pack_key":
                if packKeyHex != nil {
                    Logger.warn("Duplicate pack_key. Using the newest one")
                }
                packKeyHex = queryItem.value
            default:
                Logger.warn("Unknown query item: \(queryItem.name)")
            }
        }

        return parse(packIdHex: packIdHex, packKeyHex: packKeyHex)
    }

    private class func parseAsQueryItems(string: String) -> [URLQueryItem]? {
        guard let fakeUrl = URL(string: "http://example.com?\(string)") else {
            return nil
        }
        return URLComponents(string: fakeUrl.absoluteString)?.queryItems
    }

    public override var description: String { packId.hexadecimalString }

    // MARK: - MTLModel

    @objc
    public override init() {
        super.init()
    }

    @objc
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    @objc
    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }
}
