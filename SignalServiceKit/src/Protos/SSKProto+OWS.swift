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

@objc
public extension SSKProtoSyncMessageRead {
    var hasValidSender: Bool {
        return senderAddress != nil
    }

    var senderAddress: SignalServiceAddress? {
        let uuidString: String? = {
            guard hasSenderUuid else {
                return nil
            }

            guard let senderUuid = senderUuid else {
                owsFailDebug("senderUuid was unexpectedly nil")
                return nil
            }

            return senderUuid
        }()

        let phoneNumber: String? = {
            guard hasSenderE164 else {
                // Shouldn't happen in prod yet
                assert(FeatureFlags.allowUUIDOnlyContacts)
                return nil
            }

            guard let senderE164 = senderE164 else {
                owsFailDebug("senderE164 was unexpectedly nil")
                return nil
            }

            guard senderE164.count > 0 else {
                owsFailDebug("senderE164 was unexpectedly empty")
                return nil
            }

            return senderE164
        }()

        let address = SignalServiceAddress(uuidString: uuidString, phoneNumber: phoneNumber)
        guard address.isValid else {
            owsFailDebug("address was unexpectedly invalid")
            return nil
        }

        return address
    }
}

@objc
public extension SSKProtoVerified {
    var hasValidDestination: Bool {
        return destinationAddress != nil
    }

    var destinationAddress: SignalServiceAddress? {
        let uuidString: String? = {
            guard hasDestinationUuid else {
                return nil
            }

            guard let destinationUuid = destinationUuid else {
                owsFailDebug("destinationUuid was unexpectedly nil")
                return nil
            }

            return destinationUuid
        }()

        let phoneNumber: String? = {
            guard hasDestinationE164 else {
                // Shouldn't happen in prod yet
                assert(FeatureFlags.allowUUIDOnlyContacts)
                return nil
            }

            guard let destinationE164 = destinationE164 else {
                owsFailDebug("destinationE164 was unexpectedly nil")
                return nil
            }

            guard destinationE164.count > 0 else {
                owsFailDebug("destinationE164 was unexpectedly empty")
                return nil
            }

            return destinationE164
        }()

        let address = SignalServiceAddress(uuidString: uuidString, phoneNumber: phoneNumber)
        guard address.isValid else {
            owsFailDebug("address was unexpectedly invalid")
            return nil
        }

        return address
    }
}
