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
final public class OWSGiftBadge: MTLModel {
    @objc
    public var redemptionCredential: Data?

    @objc
    public var redemptionState: OWSGiftBadgeRedemptionState = .pending

    public convenience init(redemptionCredential: Data) {
        self.init(
            redemptionCredential: redemptionCredential,
            redemptionState: .pending
        )
    }

    private init(
        redemptionCredential: Data?,
        redemptionState: OWSGiftBadgeRedemptionState
    ) {
        self.redemptionCredential = redemptionCredential
        self.redemptionState = redemptionState

        super.init()
    }

    // This may seem unnecessary, but the app crashes at runtime when calling
    // initWithCoder: if it's not present.
    @objc
    public override init() {
        super.init()
    }

    @objc
    public required init(dictionary: [String: Any]!) throws {
        try super.init(dictionary: dictionary)
    }

    @objc
    public required init!(coder: NSCoder) {
        super.init(coder: coder)
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
        redemptionState: OWSGiftBadgeRedemptionState
    ) -> OWSGiftBadge {
        return OWSGiftBadge(
            redemptionCredential: receiptCredentialPresentation,
            redemptionState: redemptionState
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
