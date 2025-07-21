//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MobileCoin
import LibMobileCoin
import SignalServiceKit

extension MobileCoinAPI {

    // MARK: - Environment

    public enum Environment: CustomStringConvertible {
        case mobileCoinAlphaNet
        case mobileCoinMobileDev
        case signalTestNet
        case mobileCoinTestNet
        case signalMainNet
        case mobileCoinMainNet

        public static var current: Environment {
            if TSConstants.isUsingProductionService {
                return .signalMainNet
            } else {
                return .signalTestNet
            }
        }

        public var description: String {
            switch self {
            case .mobileCoinAlphaNet:
                return ".mobileCoinAlphaNet"
            case .mobileCoinMobileDev:
                return ".mobileCoinMobileDev"
            case .signalTestNet:
                return ".signalTestNet"
            case .mobileCoinTestNet:
                return ".mobileCoinTestNet"
            case .signalMainNet:
                return ".signalMainNet"
            case .mobileCoinMainNet:
                return ".mobileCoinMainNet"
            }
        }
    }

    // MARK: - MobileCoinNetworkConfig

    struct MobileCoinNetworkConfig {
        let consensusUrls: [String]
        let fogUrl: String
        let fogReportUrl: String

        static var signalMainNet: MobileCoinNetworkConfig {
            let consensusUrls = [
                "mc://node1.consensus.mob.production.namda.net",
                "mc://node2.consensus.mob.production.namda.net"
            ]
            let fogUrl = "fog://fog.prod.mobilecoinww.com"
            let fogReportUrl = fogUrl
            return MobileCoinNetworkConfig(consensusUrls: consensusUrls, fogUrl: fogUrl, fogReportUrl: fogReportUrl)
        }

        static var mobileCoinMainNet: MobileCoinNetworkConfig {
            let consensusUrls = ["mc://node1.prod.mobilecoinww.com"]
            let fogUrl = "fog://fog.prod.mobilecoinww.com"
            let fogReportUrl = fogUrl
            return MobileCoinNetworkConfig(consensusUrls: consensusUrls, fogUrl: fogUrl, fogReportUrl: fogReportUrl)
        }

        static var signalTestNet: MobileCoinNetworkConfig {
            let consensusUrls = [
                "mc://node1.consensus.mob.staging.namda.net",
                "mc://node2.consensus.mob.staging.namda.net"
            ]
            let fogUrl = "fog://fog.test.mobilecoin.com"
            let fogReportUrl = fogUrl
            return MobileCoinNetworkConfig(consensusUrls: consensusUrls, fogUrl: fogUrl, fogReportUrl: fogReportUrl)
        }

        static var mobileCoinTestNet: MobileCoinNetworkConfig {
            let consensusUrls = ["mc://node1.test.mobilecoin.com"]
            let fogUrl = "fog://fog.test.mobilecoin.com"
            let fogReportUrl = fogUrl
            return MobileCoinNetworkConfig(consensusUrls: consensusUrls, fogUrl: fogUrl, fogReportUrl: fogReportUrl)
        }

        static var mobileCoinAlphaNet: MobileCoinNetworkConfig {
            let consensusUrls = ["mc://node1.alpha.development.mobilecoin.com"]
            let fogUrl = "fog://fog.alpha.development.mobilecoin.com"
            let fogReportUrl = fogUrl
            return MobileCoinNetworkConfig(consensusUrls: consensusUrls, fogUrl: fogUrl, fogReportUrl: fogReportUrl)
        }

        static var mobileCoinMobileDev: MobileCoinNetworkConfig {
            let consensusUrls = ["mc://consensus.mobiledev.mobilecoin.com"]
            let fogUrl = "fog://fog.mobiledev.mobilecoin.com"
            let fogReportUrl = fogUrl
            return MobileCoinNetworkConfig(consensusUrls: consensusUrls, fogUrl: fogUrl, fogReportUrl: fogReportUrl)
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

    // MARK: - AttestationInfo

    struct AttestationRawInfo {
        let measurement: Data
        let hardeningAdvisories: [String]

        static func of(_ measurement: Data, _ hardeningAdvisories: [String] = []) -> Self {
            return AttestationRawInfo(measurement: measurement, hardeningAdvisories: hardeningAdvisories)
        }
    }

    private struct AttestationInfo {
        let productId: UInt16
        let minimumSecurityVersion: UInt16
        let allowedConfigAdvisories: [String]
        let allowedHardeningAdvisories: [String]
        let measurement: Measurement

        enum Measurement {
            case enclave(data: Data)
            case signer(data: Data)
        }

        static let CONSENSUS_PRODUCT_ID: UInt16 = 1
        static let CONSENSUS_SECURITY_VERSION: UInt16 = 1
        static let FOG_VIEW_PRODUCT_ID: UInt16 = 3
        static let FOG_VIEW_SECURITY_VERSION: UInt16 = 1
        static let FOG_LEDGER_PRODUCT_ID: UInt16 = 2
        static let FOG_LEDGER_SECURITY_VERSION: UInt16 = 1
        static let FOG_REPORT_PRODUCT_ID: UInt16 = 4
        static let FOG_REPORT_SECURITY_VERSION: UInt16 = 1

        static var allAllowedHardeningAdvisories: [String] { ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"] }

        init(
            measurement: Measurement,
            productId: UInt16,
            minimumSecurityVersion: UInt16,
            allowedConfigAdvisories: [String] = [],
            allowedHardeningAdvisories: [String] = []
        ) {

            self.measurement = measurement
            self.productId = productId
            self.minimumSecurityVersion = minimumSecurityVersion
            self.allowedConfigAdvisories = allowedConfigAdvisories
            self.allowedHardeningAdvisories = allowedHardeningAdvisories
        }

        static func consensus(
            measurement: Measurement,
            allowedConfigAdvisories: [String] = [],
            allowedHardeningAdvisories: [String] = []
        ) -> AttestationInfo {
            .init(
                measurement: measurement,
                productId: CONSENSUS_PRODUCT_ID,
                minimumSecurityVersion: CONSENSUS_SECURITY_VERSION,
                allowedConfigAdvisories: allowedConfigAdvisories,
                allowedHardeningAdvisories: allowedHardeningAdvisories)
        }

        static func fogView(
            measurement: Measurement,
            allowedConfigAdvisories: [String] = [],
            allowedHardeningAdvisories: [String] = []
        ) -> AttestationInfo {
            .init(
                measurement: measurement,
                productId: FOG_VIEW_PRODUCT_ID,
                minimumSecurityVersion: FOG_VIEW_SECURITY_VERSION,
                allowedConfigAdvisories: allowedConfigAdvisories,
                allowedHardeningAdvisories: allowedHardeningAdvisories)
        }

        static func fogKeyImage(
            measurement: Measurement,
            allowedConfigAdvisories: [String] = [],
            allowedHardeningAdvisories: [String] = []
        ) -> AttestationInfo {
            .init(
                measurement: measurement,
                productId: FOG_LEDGER_PRODUCT_ID,
                minimumSecurityVersion: FOG_LEDGER_SECURITY_VERSION,
                allowedConfigAdvisories: allowedConfigAdvisories,
                allowedHardeningAdvisories: allowedHardeningAdvisories)
        }

        static func fogMerkleProof(
            measurement: Measurement,
            allowedConfigAdvisories: [String] = [],
            allowedHardeningAdvisories: [String] = []
        ) -> AttestationInfo {
            .init(
                measurement: measurement,
                productId: FOG_LEDGER_PRODUCT_ID,
                minimumSecurityVersion: FOG_LEDGER_SECURITY_VERSION,
                allowedConfigAdvisories: allowedConfigAdvisories,
                allowedHardeningAdvisories: allowedHardeningAdvisories)
        }

        static func fogReport(
            measurement: Measurement,
            allowedConfigAdvisories: [String] = [],
            allowedHardeningAdvisories: [String] = []
        ) -> AttestationInfo {
            .init(
                measurement: measurement,
                productId: FOG_REPORT_PRODUCT_ID,
                minimumSecurityVersion: FOG_REPORT_SECURITY_VERSION,
                allowedConfigAdvisories: allowedConfigAdvisories,
                allowedHardeningAdvisories: allowedHardeningAdvisories)
        }
    }

    // MARK: - OWSAttestationConfig

    private struct OWSAttestationConfig {
        let consensus: Attestation
        let fogView: Attestation
        let fogKeyImage: Attestation
        let fogMerkleProof: Attestation
        let fogReport: Attestation

        private static func buildAttestation(attestationInfo: [AttestationInfo]) throws -> MobileCoin.Attestation {
            do {
                let mrEnclaves = try attestationInfo.compactMap { attestationInfo -> MobileCoin.Attestation.MrEnclave? in
                    guard case let .enclave(measurement) = attestationInfo.measurement else {
                        return nil
                    }
                    return try MobileCoin.Attestation.MrEnclave.make(
                        mrEnclave: measurement,
                        allowedConfigAdvisories: attestationInfo.allowedConfigAdvisories,
                        allowedHardeningAdvisories: attestationInfo.allowedHardeningAdvisories
                    ).get()
                }

                let mrSigners = try attestationInfo.compactMap { attestationInfo -> MobileCoin.Attestation.MrSigner? in
                    guard case let .signer(measurement) = attestationInfo.measurement else {
                        return nil
                    }
                    return try MobileCoin.Attestation.MrSigner.make(
                        mrSigner: measurement,
                        productId: attestationInfo.productId,
                        minimumSecurityVersion: attestationInfo.minimumSecurityVersion,
                        allowedConfigAdvisories: attestationInfo.allowedConfigAdvisories,
                        allowedHardeningAdvisories: attestationInfo.allowedHardeningAdvisories
                    ).get()
                }

                return MobileCoin.Attestation(mrEnclaves: mrEnclaves, mrSigners: mrSigners)
            } catch {
                owsFailDebug("Error: \(error)")
                throw error
            }
        }

        private static func buildAttestationConfig(
            consensus: [AttestationRawInfo],
            fogView: [AttestationRawInfo],
            fogLedger: [AttestationRawInfo],
            fogReport: [AttestationRawInfo]
        ) -> OWSAttestationConfig {
            let consensusAttestations = consensus
                .map { info -> AttestationInfo in
                    .consensus(
                        measurement: .enclave(data: info.measurement),
                        allowedHardeningAdvisories: info.hardeningAdvisories)
                }
            let fogViewAttestations = fogView
                .map { info -> AttestationInfo in
                    .fogView(
                        measurement: .enclave(data: info.measurement),
                        allowedHardeningAdvisories: info.hardeningAdvisories)
                }
            let fogKeyImageAttestations = fogLedger
                .map { info -> AttestationInfo in
                    .fogKeyImage(
                        measurement: .enclave(data: info.measurement),
                        allowedHardeningAdvisories: info.hardeningAdvisories)
                }
            let fogMerkleProofAttestations = fogLedger
                .map { info -> AttestationInfo in
                    .fogMerkleProof(
                        measurement: .enclave(data: info.measurement),
                        allowedHardeningAdvisories: info.hardeningAdvisories)
                }
            let fogReportAttestations = fogReport
                .map { info -> AttestationInfo in
                    .fogReport(
                        measurement: .enclave(data: info.measurement),
                        allowedHardeningAdvisories: info.hardeningAdvisories)
                }

            return buildAttestationConfig(
                consensus: consensusAttestations,
                fogView: fogViewAttestations,
                fogKeyImage: fogKeyImageAttestations,
                fogMerkleProof: fogMerkleProofAttestations,
                fogReport: fogReportAttestations)
        }

        private static func buildAttestationConfig(
            mrSigner mrSignerData: Data,
            allowedHardeningAdvisories: [String] = AttestationInfo.allAllowedHardeningAdvisories
        ) -> OWSAttestationConfig {
            let consensus = AttestationInfo.consensus(
                measurement: .signer(data: mrSignerData),
                allowedHardeningAdvisories: allowedHardeningAdvisories)
            let fogView = AttestationInfo.fogView(
                measurement: .signer(data: mrSignerData),
                allowedHardeningAdvisories: allowedHardeningAdvisories)
            let fogReport = AttestationInfo.fogReport(
                measurement: .signer(data: mrSignerData),
                allowedHardeningAdvisories: allowedHardeningAdvisories)
            let fogMerkleProof = AttestationInfo.fogMerkleProof(
                measurement: .signer(data: mrSignerData),
                allowedHardeningAdvisories: allowedHardeningAdvisories)
            let fogKeyImage = AttestationInfo.fogKeyImage(
                measurement: .signer(data: mrSignerData),
                allowedHardeningAdvisories: allowedHardeningAdvisories)

            return buildAttestationConfig(
                consensus: [consensus],
                fogView: [fogView],
                fogKeyImage: [fogKeyImage],
                fogMerkleProof: [fogMerkleProof],
                fogReport: [fogReport])
        }

        private static func buildAttestationConfig(
            consensus: [AttestationInfo],
            fogView: [AttestationInfo],
            fogKeyImage: [AttestationInfo],
            fogMerkleProof: [AttestationInfo],
            fogReport: [AttestationInfo]
        ) -> OWSAttestationConfig {
            do {
                return OWSAttestationConfig(
                    consensus: try buildAttestation(attestationInfo: consensus),
                    fogView: try buildAttestation(attestationInfo: fogView),
                    fogKeyImage: try buildAttestation(attestationInfo: fogKeyImage),
                    fogMerkleProof: try buildAttestation(attestationInfo: fogMerkleProof),
                    fogReport: try buildAttestation(attestationInfo: fogReport)
                )
            } catch {
                owsFail("Invalid attestationConfig: \(error)")
            }
        }

        static var mobileCoinMainNet: OWSAttestationConfig {
            // These networks currently share the same attestation config.
            signalMainNet
        }

        static var signalMainNet: OWSAttestationConfig {
            // We need the old and new enclave values here.
            let mrEnclaveConsensus: [AttestationRawInfo] = [
                // ~May 6th, 2024
                .of(Data.data(fromHex: "82c14d06951a2168763c8ddb9c34174f7d2059564146650661da26ab62224b8a")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"]),
                // ~July 20th, 2025
                .of(Data.data(fromHex: "b7b40b173c6e42db3d4ab54b8080440238726581ab2f4235e27c1475cf494592")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"])
            ]

            let mrEnclaveFogView: [AttestationRawInfo] = [
                // ~May 6th, 2024
                .of(Data.data(fromHex: "2f542dcd8f682b72e8921d87e06637c16f4aa4da27dce55b561335326731fa73")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"]),
                // ~July 20th, 2025
                .of(Data.data(fromHex: "57f5ba050d15d3e9c1cf19222e44a370fb64d8a683c9b33f3d433699ca2d58f2")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"])
            ]

            // Report aka Ingest.
            let mrEnclaveFogReport: [AttestationRawInfo] = [
                // ~May 6th, 2024
                .of(Data.data(fromHex: "34881106254a626842fa8557e27d07cdf863083e9e6f888d5a492a456720916f")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"]),
                // ~July 20th, 2025
                .of(Data.data(fromHex: "0578f62dd30d92e31cb8d2df8e84ca216aaf12a5ffdea011042282b53a9e9a7a")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"])
            ]

            let mrEnclaveFogLedger: [AttestationRawInfo] = [
                // ~May 6th, 2024
                .of(Data.data(fromHex: "2494f1542f30a6962707d0bf2aa6c8c08d7bed35668c9db1e5c61d863a0176d1")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"]),
                // ~July 20th, 2025
                .of(Data.data(fromHex: "3892a844d9ed7dd0f41027a43910935429bd36d82cc8dc1db2aba98ba7929dd1")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"])
            ]

            return buildAttestationConfig(consensus: mrEnclaveConsensus,
                                          fogView: mrEnclaveFogView,
                                          fogLedger: mrEnclaveFogLedger,
                                          fogReport: mrEnclaveFogReport)
        }

        static var mobileCoinTestNet: OWSAttestationConfig {
            // These networks currently share the same attestation config.
            signalTestNet
        }

        static var signalTestNet: OWSAttestationConfig {
            // We need the old and new enclave values here.
            let mrEnclaveConsensus: [AttestationRawInfo] = [
                // ~May 6, 2024
                .of(Data.data(fromHex: "ae7930646f37e026806087d2a3725d3f6d75a8e989fb320e6ecb258eb829057a")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"]),
                // ~July 8, 2025
                .of(Data.data(fromHex: "b31e1d01939df31d51855317eed5ab7be4e7c77bf13d51230e38c3f5cb9af332")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"])
            ]
            let mrEnclaveFogView: [AttestationRawInfo] = [
                // ~May 6, 2024
                .of(Data.data(fromHex: "44de03c2ba34c303e6417480644f9796161eacbe5af4f2092e413b4ebf5ccf6a")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"]),
                // ~July 8, 2025
                .of(Data.data(fromHex: "57f5ba050d15d3e9c1cf19222e44a370fb64d8a683c9b33f3d433699ca2d58f2")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"])
            ]
            // Report aka Ingest.
            let mrEnclaveFogReport: [AttestationRawInfo]  = [
                // ~May 6, 2024
                .of(Data.data(fromHex: "4a5daa23db5efa4b18071291cfa24a808f58fb0cedce7da5de804b011e87cfde")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"]),
                // ~July 8, 2025
                .of(Data.data(fromHex: "0578f62dd30d92e31cb8d2df8e84ca216aaf12a5ffdea011042282b53a9e9a7a")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"])
            ]
            let mrEnclaveFogLedger: [AttestationRawInfo]  = [
                // ~May 6, 2024
                .of(Data.data(fromHex: "065b1e17e95f2c356d4d071d434cea7eb6b95bc797f94954146736efd47057a7")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"]),
                // ~July 8, 2025
                .of(Data.data(fromHex: "3892a844d9ed7dd0f41027a43910935429bd36d82cc8dc1db2aba98ba7929dd1")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"])
            ]

            return buildAttestationConfig(consensus: mrEnclaveConsensus,
                                          fogView: mrEnclaveFogView,
                                          fogLedger: mrEnclaveFogLedger,
                                          fogReport: mrEnclaveFogReport)
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

    // MARK: - OWSAuthorization

    struct OWSAuthorization {
        let username: String
        let password: String

        private static let testAuthUsername = "user20220713"
        private static let testAuthPassword = "user20220713:1657845591:298d68fd6b1438082b15"

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

    // MARK: - TrustRootCerts

    private enum TrustRootCerts {

        private static let anchorCertificates_mobileCoin = [Certificates.load("isrgrootx1", extension: "crt")]

        static func pinPolicy(environment: Environment) throws(OWSAssertionError) -> HttpSecurityPolicy {
            let trustRootCerts: [SecCertificate] = anchorCertificates_mobileCoin
            guard !trustRootCerts.isEmpty else {
                throw OWSAssertionError("No certificate data")
            }
            return HttpSecurityPolicy(pinnedCertificates: trustRootCerts)
        }
    }

    // MARK: - MobileCoinAccount

    struct MobileCoinAccount {
        let environment: Environment
        let accountKey: MobileCoin.AccountKey
        var publicAddress: MobileCoin.PublicAddress {
            accountKey.publicAddress
        }

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

        func buildClient(signalAuthorization: OWSAuthorization) throws -> MobileCoinClient {
            Logger.info("Environment: \(environment)")
            let networkConfig = MobileCoinNetworkConfig.networkConfig(environment: environment)
            let authorization = self.authorization(signalAuthorization: signalAuthorization)
            let attestationConfig = OWSAttestationConfig.attestationConfig(environment: environment)
            let configResult = MobileCoinClient.Config.make(consensusUrls: networkConfig.consensusUrls,
                                                            consensusAttestation: attestationConfig.consensus,
                                                            fogUrls: [networkConfig.fogUrl],
                                                            fogViewAttestation: attestationConfig.fogView,
                                                            fogKeyImageAttestation: attestationConfig.fogKeyImage,
                                                            fogMerkleProofAttestation: attestationConfig.fogMerkleProof,
                                                            fogReportAttestation: attestationConfig.fogReport,
                                                            transportProtocol: .http)

            let securityPolicy: HttpSecurityPolicy
            do {
                securityPolicy = try TrustRootCerts.pinPolicy(environment: environment)
            } catch {
                owsFailDebug("Error: \(error)")
                throw error
            }

            switch configResult {
            case .success(var config):
                config.httpRequester = MobileCoinHttpRequester(securityPolicy: securityPolicy)
                let clientResult = MobileCoinClient.make(accountKey: accountKey, config: config)
                switch clientResult {
                case .success(let client):
                    // There are separate FOG and consensus auth credentials which correspond to
                    // the consensus URL and fog URLs.
                    //
                    // We currently use a MobileCoin Consensus node and Signal Fog; Signal Fog
                    // requires an auth token but MobileCoin Consensus doesn't.
                    //
                    // TODO: We'll need to setConsensusBasicAuthorization() if/when we
                    // switch to Signal consensus.
                    client.setFogBasicAuthorization(username: authorization.username,
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

    // MARK: - Fog Authority

    private static func fogAuthoritySpki(environment: Environment) -> Data {
        switch environment {
        case .mobileCoinAlphaNet,
             .mobileCoinMobileDev:
            return Data(base64Encoded: "MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAyFOockvCEc9TcO1NvsiUfFVzvtDsR64UIRRUl3tBM2Bh8KBA932/Up86RtgJVnbslxuUCrTJZCV4dgd5hAo/mzuJOy9lAGxUTpwWWG0zZJdpt8HJRVLX76CBpWrWEt7JMoEmduvsCR8q7WkSNgT0iIoSXgT/hfWnJ8KGZkN4WBzzTH7hPrAcxPrzMI7TwHqUFfmOX7/gc+bDV5ZyRORrpuu+OR2BVObkocgFJLGmcz7KRuN7/dYtdYFpiKearGvbYqBrEjeo/15chI0Bu/9oQkjPBtkvMBYjyJPrD7oPP67i0ZfqV6xCj4nWwAD3bVjVqsw9cCBHgaykW8ArFFa0VCMdLy7UymYU5SQsfXrw/mHpr27Pp2Z0/7wpuFgJHL+0ARU48OiUzkXSHX+sBLov9X6f9tsh4q/ZRorXhcJi7FnUoagBxewvlfwQfcnLX3hp1wqoRFC4w1DC+ki93vIHUqHkNnayRsf1n48fSu5DwaFfNvejap7HCDIOpCCJmRVR8mVuxi6jgjOUa4Vhb/GCzxfNIn5ZYym1RuoE0TsFO+TPMzjed3tQvG7KemGFz3pQIryb43SbG7Q+EOzIigxYDytzcxOO5Jx7r9i+amQEiIcjBICwyFoEUlVJTgSpqBZGNpznoQ4I2m+uJzM+wMFsinTZN3mp4FU5UHjQsHKG+ZMCAwEAAQ==")!
        case .signalTestNet, .mobileCoinTestNet:
            return Data(base64Encoded:
                """
                MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAvnB9wTbTOT5uoizRYaYbw7XIEkInl8E7MGOA\
                Qj+xnC+F1rIXiCnc/t1+5IIWjbRGhWzo7RAwI5sRajn2sT4rRn9NXbOzZMvIqE4hmhmEzy1YQNDnfALA\
                WNQ+WBbYGW+Vqm3IlQvAFFjVN1YYIdYhbLjAPdkgeVsWfcLDforHn6rR3QBZYZIlSBQSKRMY/tywTxeT\
                CvK2zWcS0kbbFPtBcVth7VFFVPAZXhPi9yy1AvnldO6n7KLiupVmojlEMtv4FQkk604nal+j/dOplTAT\
                V8a9AJBbPRBZ/yQg57EG2Y2MRiHOQifJx0S5VbNyMm9bkS8TD7Goi59aCW6OT1gyeotWwLg60JRZTfyJ\
                7lYWBSOzh0OnaCytRpSWtNZ6barPUeOnftbnJtE8rFhF7M4F66et0LI/cuvXYecwVwykovEVBKRF4HOK\
                9GgSm17mQMtzrD7c558TbaucOWabYR04uhdAc3s10MkuONWG0wIQhgIChYVAGnFLvSpp2/aQEq3xrRSE\
                TxsixUIjsZyWWROkuA0IFnc8d7AmcnUBvRW7FT/5thWyk5agdYUGZ+7C1o69ihR1YxmoGh69fLMPIEOh\
                Yh572+3ckgl2SaV4uo9Gvkz8MMGRBcMIMlRirSwhCfozV2RyT5Wn1NgPpyc8zJL7QdOhL7Qxb+5WjnCV\
                rQYHI2cCAwEAAQ==
                """
            )!
        case .mobileCoinMainNet, .signalMainNet:
            let mainNetFogAuthoritySpkiB64Encoded = """
                MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAyr/99fvxi104MLgDgvWPVt01TuTJ+rN4qcNBUbF5i3EMM5z\
                DZlugFHKPYPv7flCh5yDDYyLQHfWkxPQqCBAqlhSrCakvQH3HqDSpbM5FJg7pt0k5w+UQGWvP079iSEO5fMRhjE/lOR\
                kvk3/UKr2yIXjZ19iEgP8hlhk9xkI42DSg0iIhk59k3wEYPMGSkVarqlPoKBzx2+11CieXnbCkRvoNwLvdzLceY8QNo\
                Lc6h2/nht4bcjDCdB0MKNSKFLVp6XNHkVF66jC7QWTZRA/d4pgI5xa+GmkQ90zDZC2sBc+xfquVIVtk0nEvqSkUDZjv\
                7AcJaq/VdPu4uj773ojrZz094PI4Q6sdbg7mfWrcq3ZQG8t9RDXD+6cgugCTFx2Cq/vJhDAPbQHmCEaMoXv2sRSfOhR\
                jtMP1KmKUw5zXmAZa7s88+e7UXRQC+SS77V8s3hinE/I5Gqa/lzl73smhXx8l4CwGnXzlQ5h1lgEHnYLRFnIenNw/md\
                MGKlWH5HwHLX3hIujERCPAnGLDt+4MjcUiU0spDH3hC9mjPVA3ltaA3+Mk2lDw0kLrZ4Gv3/Ik9WPlYetOuWteMkR1f\
                z6VOc13+WoTJPz0dVrJsK2bUz+YvdBsoHQBbUpCkmnQ5Ok+yiuWa5vYikEJ24SEr8wUiZ4Oe12KVEcjyDIxp6QoE8kC\
                AwEAAQ==
                """
            return Data(base64Encoded: mainNetFogAuthoritySpkiB64Encoded)!
        }
    }

    class func buildAccount(forPaymentsEntropy paymentsEntropy: Data) throws -> MobileCoinAccount {
        let environment = Environment.current
        let networkConfig = MobileCoinNetworkConfig.networkConfig(environment: environment)
        let accountKey = try buildAccountKey(forPaymentsEntropy: paymentsEntropy,
                                             networkConfig: networkConfig)
        return MobileCoinAccount(environment: environment,
                                 accountKey: accountKey)
    }

    class func buildAccountKey(forPaymentsEntropy paymentsEntropy: Data,
                               networkConfig: MobileCoinNetworkConfig) throws -> MobileCoin.AccountKey {
        let passphrase = try Self.passphrase(forPaymentsEntropy: paymentsEntropy)
        let mnemonic = passphrase.asPassphrase
        let fogAuthoritySpki = Self.fogAuthoritySpki(environment: .current)
        let fogReportId = ""
        let accountIndex: UInt32 = 0
        let result = MobileCoin.AccountKey.make(mnemonic: mnemonic,
                                                fogReportUrl: networkConfig.fogReportUrl,
                                                fogReportId: fogReportId,
                                                fogAuthoritySpki: fogAuthoritySpki,
                                                accountIndex: accountIndex)

        switch result {
        case .success(let accountKey):
            return accountKey
        case .failure(let error):
            owsFailDebug("Error: \(error)")
            throw error
        }
    }
}

final class MobileCoinHttpRequester: NSObject, HttpRequester {
    static let defaultConfiguration: URLSessionConfiguration = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        return config
    }()

    private let securityPolicy: HttpSecurityPolicy

    init(securityPolicy: HttpSecurityPolicy) {
        self.securityPolicy = securityPolicy
    }

    func request(
        url: URL,
        method: LibMobileCoin.HTTPMethod,
        headers headerMap: [String: String]?,
        body: Data?,
        completion: @escaping (Result<LibMobileCoin.HTTPResponse, Error>) -> Void
    ) {
        let owsUrlSession = OWSURLSession(securityPolicy: securityPolicy, configuration: Self.defaultConfiguration)

        var headers = HttpHeaders()
        headers.addHeaderMap(headerMap, overwriteOnConflict: true)

        let promise = Promise.wrapAsync {
            return try await owsUrlSession.performRequest(url.absoluteString, method: method.sskHTTPMethod, headers: headers, body: body)
        }
        promise.done { response in
            let headerFields = response.headers.headers
            let statusCode = response.responseStatusCode
            let responseData = response.responseBodyData
            let url = response.requestUrl
            let httpResponse = LibMobileCoin.HTTPResponse(statusCode: statusCode, url: url, allHeaderFields: headerFields, responseData: responseData)
            completion(.success(httpResponse))
        }.catch { error in
            if let statusCode = error.httpStatusCode {
                completion(.success(LibMobileCoin.HTTPResponse(statusCode: statusCode, url: nil, allHeaderFields: [:], responseData: nil)))
            } else {
                Logger.warn("MobileCoin http request failed \(error)")
                completion(.failure(ConnectionError.invalidServerResponse("No Response")))
            }
        }
    }
}

extension LibMobileCoin.HTTPMethod {
    var sskHTTPMethod: SignalServiceKit.HTTPMethod {
        switch self {
        case .GET:
            return .get
        case .POST:
            return .post
        case .PUT:
            return .put
        case .HEAD:
            return .head
        case .PATCH:
            return .patch
        case .DELETE:
            return .delete
        }
    }
}
