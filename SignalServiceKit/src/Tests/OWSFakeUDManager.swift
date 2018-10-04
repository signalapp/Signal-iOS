//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalMetadataKit

#if DEBUG

@objc
public class OWSFakeUDManager: NSObject, OWSUDManager {

    @objc public func setup() {}

    // MARK: - Recipient state

    private var udRecipientSet = Set<String>()

    @objc
    public func isUDRecipientId(_ recipientId: String) -> Bool {
        return udRecipientSet.contains(recipientId)
    }

    @objc
    public func addUDRecipientId(_ recipientId: String) {
        udRecipientSet.insert(recipientId)
    }

    @objc
    public func removeUDRecipientId(_ recipientId: String) {
        udRecipientSet.remove(recipientId)
    }

    // Returns the UD access key for a given recipient if they are
    // a UD recipient and we have a valid profile key for them.
    @objc
    public func udAccessKeyForRecipient(_ recipientId: String) -> SMKUDAccessKey? {
        guard isUDRecipientId(recipientId) else {
            return nil
        }
        guard let profileKey = Randomness.generateRandomBytes(Int32(kAES256_KeyByteLength)) else {
            // Mark as "not a UD recipient".
            removeUDRecipientId(recipientId)
            return nil
        }
        do {
            let udAccessKey = try SMKUDAccessKey(profileKey: profileKey)
            return udAccessKey
        } catch {
            Logger.error("Could not determine udAccessKey: \(error)")
            removeUDRecipientId(recipientId)
            return nil
        }
    }

    // MARK: - Server Certificate

    // Tests can control the behavior of this mock by setting this property.
    @objc public var nextSenderCertificate: SMKSenderCertificate?

    @objc public func ensureSenderCertificateObjC(success:@escaping (SMKSenderCertificate) -> Void,
                                                  failure:@escaping (Error) -> Void) {
        guard let certificate = nextSenderCertificate else {
            failure(OWSUDError.assertionError(description: "No mock server certificate"))
            return
        }
        success(certificate)
    }

    // MARK: - Unrestricted Access

    private var _shouldAllowUnrestrictedAccessLocal = false
    private var _shouldAllowUnrestrictedAccessSet = Set<String>()

    @objc
    public func shouldAllowUnrestrictedAccessLocal() -> Bool {
        return _shouldAllowUnrestrictedAccessLocal
    }

    @objc
    public func setShouldAllowUnrestrictedAccessLocal(_ value: Bool) {
        _shouldAllowUnrestrictedAccessLocal = value
    }

    @objc
    public func shouldAllowUnrestrictedAccess(recipientId: String) -> Bool {
        return _shouldAllowUnrestrictedAccessSet.contains(recipientId)
    }

    @objc
    public func setShouldAllowUnrestrictedAccess(recipientId: String, shouldAllowUnrestrictedAccess: Bool) {
        if shouldAllowUnrestrictedAccess {
            _shouldAllowUnrestrictedAccessSet.insert(recipientId)
        } else {
            _shouldAllowUnrestrictedAccessSet.remove(recipientId)
        }
    }
}

#endif
