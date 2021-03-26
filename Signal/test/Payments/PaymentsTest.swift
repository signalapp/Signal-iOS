//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import XCTest
import PromiseKit
@testable import SignalServiceKit
@testable import SignalMessaging
@testable import Signal
@testable import MobileCoin

class PaymentsTest: SignalBaseTest {

    override func setUp() {
        super.setUp()

        let sskEnvironment = SSKEnvironment.shared as! MockSSKEnvironment
        sskEnvironment.payments = PaymentsImpl()
    }

    override func tearDown() {
        super.tearDown()
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

    func test_passphraseRoundtrip() {
        let paymentsEntropy = Randomness.generateRandomBytes(Int32(PaymentsConstants.paymentsEntropyLength))
        guard let passphrase = self.payments.passphrase(forPaymentsEntropy: paymentsEntropy) else {
            XCTFail("Missing passphrase.")
            return
        }
        XCTAssertEqual(paymentsEntropy, self.payments.paymentsEntropy(forPassphrase: passphrase))
        guard let mcRootEntropy = self.payments.mcRootEntropy(forPaymentsEntropy: paymentsEntropy) else {
            XCTFail("Missing mcRootEntropy.")
            return
        }
        XCTAssertEqual(mcRootEntropy.count, Int(PaymentsConstants.mcRootEntropyLength))
    }
}
