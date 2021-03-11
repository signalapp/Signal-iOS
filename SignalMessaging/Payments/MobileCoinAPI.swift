//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import MobileCoin

class MobileCoinAPI {

    // MARK: - Dependencies

    private static var networkManager: TSNetworkManager {
        SSKEnvironment.shared.networkManager
    }

    private static var payments: PaymentsImpl {
        SSKEnvironment.shared.payments as! PaymentsImpl
    }

    // MARK: -

    private let localRootEntropy: Data

    // PAYMENTS TODO: Does the SDK define this anywhere?
    static let rootEntropyLength: UInt = 32

    // TODO: Remove.
    // account key 0
    static let rootEntropy1 = Data([16, 214, 116, 65, 134, 38, 102, 69, 76, 13, 0, 235, 66, 196, 72, 231, 213, 72, 200, 228, 134, 119, 26, 17, 67, 248, 152, 127, 208, 181, 242, 116])
    // account key 1
    static let rootEntropy2 = Data([11, 118, 31, 200, 179, 216, 12, 27, 21, 122, 249, 210, 72, 52, 107, 146, 55, 225, 11, 97, 74, 129, 220, 202, 125, 144, 185, 12, 115, 74, 103, 53])
    // account key 64
    static let rootEntropy3 = Data([3, 150, 113, 59, 157, 236, 178, 72, 70, 79, 104, 181, 127, 74, 95, 123, 230, 65, 1, 89, 80, 192, 2, 119, 15, 190, 12, 229, 37, 36, 98, 171])
    // account key 65
    static let rootEntropy4 = Data([6, 86, 175, 38, 192, 203, 175, 198, 120, 214, 16, 44, 215, 252, 214, 214, 62, 207, 193, 213, 10, 29, 240, 233, 181, 144, 120, 185, 220, 27, 17, 17])
    static let rootEntropy5 = Data([184, 0, 129, 174, 135, 82, 97, 53, 117, 91, 139, 197, 12, 89, 209, 10, 89, 222, 216, 106, 235, 28, 109, 12, 138, 167, 52, 41, 153, 161, 157, 100])
    static let rootEntropy6 = Data([74, 32, 171, 68, 50, 215, 36, 155, 1, 29, 129, 87, 119, 234, 106, 90, 245, 37, 222, 244, 12, 60, 191, 247, 76, 215, 247, 31, 137, 135, 215, 99])

    // PAYMENTS TODO: Finalize this value with the designers.
    private static let timeoutDuration: TimeInterval = 30

    public let localAccount: MobileCoinAccount

    private let client: MobileCoinClient

    private init(localRootEntropy: Data,
                 localAccount: MobileCoinAccount,
                 client: MobileCoinClient) throws {

        owsAssertDebug(Self.payments.arePaymentsEnabled)

        self.localRootEntropy = localRootEntropy
        self.localAccount = localAccount
        self.client = client
    }

    public static func buildLocalAccount(localRootEntropy: Data) throws -> MobileCoinAccount {
        try Self.buildAccount(forRootEntropy: localRootEntropy)
    }

    private static func parseAuthorizationResponse(responseObject: Any?) throws -> OWSAuthorization {
        guard let params = ParamParser(responseObject: responseObject) else {
            throw OWSAssertionError("Invalid responseObject.")
        }
        let username: String = try params.required(key: "username")
        let password: String = try params.required(key: "password")
        return OWSAuthorization(username: username, password: password)
    }

    public static func buildPromise(localRootEntropy: Data) -> Promise<MobileCoinAPI> {
        firstly(on: .global()) { () -> Promise<TSNetworkManager.Response> in
            let request = OWSRequestFactory.paymentsAuthenticationCredentialRequest()
            return Self.networkManager.makePromise(request: request)
        }.map(on: .global()) { (_: URLSessionDataTask, responseObject: Any?) -> OWSAuthorization in
            try Self.parseAuthorizationResponse(responseObject: responseObject)
        }.map(on: .global()) { (signalAuthorization: OWSAuthorization) -> MobileCoinAPI in
            let localAccount = try Self.buildAccount(forRootEntropy: localRootEntropy)
            let client = try localAccount.buildClient(signalAuthorization: signalAuthorization)
            return try MobileCoinAPI(localRootEntropy: localRootEntropy,
                                     localAccount: localAccount,
                                     client: client)
        }
    }

    // MARK: -

    struct MobileCoinNetworkConfig {
        let consensusUrl: String
        let fogViewUrl: String
        let fogLedgerUrl: String
        let fogReportUrl: String

        static var signalProduction: MobileCoinNetworkConfig {
            let consensusUrl = "mc://api.consensus.payments.namda.net:443"
            let fogViewUrl = "fog-view://api.view.payments.namda.net:443"
            let fogLedgerUrl = "fog-ledger://api.ledger.payments.namda.net:443"
            let fogReportUrl = "fog://api.report.payments.namda.net:443"

            return MobileCoinNetworkConfig(consensusUrl: consensusUrl,
                                           fogViewUrl: fogViewUrl,
                                           fogLedgerUrl: fogLedgerUrl,
                                           fogReportUrl: fogReportUrl)
        }

        static var signalStaging: MobileCoinNetworkConfig {
            let consensusUrl = "mc://ccn101.test.consensus.payments.namda.net:443"
            let fogViewUrl = "fog-view://api-staging.view.payments.namda.net:443"
            let fogLedgerUrl = "fog-ledger://api-staging.ledger.payments.namda.net:443"
            let fogReportUrl = "fog://api-staging.report.payments.namda.net:443"

            return MobileCoinNetworkConfig(consensusUrl: consensusUrl,
                                           fogViewUrl: fogViewUrl,
                                           fogLedgerUrl: fogLedgerUrl,
                                           fogReportUrl: fogReportUrl)
        }

        static var mobileCoinAlphaNet: MobileCoinNetworkConfig {
            let consensusUrl = "mc://consensus.alpha.mobilecoin.com"
            let fogViewUrl = "fog-view://fog-view.alpha.mobilecoin.com"
            let fogLedgerUrl = "fog-ledger://fog-ledger.alpha.mobilecoin.com"
            let fogReportUrl = "fog://fog-report.alpha.mobilecoin.com"

            //        let consensusUrl = "mc://node1.alpha.mobilecoin.com"
            //        let fogViewUrl = "fog-view://discovery.alpha.mobilecoin.com"
            //        let fogLedgerUrl = "fog-ledger://fog-ledger.alpha.mobilecoin.com"
            //        let fogReportUrl = "fog://discovery.alpha.mobilecoin.com"
            return MobileCoinNetworkConfig(consensusUrl: consensusUrl,
                                           fogViewUrl: fogViewUrl,
                                           fogLedgerUrl: fogLedgerUrl,
                                           fogReportUrl: fogReportUrl)
        }

        static var mobileCoinMobileDev: MobileCoinNetworkConfig {
            let consensusUrl = "mc://consensus.mobiledev.mobilecoin.com"
            let fogViewUrl = "fog-view://fog-view.mobiledev.mobilecoin.com"
            let fogLedgerUrl = "fog-ledger://fog-ledger.mobiledev.mobilecoin.com"
            let fogReportUrl = "fog://fog-report.mobiledev.mobilecoin.com"

            return MobileCoinNetworkConfig(consensusUrl: consensusUrl,
                                           fogViewUrl: fogViewUrl,
                                           fogLedgerUrl: fogLedgerUrl,
                                           fogReportUrl: fogReportUrl)
        }

        static func networkConfig(environment: Environment) -> MobileCoinNetworkConfig {
            switch environment {
            case .mobileCoinAlphaNet:
                return MobileCoinNetworkConfig.mobileCoinAlphaNet
            case .mobileCoinMobileDev:
                return MobileCoinNetworkConfig.mobileCoinMobileDev
            case .signalStaging:
                return MobileCoinNetworkConfig.signalStaging
            case .signalProduction:
                return MobileCoinNetworkConfig.signalProduction
            }
        }
    }

    struct OWSAttestationConfig {
        let consensus: Attestation
        let fogView: Attestation
        let fogKeyImage: Attestation
        let fogMerkleProof: Attestation
        let fogIngest: Attestation

        static let CONSENSUS_PRODUCT_ID: UInt16 = 1
        static let CONSENSUS_SECURITY_VERSION: UInt16 = 1
        static let FOG_VIEW_PRODUCT_ID: UInt16 = 3
        static let FOG_VIEW_SECURITY_VERSION: UInt16 = 1
        static let FOG_LEDGER_PRODUCT_ID: UInt16 = 2
        static let FOG_LEDGER_SECURITY_VERSION: UInt16 = 1
        static let FOG_INGEST_PRODUCT_ID: UInt16 = 4
        static let FOG_INGEST_SECURITY_VERSION: UInt16 = 1

        static var allowedHardeningAdvisories: [String] { ["INTEL-SA-00334"] }

        static var signalStaging: OWSAttestationConfig {
            // PAYMENTS TODO:
            let phonyMrSigner = Data([
                191, 127, 169, 87, 166, 169, 74, 203, 88, 136, 81, 188, 135, 103, 224, 202, 87, 112, 108,
                121, 244, 252, 42, 166, 188, 185, 147, 1, 44, 60, 56, 108
            ])

            do {
                return OWSAttestationConfig(
                    consensus: try Attestation(
                        mrSigner: phonyMrSigner,
                        productId: CONSENSUS_PRODUCT_ID,
                        minimumSecurityVersion: CONSENSUS_SECURITY_VERSION,
                        allowedHardeningAdvisories: allowedHardeningAdvisories),
                    fogView: try Attestation(
                        mrSigner: phonyMrSigner,
                        productId: FOG_VIEW_PRODUCT_ID,
                        minimumSecurityVersion: CONSENSUS_SECURITY_VERSION,
                        allowedHardeningAdvisories: allowedHardeningAdvisories),
                    fogKeyImage: try Attestation(
                        mrSigner: phonyMrSigner,
                        productId: FOG_LEDGER_PRODUCT_ID,
                        minimumSecurityVersion: CONSENSUS_SECURITY_VERSION,
                        allowedHardeningAdvisories: allowedHardeningAdvisories),
                    fogMerkleProof: try Attestation(
                        mrSigner: phonyMrSigner,
                        productId: FOG_LEDGER_PRODUCT_ID,
                        minimumSecurityVersion: CONSENSUS_SECURITY_VERSION,
                        allowedHardeningAdvisories: allowedHardeningAdvisories),
                    fogIngest: try Attestation(
                        mrSigner: phonyMrSigner,
                        productId: FOG_INGEST_PRODUCT_ID,
                        minimumSecurityVersion: CONSENSUS_SECURITY_VERSION,
                        allowedHardeningAdvisories: allowedHardeningAdvisories))
            } catch {
                owsFail("Invalid attestationConfig: \(error)")
            }
        }

        static var signalProduction: OWSAttestationConfig {
            // PAYMENTS TODO:
            let phonyMrSigner = Data([
                191, 127, 169, 87, 166, 169, 74, 203, 88, 136, 81, 188, 135, 103, 224, 202, 87, 112, 108,
                121, 244, 252, 42, 166, 188, 185, 147, 1, 44, 60, 56, 108
            ])

            do {
                return OWSAttestationConfig(
                    consensus: try Attestation(
                        mrSigner: phonyMrSigner,
                        productId: CONSENSUS_PRODUCT_ID,
                        minimumSecurityVersion: CONSENSUS_SECURITY_VERSION,
                        allowedHardeningAdvisories: allowedHardeningAdvisories),
                    fogView: try Attestation(
                        mrSigner: phonyMrSigner,
                        productId: FOG_VIEW_PRODUCT_ID,
                        minimumSecurityVersion: CONSENSUS_SECURITY_VERSION,
                        allowedHardeningAdvisories: allowedHardeningAdvisories),
                    fogKeyImage: try Attestation(
                        mrSigner: phonyMrSigner,
                        productId: FOG_LEDGER_PRODUCT_ID,
                        minimumSecurityVersion: CONSENSUS_SECURITY_VERSION,
                        allowedHardeningAdvisories: allowedHardeningAdvisories),
                    fogMerkleProof: try Attestation(
                        mrSigner: phonyMrSigner,
                        productId: FOG_LEDGER_PRODUCT_ID,
                        minimumSecurityVersion: CONSENSUS_SECURITY_VERSION,
                        allowedHardeningAdvisories: allowedHardeningAdvisories),
                    fogIngest: try Attestation(
                        mrSigner: phonyMrSigner,
                        productId: FOG_INGEST_PRODUCT_ID,
                        minimumSecurityVersion: CONSENSUS_SECURITY_VERSION,
                        allowedHardeningAdvisories: allowedHardeningAdvisories))
            } catch {
                owsFail("Invalid attestationConfig: \(error)")
            }
        }

        static func attestationConfig(environment: Environment) -> OWSAttestationConfig {
            switch environment {
            case .mobileCoinAlphaNet, .mobileCoinMobileDev:
                owsFail("Invalid environment: \(environment)")
            case .signalStaging:
                return signalStaging
            case .signalProduction:
                return signalProduction
            }
        }
    }

    struct OWSAuthorization {
        let username: String
        let password: String

        private static let testAuthUsername = "user1"
        private static let testAuthPassword = "user1:1602029157:9bdcd071b4d7b276a4a6"

        static var mobileCoinAlpha: OWSAuthorization {
            OWSAuthorization(username: testAuthUsername,
                             password: testAuthPassword)
        }

        static var mobileCoinMobileDev: OWSAuthorization {
            OWSAuthorization(username: testAuthUsername,
                             password: testAuthPassword)
        }
    }

    struct MobileCoinAccount {
        let environment: Environment
        let accountKey: MobileCoin.AccountKey

        fileprivate func buildClient(signalAuthorization: OWSAuthorization) throws -> MobileCoinClient {
            let networkConfig = MobileCoinNetworkConfig.networkConfig(environment: environment)
            let client: MobileCoinClient
            let authorization: OWSAuthorization
            switch environment {
            case .signalProduction, .signalStaging:
                authorization = signalAuthorization
                let attestationConfig = OWSAttestationConfig.attestationConfig(environment: environment)
                let config = try MobileCoinClient.Config(consensusUrl: networkConfig.consensusUrl,
                                                         consensusAttestation: attestationConfig.consensus,
                                                         fogViewUrl: networkConfig.fogViewUrl,
                                                         fogViewAttestation: attestationConfig.fogView,
                                                         fogLedgerUrl: networkConfig.fogLedgerUrl,
                                                         fogKeyImageAttestation: attestationConfig.fogKeyImage,
                                                         fogMerkleProofAttestation: attestationConfig.fogMerkleProof,
                                                         fogIngestAttestation: attestationConfig.fogIngest)
                client = try MobileCoinClient(accountKey: accountKey, config: config)
            case .mobileCoinAlphaNet:
                authorization = OWSAuthorization.mobileCoinAlpha
                let config = try MobileCoinClient.Config(consensusUrl: networkConfig.consensusUrl,
                                                         fogViewUrl: networkConfig.fogViewUrl,
                                                         fogLedgerUrl: networkConfig.fogLedgerUrl)
                client = try MobileCoinClient(accountKey: accountKey, config: config)
            case .mobileCoinMobileDev:
                authorization = OWSAuthorization.mobileCoinMobileDev
                let config = try MobileCoinClient.Config(consensusUrl: networkConfig.consensusUrl,
                                                         fogViewUrl: networkConfig.fogViewUrl,
                                                         fogLedgerUrl: networkConfig.fogLedgerUrl)
                client = try MobileCoinClient(accountKey: accountKey, config: config)
            }
            client.setBasicAuthorization(username: authorization.username,
                                         password: authorization.password)
            return client
        }
    }

    // PAYMENTS TODO:
    private enum DevFlags {
        static let useMobileCoinAlphaNet = DebugFlags.paymentsInternalBeta
        static let useMobileCoinMobileDev = false
    }

    enum Environment {
        case mobileCoinAlphaNet
        case mobileCoinMobileDev
        case signalStaging
        case signalProduction

        static var current: Environment {
            if DevFlags.useMobileCoinAlphaNet {
                return .mobileCoinAlphaNet
            } else if DevFlags.useMobileCoinMobileDev {
                return .mobileCoinMobileDev
            } else {
                return (FeatureFlags.isUsingProductionService
                            ? .signalProduction
                            : .signalStaging)
            }
        }
    }

    // PAYMENTS TODO: Network config could theoretically differ for each account.
    class func buildAccount(forRootEntropy rootEntropy: Data) throws -> MobileCoinAccount {
        let environment = Environment.current
        let networkConfig = MobileCoinNetworkConfig.networkConfig(environment: environment)
        let accountKey = try buildAccountKey(forRootEntropy: rootEntropy,
                                             networkConfig: networkConfig)
        return MobileCoinAccount(environment: environment,
                                 accountKey: accountKey)
    }

    class func buildAccountKey(forRootEntropy rootEntropy: Data,
                               networkConfig: MobileCoinNetworkConfig) throws -> MobileCoin.AccountKey {
        // Payments TODO:
        //
        // TODO: This is the value for alpha net.
        let fogAuthoritySpki = Data(base64Encoded: "MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAyFOockvCEc9TcO1NvsiUfFVzvtDsR64UIRRUl3tBM2Bh8KBA932/Up86RtgJVnbslxuUCrTJZCV4dgd5hAo/mzuJOy9lAGxUTpwWWG0zZJdpt8HJRVLX76CBpWrWEt7JMoEmduvsCR8q7WkSNgT0iIoSXgT/hfWnJ8KGZkN4WBzzTH7hPrAcxPrzMI7TwHqUFfmOX7/gc+bDV5ZyRORrpuu+OR2BVObkocgFJLGmcz7KRuN7/dYtdYFpiKearGvbYqBrEjeo/15chI0Bu/9oQkjPBtkvMBYjyJPrD7oPP67i0ZfqV6xCj4nWwAD3bVjVqsw9cCBHgaykW8ArFFa0VCMdLy7UymYU5SQsfXrw/mHpr27Pp2Z0/7wpuFgJHL+0ARU48OiUzkXSHX+sBLov9X6f9tsh4q/ZRorXhcJi7FnUoagBxewvlfwQfcnLX3hp1wqoRFC4w1DC+ki93vIHUqHkNnayRsf1n48fSu5DwaFfNvejap7HCDIOpCCJmRVR8mVuxi6jgjOUa4Vhb/GCzxfNIn5ZYym1RuoE0TsFO+TPMzjed3tQvG7KemGFz3pQIryb43SbG7Q+EOzIigxYDytzcxOO5Jx7r9i+amQEiIcjBICwyFoEUlVJTgSpqBZGNpznoQ4I2m+uJzM+wMFsinTZN3mp4FU5UHjQsHKG+ZMCAwEAAQ==")!
        let fogReportId = ""
        let result = MobileCoin.AccountKey.make(rootEntropy: rootEntropy,
                                                fogReportUrl: networkConfig.fogReportUrl,
                                                fogAuthoritySpki: fogAuthoritySpki,
                                                fogReportId: fogReportId)
        switch result {
        case .success(let accountKey):
            return accountKey
        case .failure(let error):
            owsFailDebug("Error: \(error)")
            throw error
        }
    }

    class func isValidMobileCoinPublicAddress(_ publicAddressData: Data) -> Bool {
        MobileCoin.PublicAddress(serializedData: publicAddressData) != nil
    }

    // MARK: -

    func getLocalBalance() -> Promise<TSPaymentAmount> {
        Logger.verbose("")

        let client = self.client

        return firstly(on: .global()) { () throws -> Promise<MobileCoin.Balance> in
            let (promise, resolver) = Promise<MobileCoin.Balance>.pending()
            if DebugFlags.paymentsNoRequestsComplete.get() {
                // Never resolve.
                return promise
            }
            client.updateBalance { (result: Swift.Result<Balance, ConnectionError>) in
                switch result {
                case .success(let balance):
                    resolver.fulfill(balance)
                case .failure(let error):
                    let error = Self.convertMCError(error: error)
                    resolver.reject(error)
                }
            }
            return promise
        }.map(on: .global()) { (balance: MobileCoin.Balance) -> TSPaymentAmount in
            Logger.verbose("Success: \(balance)")
            // We do not need to support amountPicoMobHigh.
            guard let amountPicoMob = balance.amountPicoMob() else {
                throw OWSAssertionError("Invalid balance.")
            }
            return TSPaymentAmount(currency: .mobileCoin, picoMob: amountPicoMob)
        }.recover(on: .global()) { (error: Error) -> Promise<TSPaymentAmount> in
            owsFailDebugUnlessMCNetworkFailure(error)
            throw error
        }.timeout(seconds: Self.timeoutDuration, description: "getLocalBalance") { () -> Error in
            PaymentsError.timeout
        }
    }

    func getMinimumFee(forPaymentAmount paymentAmount: TSPaymentAmount) -> Promise<TSPaymentAmount> {
        Logger.verbose("")

        let client = self.client

        return firstly(on: .global()) { () throws -> Promise<TSPaymentAmount> in
            guard paymentAmount.currency == .mobileCoin else {
                throw OWSAssertionError("Invalid currency.")
            }
            guard paymentAmount.picoMob > 0 else {
                throw OWSAssertionError("Invalid amount.")
            }

            let (promise, resolver) = Promise<TSPaymentAmount>.pending()
            if DebugFlags.paymentsNoRequestsComplete.get() {
                // Never resolve.
                return promise
            }
            // We don't need to support amountPicoMobHigh.
            //
            // TODO: Are we always going to use _minimum_ fee?
            client.minimumFee(amount: paymentAmount.picoMob) { (result: Swift.Result<UInt64, ConnectionError>) in
                switch result {
                case .success(let feePicoMob):
                    let fee = TSPaymentAmount(currency: .mobileCoin, picoMob: feePicoMob)
                    guard paymentAmount.currency == .mobileCoin,
                          fee.currency == .mobileCoin else {
                        resolver.reject(OWSAssertionError("Invalid currency."))
                        return
                    }
                    guard paymentAmount.picoMob > 0,
                          fee.picoMob > 0 else {
                        resolver.reject(OWSAssertionError("Invalid amount."))
                        return
                    }
                    Logger.verbose("Success paymentAmount: \(paymentAmount), fee: \(fee), ")
                    resolver.fulfill(fee)
                case .failure(let error):
                    let error = Self.convertMCError(error: error)
                    resolver.reject(error)
                }
            }
            return promise
        }.map(on: .global()) { (value: TSPaymentAmount) -> TSPaymentAmount in
            Logger.verbose("Success: \(value)")
            return value
        }.recover(on: .global()) { (error: Error) -> Promise<TSPaymentAmount> in
            owsFailDebugUnlessMCNetworkFailure(error)
            throw error
        }.timeout(seconds: Self.timeoutDuration, description: "prepareTransaction") { () -> Error in
            PaymentsError.timeout
        }
    }

    func getEstimatedFee(forPaymentAmount paymentAmount: TSPaymentAmount) -> Promise<TSPaymentAmount> {
        // TODO: Use proper SDK method when ready.
        getMinimumFee(forPaymentAmount: paymentAmount)
    }

    struct PreparedTransaction {
        let transaction: MobileCoin.Transaction
        let receipt: MobileCoin.Receipt
        let feeAmount: TSPaymentAmount
    }

    func prepareTransaction(paymentAmount: TSPaymentAmount,
                            recipientPublicAddress: MobileCoin.PublicAddress) -> Promise<PreparedTransaction> {
        Logger.verbose("")

        let client = self.client

        return firstly(on: .global()) { () throws -> Promise<TSPaymentAmount> in
            // prepareTransaction() will fail if local balance is not yet known.
            self.getLocalBalance()
        }.then(on: .global()) { (balance: TSPaymentAmount) -> Promise<TSPaymentAmount> in
            Logger.verbose("balance: \(balance.picoMob)")
            return self.getMinimumFee(forPaymentAmount: paymentAmount)
        }.then(on: .global()) { (feeAmount: TSPaymentAmount) -> Promise<PreparedTransaction> in
            guard paymentAmount.isValidAmount(canBeEmpty: false) else {
                throw OWSAssertionError("Invalid amount.")
            }
            guard feeAmount.isValidAmount(canBeEmpty: false) else {
                throw OWSAssertionError("Invalid fee.")
            }

            let (promise, resolver) = Promise<PreparedTransaction>.pending()
            if DebugFlags.paymentsNoRequestsComplete.get() {
                // Never resolve.
                return promise
            }
            // We don't need to support amountPicoMobHigh.
            client.prepareTransaction(to: recipientPublicAddress,
                                      amount: paymentAmount.picoMob,
                                      fee: feeAmount.picoMob) { (result: Swift.Result<(transaction: MobileCoin.Transaction,
                                                                                       receipt: MobileCoin.Receipt),
                                                                                      TransactionPreparationError>) in
                                        switch result {
                                        case .success(let transactionAndReceipt):
                                            let (transaction, receipt) = transactionAndReceipt
                                            let preparedTransaction = PreparedTransaction(transaction: transaction,
                                                                                          receipt: receipt,
                                                                                          feeAmount: feeAmount)
                                            resolver.fulfill(preparedTransaction)
                                        case .failure(let error):
                                            let error = Self.convertMCError(error: error)
                                            resolver.reject(error)
                                        }
            }
            return promise
        }.recover(on: .global()) { (error: Error) -> Promise<PreparedTransaction> in
            owsFailDebugUnlessMCNetworkFailure(error)
            throw error
        }.timeout(seconds: Self.timeoutDuration, description: "prepareTransaction") { () -> Error in
            PaymentsError.timeout
        }
    }

    func submitTransaction(transaction: MobileCoin.Transaction) -> Promise<Void> {
        Logger.verbose("")

        guard !DebugFlags.paymentsFailOutgoingSubmission.get() else {
            return Promise(error: OWSGenericError("Failed."))
        }

        return firstly(on: .global()) { () throws -> Promise<Void> in
            let (promise, resolver) = Promise<Void>.pending()
            if DebugFlags.paymentsNoRequestsComplete.get() {
                // Never resolve.
                return promise
            }
            let client = self.client
            client.submitTransaction(transaction) { (result: Swift.Result<Void, ConnectionError>) in
                switch result {
                case .success:
                    resolver.fulfill(())
                    break
                case .failure(let error):
                    let error = Self.convertMCError(error: error)
                    resolver.reject(error)
                    break
                }
            }
            return promise
        }.map(on: .global()) { () -> Void in
            Logger.verbose("Success.")
        }.recover(on: .global()) { (error: Error) -> Promise<Void> in
            owsFailDebugUnlessMCNetworkFailure(error)
            throw error
        }.timeout(seconds: Self.timeoutDuration, description: "submitTransaction") { () -> Error in
            PaymentsError.timeout
        }
    }

    func getOutgoingTransactionStatus(transaction: MobileCoin.Transaction) -> Promise<MCOutgoingTransactionStatus> {
        Logger.verbose("")

        guard !DebugFlags.paymentsFailOutgoingVerification.get() else {
            return Promise(error: OWSGenericError("Failed."))
        }

        let client = self.client
        return firstly(on: .global()) { () throws -> Promise<MCOutgoingTransactionStatus> in
            let (promise, resolver) = Promise<MCOutgoingTransactionStatus>.pending()
            if DebugFlags.paymentsNoRequestsComplete.get() {
                // Never resolve.
                return promise
            }
            client.status(of: transaction) { (result: Swift.Result<MobileCoin.TransactionStatus, ConnectionError>) in
                switch result {
                case .success(let transactionStatus):
                    resolver.fulfill(MCOutgoingTransactionStatus(transactionStatus: transactionStatus))
                    break
                case .failure(let error):
                    let error = Self.convertMCError(error: error)
                    resolver.reject(error)
                    break
                }
            }
            return promise
        }.map(on: .global()) { (value: MCOutgoingTransactionStatus) -> MCOutgoingTransactionStatus in
            Logger.verbose("Success: \(value)")
            return value
        }.recover(on: .global()) { (error: Error) -> Promise<MCOutgoingTransactionStatus> in
            owsFailDebugUnlessMCNetworkFailure(error)
            throw error
        }.timeout(seconds: Self.timeoutDuration, description: "getOutgoingTransactionStatus") { () -> Error in
            PaymentsError.timeout
        }
    }

    func paymentAmount(forReceipt receipt: MobileCoin.Receipt) throws -> TSPaymentAmount {
        try Self.paymentAmount(forReceipt: receipt, localAccount: localAccount)
    }

    static func paymentAmount(forReceipt receipt: MobileCoin.Receipt,
                              localAccount: MobileCoinAccount) throws -> TSPaymentAmount {
        guard let picoMob = receipt.validateAndUnmaskValue(accountKey: localAccount.accountKey) else {
            // This can happen if the receipt was address to a different account.
            owsFailDebug("Receipt missing amount.")
            throw PaymentsError.invalidAmount
        }
        guard picoMob > 0 else {
            owsFailDebug("Receipt has invalid amount.")
            throw PaymentsError.invalidAmount
        }
        return TSPaymentAmount(currency: .mobileCoin, picoMob: picoMob)
    }

    func getIncomingReceiptStatus(receipt: MobileCoin.Receipt) -> Promise<MCIncomingReceiptStatus> {
        Logger.verbose("")

        guard !DebugFlags.paymentsFailIncomingVerification.get() else {
            return Promise(error: OWSGenericError("Failed."))
        }

        let client = self.client
        let localAccount = self.localAccount

        return firstly(on: .global()) { () throws -> Promise<MCIncomingReceiptStatus> in
            let paymentAmount: TSPaymentAmount
            do {
                paymentAmount = try Self.paymentAmount(forReceipt: receipt,
                                                       localAccount: localAccount)
            } catch {
                owsFailDebug("Error: \(error)")
                return Promise.value(MCIncomingReceiptStatus(receiptStatus: .failed,
                                                             paymentAmount: .zeroMob,
                                                             txOutPublicKey: Data()))
            }
            let txOutPublicKey: Data = receipt.txOutPublicKey

            let (promise, resolver) = Promise<MCIncomingReceiptStatus>.pending()
            if DebugFlags.paymentsNoRequestsComplete.get() {
                // Never resolve.
                return promise
            }
            client.status(of: receipt) { (result: Swift.Result<MobileCoin.ReceiptStatus, ReceiptStatusCheckError>) in
                switch result {
                case .success(let receiptStatus):
                    resolver.fulfill(MCIncomingReceiptStatus(receiptStatus: receiptStatus,
                                                             paymentAmount: paymentAmount,
                                                             txOutPublicKey: txOutPublicKey))
                    break
                case .failure(let error):
                    let error = Self.convertMCError(error: error)
                    resolver.reject(error)
                    break
                }
            }
            return promise
        }.map(on: .global()) { (value: MCIncomingReceiptStatus) -> MCIncomingReceiptStatus in
            Logger.verbose("Success: \(value)")
            return value
        }.recover(on: .global()) { (error: Error) -> Promise<MCIncomingReceiptStatus> in
            owsFailDebugUnlessMCNetworkFailure(error)
            throw error
        }.timeout(seconds: Self.timeoutDuration, description: "getIncomingReceiptStatus") { () -> Error in
            PaymentsError.timeout
        }
    }

    func getAccountActivity() -> Promise<MobileCoin.AccountActivity> {
        Logger.verbose("")

        let client = self.client

        return firstly(on: .global()) { () throws -> Promise<MobileCoin.AccountActivity> in
            let (promise, resolver) = Promise<MobileCoin.AccountActivity>.pending()
            if DebugFlags.paymentsNoRequestsComplete.get() {
                // Never resolve.
                return promise
            }
            client.updateBalance { (result: Swift.Result<Balance, ConnectionError>) in
                switch result {
                case .success:
                    resolver.fulfill(client.accountActivity)
                case .failure(let error):
                    let error = Self.convertMCError(error: error)
                    resolver.reject(error)
                }
            }
            return promise
        }.map(on: .global()) { (accountActivity: MobileCoin.AccountActivity) -> MobileCoin.AccountActivity in
            Logger.verbose("Success: \(accountActivity.blockCount)")
            return accountActivity
        }.recover(on: .global()) { (error: Error) -> Promise<MobileCoin.AccountActivity> in
            owsFailDebugUnlessMCNetworkFailure(error)
            throw error
        }.timeout(seconds: Self.timeoutDuration, description: "getAccountActivity") { () -> Error in
            PaymentsError.timeout
        }
    }
}

// MARK: -

extension MobileCoin.PublicAddress {
    var asPaymentAddress: TSPaymentAddress {
        return TSPaymentAddress(currency: .mobileCoin,
                                mobileCoinPublicAddressData: serializedData)
    }
}

// MARK: -

extension TSPaymentAddress {
    func asPublicAddress() throws -> MobileCoin.PublicAddress {
        guard currency == .mobileCoin else {
            throw PaymentsError.invalidCurrency
        }
        guard let address = MobileCoin.PublicAddress(serializedData: mobileCoinPublicAddressData) else {
            throw OWSAssertionError("Invalid mobileCoinPublicAddressData.")
        }
        return address
    }
}

// MARK: -

struct MCIncomingReceiptStatus {
    let receiptStatus: MobileCoin.ReceiptStatus
    let paymentAmount: TSPaymentAmount
    let txOutPublicKey: Data
}

// MARK: -

struct MCOutgoingTransactionStatus {
    let transactionStatus: MobileCoin.TransactionStatus
}

// MARK: - Error Handling

extension MobileCoinAPI {
    public static func convertMCError(error: Error) -> PaymentsError {
        switch error {
        case let error as MobileCoin.InvalidInputError:
            owsFailDebug("Error: \(error)")
            return PaymentsError.invalidInput
        case let error as MobileCoin.ConnectionError:
            switch error {
            case .connectionFailure(let reason):
                Logger.warn("Error: \(error), \(reason)")
                return PaymentsError.connectionFailure
            case .authorizationFailure(let reason):
                owsFailDebug("Error: \(error), \(reason)")
                return PaymentsError.authorizationFailure
            case .invalidServerResponse(let reason):
                owsFailDebug("Error: \(error), \(reason)")
                return PaymentsError.invalidServerResponse
            case .attestationVerificationFailed(let reason):
                owsFailDebug("Error: \(error), \(reason)")
                return PaymentsError.attestationVerificationFailed
            case .outdatedClient(let reason):
                owsFailDebug("Error: \(error), \(reason)")
                return PaymentsError.outdatedClient
            case .serverRateLimited(let reason):
                owsFailDebug("Error: \(error), \(reason)")
                return PaymentsError.serverRateLimited
            }
        case let error as MobileCoin.TransactionPreparationError:
            switch error {
            case .invalidInput(let reason):
                owsFailDebug("Error: \(error), \(reason)")
                return PaymentsError.invalidInput
            case .insufficientBalance:
                Logger.warn("Error: \(error)")
                return PaymentsError.insufficientFunds
            case .connectionError(let connectionError):
                // Recurse.
                return convertMCError(error: connectionError)
            }
        case let error as MobileCoin.ReceiptStatusCheckError:
            switch error {
            case .invalidReceipt(let invalidInputError):
                // Recurse.
                return convertMCError(error: invalidInputError)
            case .connectionError(let connectionError):
                // Recurse.
                return convertMCError(error: connectionError)
            }
        default:
            owsFailDebug("Unexpected error: \(error)")
            return PaymentsError.unknownSDKError
        }
    }
}

// MARK: -

public extension PaymentsError {
    var isPaymentsNetworkFailure: Bool {
        switch self {
        case .notEnabled,
             .userNotRegisteredOrAppNotReady,
             .userHasNoPublicAddress,
             .invalidCurrency,
             .invalidWalletKey,
             .invalidAmount,
             .invalidFee,
             .insufficientFunds,
             .invalidModel,
             .tooOldToSubmit,
             .indeterminateState,
             .unknownSDKError,
             .invalidInput,
             .authorizationFailure,
             .invalidServerResponse,
             .attestationVerificationFailed,
             .outdatedClient,
             .serverRateLimited,
             .serializationError,
             .verificationStatusUnknown,
             .ledgerBlockTimestampUnknown,
             .missingModel:
            return false
        case .connectionFailure,
             .timeout:
            return true
        }
    }
}

// MARK: -

// A variant of owsFailDebugUnlessNetworkFailure() that can handle
// network failures from the MobileCoin SDK.
@inlinable
public func owsFailDebugUnlessMCNetworkFailure(_ error: Error,
                                                file: String = #file,
                                                function: String = #function,
                                                line: Int = #line) {
    if let paymentsError = error as? PaymentsError {
        if paymentsError.isPaymentsNetworkFailure {
            // Log but otherwise ignore network failures.
            Logger.warn("Error: \(error)", file: file, function: function, line: line)
        } else {
            owsFailDebug("Error: \(error)", file: file, function: function, line: line)
        }
    } else if nil != error as? OWSAssertionError {
        owsFailDebug("Unexpected error: \(error)")
    } else {
        owsFailDebugUnlessNetworkFailure(error)
    }
}
