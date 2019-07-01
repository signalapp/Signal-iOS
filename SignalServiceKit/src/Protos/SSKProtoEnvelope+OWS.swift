//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension SSKProtoEnvelope {
    var hasValidSource: Bool {
        return sourceAddress != nil
    }

    var sourceAddress: SignalServiceAddress? {
        let uuidString: String? = {
            guard hasSourceUuid else {
                return nil
            }

            guard let sourceUuid = sourceUuid else {
                owsFailDebug("sourceUuid was unexpectedly nil")
                return nil
            }

            return sourceUuid
        }()

        let phoneNumber: String? = {
            guard hasSourceE164 else {
                // Shouldn't happen in prod yet
                assert(FeatureFlags.allowUUIDOnlyContacts)
                return nil
            }

            guard let sourceE164 = sourceE164 else {
                owsFailDebug("sourceE164 was unexpectedly nil")
                return nil
            }

            guard sourceE164.count > 0 else {
                owsFailDebug("sourceE164 was unexpectedly empty")
                return nil
            }

            return sourceE164
        }()

        let address = SignalServiceAddress(uuidString: uuidString, phoneNumber: phoneNumber)
        guard address.isValid else {
            owsFailDebug("address was unexpectedly invalid")
            return nil
        }

        return address
    }
}
