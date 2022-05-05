//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

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
}
