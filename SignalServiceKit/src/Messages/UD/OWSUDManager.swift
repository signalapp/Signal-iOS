//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalMetadataKit
import SignalCoreKit

public enum OWSUDError: Error {
    case assertionError(description: String)
}

@objc public protocol OWSUDManager: class {

    @objc func setup()

    // MARK: - Recipient state

    @objc func isUDRecipientId(_ recipientId: String) -> Bool

    // No-op if this recipient id is already marked as a "UD recipient".
    @objc func addUDRecipientId(_ recipientId: String)

    // No-op if this recipient id is already marked as _NOT_ a "UD recipient".
    @objc func removeUDRecipientId(_ recipientId: String)
}

// MARK: -

@objc
public class OWSUDManagerImpl: NSObject, OWSUDManager {

    private let dbConnection: YapDatabaseConnection

    private let kUDRecipientModeCollection = "kUDRecipientModeCollection"
    private let kUDCollection = "kUDCollection"
    private let kUDCurrentSenderCertificateKey = "kUDCurrentSenderCertificateKey"

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

    // MARK: - Singletons

    private var networkManager: TSNetworkManager {
        return SSKEnvironment.shared.networkManager
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
        return nil
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
        return Promise { fulfill, reject in
            // If there is a valid cached sender certificate, use that.
            if let certificateData = senderCertificate() {
                fulfill(certificateData)
                return
            }
            // Try to obtain a new sender certificate.
            requestSenderCertificate()
                .then(execute: { certificateData in
                    fulfill(certificateData)
                })
                .catch(execute: { (error) in
                    reject(error)
                })
        }
    }

    private func requestSenderCertificate() -> Promise<Data> {
        return Promise { fulfill, reject in
            let request = OWSRequestFactory.udSenderCertificateRequest()
            self.networkManager.makeRequest(
                request,
                success: { (_: URLSessionDataTask?, responseObject: Any?) -> Void in
                    do {
                        let certificateData = try self.parseSenderCertificateResponse(responseObject: responseObject)

                        guard self.isValidCertificate(certificateData: certificateData) else {
                            reject (OWSUDError.assertionError(description: "Invalid sender certificate returned by server"))
                            return
                        }

                        // Cache the current sender certificate.
                        self.setSenderCertificate(certificateData)

                        fulfill(certificateData)
                    } catch {
                        reject(error)
                    }
            },
                failure: { (_: URLSessionDataTask?, error: Error?) in
                    guard let error = error else {
                        Logger.error("Missing error.")
                        return
                    }

                    reject(error)
            })
        }
    }

    private func parseSenderCertificateResponse(responseObject: Any?) throws -> Data {
        guard let parser = ParamParser(responseObject: responseObject) else {
            throw OWSUDError.assertionError(description: "Invalid sender certificate response")
        }

        return try parser.requiredBase64EncodedData(key: "certificate")
    }

    private func isValidCertificate(certificateData: Data) -> Bool {
        do {
            let certificate = try SMKSenderCertificate.parse(data: certificateData)
            let expirationDate = NSDate.ows_date(withMillisecondsSince1970: certificate.expirationTimestamp)
            // TODO: What's the cutoff for rotating your sender cert?  A day or two before expiration?
            return (expirationDate as NSDate).isAfterNow()
        } catch {
            OWSLogger.error("Certificate could not be parsed: \(error)")
            return false
        }
    }
}
