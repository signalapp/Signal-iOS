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

    // MARK: - Passphrases & Entropy

    public static func passphrase(forPaymentsEntropy paymentsEntropy: Data) throws -> PaymentsPassphrase {
        guard paymentsEntropy.count == PaymentsConstants.paymentsEntropyLength else {
            throw PaymentsError.invalidEntropy
        }
        let result = MobileCoin.Mnemonic.mnemonic(fromEntropy: paymentsEntropy)
        switch result {
        case .success(let mnemonic):
            return try PaymentsPassphrase.parse(passphrase: mnemonic)
        case .failure(let error):
            owsFailDebug("Error: \(error)")
            let error = Self.convertMCError(error: error)
            throw error
        }
    }

    public static func paymentsEntropy(forPassphrase passphrase: PaymentsPassphrase) throws -> Data {
        let mnemonic = passphrase.asPassphrase
        let result = MobileCoin.Mnemonic.entropy(fromMnemonic: mnemonic)
        switch result {
        case .success(let paymentsEntropy):
            guard paymentsEntropy.count == PaymentsConstants.paymentsEntropyLength else {
                throw PaymentsError.invalidEntropy
            }
            return paymentsEntropy
        case .failure(let error):
            owsFailDebug("Error: \(error)")
            let error = Self.convertMCError(error: error)
            throw error
        }
    }

    public static func mcRootEntropy(forPaymentsEntropy paymentsEntropy: Data) throws -> Data {
        guard paymentsEntropy.count == PaymentsConstants.paymentsEntropyLength else {
            throw PaymentsError.invalidEntropy
        }
        let passphrase = try Self.passphrase(forPaymentsEntropy: paymentsEntropy)
        let mnemonic = passphrase.asPassphrase
        let result = AccountKey.rootEntropy(fromMnemonic: mnemonic, accountIndex: 0)
        switch result {
        case .success(let mcRootEntropy):
            guard mcRootEntropy.count == PaymentsConstants.mcRootEntropyLength else {
                throw PaymentsError.invalidEntropy
            }
            return mcRootEntropy
        case .failure(let error):
            owsFailDebug("Error: \(error)")
            let error = Self.convertMCError(error: error)
            throw error
        }
    }

    public static func isValidPassphraseWord(_ word: String?) -> Bool {
        guard let word = word?.strippedOrNil else {
            return false
        }
        return !MobileCoin.Mnemonic.words(matchingPrefix: word).isEmpty
    }

    // MARK: -

    private let mcRootEntropy: Data

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
    private static let timeoutDuration: TimeInterval = 60

    public let localAccount: MobileCoinAccount

    private let client: MobileCoinClient

    private init(mcRootEntropy: Data,
                 localAccount: MobileCoinAccount,
                 client: MobileCoinClient) throws {

        guard mcRootEntropy.count == PaymentsConstants.mcRootEntropyLength else {
            throw PaymentsError.invalidEntropy
        }

        owsAssertDebug(Self.payments.arePaymentsEnabled)

        self.mcRootEntropy = mcRootEntropy
        self.localAccount = localAccount
        self.client = client
    }

    // MARK: -

    public static func configureSDKLogging() {
        if DebugFlags.internalLogging {
            MobileCoinLogging.logSensitiveData = true
        }
    }

    // MARK: -

    public static func buildLocalAccount(mcRootEntropy: Data) throws -> MobileCoinAccount {
        try Self.buildAccount(forMCRootEntropy: mcRootEntropy)
    }

    private static func parseAuthorizationResponse(responseObject: Any?) throws -> OWSAuthorization {
        guard let params = ParamParser(responseObject: responseObject) else {
            throw OWSAssertionError("Invalid responseObject.")
        }
        let username: String = try params.required(key: "username")
        let password: String = try params.required(key: "password")
        return OWSAuthorization(username: username, password: password)
    }

    public static func buildPromise(mcRootEntropy: Data) -> Promise<MobileCoinAPI> {
        firstly(on: .global()) { () -> Promise<TSNetworkManager.Response> in
            let request = OWSRequestFactory.paymentsAuthenticationCredentialRequest()
            return Self.networkManager.makePromise(request: request)
        }.map(on: .global()) { (_: URLSessionDataTask, responseObject: Any?) -> OWSAuthorization in
            try Self.parseAuthorizationResponse(responseObject: responseObject)
        }.map(on: .global()) { (signalAuthorization: OWSAuthorization) -> MobileCoinAPI in
            let localAccount = try Self.buildAccount(forMCRootEntropy: mcRootEntropy)
            let client = try localAccount.buildClient(signalAuthorization: signalAuthorization)
            return try MobileCoinAPI(mcRootEntropy: mcRootEntropy,
                                     localAccount: localAccount,
                                     client: client)
        }
    }

    // MARK: -

    struct MobileCoinNetworkConfig {
        let consensusUrl: String
        let fogUrl: String

        static var signalMainNet: MobileCoinNetworkConfig {
            owsFail("TODO: Set this value.")
        }

        static var mobileCoinMainNet: MobileCoinNetworkConfig {
            owsFail("TODO: Set this value.")
        }

        static var signalTestNet: MobileCoinNetworkConfig {
            let consensusUrl = "mc://node1.test.mobilecoin.com"
            let fogUrl = "fog://service.fog.mob.staging.namda.net"
            return MobileCoinNetworkConfig(consensusUrl: consensusUrl, fogUrl: fogUrl)
        }

        static var mobileCoinTestNet: MobileCoinNetworkConfig {
            let consensusUrl = "mc://node1.test.mobilecoin.com"
            let fogUrl = "fog://fog.test.mobilecoin.com"
            return MobileCoinNetworkConfig(consensusUrl: consensusUrl, fogUrl: fogUrl)
        }

        static var mobileCoinAlphaNet: MobileCoinNetworkConfig {
            let consensusUrl = "mc://consensus.alpha.mobilecoin.com"
            let fogUrl = "fog://fog.alpha.mobilecoin.com"
            return MobileCoinNetworkConfig(consensusUrl: consensusUrl, fogUrl: fogUrl)
        }

        static var mobileCoinMobileDev: MobileCoinNetworkConfig {
            let consensusUrl = "mc://consensus.mobiledev.mobilecoin.com"
            let fogUrl = "fog://fog.mobiledev.mobilecoin.com"
            return MobileCoinNetworkConfig(consensusUrl: consensusUrl, fogUrl: fogUrl)
        }

        static func networkConfig(environment: Environment) -> MobileCoinNetworkConfig {
            switch environment {
            case .mobileCoinAlphaNet:
                return MobileCoinNetworkConfig.mobileCoinAlphaNet
            case .mobileCoinMobileDev:
                return MobileCoinNetworkConfig.mobileCoinMobileDev
            case .mobileCoinTestNet:
                return MobileCoinNetworkConfig.mobileCoinTestNet
            case .signalTestNet:
                return MobileCoinNetworkConfig.signalTestNet
            case .mobileCoinMainNet:
                return MobileCoinNetworkConfig.mobileCoinMainNet
            case .signalMainNet:
                return MobileCoinNetworkConfig.signalMainNet
            }
        }
    }

    private struct AttestationInfo {
        let productId: UInt16
        let minimumSecurityVersion: UInt16
        let allowedConfigAdvisories: [String]
        let allowedHardeningAdvisories: [String]

        static let CONSENSUS_PRODUCT_ID: UInt16 = 1
        static let CONSENSUS_SECURITY_VERSION: UInt16 = 1
        static let FOG_VIEW_PRODUCT_ID: UInt16 = 3
        static let FOG_VIEW_SECURITY_VERSION: UInt16 = 1
        static let FOG_LEDGER_PRODUCT_ID: UInt16 = 2
        static let FOG_LEDGER_SECURITY_VERSION: UInt16 = 1
        static let FOG_REPORT_PRODUCT_ID: UInt16 = 4
        static let FOG_REPORT_SECURITY_VERSION: UInt16 = 1

        static var allowedHardeningAdvisories: [String] { ["INTEL-SA-00334"] }

        init(productId: UInt16,
             minimumSecurityVersion: UInt16,
             allowedConfigAdvisories: [String] = [],
             allowedHardeningAdvisories: [String] = []) {

            self.productId = productId
            self.minimumSecurityVersion = minimumSecurityVersion
            self.allowedConfigAdvisories = allowedConfigAdvisories
            self.allowedHardeningAdvisories = allowedHardeningAdvisories
        }

        static var consensus: AttestationInfo {
            .init(productId: CONSENSUS_PRODUCT_ID,
                  minimumSecurityVersion: CONSENSUS_SECURITY_VERSION,
                  allowedHardeningAdvisories: Self.allowedHardeningAdvisories)
        }

        static var fogView: AttestationInfo {
            .init(productId: FOG_VIEW_PRODUCT_ID,
                  minimumSecurityVersion: FOG_VIEW_SECURITY_VERSION,
                  allowedHardeningAdvisories: Self.allowedHardeningAdvisories)
        }

        static var fogKeyImage: AttestationInfo {
            .init(productId: FOG_LEDGER_PRODUCT_ID,
                  minimumSecurityVersion: FOG_LEDGER_SECURITY_VERSION,
                  allowedHardeningAdvisories: Self.allowedHardeningAdvisories)
        }

        static var fogMerkleProof: AttestationInfo {
            .init(productId: FOG_LEDGER_PRODUCT_ID,
                  minimumSecurityVersion: FOG_LEDGER_SECURITY_VERSION,
                  allowedHardeningAdvisories: Self.allowedHardeningAdvisories)
        }

        static var fogReport: AttestationInfo {
            .init(productId: FOG_REPORT_PRODUCT_ID,
                  minimumSecurityVersion: FOG_REPORT_SECURITY_VERSION,
                  allowedHardeningAdvisories: Self.allowedHardeningAdvisories)
        }
    }

    private enum AttestationType {
        case mrSigner(mrSignerData: Data)
        case mrEnclave(mrEnclaveData: Data)
    }

    private struct OWSAttestationConfig {
        let consensus: Attestation
        let fogView: Attestation
        let fogKeyImage: Attestation
        let fogMerkleProof: Attestation
        let fogReport: Attestation

        private static func buildMrSigner(mrSignerData: Data,
                                          attestationInfo: AttestationInfo) throws -> MobileCoin.Attestation.MrSigner {
            let result = MobileCoin.Attestation.MrSigner.make(mrSigner: mrSignerData,
                                                              productId: attestationInfo.productId,
                                                              minimumSecurityVersion: attestationInfo.minimumSecurityVersion,
                                                              allowedConfigAdvisories: attestationInfo.allowedConfigAdvisories,
                                                              allowedHardeningAdvisories: attestationInfo.allowedHardeningAdvisories)
            switch result {
            case .success(let mrSigner):
                return mrSigner
            case .failure(let error):
                owsFailDebug("Error: \(error)")
                throw error
            }
        }

        private static func buildMrEnclave(mrEnclaveData: Data,
                                          attestationInfo: AttestationInfo) throws -> MobileCoin.Attestation.MrEnclave {
            let result = MobileCoin.Attestation.MrEnclave.make(mrEnclave: mrEnclaveData,
                                                              allowedConfigAdvisories: attestationInfo.allowedConfigAdvisories,
                                                              allowedHardeningAdvisories: attestationInfo.allowedHardeningAdvisories)
            switch result {
            case .success(let mrEnclave):
                return mrEnclave
            case .failure(let error):
                owsFailDebug("Error: \(error)")
                throw error
            }
        }

        private static func buildAttestation(attestationType: AttestationType,
                                             attestationInfo: AttestationInfo) throws -> MobileCoin.Attestation {
            switch attestationType {
            case .mrSigner(let mrSignerData):
                let mrSigner = try buildMrSigner(mrSignerData: mrSignerData,
                                                 attestationInfo: attestationInfo)
                return MobileCoin.Attestation(mrSigners: [mrSigner])
            case .mrEnclave(let mrEnclaveData):
                let mrEnclave = try buildMrEnclave(mrEnclaveData: mrEnclaveData,
                                                   attestationInfo: attestationInfo)
                return MobileCoin.Attestation(mrEnclaves: [mrEnclave])
            }
        }

        private static func buildAttestationConfig(mrSigner mrSignerData: Data) -> OWSAttestationConfig {
            do {
                let attestationType: AttestationType = .mrSigner(mrSignerData: mrSignerData)
                func _buildAttestation(attestationInfo: AttestationInfo) throws -> MobileCoin.Attestation {
                    try buildAttestation(attestationType: attestationType, attestationInfo: attestationInfo)
                }
                return OWSAttestationConfig(
                    consensus: try _buildAttestation(attestationInfo: .consensus),
                    fogView: try _buildAttestation(attestationInfo: .fogView),
                    fogKeyImage: try _buildAttestation(attestationInfo: .fogKeyImage),
                    fogMerkleProof: try _buildAttestation(attestationInfo: .fogMerkleProof),
                    fogReport: try _buildAttestation(attestationInfo: .fogReport))
            } catch {
                owsFail("Invalid attestationConfig: \(error)")
            }
        }

        private static func buildAttestationConfig(mrEnclaveConsensus: Data,
                                                   mrEnclaveFogView: Data,
                                                   mrEnclaveFogKeyImage: Data,
                                                   mrEnclaveFogMerkleProof: Data,
                                                   mrEnclaveFogReport: Data) -> OWSAttestationConfig {
            do {
                return OWSAttestationConfig(
                    consensus: try buildAttestation(attestationType: .mrEnclave(mrEnclaveData: mrEnclaveConsensus),
                                                    attestationInfo: .consensus),
                    fogView: try buildAttestation(attestationType: .mrEnclave(mrEnclaveData: mrEnclaveFogView),
                                                  attestationInfo: .fogView),
                    fogKeyImage: try buildAttestation(attestationType: .mrEnclave(mrEnclaveData: mrEnclaveFogKeyImage),
                                                      attestationInfo: .fogKeyImage),
                    fogMerkleProof: try buildAttestation(attestationType: .mrEnclave(mrEnclaveData: mrEnclaveFogMerkleProof),
                                                         attestationInfo: .fogMerkleProof),
                    fogReport: try buildAttestation(attestationType: .mrEnclave(mrEnclaveData: mrEnclaveFogReport),
                                                    attestationInfo: .fogReport)
                )
            } catch {
                owsFail("Invalid attestationConfig: \(error)")
            }
        }

        static var signalMainNet: OWSAttestationConfig {
            owsFail("TODO: Set this value.")
        }

        static var mobileCoinMainNet: OWSAttestationConfig {
            owsFail("TODO: Set this value.")
        }

        static var mobileCoinTestNet: OWSAttestationConfig {
            // These networks currently share the same attestation config.
            signalTestNet
        }

        static var signalTestNet: OWSAttestationConfig {
            let mrEnclaveConsensus = Data.data(fromHex: "cad79d32f4339f650671ce74d072ae9c1c01d84edd059bd4314932a7a8b29f3f")!
            let mrEnclaveFogView = Data.data(fromHex: "4e598799faa4bb08a3bd55c0bcda7e1d22e41151d0c591f6c2a48b3562b0881e")!
            let mrEnclaveFogIngest = Data.data(fromHex: "185875464ccd67a879d58181055383505a719b364b12d56d9bef90a40bed07ca")!
            let mrEnclaveFogLedger = Data.data(fromHex: "7330c9987f21b91313b39dcdeaa7da8da5ca101c929f5740c207742c762e6dcd")!
            return buildAttestationConfig(mrEnclaveConsensus: mrEnclaveConsensus,
                                          mrEnclaveFogView: mrEnclaveFogView,
                                          mrEnclaveFogKeyImage: mrEnclaveFogLedger,
                                          mrEnclaveFogMerkleProof: mrEnclaveFogLedger,
                                          mrEnclaveFogReport: mrEnclaveFogIngest)
        }

        static var mobileCoinAlphaNet: OWSAttestationConfig {
            let mrSigner = Data([
                126, 229, 226, 157, 116, 98, 63, 219, 198, 251, 241, 69, 75, 230, 243, 187, 11, 134, 193,
                35, 102, 183, 180, 120, 173, 19, 53, 62, 68, 222, 132, 17
            ])
            return buildAttestationConfig(mrSigner: mrSigner)
        }

        static var mobileCoinMobileDev: OWSAttestationConfig {
            let mrSigner = Data([
                191, 127, 169, 87, 166, 169, 74, 203, 88, 136, 81, 188, 135, 103, 224, 202, 87, 112, 108,
                121, 244, 252, 42, 166, 188, 185, 147, 1, 44, 60, 56, 108
            ])
            return buildAttestationConfig(mrSigner: mrSigner)
        }

        static func attestationConfig(environment: Environment) -> OWSAttestationConfig {
            switch environment {
            case .mobileCoinAlphaNet:
                return mobileCoinAlphaNet
            case .mobileCoinMobileDev:
                return mobileCoinMobileDev
            case .mobileCoinTestNet:
                return mobileCoinTestNet
            case .signalTestNet:
                return signalTestNet
            case .mobileCoinMainNet:
                return mobileCoinMainNet
            case .signalMainNet:
                return signalMainNet
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

        static var mobileCoinTestNet: OWSAuthorization {
            owsFail("TODO: Set this value.")
        }

        static var mobileCoinMainNet: OWSAuthorization {
            owsFail("TODO: Set this value.")
        }
    }

    @objc
    private class Certificates: NSObject {

        enum CertificateBundle {
            case mainApp
            case ssk
        }

        static func certificateData(forService certFilename: String,
                                    type: String,
                                    certificateBundle: CertificateBundle,
                                    verifyDer: Bool = false) -> Data {
            let bundle: Bundle = {
                switch certificateBundle {
                case .mainApp:
                    return Bundle(for: self)
                case .ssk:
                    return Bundle(for: OWSHTTPSecurityPolicy.self)
                }
            }()
            guard let filepath = bundle.path(forResource: certFilename, ofType: type) else {
                owsFail("Missing cert: \(certFilename)")
            }
            guard OWSFileSystem.fileOrFolderExists(atPath: filepath) else {
                owsFail("Missing cert: \(certFilename)")
            }
            let data = try! Data(contentsOf: URL(fileURLWithPath: filepath))
            guard !data.isEmpty else {
                owsFail("Invalid cert: \(certFilename)")
            }
            if verifyDer {
                guard let certificate = SecCertificateCreateWithData(nil, data as CFData) else {
                    owsFail("Invalid cert: \(certFilename)")
                }
                let derData = SecCertificateCopyData(certificate) as Data
                return derData
            } else {
                return data
            }
        }
    }

    @objc
    private class TrustRootCerts: NSObject {

        static func anchorCertificates_mobileCoin() -> [Data] {
            [
                Certificates.certificateData(forService: "8395", type: "der", certificateBundle: .ssk, verifyDer: true)
            ]
        }

        static func loadTrustRootCerts() -> [Data] {
            anchorCertificates_mobileCoin()
        }

        static func pinConfig(_ config: MobileCoinClient.Config,
                              environment: Environment) throws -> MobileCoinClient.Config {
            let trustRootCertDatas = loadTrustRootCerts()
            guard !trustRootCertDatas.isEmpty else {
                return config
            }

            var config = config
            switch config.setFogTrustRoots(trustRootCertDatas) {
            case .success:
                switch config.setConsensusTrustRoots(trustRootCertDatas) {
                case .success:
                    return config

                case .failure(let error):
                    owsFailDebug("Error: \(error)")
                    throw error
                }
            case .failure(let error):
                owsFailDebug("Error: \(error)")
                throw error
            }
        }
    }

    struct MobileCoinAccount {
        let environment: Environment
        let accountKey: MobileCoin.AccountKey

        fileprivate func authorization(signalAuthorization: OWSAuthorization) -> OWSAuthorization {
            switch environment {
            case .signalTestNet, .signalMainNet:
                return signalAuthorization
            case .mobileCoinAlphaNet:
                return OWSAuthorization.mobileCoinAlpha
            case .mobileCoinMobileDev:
                return OWSAuthorization.mobileCoinMobileDev
            case .mobileCoinTestNet, .mobileCoinMainNet:
                return signalAuthorization
            }
        }

        fileprivate func buildClient(signalAuthorization: OWSAuthorization) throws -> MobileCoinClient {
            Logger.info("Environment: \(environment)")
            let networkConfig = MobileCoinNetworkConfig.networkConfig(environment: environment)
            let authorization = self.authorization(signalAuthorization: signalAuthorization)
            let attestationConfig = OWSAttestationConfig.attestationConfig(environment: environment)
            let configResult = MobileCoinClient.Config.make(consensusUrl: networkConfig.consensusUrl,
                                                            consensusAttestation: attestationConfig.consensus,
                                                            fogUrl: networkConfig.fogUrl,
                                                            fogViewAttestation: attestationConfig.fogView,
                                                            fogKeyImageAttestation: attestationConfig.fogKeyImage,
                                                            fogMerkleProofAttestation: attestationConfig.fogMerkleProof,
                                                            fogReportAttestation: attestationConfig.fogReport)
            switch configResult {
            case .success(let config):
                let config = try TrustRootCerts.pinConfig(config, environment: environment)

                let clientResult = MobileCoinClient.make(accountKey: accountKey, config: config)
                switch clientResult {
                case .success(let client):
                    client.setBasicAuthorization(username: authorization.username,
                                                 password: authorization.password)
                    return client
                case .failure(let error):
                    owsFailDebug("Error: \(error)")
                    throw error
                }
            case .failure(let error):
                owsFailDebug("Error: \(error)")
                throw error
            }
        }
    }

    enum Environment {
        case mobileCoinAlphaNet
        case mobileCoinMobileDev
        case signalTestNet
        case mobileCoinTestNet
        case signalMainNet
        case mobileCoinMainNet

        static var current: Environment {
            if DebugFlags.paymentsInternalBeta {
                // TODO: Revisit. 
                #if TESTABLE_BUILD
                return .mobileCoinAlphaNet
                #else
                return .signalTestNet
                #endif
            } else {
                return .signalMainNet
            }
        }
    }

    private static func fogAuthoritySpki(environment: Environment) -> Data {
        switch environment {
        case .mobileCoinAlphaNet,
             .mobileCoinMobileDev:
            return Data(base64Encoded: "MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAyFOockvCEc9TcO1NvsiUfFVzvtDsR64UIRRUl3tBM2Bh8KBA932/Up86RtgJVnbslxuUCrTJZCV4dgd5hAo/mzuJOy9lAGxUTpwWWG0zZJdpt8HJRVLX76CBpWrWEt7JMoEmduvsCR8q7WkSNgT0iIoSXgT/hfWnJ8KGZkN4WBzzTH7hPrAcxPrzMI7TwHqUFfmOX7/gc+bDV5ZyRORrpuu+OR2BVObkocgFJLGmcz7KRuN7/dYtdYFpiKearGvbYqBrEjeo/15chI0Bu/9oQkjPBtkvMBYjyJPrD7oPP67i0ZfqV6xCj4nWwAD3bVjVqsw9cCBHgaykW8ArFFa0VCMdLy7UymYU5SQsfXrw/mHpr27Pp2Z0/7wpuFgJHL+0ARU48OiUzkXSHX+sBLov9X6f9tsh4q/ZRorXhcJi7FnUoagBxewvlfwQfcnLX3hp1wqoRFC4w1DC+ki93vIHUqHkNnayRsf1n48fSu5DwaFfNvejap7HCDIOpCCJmRVR8mVuxi6jgjOUa4Vhb/GCzxfNIn5ZYym1RuoE0TsFO+TPMzjed3tQvG7KemGFz3pQIryb43SbG7Q+EOzIigxYDytzcxOO5Jx7r9i+amQEiIcjBICwyFoEUlVJTgSpqBZGNpznoQ4I2m+uJzM+wMFsinTZN3mp4FU5UHjQsHKG+ZMCAwEAAQ==")!
        case .mobileCoinTestNet:
            return Certificates.certificateData(forService: "authority-mobilecoin-testnet", type: "pem", certificateBundle: .ssk)
        case .signalTestNet:
//            return Certificates.certificateData(forService: "authority-signal-testnet", type: "pem", certificateBundle: .ssk)
            return Data(base64Encoded: "MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAoCMq8nnjTq5EEQ4EI7yr" +
                            "ABL9P4y4h1P/h0DepWgXx+w/fywcfRSZINxbaMpvcV3uSJayExrpV1KmaS2wfASe" +
                            "YhSj+rEzAm0XUOw3Q94NOx5A/dOQag/d1SS6/QpF3PQYZTULnRFetmM4yzEnXsXc" +
                            "WtzEu0hh02wYJbLeAq4CCcPTPe2qckrbUP9sD18/KOzzNeypF4p5dQ2m/ezfxtga" +
                            "LvdUMVDVIAs2v9a5iu6ce4bIcwTIUXgX0w3+UKRx8zqowc3HIqo9yeaGn4ZOwQHv" +
                            "AJZecPmb2pH1nK+BtDUvHpvf+Y3/NJxwh+IPp6Ef8aoUxs2g5oIBZ3Q31fjS2Bh2" +
                            "gmwoVooyytEysPAHvRPVBxXxLi36WpKfk1Vq8K7cgYh3IraOkH2/l2Pyi8EYYFkW" +
                            "sLYofYogaiPzVoq2ZdcizfoJWIYei5mgq+8m0ZKZYLebK1i2GdseBJNIbSt3wCNX" +
                            "ZxyN6uqFHOCB29gmA5cbKvs/j9mDz64PJe9LCanqcDQV1U5l9dt9UdmUt7Ab1PjB" +
                            "toIFaP+u473Z0hmZdCgAivuiBMMYMqt2V2EIw4IXLASE3roLOYp0p7h0IQHb+lVI" +
                            "uEl0ZmwAI30ZmzgcWc7RBeWD1/zNt55zzhfPRLx/DfDY5Kdp6oFHWMvI2r1/oZkd" +
                            "hjFp7pV6qrl7vOyR5QqmuRkCAwEAAQ==")!

        case .mobileCoinMainNet:
            owsFail("TODO: Set this value.")
        case .signalMainNet:
            owsFail("TODO: Set this value.")
        }
    }

    // PAYMENTS TODO: Network config could theoretically differ for each account.
    class func buildAccount(forMCRootEntropy mcRootEntropy: Data) throws -> MobileCoinAccount {
        let environment = Environment.current
        let networkConfig = MobileCoinNetworkConfig.networkConfig(environment: environment)
        let accountKey = try buildAccountKey(forMCRootEntropy: mcRootEntropy,
                                             networkConfig: networkConfig)
        return MobileCoinAccount(environment: environment,
                                 accountKey: accountKey)
    }

    class func buildAccountKey(forMCRootEntropy mcRootEntropy: Data,
                               networkConfig: MobileCoinNetworkConfig) throws -> MobileCoin.AccountKey {
        let fogAuthoritySpki = Self.fogAuthoritySpki(environment: .current)
        let fogReportId = ""
        let result = MobileCoin.AccountKey.make(rootEntropy: mcRootEntropy,
                                                fogReportUrl: networkConfig.fogUrl,
                                                fogReportId: fogReportId,
                                                fogAuthoritySpki: fogAuthoritySpki)
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

    func getEstimatedFee(forPaymentAmount paymentAmount: TSPaymentAmount) throws -> TSPaymentAmount {
        Logger.verbose("")

        guard paymentAmount.isValidAmount(canBeEmpty: false) else {
            throw OWSAssertionError("Invalid amount.")
        }

        // We don't need to support amountPicoMobHigh.
        let result = client.estimateTotalFee(toSendAmount: paymentAmount.picoMob,
                                             feeLevel: Self.feeLevel)
        switch result {
        case .success(let feePicoMob):
            let fee = TSPaymentAmount(currency: .mobileCoin, picoMob: feePicoMob)
            guard fee.isValidAmount(canBeEmpty: false) else {
                throw OWSAssertionError("Invalid amount.")
            }
            Logger.verbose("Success paymentAmount: \(paymentAmount), fee: \(fee), ")
            return fee
        case .failure(let error):
            let error = Self.convertMCError(error: error)
            owsFailDebugUnlessMCNetworkFailure(error)
            throw error
        }
    }

    func maxTransactionAmount() throws -> TSPaymentAmount {
        // We don't need to support amountPicoMobHigh.
        let result = client.amountTransferable(feeLevel: Self.feeLevel)
        switch result {
        case .success(let feePicoMob):
            let paymentAmount = TSPaymentAmount(currency: .mobileCoin, picoMob: feePicoMob)
            guard paymentAmount.isValidAmount(canBeEmpty: true) else {
                throw OWSAssertionError("Invalid amount.")
            }
            Logger.verbose("Success paymentAmount: \(paymentAmount), ")
            return paymentAmount
        case .failure(let error):
            let error = Self.convertMCError(error: error)
            owsFailDebugUnlessMCNetworkFailure(error)
            throw error
        }
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
        }.map(on: .global()) { (balance: TSPaymentAmount) -> TSPaymentAmount in
            Logger.verbose("balance: \(balance.picoMob)")
            return try self.getEstimatedFee(forPaymentAmount: paymentAmount)
        }.then(on: .global()) { (estimatedFeeAmount: TSPaymentAmount) -> Promise<PreparedTransaction> in
            guard paymentAmount.isValidAmount(canBeEmpty: false) else {
                throw OWSAssertionError("Invalid amount.")
            }
            guard estimatedFeeAmount.isValidAmount(canBeEmpty: false) else {
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
                                      fee: estimatedFeeAmount.picoMob) { (result: Swift.Result<(transaction: MobileCoin.Transaction,
                                                                                                receipt: MobileCoin.Receipt),
                                                                                               TransactionPreparationError>) in
                switch result {
                case .success(let transactionAndReceipt):
                    let (transaction, receipt) = transactionAndReceipt
                    let finalFeeAmount = TSPaymentAmount(currency: .mobileCoin,
                                                         picoMob: transaction.fee)
                    owsAssertDebug(estimatedFeeAmount == finalFeeAmount)
                    let preparedTransaction = PreparedTransaction(transaction: transaction,
                                                                  receipt: receipt,
                                                                  feeAmount: finalFeeAmount)
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

    // TODO: Are we always going to use _minimum_ fee?
    private static let feeLevel: MobileCoin.FeeLevel = .minimum

    func requiresDefragmentation(forPaymentAmount paymentAmount: TSPaymentAmount) -> Promise<Bool> {
        Logger.verbose("")

        let client = self.client

        return firstly(on: .global()) { () throws -> Promise<Bool> in
            let result = client.requiresDefragmentation(toSendAmount: paymentAmount.picoMob, feeLevel: Self.feeLevel)
            switch result {
            case .success(let shouldDefragment):
                return Promise.value(shouldDefragment)
            case .failure(let error):
                let error = Self.convertMCError(error: error)
                throw error
            }
        }.timeout(seconds: Self.timeoutDuration, description: "requiresDefragmentation") { () -> Error in
            PaymentsError.timeout
        }
    }

    func prepareDefragmentationStepTransactions(forPaymentAmount paymentAmount: TSPaymentAmount) -> Promise<[MobileCoin.Transaction]> {
        Logger.verbose("")

        let client = self.client

        return firstly(on: .global()) { () throws -> Promise<[MobileCoin.Transaction]> in
            let (promise, resolver) = Promise<[MobileCoin.Transaction]>.pending()
            if DebugFlags.paymentsNoRequestsComplete.get() {
                // Never resolve.
                return promise
            }
            client.prepareDefragmentationStepTransactions(toSendAmount: paymentAmount.picoMob,
                                                          feeLevel: Self.feeLevel) { (result: Swift.Result<[MobileCoin.Transaction],
                                                                                                           MobileCoin.DefragTransactionPreparationError>) in
                switch result {
                case .success(let transactions):
                    resolver.fulfill(transactions)
                    break
                case .failure(let error):
                    let error = Self.convertMCError(error: error)
                    resolver.reject(error)
                    break
                }
            }
            return promise
        }.timeout(seconds: Self.timeoutDuration, description: "prepareDefragmentationStepTransactions") { () -> Error in
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
            client.submitTransaction(transaction) { (result: Swift.Result<Void, TransactionSubmissionError>) in
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
        return firstly(on: .global()) { () throws -> Promise<TSPaymentAmount> in
            // .status(of: transaction) requires an updated balance.
            //
            // TODO: We could improve perf when verifying multiple transactions by getting balance just once.
            self.getLocalBalance()
        }.then(on: .global()) { (_: TSPaymentAmount) -> Promise<MCOutgoingTransactionStatus> in
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

        return firstly(on: .global()) { () throws -> Promise<TSPaymentAmount> in
            // .status(of: receipt) requires an updated balance.
            //
            // TODO: We could improve perf when verifying multiple receipts by getting balance just once.
            self.getLocalBalance()
        }.map(on: .global()) { (_: TSPaymentAmount) -> MCIncomingReceiptStatus in
            let paymentAmount: TSPaymentAmount
            do {
                paymentAmount = try Self.paymentAmount(forReceipt: receipt,
                                                       localAccount: localAccount)
            } catch {
                owsFailDebug("Error: \(error)")
                return MCIncomingReceiptStatus(receiptStatus: .failed,
                                               paymentAmount: .zeroMob,
                                               txOutPublicKey: Data())
            }
            let txOutPublicKey: Data = receipt.txOutPublicKey

            let result = client.status(of: receipt)
            switch result {
            case .success(let receiptStatus):
                return MCIncomingReceiptStatus(receiptStatus: receiptStatus,
                                               paymentAmount: paymentAmount,
                                               txOutPublicKey: txOutPublicKey)
            case .failure(let error):
                let error = Self.convertMCError(error: error)
                throw error
            }
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
                Logger.warn("Error: \(error), reason: \(reason)")
                return PaymentsError.connectionFailure
            case .authorizationFailure(let reason):
                owsFailDebug("Error: \(error), reason: \(reason)")

                // Immediately discard the SDK client instance; the auth token may be stale.
                SSKEnvironment.shared.payments.didReceiveMCAuthError()

                return PaymentsError.authorizationFailure
            case .invalidServerResponse(let reason):
                owsFailDebug("Error: \(error), reason: \(reason)")
                return PaymentsError.invalidServerResponse
            case .attestationVerificationFailed(let reason):
                owsFailDebug("Error: \(error), reason: \(reason)")
                return PaymentsError.attestationVerificationFailed
            case .outdatedClient(let reason):
                owsFailDebug("Error: \(error), reason: \(reason)")
                return PaymentsError.outdatedClient
            case .serverRateLimited(let reason):
                owsFailDebug("Error: \(error), reason: \(reason)")
                return PaymentsError.serverRateLimited
            }
        case let error as MobileCoin.TransactionPreparationError:
            switch error {
            case .invalidInput(let reason):
                owsFailDebug("Error: \(error), reason: \(reason)")
                return PaymentsError.invalidInput
            case .insufficientBalance:
                Logger.warn("Error: \(error)")
                return PaymentsError.insufficientFunds
            case .defragmentationRequired:
                Logger.warn("Error: \(error)")
                return PaymentsError.defragmentationRequired
            case .connectionError(let connectionError):
                // Recurse.
                return convertMCError(error: connectionError)
            }
        case let error as MobileCoin.TransactionSubmissionError:
            switch error {
            case .connectionError(let connectionError):
                // Recurse.
                return convertMCError(error: connectionError)
            case .invalidTransaction:
                Logger.warn("Error: \(error)")
                return PaymentsError.invalidTransaction
            case .feeError:
                Logger.warn("Error: \(error)")
                return PaymentsError.invalidFee
            case .tombstoneBlockTooFar:
                Logger.warn("Error: \(error)")
                // Map to .invalidTransaction
                return PaymentsError.invalidTransaction
            case .inputsAlreadySpent:
                Logger.warn("Error: \(error)")
                return PaymentsError.inputsAlreadySpent
            }
        case let error as MobileCoin.TransactionEstimationError:
            switch error {
            case .invalidInput(let reason):
                owsFailDebug("Error: \(error), reason: \(reason)")
                return PaymentsError.invalidInput
            case .insufficientBalance:
                Logger.warn("Error: \(error)")
                return PaymentsError.insufficientFunds
            }
        case let error as MobileCoin.DefragTransactionPreparationError:
            switch error {
            case .invalidInput(let reason):
                owsFailDebug("Error: \(error), reason: \(reason)")
                return PaymentsError.invalidInput
            case .insufficientBalance:
                Logger.warn("Error: \(error)")
                return PaymentsError.insufficientFunds
            case .connectionError(let connectionError):
                // Recurse.
                return convertMCError(error: connectionError)
            }
        case let error as MobileCoin.BalanceTransferEstimationError:
            switch error {
            case .feeExceedsBalance:
                // TODO: Review this mapping.
                Logger.warn("Error: \(error)")
                return PaymentsError.insufficientFunds
            case .balanceOverflow:
                // TODO: Review this mapping.
                Logger.warn("Error: \(error)")
                return PaymentsError.insufficientFunds
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
             .missingModel,
             .defragmentationRequired,
             .invalidTransaction,
             .inputsAlreadySpent,
             .defragmentationFailed,
             .invalidPassphrase,
             .invalidEntropy,
             .killSwitch:
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

// MARK: - URLs

extension MobileCoinAPI {
    static func formatAsBase58(publicAddress: MobileCoin.PublicAddress) -> String {
        return Base58Coder.encode(publicAddress)
    }

    static func formatAsUrl(publicAddress: MobileCoin.PublicAddress) -> String {
        MobUri.encode(publicAddress)
    }

    static func parseAsPublicAddress(url: URL) -> MobileCoin.PublicAddress? {
        let result = MobUri.decode(uri: url.absoluteString)
        switch result {
        case .success(let payload):
            switch payload {
            case .publicAddress(let publicAddress):
                return publicAddress
            case .paymentRequest(let paymentRequest):
                // TODO: We could honor the amount and memo.
                return paymentRequest.publicAddress
            case .transferPayload:
                // TODO: We could handle transferPayload.
                owsFailDebug("Unexpected payload.")
                return nil
            }
        case .failure(let error):
            let error = Self.convertMCError(error: error)
            owsFailDebugUnlessMCNetworkFailure(error)
            return nil
        }
    }

    static func parse(publicAddressBase58 base58: String) -> MobileCoin.PublicAddress? {
        // TODO: Replace with SDK method when available.
        guard let result = Base58Coder.decode(base58) else {
            Logger.verbose("Invalid base58: \(base58)")
            Logger.warn("Invalid base58.")
            return nil
        }
        switch result {
        case .publicAddress(let publicAddress):
            return publicAddress
        default:
            Logger.verbose("Invalid base58: \(base58)")
            Logger.warn("Invalid base58.")
            return nil
        }
    }
}
