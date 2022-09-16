//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class DisappearingMessageToken: MTLModel {
    @objc
    public var isEnabled: Bool {
        return durationSeconds > 0
    }

    @objc
    public var durationSeconds: UInt32 = 0

    @objc
    public init(isEnabled: Bool, durationSeconds: UInt32) {
        // Consider disabled if duration is zero.
        // Use zero duration if not enabled.
        self.durationSeconds = isEnabled ? durationSeconds : 0

        super.init()
    }

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

    // MARK: -

    @objc
    public static var disabledToken: DisappearingMessageToken {
        return DisappearingMessageToken(isEnabled: false, durationSeconds: 0)
    }

    @objc
    public class func token(forProtoExpireTimer expireTimer: UInt32) -> DisappearingMessageToken {
        if expireTimer > 0 {
            return DisappearingMessageToken(isEnabled: true, durationSeconds: expireTimer)
        } else {
            return .disabledToken
        }
    }

    @objc
    public var durationString: String {
        // This might be zero if DMs are not enabled.
        String.formatDurationLossless(durationSeconds: durationSeconds)
    }
}

// MARK: -

public extension OWSDisappearingMessagesConfiguration {
    @objc
    var asToken: DisappearingMessageToken {
        return DisappearingMessageToken(isEnabled: isEnabled, durationSeconds: durationSeconds)
    }

    @objc
    @discardableResult
    static func applyToken(_ token: DisappearingMessageToken,
                           toThread thread: TSThread,
                           transaction: SDSAnyWriteTransaction) -> OWSDisappearingMessagesConfiguration {
        let oldConfiguration = OWSDisappearingMessagesConfiguration.fetchOrBuildDefault(with: thread,
                                                                                        transaction: transaction)
        return oldConfiguration.applyToken(token, transaction: transaction)
    }

    @objc
    @discardableResult
    func applyToken(_ token: DisappearingMessageToken,
                    transaction: SDSAnyWriteTransaction) -> OWSDisappearingMessagesConfiguration {
        let newConfiguration: OWSDisappearingMessagesConfiguration
        if token.isEnabled {
            newConfiguration = self.copyAsEnabled(withDurationSeconds: token.durationSeconds)
        } else {
            newConfiguration = self.copy(withIsEnabled: false)
        }
        newConfiguration.anyUpsert(transaction: transaction)
        return newConfiguration
    }
}
