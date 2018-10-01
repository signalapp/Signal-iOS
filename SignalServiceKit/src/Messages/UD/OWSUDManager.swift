//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalMetadataKit
import SignalCoreKit

public enum OWSUDError: Error {
    case assertionError(description: String)
    case invalidData(description: String)
}

@objc public protocol OWSUDManager: class {

    @objc func setup()

    // MARK: - Recipient state

    @objc func isUDRecipientId(_ recipientId: String) -> Bool

    // No-op if this recipient id is already marked as a "UD recipient".
    @objc func addUDRecipientId(_ recipientId: String)

    // No-op if this recipient id is already marked as _NOT_ a "UD recipient".
    @objc func removeUDRecipientId(_ recipientId: String)

    // MARK: - Sender Certificate

    // We use completion handlers instead of a promise so that message sending
    // logic can access the certificate data.
    @objc func ensureSenderCertificateObjC(success:@escaping (Data) -> Void,
                                            failure:@escaping (Error) -> Void)

    // MARK: - Unrestricted Access

    @objc func allowUnrestrictedAccess() -> Bool

    @objc func setAllowUnrestrictedAccess(_ value: Bool)
}

// MARK: -

@objc
public class OWSUDManagerImpl: NSObject, OWSUDManager {

    private let dbConnection: YapDatabaseConnection

    private let kUDRecipientModeCollection = "kUDRecipientModeCollection"
    private let kUDCollection = "kUDCollection"
    private let kUDCurrentSenderCertificateKey = "kUDCurrentSenderCertificateKey"
    private let kUDUnrestrictedAccessKey = "kUDUnrestrictedAccessKey"

    @objc
    public required init(primaryStorage: OWSPrimaryStorage) {
        self.dbConnection = primaryStorage.newDatabaseConnection()

        super.init()

        SwiftSingletons.register(self)
    }

    @objc public func setup() {
        AppReadiness.runNowOrWhenAppIsReady {
            guard TSAccountManager.isRegistered() else {
                return
            }
            self.ensureSenderCertificate().retainUntilComplete()
        }
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(registrationStateDidChange),
                                               name: .RegistrationStateDidChange,
                                               object: nil)
    }

    @objc
    func registrationStateDidChange() {
        AssertIsOnMainThread()

        ensureSenderCertificate().retainUntilComplete()
    }

    // MARK: - Recipient state

    @objc
    public func isUDRecipientId(_ recipientId: String) -> Bool {
        return dbConnection.bool(forKey: recipientId, inCollection: kUDRecipientModeCollection, defaultValue: false)
    }

    @objc
    public func addUDRecipientId(_ recipientId: String) {
        dbConnection.setBool(true, forKey: recipientId, inCollection: kUDRecipientModeCollection)
    }

    @objc
    public func removeUDRecipientId(_ recipientId: String) {
        dbConnection.removeObject(forKey: recipientId, inCollection: kUDRecipientModeCollection)
    }

    // MARK: - Sender Certificate

    #if DEBUG
    @objc
    public func hasSenderCertificate() -> Bool {
        return senderCertificate() != nil
    }
    #endif

    private func senderCertificate() -> Data? {
        guard let certificateData = dbConnection.object(forKey: kUDCurrentSenderCertificateKey, inCollection: kUDCollection) as? Data else {
            return nil
        }

        guard isValidCertificate(certificateData: certificateData) else {
            Logger.warn("Current sender certificate is not valid.")
            return nil
        }

        return certificateData
    }

    private func setSenderCertificate(_ certificateData: Data) {
        dbConnection.setObject(certificateData, forKey: kUDCurrentSenderCertificateKey, inCollection: kUDCollection)
    }

    @objc
    public func ensureSenderCertificateObjC(success:@escaping (Data) -> Void,
                                        failure:@escaping (Error) -> Void) {
        ensureSenderCertificate()
            .then(execute: { certificateData in
                success(certificateData)
            })
            .catch(execute: { (error) in
                failure(error)
            }).retainUntilComplete()
    }

    public func ensureSenderCertificate() -> Promise<Data> {
        // If there is a valid cached sender certificate, use that.
        if let certificateData = senderCertificate() {
            return Promise(value: certificateData)
        }
        // Try to obtain a new sender certificate.
        return requestSenderCertificate().then { (certificateData) in
            // Cache the current sender certificate.
            self.setSenderCertificate(certificateData)

            return Promise(value: certificateData)
        }
    }

    private func requestSenderCertificate() -> Promise<Data> {
        return SignalServiceRestClient().requestUDSenderCertificate().then { (certificateData) in
            guard self.isValidCertificate(certificateData: certificateData) else {
                throw OWSUDError.invalidData(description: "Invalid sender certificate returned by server")
            }

            return Promise(value: certificateData)
        }
    }

    private func isValidCertificate(certificateData: Data) -> Bool {
        do {
            let certificate = try SMKSenderCertificate.parse(data: certificateData)
            let expirationMs = certificate.expirationTimestamp
            let nowMs = NSDate.ows_millisecondTimeStamp()
            // Ensure that the certificate will not expire in the next hour.
            // We want a threshold long enough to ensure that any outgoing message
            // sends will complete before the expiration.
            let isValid = nowMs + kHourInMs < expirationMs
            return isValid
        } catch {
            OWSLogger.error("Certificate could not be parsed: \(error)")
            return false
        }
    }

    // MARK: - Unrestricted Access

    @objc
    public func allowUnrestrictedAccess() -> Bool {
        return dbConnection.bool(forKey: kUDUnrestrictedAccessKey, inCollection: kUDRecipientModeCollection, defaultValue: false)
    }

    @objc
    public func setAllowUnrestrictedAccess(_ value: Bool) {
        dbConnection.setBool(value, forKey: kUDUnrestrictedAccessKey, inCollection: kUDRecipientModeCollection)
    }
}
