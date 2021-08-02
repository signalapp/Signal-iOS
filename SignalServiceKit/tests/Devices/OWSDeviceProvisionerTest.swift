//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest

@testable import SignalServiceKit

class OWSDeviceProvisionerTest: SSKBaseTestSwift {

    class OWSFakeDeviceProvisioningService: OWSDeviceProvisioningService {
        public override func provision(messageBody: Data,
                                       ephemeralDeviceId: String,
                                       success: @escaping () -> Void,
                                       failure: @escaping (Error) -> Void) {
            Logger.info("faking successful provisioning")
            success()
        }
    }

    // MARK: -

    class OWSFakeDeviceProvisioningCodeService: OWSDeviceProvisioningCodeService {
        public override func requestProvisioningCode(success: @escaping (String) -> Void,
                                                     failure: @escaping (Error) -> Void) {
            Logger.info("faking successful provisioning code fetching")
            success("fake-provisioning-code")
        }
    }

    // MARK: -

    override func setUp() {
        super.setUp()

        let sskEnvironment = SSKEnvironment.shared as! MockSSKEnvironment
        sskEnvironment.networkManagerRef = OWSFakeNetworkManager()
    }

    func testProvisioning() {
        let expectation = self.expectation(description: "Provisioning Success")

        let nullKey = Data(repeating: 0, count: 32)
        let myPublicKey = nullKey
        let myPrivateKey = nullKey
        let theirPublicKey = nullKey
        let profileKey = nullKey
        let accountAddress = SignalServiceAddress(phoneNumber: "13213214321")

        let provisioner = OWSDeviceProvisioner(myPublicKey: myPublicKey,
                                               myPrivateKey: myPrivateKey,
                                               theirPublicKey: theirPublicKey,
                                               theirEphemeralDeviceId: "",
                                               accountAddress: accountAddress,
                                               profileKey: profileKey,
                                               readReceiptsEnabled: true,
                                               provisioningCodeService: OWSFakeDeviceProvisioningCodeService(),
                                               provisioningService: OWSFakeDeviceProvisioningService())

        provisioner.provision(success: {
            expectation.fulfill()
        },
        failure: { error in
            XCTFail("Failed to provision with error: \(error)")
        })

        self.waitForExpectations(timeout: 5.0, handler: nil)
    }
}
