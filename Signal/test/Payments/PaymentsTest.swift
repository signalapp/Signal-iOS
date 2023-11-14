//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import MobileCoin
@testable import Signal
@testable import SignalMessaging
@testable import SignalServiceKit
@testable import SignalUI

class PaymentsTest: SignalBaseTest {
    override func setUp() {
        super.setUp()

        SSKEnvironment.shared.setPaymentsHelperForUnitTests(PaymentsHelperImpl())
        SUIEnvironment.shared.paymentsRef = PaymentsImpl()
    }

    func test_urlRoundtrip() {
        let publicAddressBase58 = "2HWLR6wNtJAYbuyZom35NMrz2uugsBtrdTcmwEtDgGmSHuEWpuosZy9rqLJNXLKWpAWXR8KjFUzScYhmyr1wzi3bYrMffdUzzCFbcRqoKvdPFrTvnS8TB2GmQG3zZbME4gNEs7bvvEQfHQ3SpRk6TQEbMcsfF3G1a1SEWz8v7ucEJZ1Wc9tV1ykfHgAVEZGMHUGeWns34LnUPneEfbzsizafEqY7iXnt9GFntZ53UYx2PNQ3xgWcAc8RPTi7"
        guard let publicAddress = PaymentsImpl.parse(publicAddressBase58: publicAddressBase58) else {
            XCTFail("Could not parse publicAddressBase58.")
            return
        }
        XCTAssertEqual(publicAddressBase58, PaymentsImpl.formatAsBase58(publicAddress: publicAddress))

        let urlString = PaymentsImpl.formatAsUrl(publicAddress: publicAddress)
        guard let url = URL(string: urlString) else {
            XCTFail("Invalid urlString.")
            return
        }
        guard let publicAddressFromUrl = PaymentsImpl.parseAsPublicAddress(url: url) else {
            XCTFail("Could not parse url.")
            return
        }
        XCTAssertEqual(publicAddressBase58, PaymentsImpl.formatAsBase58(publicAddress: publicAddressFromUrl))
    }

    func test_passphraseRoundtrip1() {
        let paymentsEntropy = Randomness.generateRandomBytes(Int32(PaymentsConstants.paymentsEntropyLength))
        guard let passphrase = self.paymentsSwift.passphrase(forPaymentsEntropy: paymentsEntropy) else {
            XCTFail("Missing passphrase.")
            return
        }
        XCTAssertEqual(paymentsEntropy, self.paymentsSwift.paymentsEntropy(forPassphrase: passphrase))
    }

    func test_passphraseRoundtrip2() {
        let passphraseWords: [String] = "glide belt note artist surge aware disease cry mobile assume weird space pigeon scrap vast iron maximum begin rug public spice remember sword cruel".split(separator: " ").map { String($0) }
        let passphrase1 = try! PaymentsPassphrase(words: passphraseWords)
        let paymentsEntropy = self.paymentsSwift.paymentsEntropy(forPassphrase: passphrase1)!
        guard let passphrase2 = self.paymentsSwift.passphrase(forPaymentsEntropy: paymentsEntropy) else {
            XCTFail("Missing passphrase.")
            return
        }
        XCTAssertEqual(passphrase1, passphrase2)
        let paymentsEntropyExpected = Data(base64Encoded: "YwKeWoaNpCCPwamOYb/k6CpLgvxrsoliivRWjRlrdxE=")!
        XCTAssertEqual(paymentsEntropyExpected, paymentsEntropy)
    }

    func test_paymentAddressSigning() {
        let identityKeyPair = ECKeyPair.generateKeyPair()
        let publicAddressData = Randomness.generateRandomBytes(256)
        let signatureData = try! TSPaymentAddress.sign(identityKeyPair: identityKeyPair,
                                                       publicAddressData: publicAddressData)
        XCTAssertTrue(TSPaymentAddress.verifySignature(identityKey: identityKeyPair.keyPair.identityKey,
                                                       publicAddressData: publicAddressData,
                                                       signatureData: signatureData))
        let fakeSignatureData = Randomness.generateRandomBytes(Int32(signatureData.count))
        XCTAssertFalse(TSPaymentAddress.verifySignature(identityKey: identityKeyPair.keyPair.identityKey,
                                                        publicAddressData: publicAddressData,
                                                        signatureData: fakeSignatureData))
    }

    func test_isValidPhoneNumberForPayments_remoteConfigBlocklist() {
        XCTAssertTrue(PaymentsHelperImpl.isValidPhoneNumberForPayments_remoteConfigBlocklist("+523456",
                                                                                             paymentsDisabledRegions: ["1", "234"]))
        XCTAssertFalse(PaymentsHelperImpl.isValidPhoneNumberForPayments_remoteConfigBlocklist("+123456",
                                                                                              paymentsDisabledRegions: ["1", "234"]))
        XCTAssertTrue(PaymentsHelperImpl.isValidPhoneNumberForPayments_remoteConfigBlocklist("+233333333",
                                                                                             paymentsDisabledRegions: ["1", "234"]))
        XCTAssertFalse(PaymentsHelperImpl.isValidPhoneNumberForPayments_remoteConfigBlocklist("+234333333",
                                                                                              paymentsDisabledRegions: ["1", "234"]))
    }
}
