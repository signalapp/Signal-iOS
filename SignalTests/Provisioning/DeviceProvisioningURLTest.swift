//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import Testing
@testable import Signal

struct DeviceProvisioningURLTest {
    @Test(arguments: [
        (
            urlString: "sgnl://linkdevice?uuid=asd&pub_key=BQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            uuid: "asd",
            publicKeyData: Data(repeating: 0, count: 32),
        ),
        (
            urlString: "sgnl://linkdevice?uuid=nw_QVJRauc7Y-g39lB_3fA%3D%3D&pub_key=BdDF6+/UPrbtdNGGRtLqDie8khmxlEEMrN8t/mNF1m5V&capabilities=",
            uuid: "nw_QVJRauc7Y-g39lB_3fA==",
            publicKeyData: Data(base64Encoded: "0MXr79Q+tu100YZG0uoOJ7ySGbGUQQys3y3+Y0XWblU=")!,
        ),
        (
            urlString: "sgnl://linkdevice?uuid=nw_QVJRauc7Y-g39lB_3fA%3D%3D&pub_key=BdDF6%2B%2FUPrbtdNGGRtLqDie8khmxlEEMrN8t%2FmNF1m5V&capabilities=",
            uuid: "nw_QVJRauc7Y-g39lB_3fA==",
            publicKeyData: Data(base64Encoded: "0MXr79Q+tu100YZG0uoOJ7ySGbGUQQys3y3+Y0XWblU=")!,
        ),
        (
            urlString: "sgnl://linkdevice?uuid=nw_QVJRauc7Y-g39lB_3fA%3D%3D&pub_key=BdDF6-_UPrbtdNGGRtLqDie8khmxlEEMrN8t_mNF1m5V&capabilities=",
            uuid: "nw_QVJRauc7Y-g39lB_3fA==",
            publicKeyData: Data(base64Encoded: "0MXr79Q+tu100YZG0uoOJ7ySGbGUQQys3y3+Y0XWblU=")!,
        ),
    ])
    func testValid(testCase: (urlString: String, uuid: String, publicKeyData: Data)) throws {
        let url = try #require(DeviceProvisioningURL(urlString: testCase.urlString))
        #expect(url.ephemeralDeviceId == testCase.uuid)
        let publicKey = try PublicKey(keyData: testCase.publicKeyData)
        #expect(url.publicKey == publicKey)
    }

    @Test(arguments: [
        "",
        "sgnl://linkdevice?uuid=BQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "sgnl://linkdevice?pub_key=BQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "sgnl://linkdevice/uuid=asd&pub_key=BQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    ])
    func testInvalid(urlString: String) {
        #expect(DeviceProvisioningURL(urlString: urlString) == nil)
    }
}
