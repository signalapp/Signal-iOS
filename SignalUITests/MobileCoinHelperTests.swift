//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import SignalUI

class MobileCoinHelperTests: XCTestCase {
    func testInfoForReceiptData() {
        let receiptData = Data(base64Encoded: """
        CiIKIARfCkd3ZdIMRhXSGvi72N2cDjtc5A0LvdPCgTMBWX5JEiIKIFf4+WnFJ5XvgQ3Si6ewxByjiZKIhwJO4AfN1cP\
        9PDr+GGQiLQoiCiDIZT/y7TcjyGcnounBT/vfd3aEthkR9NSPRDC3iwGQFxG5uTt4u1G0bg==
        """)!

        let helperSDK = MobileCoinHelperSDK()
        let helperMinimal = MobileCoinHelperMinimal()

        let infoSDK = try! helperSDK.info(forReceiptData: receiptData)
        let infoMinimal = try! helperMinimal.info(forReceiptData: receiptData)
        XCTAssertEqual(infoSDK.txOutPublicKey, infoMinimal.txOutPublicKey)

        let txOutPublicKeyData = Data(base64Encoded: "BF8KR3dl0gxGFdIa+LvY3ZwOO1zkDQu908KBMwFZfkk=")!
        XCTAssertEqual(txOutPublicKeyData, infoSDK.txOutPublicKey)
        XCTAssertEqual(txOutPublicKeyData, infoMinimal.txOutPublicKey)
    }

    func testIsValidMobileCoinPublicAddress() {
        let addressData = Data(base64Encoded: """
        CiIKIAitQoKLk05lkHlPeIxaVZmvoSyoCAuQr7u/kooKMM1vEiIKIEqh630jt7/k2zlzJ32Fhy633P4XXJPFyHWOz9e\
        ArWoQGiRmb2c6Ly9mb2ctcmVwb3J0LmZha2UubW9iaWxlY29pbi5jb20qQEIjVGb+GOA3SXR9U2uPAY9AX02bJQsh28\
        MHNhMoep49uuWGzbq7a0Ya2YJyNb7xUqpSBnmjAKfpUQLqQkMMzYE=
        """)!

        let helperSDK = MobileCoinHelperSDK()
        let helperMinimal = MobileCoinHelperMinimal()

        XCTAssertTrue(helperSDK.isValidMobileCoinPublicAddress(addressData))
        XCTAssertTrue(helperMinimal.isValidMobileCoinPublicAddress(addressData))

        let randomData = Randomness.generateRandomBytes(Int32(addressData.count))
        XCTAssertFalse(helperSDK.isValidMobileCoinPublicAddress(randomData))
        XCTAssertFalse(helperMinimal.isValidMobileCoinPublicAddress(randomData))
    }
}
