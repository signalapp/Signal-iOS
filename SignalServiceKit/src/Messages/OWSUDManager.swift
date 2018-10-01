//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public enum OWSUDError: Error {
    case assertionError(description: String)
}

@objc public protocol OWSUDManager: class {

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
    private let kUDCurrentServerCertificateKey = "kUDCurrentServerCertificateKey"

    @objc
    public required init(primaryStorage: OWSPrimaryStorage) {
        self.dbConnection = primaryStorage.newDatabaseConnection()

        super.init()

        SwiftSingletons.register(self)
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

    // MARK: - Server Certificate

    #if DEBUG
    @objc
    public func hasServerCertificate() -> Bool {
        return serverCertificate() != nil
    }
    #endif

    private func serverCertificate() -> Data? {
        guard let certificateData = dbConnection.object(forKey: kUDCurrentServerCertificateKey, inCollection: kUDCollection) as? Data else {
            return nil
        }
        // TODO: Parse certificate and ensure that it is still valid.
        return certificateData
    }

    private func setServerCertificate(_ certificateData: Data) {
        dbConnection.setObject(certificateData, forKey: kUDCurrentServerCertificateKey, inCollection: kUDCollection)
    }

    @objc
    public func ensureServerCertificateObjC(success:@escaping (Data) -> Void,
                                        failure:@escaping (Error) -> Void) {
        ensureServerCertificate()
            .then(execute: { certificateData in
                success(certificateData)
            })
            .catch(execute: { (error) in
                failure(error)
            }).retainUntilComplete()
    }

    public func ensureServerCertificate() -> Promise<Data> {
        return Promise { fulfill, reject in
            // If there is an existing server certificate, use that.
            if let certificateData = serverCertificate() {
                fulfill(certificateData)
                return
            }
            // Try to obtain a new server certificate.
            requestServerCertificate()
                .then(execute: { certificateData in
                    fulfill(certificateData)
                })
                .catch(execute: { (error) in
                    reject(error)
                })
        }
    }

    private func requestServerCertificate() -> Promise<Data> {
        return Promise { fulfill, reject in
            let request = OWSRequestFactory.udServerCertificateRequest()
            self.networkManager.makeRequest(
                request,
                success: { (_: URLSessionDataTask?, responseObject: Any?) -> Void in
                    do {
                        let certificateData = try self.parseServerCertificateResponse(responseObject: responseObject)

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

    private func parseServerCertificateResponse(responseObject: Any?) throws -> Data {
        guard let parser = ParamParser(responseObject: responseObject) else {
            throw OWSUDError.assertionError(description: "Invalid server certificate response")
        }

        return try parser.requiredBase64EncodedData(key: "certificate")
    }
}
