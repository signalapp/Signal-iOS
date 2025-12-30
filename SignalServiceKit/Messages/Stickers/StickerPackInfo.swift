//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(StickerPackInfo)
public final class StickerPackInfo: NSObject, NSCoding, NSCopying {
    public init?(coder: NSCoder) {
        self.packId = coder.decodeObject(of: NSData.self, forKey: "packId") as Data?
        self.packKey = coder.decodeObject(of: NSData.self, forKey: "packKey") as Data?
    }

    public func encode(with coder: NSCoder) {
        if let packId {
            coder.encode(packId, forKey: "packId")
        }
        if let packKey {
            coder.encode(packKey, forKey: "packKey")
        }
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(packId)
        hasher.combine(packKey)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard type(of: self) == type(of: object) else { return false }
        guard self.packId == object.packId else { return false }
        guard self.packKey == object.packKey else { return false }
        return true
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return self
    }

    @objc
    public let packId: Data!
    @objc
    public let packKey: Data!

    @objc
    public init(packId: Data, packKey: Data) {
        owsPrecondition(!packId.isEmpty && packKey.count == StickerManager.packKeyLength)
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
            return nil
        }
        guard let packKeyHex, !packKeyHex.isEmpty else {
            Logger.warn("Invalid packKeyHex")
            return nil
        }
        return parse(packId: Data.data(fromHex: packIdHex), packKey: Data.data(fromHex: packKeyHex))
    }

    public class func parse(packId: Data?, packKey: Data?) -> StickerPackInfo? {
        guard let packId, !packId.isEmpty else {
            Logger.warn("Invalid packId")
            return nil
        }
        guard let packKey, packKey.count == StickerManager.packKeyLength else {
            Logger.warn("Invalid packKey")
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

    override public var description: String { packId.hexadecimalString }
}
