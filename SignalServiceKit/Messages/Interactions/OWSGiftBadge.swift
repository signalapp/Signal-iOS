//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public enum GiftBadgeError: Error {
    case noGiftBadge
    case malformed
}

@objc
public enum OWSGiftBadgeRedemptionState: Int {
    case pending = 1
    case redeemed = 2
    case opened = 3
    // TODO: (GB) Add a failure state.
}

@objc
public final class OWSGiftBadge: NSObject, NSCoding, NSCopying {
    public init?(coder: NSCoder) {
        self.redemptionCredential = coder.decodeObject(of: NSData.self, forKey: "redemptionCredential") as Data?
        self.redemptionState = (coder.decodeObject(of: NSNumber.self, forKey: "redemptionState")?.intValue).flatMap(OWSGiftBadgeRedemptionState.init(rawValue:)) ?? .pending
    }

    public func encode(with coder: NSCoder) {
        if let redemptionCredential {
            coder.encode(redemptionCredential, forKey: "redemptionCredential")
        }
        coder.encode(NSNumber(value: self.redemptionState.rawValue), forKey: "redemptionState")
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(redemptionCredential)
        hasher.combine(redemptionState)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard type(of: self) == type(of: object) else { return false }
        guard self.redemptionCredential == object.redemptionCredential else { return false }
        guard self.redemptionState == object.redemptionState else { return false }
        return true
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return Self(
            redemptionCredential: redemptionCredential,
            redemptionState: redemptionState,
        )
    }

    @objc
    public let redemptionCredential: Data?
    public var redemptionState: OWSGiftBadgeRedemptionState

    public convenience init(redemptionCredential: Data) {
        self.init(
            redemptionCredential: redemptionCredential,
            redemptionState: .pending,
        )
    }

    private init(
        redemptionCredential: Data?,
        redemptionState: OWSGiftBadgeRedemptionState,
    ) {
        self.redemptionCredential = redemptionCredential
        self.redemptionState = redemptionState

        super.init()
    }

    public func getReceiptCredentialPresentation() throws -> ReceiptCredentialPresentation {
        guard let rcPresentationData = self.redemptionCredential else {
            throw GiftBadgeError.malformed
        }
        return try ReceiptCredentialPresentation(contents: rcPresentationData)
    }

    public struct Level: Hashable {
        public var rawLevel: UInt64

        public static let signalGift = Level(rawLevel: 100)
    }

    public func getReceiptDetails() throws -> (level: Level, expirationTime: Date) {
        let rcPresentation = try self.getReceiptCredentialPresentation()

        let receiptLevel = Level(rawLevel: try rcPresentation.getReceiptLevel())
        let receiptExpiration = try rcPresentation.getReceiptExpirationTime()

        return (receiptLevel, Date(timeIntervalSince1970: TimeInterval(receiptExpiration)))
    }

    // MARK: -

    public class func restoreFromBackup(
        receiptCredentialPresentation: Data?,
        redemptionState: OWSGiftBadgeRedemptionState,
    ) -> OWSGiftBadge {
        return OWSGiftBadge(
            redemptionCredential: receiptCredentialPresentation,
            redemptionState: redemptionState,
        )
    }

    // MARK: -

    @objc(maybeBuildFromDataMessage:)
    public class func maybeBuild(from dataMessage: SSKProtoDataMessage) -> OWSGiftBadge? {
        do {
            return try self.build(from: dataMessage)
        } catch GiftBadgeError.noGiftBadge {
            // this isn't an error -- it will be codepath for all non-gift messages
            return nil
        } catch {
            Logger.warn("Couldn't parse incoming gift badge: \(error)")
            return nil
        }
    }

    private class func build(from dataMessage: SSKProtoDataMessage) throws -> OWSGiftBadge {
        guard let giftBadge = dataMessage.giftBadge else {
            throw GiftBadgeError.noGiftBadge
        }
        guard let rcPresentationData = giftBadge.receiptCredentialPresentation else {
            throw GiftBadgeError.malformed
        }
        let result = OWSGiftBadge(redemptionCredential: rcPresentationData)
        // If we can't parse the details, drop the message.
        _ = try result.getReceiptDetails()
        return result
    }
}
