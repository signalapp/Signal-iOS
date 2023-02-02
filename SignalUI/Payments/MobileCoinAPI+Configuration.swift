//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MobileCoin
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
            let fogUrl = "fog://service.fog.mob.production.namda.net"
            let fogReportUrl = "fog://fog-rpt-prd.namda.net"
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
            let fogUrl = "fog://service.fog.mob.staging.namda.net"
            let fogReportUrl = "fog://fog-rpt-stg.namda.net"
            return MobileCoinNetworkConfig(consensusUrls: consensusUrls, fogUrl: fogUrl, fogReportUrl: fogReportUrl)
        }

        static var mobileCoinTestNet: MobileCoinNetworkConfig {
            let consensusUrls = ["mc://node1.test.mobilecoin.com"]
            let fogUrl = "fog://fog.test.mobilecoin.com"
            let fogReportUrl = fogUrl
            return MobileCoinNetworkConfig(consensusUrls: consensusUrls, fogUrl: fogUrl, fogReportUrl: fogReportUrl)
        }

        static var mobileCoinAlphaNet: MobileCoinNetworkConfig {
            let consensusUrls = ["mc://consensus.alpha.mobilecoin.com"]
            let fogUrl = "fog://fog.alpha.mobilecoin.com"
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
                // ~June 23, 2021
                .of(Data.data(fromHex: "653228afd2b02a6c28f1dc3b108b1dfa457d170b32ae8ec2978f941bd1655c83")!, ["INTEL-SA-00334"]),
                // ~July 8th, 2022
                .of(Data.data(fromHex: "733080d6ece4504f66ba606fa8163dae0a5220f3dbf6ca55fbafbac12c6f1897")!, ["INTEL-SA-00334"]),
                // ~August 10th, 2022
                .of(Data.data(fromHex: "d6e54e43c368f0fa2c5f13361afd303ee8f890424e99bd6c367f6164b5fff1b5")!, ["INTEL-SA-00334", "INTEL-SA-00615"]),
                // ~November 2nd, 2022
                .of(Data.data(fromHex: "207c9705bf640fdb960034595433ee1ff914f9154fbe4bc7fc8a97e912961e5c")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"]),
                // ~December 15th, 2022
                .of(Data.data(fromHex: "e35bc15ee92775029a60a715dca05d310ad40993f56ad43bca7e649ccc9021b5")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"])
            ]

            let mrEnclaveFogView: [AttestationRawInfo] = [
                // ~June 23, 2021
                .of(Data.data(fromHex: "dd84abda7f05116e21fcd1ee6361b0ec29445fff0472131eaf37bf06255b567a")!, ["INTEL-SA-00334"]),
                // ~July 8th, 2022
                .of(Data.data(fromHex: "c64a3b04348b10596442868758875f312dc3a755b450805149774a091d2822d3")!, ["INTEL-SA-00334"]),
                // ~August 10th, 2022
                .of(Data.data(fromHex: "3d6e528ee0574ae3299915ea608b71ddd17cbe855d4f5e1c46df9b0d22b04cdb")!, ["INTEL-SA-00334", "INTEL-SA-00615"]),
                // ~November 2nd, 2022
                .of(Data.data(fromHex: "fd4c1c82cca13fa007be15a4c90e2b506c093b21c2e7021a055cbb34aa232f3f")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"]),
                // ~December 15th, 2022
                .of(Data.data(fromHex: "da209f4b24e8f4471bd6440c4e9f1b3100f1da09e2836d236e285b274901ed3b")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"])
            ]

            // Report aka Ingest.
            let mrEnclaveFogReport: [AttestationRawInfo] = [
                // ~June 23, 2021
                .of(Data.data(fromHex: "f3f7e9a674c55fb2af543513527b6a7872de305bac171783f6716a0bf6919499")!, ["INTEL-SA-00334"]),
                // ~July 8th, 2022
                .of(Data.data(fromHex: "660103d766cde0fd1e1cfb443b99e52da2ce0617d0dee42f8b875f7104942c6b")!, ["INTEL-SA-00334"]),
                // ~August 10th, 2022
                .of(Data.data(fromHex: "3e9bf61f3191add7b054f0e591b62f832854606f6594fd63faef1e2aedec4021")!, ["INTEL-SA-00334", "INTEL-SA-00615"]),
                // ~November 2nd, 2022
                .of(Data.data(fromHex: "3370f131b41e5a49ed97c4188f7a976461ac6127f8d222a37929ac46b46d560e")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"]),
                // ~December 15th, 2022
                .of(Data.data(fromHex: "a8af815564569aae3558d8e4e4be14d1bcec896623166a10494b4eaea3e1c48c")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"])
            ]

            let mrEnclaveFogLedger: [AttestationRawInfo] = [
                // ~June 23, 2021
                .of(Data.data(fromHex: "89db0d1684fcc98258295c39f4ab68f7de5917ef30f0004d9a86f29930cebbbd")!, ["INTEL-SA-00334"]),
                // ~July 8th, 2022
                .of(Data.data(fromHex: "ed8ed6e1b4b6827e5543b25c1c13b9c06b478d819f8df912eb11fa140780fc51")!, ["INTEL-SA-00334"]),
                // ~August 10th, 2022
                .of(Data.data(fromHex: "92fb35d0f603ceb5eaf2988b24a41d4a4a83f8fb9cd72e67c3bc37960d864ad6")!, ["INTEL-SA-00334", "INTEL-SA-00615"]),
                // ~November 2nd, 2022
                .of(Data.data(fromHex: "dca7521ce4564cc2e54e1637e533ea9d1901c2adcbab0e7a41055e719fb0ff9d")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"]),
                // ~December 15th, 2022
                .of(Data.data(fromHex: "8c80a2b95a549fa8d928dd0f0771be4f3d774408c0f98bf670b1a2c390706bf3")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"])
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
                // ~June 2, 2021
                .of(Data.data(fromHex: "9659ea738275b3999bf1700398b60281be03af5cb399738a89b49ea2496595af")!, ["INTEL-SA-00334"]),
                // ~July 13, 2022
                .of(Data.data(fromHex: "4f134dcfd9c0885956f2f9af0f05c2050d8bdee2dc63b468a640670d7adeb7f8")!, ["INTEL-SA-00334"]),
                // ~Aug 16, 2022
                .of(Data.data(fromHex: "01746f4dd25f8623d603534425ed45833687eca2b3ba25bdd87180b9471dac28")!, ["INTEL-SA-00334", "INTEL-SA-00615"]),
                // ~Nov 8, 2022
                .of(Data.data(fromHex: "5fe2b72fe5f01c269de0a3678728e7e97d823a953b053e43fbf934f439d290e6")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"])
            ]
            let mrEnclaveFogView: [AttestationRawInfo] = [
                // ~June 2, 2021
                .of(Data.data(fromHex: "e154f108c7758b5aa7161c3824c176f0c20f63012463bf3cc5651e678f02fb9e")!, ["INTEL-SA-00334"]),
                // ~July 13, 2022
                .of(Data.data(fromHex: "719ca43abbe02f507bb91ea11ff8bc900aa86363a7d7e77b8130426fc53d8684")!, ["INTEL-SA-00334"]),
                // ~Aug 16, 2022
                .of(Data.data(fromHex: "3d6e528ee0574ae3299915ea608b71ddd17cbe855d4f5e1c46df9b0d22b04cdb")!, ["INTEL-SA-00334", "INTEL-SA-00615"]),
                // ~Nov 8, 2022
                .of(Data.data(fromHex: "be1d711887530929fbc06ef8b77b618db15e9cd1dd0265559ea45f60a532ee52")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"])
            ]
            // Report aka Ingest.
            let mrEnclaveFogReport: [AttestationRawInfo]  = [
                // ~June 2, 2021
                .of(Data.data(fromHex: "a4764346f91979b4906d4ce26102228efe3aba39216dec1e7d22e6b06f919f11")!, ["INTEL-SA-00334"]),
                // ~July 13, 2022
                .of(Data.data(fromHex: "8f2f3bf81f24bf493fa6d76e29e0f081815022592b1e854f95bda750aece7452")!, ["INTEL-SA-00334"]),
                // ~Aug 16, 2022
                .of(Data.data(fromHex: "3e9bf61f3191add7b054f0e591b62f832854606f6594fd63faef1e2aedec4021")!, ["INTEL-SA-00334", "INTEL-SA-00615"]),
                // ~Nov 8, 2022
                .of(Data.data(fromHex: "d901b5c4960f49871a848fd157c7c0b03351253d65bb839698ddd5df138ad7b6")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"])
            ]
            let mrEnclaveFogLedger: [AttestationRawInfo]  = [
                // ~June 2, 2021
                .of(Data.data(fromHex: "768f7bea6171fb83d775ee8485e4b5fcebf5f664ca7e8b9ceef9c7c21e9d9bf3")!, ["INTEL-SA-00334"]),
                // ~July 13, 2022
                .of(Data.data(fromHex: "685481b33f2846585f33506ab65649c98a4a6d1244989651fd0fcde904ebd82f")!, ["INTEL-SA-00334"]),
                // ~Aug 16, 2022
                .of(Data.data(fromHex: "92fb35d0f603ceb5eaf2988b24a41d4a4a83f8fb9cd72e67c3bc37960d864ad6")!, ["INTEL-SA-00334", "INTEL-SA-00615"]),
                // ~Nov 8, 2022
                .of(Data.data(fromHex: "d5159ba907066384fae65842b5311f853b028c5ee4594f3b38dfc02acddf6fe3")!, ["INTEL-SA-00334", "INTEL-SA-00615", "INTEL-SA-00657"])
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

    // MARK: - Certificates

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

    // MARK: - TrustRootCerts

    @objc
    private class TrustRootCerts: NSObject {

        static func anchorCertificates_mobileCoin() -> [Data] {
            [
                Certificates.certificateData(forService: "isrgrootx1", type: "der", certificateBundle: .ssk, verifyDer: true)
            ]
        }

        static func pinPolicy(environment: Environment) -> Result<OWSHTTPSecurityPolicy, Error> {
            let trustRootCertDatas: [Data] = anchorCertificates_mobileCoin()
            guard !trustRootCertDatas.isEmpty else {
                return .failure(OWSAssertionError("No certificate data"))
            }

            let securityPolicy =  OWSHTTPSecurityPolicy(pinnedCertificates: Set(trustRootCertDatas))
            return .success(securityPolicy)
        }
    }

    // MARK: - MobileCoinAccount

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

            let securityPolicy: OWSHTTPSecurityPolicy
            do {
                securityPolicy = try TrustRootCerts.pinPolicy(environment: environment).get()
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
        case .mobileCoinTestNet:
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
        case .signalTestNet:
            return Data(base64Encoded:
                """
                MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAoCMq8nnjTq5EEQ4EI7yrABL9P4y4h1P/h0De\
                pWgXx+w/fywcfRSZINxbaMpvcV3uSJayExrpV1KmaS2wfASeYhSj+rEzAm0XUOw3Q94NOx5A/dOQag/d\
                1SS6/QpF3PQYZTULnRFetmM4yzEnXsXcWtzEu0hh02wYJbLeAq4CCcPTPe2qckrbUP9sD18/KOzzNeyp\
                F4p5dQ2m/ezfxtgaLvdUMVDVIAs2v9a5iu6ce4bIcwTIUXgX0w3+UKRx8zqowc3HIqo9yeaGn4ZOwQHv\
                AJZecPmb2pH1nK+BtDUvHpvf+Y3/NJxwh+IPp6Ef8aoUxs2g5oIBZ3Q31fjS2Bh2gmwoVooyytEysPAH\
                vRPVBxXxLi36WpKfk1Vq8K7cgYh3IraOkH2/l2Pyi8EYYFkWsLYofYogaiPzVoq2ZdcizfoJWIYei5mg\
                q+8m0ZKZYLebK1i2GdseBJNIbSt3wCNXZxyN6uqFHOCB29gmA5cbKvs/j9mDz64PJe9LCanqcDQV1U5l\
                9dt9UdmUt7Ab1PjBtoIFaP+u473Z0hmZdCgAivuiBMMYMqt2V2EIw4IXLASE3roLOYp0p7h0IQHb+lVI\
                uEl0ZmwAI30ZmzgcWc7RBeWD1/zNt55zzhfPRLx/DfDY5Kdp6oFHWMvI2r1/oZkdhjFp7pV6qrl7vOyR\
                5QqmuRkCAwEAAQ==
                """
            )!
        case .mobileCoinMainNet:
            owsFail("TODO: Set this value.")
        case .signalMainNet:
            return Data(base64Encoded: "MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAxaNIOgcoQtq0S64dFVha6rn0hDv/ec+W0cKRdFKygiyp5xuWdW3YKVAkK1PPgSDD2dwmMN/1xcGWrPMqezx1h1xCzbr7HL7XvLyFyoiMB2JYd7aoIuGIbHpCOlpm8ulVnkOX7BNuo0Hi2F0AAHyTPwmtVMt6RZmae1Z/Pl2I06+GgWN6vufV7jcjiLT3yQPsn1kVSj+DYCf3zq+1sCknKIvoRPMdQh9Vi3I/fqNXz00DSB7lt3v5/FQ6sPbjljqdGD/qUl4xKRW+EoDLlAUfzahomQOLXVAlxcws3Ua5cZUhaJi6U5jVfw5Ng2N7FwX/D5oX82r9o3xcFqhWpGnfSxSrAudv1X7WskXomKhUzMl/0exWpcJbdrQWB/qshzi9Et7HEDNY+xEDiwGiikj5f0Lb+QA4mBMlAhY/cmWec8NKi1gf3Dmubh6c3sNteb9OpZ/irA3AfE8jI37K1rvezDI8kbNtmYgvyhfz0lZzRT2WAfffiTe565rJglvKa8rh8eszKk2HC9DyxUb/TcyL/OjGhe2fDYO2t6brAXCqjPZAEkVJq3I30NmnPdE19SQeP7wuaUIb3U7MGxoZC/NuJoxZh8svvZ8cyqVjG+dOQ6/UfrFY0jiswT8AsrfqBis/ZV5EFukZr+zbPtg2MH0H3tSJ14BCLduvc7FY6lAZmOcCAwEAAQ==")!
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

    private let securityPolicy: OWSHTTPSecurityPolicy

    init(securityPolicy: OWSHTTPSecurityPolicy) {
        self.securityPolicy = securityPolicy
    }

    func request(
        url: URL,
        method: MobileCoin.HTTPMethod,
        headers: [String: String]?,
        body: Data?,
        completion: @escaping (Result<MobileCoin.HTTPResponse, Error>) -> Void
    ) {
        var request = URLRequest(url: url.absoluteURL)
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.allHTTPHeaderFields = headers

        let owsUrlSession = OWSURLSession(securityPolicy: securityPolicy, configuration: Self.defaultConfiguration)

        firstly(on: .sharedUtility) {
            owsUrlSession.dataTaskPromise(url.absoluteString, method: method.sskHTTPMethod, headers: headers, body: body)
        }.done { response in
            let headerFields = response.responseHeaders
            let statusCode = response.responseStatusCode
            let responseData = response.responseBodyData
            let url = response.requestUrl
            let httpResponse = MobileCoin.HTTPResponse(statusCode: statusCode, url: url, allHeaderFields: headerFields, responseData: responseData)
            completion(.success(httpResponse))
        }.catch { error in
            if let statusCode = error.httpStatusCode {
                completion(.success(MobileCoin.HTTPResponse(statusCode: statusCode, url: nil, allHeaderFields: [:], responseData: nil)))
            } else {
                Logger.warn("MobileCoin http request failed \(error)")
                completion(.failure(ConnectionError.invalidServerResponse("No Response")))
            }
        }
    }
}

extension MobileCoin.HTTPMethod {
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
