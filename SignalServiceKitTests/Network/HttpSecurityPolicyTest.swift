//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
import Security
import Testing

@testable import SignalServiceKit

struct HttpSecurityPolicyTest {

    // MARK: - Trust evaluation

    /// A chain that validates and carries no rejected key is accepted.
    @Test
    func validChainWithNothingRejectedIsAccepted() throws {
        let trust = try Self.makeServerTrust(
            chain: Self.goodChain,
            anchor: Self.testRootABase64,
            domain: Self.goodLeafDomain,
        )
        let policy = HttpSecurityPolicy(rejectedSPKI: [])

        #expect(policy.evaluate(serverTrust: trust, domain: Self.goodLeafDomain))
    }

    /// The same chain is rejected once its intermediate's key is on the list, even
    /// though the chain itself still validates via the serverTrust.
    @Test
    func chainCarryingARejectedKeyIsRefused() throws {
        let rejectedKey = try Self.rejectedKeyDigest
        let trust = try Self.makeServerTrust(
            chain: Self.badChain,
            anchor: Self.testRootABase64,
            domain: Self.badLeafDomain,
        )
        let policy = HttpSecurityPolicy(rejectedSPKI: [rejectedKey])

        #expect(!policy.evaluate(serverTrust: trust, domain: Self.badLeafDomain))
    }

    /// The cross-signed case
    /// This is the same leaf certificate as above, but chaining through the
    /// cross-signed copy of the compromised CA up to an entirely different root.
    /// It is a different certificate chain by every measure except for the compromised key
    @Test
    func crossSignedChainCarryingTheSameRejectedKeyIsAlsoRefused() throws {
        let rejectedKey = try Self.rejectedKeyDigest

        // The chain is valid: a policy rejecting nothing will accept this trust
        let permissiveTrust = try Self.makeServerTrust(
            chain: Self.crossSignedBadChain,
            anchor: Self.testRootBBase64,
            domain: Self.badLeafDomain,
        )
        #expect(HttpSecurityPolicy(rejectedSPKI: []).evaluate(
            serverTrust: permissiveTrust,
            domain: Self.badLeafDomain,
        ))

        // So the rejected SPKI key is the only thing that can refuse it.
        // Note: A fresh trust object is used to avoid any caching
        let trust = try Self.makeServerTrust(
            chain: Self.crossSignedBadChain,
            anchor: Self.testRootBBase64,
            domain: Self.badLeafDomain,
        )
        #expect(!HttpSecurityPolicy(rejectedSPKI: [rejectedKey]).evaluate(
            serverTrust: trust,
            domain: Self.badLeafDomain,
        ))
    }

    /// Rejecting one key doesn't reject unrelated chains, including chains sharing
    /// the rejected CA's issuer.
    @Test
    func unrelatedChainIsUnaffectedByARejectedKey() throws {
        let rejectedKey = try Self.rejectedKeyDigest
        let trust = try Self.makeServerTrust(
            chain: Self.goodChain,
            anchor: Self.testRootABase64,
            domain: Self.goodLeafDomain,
        )
        let policy = HttpSecurityPolicy(rejectedSPKI: [rejectedKey])

        #expect(policy.evaluate(serverTrust: trust, domain: Self.goodLeafDomain))
    }

    /// A chain that doesn't reach its anchor is refused before the key check runs.
    @Test
    func chainThatDoesNotValidateIsRefused() throws {
        // The good leaf and its CA, anchored at the unrelated cross-signing root.
        let trust = try Self.makeServerTrust(
            chain: Self.goodChain,
            anchor: Self.testRootBBase64,
            domain: Self.goodLeafDomain,
        )
        let policy = HttpSecurityPolicy(rejectedSPKI: [])

        #expect(!policy.evaluate(serverTrust: trust, domain: Self.goodLeafDomain))
    }

    /// A hostname the leaf doesn't cover is refused by the SSL policy. goodLeaf is
    /// valid for its own host, not for badLeaf's.
    @Test
    func chainForTheWrongHostIsRefused() throws {
        let trust = try Self.makeServerTrust(
            chain: Self.goodChain,
            anchor: Self.testRootABase64,
            domain: Self.badLeafDomain,
        )
        let policy = HttpSecurityPolicy(rejectedSPKI: [])

        #expect(!policy.evaluate(serverTrust: trust, domain: Self.badLeafDomain))
    }

    // MARK: - Test setup code

    /// The hosts named in the generated leaf certificates' subject.
    private static let goodLeafDomain = "goodleaf.signal.org"
    private static let badLeafDomain = "badleaf.signal.org"

    /// Trust evaluation is pinned to a fixed instant inside the fixtures' validity
    /// window so the tests don't begin failing when the leaf certificates expire.
    /// Regenerating the fixtures moves that window; the generator prints the dates.
    private static let verifyDate = Date(timeIntervalSince1970: 1_811_808_000) // 2027-06-01

    private static var goodChain: [String] { [goodLeafBase64, goodCaBase64] }
    private static var badChain: [String] { [badLeafBase64, badCaBase64] }
    private static var crossSignedBadChain: [String] { [badLeafBase64, crossSignedBadCaBase64] }

    /// The SHA-256 of the compromised CA's SubjectPublicKeyInfo
    private static var rejectedKeyDigest: Data {
        get throws {
            let badCa = try makeCertificate(base64Der: badCaBase64)
            let spki = try #require(HttpSecurityPolicy.subjectPublicKeyInfo(of: badCa))
            return Data(SHA256.hash(data: spki))
        }
    }

    /// Builds a server trust from a leaf-first chain, anchored at the given root,
    /// similar to what a TLS handshake would hand to `evaluate`.
    private static func makeServerTrust(chain: [String], anchor: String, domain: String) throws -> SecTrust {
        let certificates = try chain.map { try makeCertificate(base64Der: $0) }
        let anchorCertificate = try makeCertificate(base64Der: anchor)

        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(
            certificates as CFArray,
            SecPolicyCreateSSL(true, domain as CFString),
            &trust,
        )
        #expect(status == errSecSuccess)
        let serverTrust = try #require(trust)

        // Set the top level certificates of the trust chain
        #expect(
            SecTrustSetAnchorCertificates(
                serverTrust,
                [anchorCertificate] as CFArray,
            ) == errSecSuccess,
        )
        // Don't fall back to the system roots; this is the only source of trust.
        #expect(SecTrustSetAnchorCertificatesOnly(serverTrust, true) == errSecSuccess)
        // Set the date the cert verifies against to avoid dealing with the certs expiring
        #expect(SecTrustSetVerifyDate(serverTrust, verifyDate as CFDate) == errSecSuccess)

        return serverTrust
    }

    private static func makeCertificate(base64Der: String) throws -> SecCertificate {
        let der = try #require(Data(base64Encoded: base64Der))
        return try #require(SecCertificateCreateWithData(nil, der as CFData))
    }

    // MARK: - Generated certificate authorities

    /// Mock certificate authorities approximating the structure of the eMudhra compromise
    ///
    /// ```
    ///         ANCHOR                            ANCHOR
    ///  +------------------------+    +---------------------------------+
    ///  | Test Root TLS CA - A1  |    | Test Cross-Signing Root CA - A2 |
    ///  | self-signed - EC P-384 |    | self-signed - RSA-2048          |
    ///  +---+----------------+---+    +----------------+----------------+
    ///      | signs          | signs                   | signs
    ///      v                v                         v
    /// +------------------+  +------------------+  +------------------+
    /// | Test Sub CA - B1 |  | Test Sub CA - B2 |  | Test Sub CA - B2 |
    /// | (good)           |  | (bad)            |  | (bad, crossed)   |
    /// | EC P-384         |  | EC P-384 - key K |  | EC P-384 - key K |
    /// | serial 0x1002    |  | serial 0x1001    |  | serial 0x2001    |
    /// | cert EDBCA335... |  | cert B9555608... |  | cert AA4A2BA4... |   <- differ
    /// | spki A2312828... |  | spki 530C4DD6... |  | spki 530C4DD6... |   <- IDENTICAL
    /// +--------+---------+  +--------+---------+  +--------+---------+
    ///           |                     |    same subject,   |
    ///           |                     |   same key pair K  |
    ///           | signs               +-----------+--------+
    ///           v                                 v
    ///  +-------------------------+  +-------------------------+
    ///  | goodLeaf                |  | badLeaf                 |
    ///  | EC P-256                |  | EC P-256                |
    ///  | serial 0x3001           |  | serial 0x3002           |
    ///  | cert 98D8455C...        |  | cert A56E512A...        |
    ///  | SAN goodleaf.signal.org |  | SAN badleaf.signal.org  |
    ///  +-------------------------+  +-------------------------+
    ///                                   signed once, by key K, so it
    ///                                   verifies under EITHER B2 certificate
    /// ```
    ///
    /// The three chains the tests build:
    ///
    /// ```
    /// 1  accepted
    ///    goodLeaf --> Test Sub CA - B1 --> Test Root TLS CA - A1        [anchor]
    ///
    /// 2  refused: key 530C4DD6... is on the list
    ///    badLeaf ---> Test Sub CA - B2 --> Test Root TLS CA - A1        [anchor]
    ///                 cert B9555608...
    ///                 spki 530C4DD6...  <- match
    ///
    /// 3  refused: the SAME spki entry on the list, but different in everything else
    ///    badLeaf ---> Test Sub CA - B2 --> Test Cross-Signing Root      [anchor]
    ///    ^            cert AA4A2BA4...       CA - A2
    ///    |            spki 530C4DD6...  <- match
    ///    +-- byte-identical leaf to chain 2
    /// ```
    ///
    /// What a denylist sees across chains 2 and 3:
    ///
    /// ```
    ///                     chain 2        chain 3    one entry covers both?
    ///   leaf certificate  A56E512A  ==   A56E512A   (same leaf)
    ///   CA certificate    B9555608  !=   AA4A2BA4   no, needs two entries
    ///   CA public key     530C4DD6  ==   530C4DD6   yes, needs one entry
    ///   root              DA732553  !=   4C662354   no, different anchors
    ///   signature algo    ecdsa-384 !=   sha256RSA  no
    /// ```
    ///
    /// That middle 'CA public key' is the issue this is trying to address. The two chains differ in CA
    /// certificate, root, anchor and signature algorithm and agree only on the compromised
    /// key. `530C4DD656D2...` stands in for one of the eight `defaultRejectedSPKI`
    /// entries that replaced sixteen certificate digests.
    ///
    /// Chain 1 terminates at the same root as chain 2 and its CA shares an issuer
    /// with the compromised one, so a check keying off the issuer or the anchor
    /// would wrongly reject it.

    /// Root A: self-signed, and the anchor for chains 1 and 2.
    ///
    ///     subject  CN=Test Root TLS CA - A1
    ///     issuer   CN=Test Root TLS CA - A1
    ///     serial   717C81DB44CEE7B313F1FEA2BCD9ED9C87A29D73
    ///     cert     DA73255318C47A4EFA3AC71D76D464437439EE8483565C6A4A3FAEC161705FCC
    ///     spki     E14022E8076B909BA0E841487EFBCDC4AE9998D523D893BDD4535C7AB8F83300
    private static let testRootABase64 =
        "MIICGDCCAZ+gAwIBAgIUcXyB20TO57MT8f6ivNntnIeinXMwCgYIKoZIzj0EAwMwTDEdMBsG" +
        "A1UECgwUU2lnbmFsIFRlc3QgRml4dHVyZXMxCzAJBgNVBAYTAlVTMR4wHAYDVQQDDBVUZXN0" +
        "IFJvb3QgVExTIENBIC0gQTEwHhcNMjYxMDIyMTYwODM1WhcNMzYxMDE5MTYwODM1WjBMMR0w" +
        "GwYDVQQKDBRTaWduYWwgVGVzdCBGaXh0dXJlczELMAkGA1UEBhMCVVMxHjAcBgNVBAMMFVRl" +
        "c3QgUm9vdCBUTFMgQ0EgLSBBMTB2MBAGByqGSM49AgEGBSuBBAAiA2IABNh5wapXCKgOQQc7" +
        "qVemN/TO5BxcCNLcROZRt92HeGQaL/nKLJjj8EbKScMbeKD65fsLdx7m2MiO4r5uGZKb8Ojo" +
        "RDfsOskNmC/hAr43rAddU3T16qXRseo4cdrktpbRE6NCMEAwDwYDVR0TAQH/BAUwAwEB/zAO" +
        "BgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFK1nJ/9drStEuc+5xQHk62ChdKirMAoGCCqGSM49" +
        "BAMDA2cAMGQCMG+k54SpudIclKkwfygYFuxlzZCl0NWcTF5mys7qIbEwABqw4tEfTsQj07ZH" +
        "OagMvQIwU9VaFy08dDZ2htpxFzukWLhsyWa+Ji2R09QtcYBq3DdFlQs3tNedgRlRsv+2sPTc"

    /// Root B: self-signed, and the anchor for chain 3. RSA, so the two
    /// cross-signed certificates differ in signature algorithm as well as issuer.
    ///
    ///     subject  CN=Test Cross-Signing Root CA - A2
    ///     issuer   CN=Test Cross-Signing Root CA - A2
    ///     serial   0634DA7022AAFF06AC4442A8AF9E63D64D90E848
    ///     cert     4C662354F3692A4BC9D2074337B738CEC06238D2E960CE56373313750CCA0848
    ///     spki     3D0C5628AB5D7067914809CE88681E538AD2208F2BE0E34C3FEB7D0AEF2DE4BC
    private static let testRootBBase64 =
        "MIIDfDCCAmSgAwIBAgIUBjTacCKq/wasREKor55j1k2Q6EgwDQYJKoZIhvcNAQELBQAwVjEd" +
        "MBsGA1UECgwUU2lnbmFsIFRlc3QgRml4dHVyZXMxCzAJBgNVBAYTAlVTMSgwJgYDVQQDDB9U" +
        "ZXN0IENyb3NzLVNpZ25pbmcgUm9vdCBDQSAtIEEyMB4XDTI2MTAyMjE2MDgzNVoXDTM2MTAx" +
        "OTE2MDgzNVowVjEdMBsGA1UECgwUU2lnbmFsIFRlc3QgRml4dHVyZXMxCzAJBgNVBAYTAlVT" +
        "MSgwJgYDVQQDDB9UZXN0IENyb3NzLVNpZ25pbmcgUm9vdCBDQSAtIEEyMIIBIjANBgkqhkiG" +
        "9w0BAQEFAAOCAQ8AMIIBCgKCAQEArwDQlXrdL1WKblGezfFmbq5yx8RLyweo1hn0T3oK/ZfE" +
        "DEWipLQqb6cUOWj2otzu3LIRvOJFsFir0cii5Rz7SmY4b7SmuBn/W0m2LdWtWeYlQnaos/1c" +
        "y5gCqO4wNOtrFwpzFa6e3lI41rAIW4FfIiUePq8LHQMqckKbrPnZpBTlb8MTprSF6k4kMN6d" +
        "LtXODoQaUG3VCBJaw3hWfYG9X1hkWxOKFDi5mPKjk8zAm94kXLrD/QoIQcSp3TDNMON5tp94" +
        "yaUQ/SoSG+KRAZoZKCOAkP9mezPXtnpxQ9WZaYyqqgOAT8YFQSKLMjnTs7z7ndgI31o8nc8B" +
        "autIOsDbZQIDAQABo0IwQDAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBBjAdBgNV" +
        "HQ4EFgQU7GH1g34648GXH8l0RuluFAcT3RUwDQYJKoZIhvcNAQELBQADggEBAGlE3NRGi7HC" +
        "zJMycWVj3ameOBfinUQb2W9tr8RQtDaNoNskVSEEQ/d7PSykZnPuu0aLFbGbqXuy9kB+W6ZM" +
        "PJfk8Kp0HNmO1sfqQSHgV5XUii2BEoykYjx8tZNdalaxTh89wwl2yUx6koOXhet9HgE7w8Nn" +
        "Fz0R97Q3tD5rVn3A9c2UtYOvswmLW6Wot6ZlrOyqr9ekW+YaB3VkD2rsSyuERvT7f1lj0+rX" +
        "qK64ZkziezBikpiDCzNEdXK4xSHJUfTVKsEEeS1c0MmnMU7VLUtvdf8eYa/gkrpx4SJX4hUq" +
        "wZOb75K5W5yIAcLrE2pYeH7c/rvTp319R18TX6mEwWs="

    /// (1) The good sub-CA. Issued by root A, so it shares an issuer
    /// with the compromised CA below and terminates at the same anchor.
    ///
    ///     subject  CN=Test Sub CA - B1
    ///     issuer   CN=Test Root TLS CA - A1
    ///     serial   1002
    ///     cert     EDBCA335C77983767674D0F79C7C85C2B2E3DE24E0D7AC2CF34989B26888C6CF
    ///     spki     A2312828634588F0415D6FA55F8B885093ACC051D73C01658310E73CA30C3EB5
    private static let goodCaBase64 =
        "MIICSDCCAc2gAwIBAgICEAIwCgYIKoZIzj0EAwMwTDEdMBsGA1UECgwUU2lnbmFsIFRlc3Qg" +
        "Rml4dHVyZXMxCzAJBgNVBAYTAlVTMR4wHAYDVQQDDBVUZXN0IFJvb3QgVExTIENBIC0gQTEw" +
        "HhcNMjYxMDIyMTYwODM1WhcNMzYxMDE5MTYwODM1WjBHMR0wGwYDVQQKDBRTaWduYWwgVGVz" +
        "dCBGaXh0dXJlczELMAkGA1UEBhMCVVMxGTAXBgNVBAMMEFRlc3QgU3ViIENBIC0gQjEwdjAQ" +
        "BgcqhkjOPQIBBgUrgQQAIgNiAATTvO7ueGRNhm0FOiLls/GmHaHzD77u1kEBbeGZ/iPp0Usz" +
        "S0xtdRfNA7juqrsMAeKpHUa4ZY7m87EhNmm6MFxD7BlDsYabIb5w9vR00xlVfOdz0KFKNRSO" +
        "WJPjGobb7JKjgYYwgYMwEgYDVR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8EBAMCAQYwHQYD" +
        "VR0OBBYEFL38NEeC8oWbObmhWgYCqdi+/1vnMB8GA1UdIwQYMBaAFK1nJ/9drStEuc+5xQHk" +
        "62ChdKirMB0GA1UdJQQWMBQGCCsGAQUFBwMBBggrBgEFBQcDAjAKBggqhkjOPQQDAwNpADBm" +
        "AjEAiMDzeW1v4HwzIuBriQBUHnxwOYoSdk0hRxHJJMypcCv/sbaUWktc5HKYcF+B00OAAjEA" +
        "s9OnKIzFBsTwGmuoVwNrAmbaPjC6//qbIWwHhEauJum8CU8D/8HcKPKPRadAcw31"

    /// (2) The compromised sub-CA, as issued by root A.
    ///
    ///     subject  CN=Test Sub CA - B2
    ///     issuer   CN=Test Root TLS CA - A1
    ///     serial   1001
    ///     cert     B95556082481A867BFC8613E622A17351B8A8085A16C74169A7B18524B11A1DE
    ///     spki     530C4DD656D2A0F117D5A9D2A6157DF39885D466F8A9524D6702A978F8E40AF4
    private static let badCaBase64 =
        "MIICRjCCAc2gAwIBAgICEAEwCgYIKoZIzj0EAwMwTDEdMBsGA1UECgwUU2lnbmFsIFRlc3Qg" +
        "Rml4dHVyZXMxCzAJBgNVBAYTAlVTMR4wHAYDVQQDDBVUZXN0IFJvb3QgVExTIENBIC0gQTEw" +
        "HhcNMjYxMDIyMTYwODM1WhcNMzYxMDE5MTYwODM1WjBHMR0wGwYDVQQKDBRTaWduYWwgVGVz" +
        "dCBGaXh0dXJlczELMAkGA1UEBhMCVVMxGTAXBgNVBAMMEFRlc3QgU3ViIENBIC0gQjIwdjAQ" +
        "BgcqhkjOPQIBBgUrgQQAIgNiAASIEBGW0N9ITrIWrXvoy+KARrA9EfUyjPjEBfxgfHcuwwPT" +
        "tJEKYhGtOFJt96E91mvwU74zxN5dArYul5FjE43V1/iUWHLWPW3yIfIYfJDfz6OFTSIvQkee" +
        "/FZUaHGCykCjgYYwgYMwEgYDVR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8EBAMCAQYwHQYD" +
        "VR0OBBYEFBY/uDZ8nmEiM1rpVUh/Rr1mdN91MB8GA1UdIwQYMBaAFK1nJ/9drStEuc+5xQHk" +
        "62ChdKirMB0GA1UdJQQWMBQGCCsGAQUFBwMBBggrBgEFBQcDAjAKBggqhkjOPQQDAwNnADBk" +
        "AjAd7i/xE0q7HqqW0jW1v78oUIlISS22oE1mdHBxibrT2fE2M0dJQaw/mbUOmDIXpVkCMC8E" +
        "m1UDdSswgSkb6cP00w/7hSOdjVPj8DWjiPGvIC7l7jol0p3ZxQgsG7ALVs5oNQ=="

    /// (3) The same CA and the same key pair, cross-signed by root B.
    /// Note that `spki` matches (2) exactly while `cert` does not.
    ///
    ///     subject  CN=Test Sub CA - B2
    ///     issuer   CN=Test Cross-Signing Root CA - A2
    ///     serial   2001
    ///     cert     AA4A2BA4274636224562F246CC603FD1EDD329D7AA7402082B0A404177D10F6D
    ///     spki     530C4DD656D2A0F117D5A9D2A6157DF39885D466F8A9524D6702A978F8E40AF4
    private static let crossSignedBadCaBase64 =
        "MIIC8jCCAdqgAwIBAgICIAEwDQYJKoZIhvcNAQELBQAwVjEdMBsGA1UECgwUU2lnbmFsIFRl" +
        "c3QgRml4dHVyZXMxCzAJBgNVBAYTAlVTMSgwJgYDVQQDDB9UZXN0IENyb3NzLVNpZ25pbmcg" +
        "Um9vdCBDQSAtIEEyMB4XDTI2MTAyMjE2MDgzNVoXDTM2MTAxOTE2MDgzNVowRzEdMBsGA1UE" +
        "CgwUU2lnbmFsIFRlc3QgRml4dHVyZXMxCzAJBgNVBAYTAlVTMRkwFwYDVQQDDBBUZXN0IFN1" +
        "YiBDQSAtIEIyMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAEiBARltDfSE6yFq176MvigEawPRH1" +
        "Moz4xAX8YHx3LsMD07SRCmIRrThSbfehPdZr8FO+M8TeXQK2LpeRYxON1df4lFhy1j1t8iHy" +
        "GHyQ38+jhU0iL0JHnvxWVGhxgspAo4GGMIGDMBIGA1UdEwEB/wQIMAYBAf8CAQAwDgYDVR0P" +
        "AQH/BAQDAgEGMB0GA1UdDgQWBBQWP7g2fJ5hIjNa6VVIf0a9ZnTfdTAfBgNVHSMEGDAWgBTs" +
        "YfWDfjrjwZcfyXRG6W4UBxPdFTAdBgNVHSUEFjAUBggrBgEFBQcDAQYIKwYBBQUHAwIwDQYJ" +
        "KoZIhvcNAQELBQADggEBAEtgnboFcDRyGaK3xHDNkGyEFJjk7SNLaFlUAVTbBTqbrHMXJ5Yb" +
        "tqsAbAxij47xUIZlG7kQN+n8+wCbnLEw92p5SrwF5slWyStxfm46/Y+PocEY0zHAmHo+/JPl" +
        "hugVc4Fac+hYvd/eG/UI82wrZXyZjjiU/QtA7rlOoiYkfGKZxS4hwzP7Nb7wyAOmEpSl1qSq" +
        "P3RnRYn76hYdt1dSJ9VWBx4I12HnqfZ4aYdxwehoC+WYKOcwfak7WDTtRS6mLHQzLeUXUdsc" +
        "HLyfY2/vRy7rC+xYNpKiJVs0ydP+Qyfq6/O/uZuh28A4EHhZoqGGYNQ3pH0gY9DIRbmip+I1" +
        "bJk="

    /// goodLeaf: the end-entity certificate beneath B1.
    ///
    ///     subject  CN=goodleaf.signal.org
    ///     issuer   CN=Test Sub CA - B1
    ///     serial   3001
    ///     cert     98D8455C9F60772C8E9F1769F5038C06CD8A37E3098EC8FC48317F93A1907583
    ///     spki     87BD82136036A7E66B2701313AC6B086A05CB90401B8CF6328BBDA92F41963BB
    private static let goodLeafBase64 =
        "MIICNzCCAb6gAwIBAgICMAEwCgYIKoZIzj0EAwMwRzEdMBsGA1UECgwUU2lnbmFsIFRlc3Qg" +
        "Rml4dHVyZXMxCzAJBgNVBAYTAlVTMRkwFwYDVQQDDBBUZXN0IFN1YiBDQSAtIEIxMB4XDTI2" +
        "MTAyMjE2MDgzNVoXDTI3MTEyMzE2MDgzNVowSjEdMBsGA1UECgwUU2lnbmFsIFRlc3QgRml4" +
        "dHVyZXMxCzAJBgNVBAYTAlVTMRwwGgYDVQQDDBNnb29kbGVhZi5zaWduYWwub3JnMFkwEwYH" +
        "KoZIzj0CAQYIKoZIzj0DAQcDQgAE2u4WAKUfQi1WoMNEyL2PVqSb4JCGuZ7BvE1KiYFeQ1fd" +
        "GD/NzI4VP21py8IuRdsv+ZFNuY9wGV5RDobLXBoRsqOBljCBkzAMBgNVHRMBAf8EAjAAMA4G" +
        "A1UdDwEB/wQEAwIFoDATBgNVHSUEDDAKBggrBgEFBQcDATAdBgNVHQ4EFgQUcOTYztCWIwUA" +
        "nHUrLSB7SoBHHw4wHwYDVR0jBBgwFoAUvfw0R4LyhZs5uaFaBgKp2L7/W+cwHgYDVR0RBBcw" +
        "FYITZ29vZGxlYWYuc2lnbmFsLm9yZzAKBggqhkjOPQQDAwNnADBkAjAwKtElsOEJe6qE/Der" +
        "fZKCd3mEdYpBxxUPSNIpu0lMUMGBKtG6TwPHyef7rgMqWMwCMHlB1O5lNvTb9OGrkqY1v8oV" +
        "xF2SY/9Dis7VXNGq69+lZTjFvc1olhpVI64scMfPag=="

    /// badLeaf: the end-entity certificate beneath B2. Signed by that CA's
    /// key, so it validates through either (2) or (3) unchanged.
    ///
    ///     subject  CN=badleaf.signal.org
    ///     issuer   CN=Test Sub CA - B2
    ///     serial   3002
    ///     cert     A56E512A397EA000ECF9D399962327C732518E8CD8764ABDC0CDA117AB1952A6
    ///     spki     3B51EB93CB1A0231EDC9FDFE97BF417BD34DF13FD67371A909205BE4E820F284
    private static let badLeafBase64 =
        "MIICNTCCAbygAwIBAgICMAIwCgYIKoZIzj0EAwMwRzEdMBsGA1UECgwUU2lnbmFsIFRlc3Qg" +
        "Rml4dHVyZXMxCzAJBgNVBAYTAlVTMRkwFwYDVQQDDBBUZXN0IFN1YiBDQSAtIEIyMB4XDTI2" +
        "MTAyMjE2MDgzNVoXDTI3MTEyMzE2MDgzNVowSTEdMBsGA1UECgwUU2lnbmFsIFRlc3QgRml4" +
        "dHVyZXMxCzAJBgNVBAYTAlVTMRswGQYDVQQDDBJiYWRsZWFmLnNpZ25hbC5vcmcwWTATBgcq" +
        "hkjOPQIBBggqhkjOPQMBBwNCAARISsGJ2hwFPsGIS+gu2Ci+2zeqpzPidELtn5Wy5bElHEK+" +
        "sV9dFbDEMVcjUMwGeowHcKh3TWN6FLZ2Ka5zNPA6o4GVMIGSMAwGA1UdEwEB/wQCMAAwDgYD" +
        "VR0PAQH/BAQDAgWgMBMGA1UdJQQMMAoGCCsGAQUFBwMBMB0GA1UdDgQWBBTol2o4HAsbCgfT" +
        "taVO8uecoTIaPDAfBgNVHSMEGDAWgBQWP7g2fJ5hIjNa6VVIf0a9ZnTfdTAdBgNVHREEFjAU" +
        "ghJiYWRsZWFmLnNpZ25hbC5vcmcwCgYIKoZIzj0EAwMDZwAwZAIwVoYCGE6AzHOVIP0vvbp8" +
        "cGrC0CTkTn3Scdl0aExOvlz6AbcjCQQp8MMPWO7GblxVAjBKOjUVE7aa7lcZonQxvnJj+p4y" +
        "X8+qxb6V+ryehh9zcPZhgsXnacIAKPZrfB5UT28="
}

struct DERScannerTest {

    // MARK: - DERScanner tests

    // These could go in a separate file, but its a small test, and
    // the struct is internal to HttpSecurityPolicyTest
    // Also, for explaination of the fields in the test,
    // see: https://en.wikipedia.org/wiki/X.690#DER_encoding

    /// Malformed input is rejected rather than parsed into something arbitrary.
    @Test
    func derScannerRejectsMalformedInput() {
        func firstElement(_ bytes: Data) -> HttpSecurityPolicy.DERScanner.Element? {
            var scanner = HttpSecurityPolicy.DERScanner(data: bytes)
            return scanner.read()
        }

        // Too short to hold even a tag and a length.
        #expect(firstElement(Data()) == nil)
        #expect(firstElement(Data([0x30])) == nil) // 0x30 => SEQUENCE

        // The indefinite length form (0x80 0x00), which DER doesn't permit.
        #expect(firstElement(Data([0x30, 0x80, 0x00, 0x00])) == nil)

        // A static length that runs past the end of the available bytes.
        #expect(firstElement(Data([0x30, 0x7F, 0x01, 0x02])) == nil)
        // A variable length that runs past the end of the available bytes.
        #expect(firstElement(Data([0x30, 0x84, 0x7F, 0xFF, 0xFF, 0xFF])) == nil)

        // A long form length too large to be a certificate.
        #expect(firstElement(Data([0x30, 0x85, 0x01, 0x02, 0x03, 0x04, 0x05])) == nil)
    }

    /// A well-formed element reports its own bounds and those of its contents.
    @Test
    func derScannerReadsElements() throws {
        // SEQUENCE { INTEGER 1 }, then a trailing INTEGER 2.
        var scanner = HttpSecurityPolicy.DERScanner(data: Data([0x30, 0x03, 0x02, 0x01, 0x01, 0x02, 0x01, 0x02]))

        let sequenceRead = scanner.read()
        let sequence = try #require(sequenceRead)
        #expect(sequence.tag == HttpSecurityPolicy.DERScanner.sequenceTag)
        #expect(sequence.elementRange == 0..<5)
        #expect(sequence.contentRange == 2..<5)

        let trailingIntegerRead = scanner.read()
        let trailing = try #require(trailingIntegerRead)
        #expect(trailing.elementRange == 5..<8)

        #expect(scanner.read() == nil)
    }
}
