//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import LibSignalClient

public enum GiftBadgeError: Error {
    case noGiftBadge
    case featureNotEnabled
    case malformed
}

@objc
public enum OWSGiftBadgeRedemptionState: Int {
    case pending = 1
    // TODO: (GB) Add states for redeeming, redeemed, and failed.
}

@objc
public class OWSGiftBadge: MTLModel {
    @objc
    public var redemptionCredential: Data?

    @objc
    public var redemptionState: OWSGiftBadgeRedemptionState = .pending

    public init(redemptionCredential: Data) {
        self.redemptionCredential = redemptionCredential
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
        guard FeatureFlags.giftBadgeReceiving else {
            throw GiftBadgeError.featureNotEnabled
        }
        guard let rcPresentationData = giftBadge.receiptCredentialPresentation else {
            throw GiftBadgeError.malformed
        }
        // If we can't parse the credential, we should drop the message.
        let rcPresentation = try ReceiptCredentialPresentation(contents: [UInt8](rcPresentationData))

        // TODO: (GB) Validate additional fields, if necessary.
        _ = rcPresentation

        return .init(redemptionCredential: rcPresentationData)
    }
}
