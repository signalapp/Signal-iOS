//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

import LibSignalClient
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
        let theirPublicKey = nullKey
        let profileKey = nullKey
        let accountAddress = SignalServiceAddress(uuid: UUID(), phoneNumber: "13213214321")

        let provisioner = OWSDeviceProvisioner(myAciIdentityKeyPair: IdentityKeyPair.generate(),
                                               theirPublicKey: theirPublicKey,
                                               theirEphemeralDeviceId: "",
                                               accountAddress: accountAddress,
                                               pni: UUID(),
                                               profileKey: profileKey,
                                               readReceiptsEnabled: true,
                                               provisioningCodeService: OWSFakeDeviceProvisioningCodeService(),
                                               provisioningService: OWSFakeDeviceProvisioningService())

        provisioner.provision(
            success: {
                expectation.fulfill()
            },
            failure: { error in
                XCTFail("Failed to provision with error: \(error)")
            })

        self.waitForExpectations(timeout: 5.0, handler: nil)
    }
}
