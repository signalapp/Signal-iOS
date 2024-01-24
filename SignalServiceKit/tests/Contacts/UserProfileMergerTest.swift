//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class UserProfileMergerTest: XCTestCase {
    private var userProfileStore: MockUserProfileStore!
    private var userProfileMerger: UserProfileMerger!

    override func setUp() {
        super.setUp()

        userProfileStore = MockUserProfileStore()
        userProfileMerger = UserProfileMerger(
            userProfileStore: userProfileStore,
            setProfileKeyShim: { [userProfileStore] userProfile, profileKey, tx in
                userProfile.setValue(profileKey, forKey: "profileKey")
                userProfileStore!.updateUserProfile(userProfile, tx: tx)
            }
        )
    }

    func testMergeLocal() {
        let aci = Aci.constantForTesting("00000000-0000-4000-8000-000000000aaa")
        let pni = Pni.constantForTesting("PNI:00000000-0000-4000-8000-000000000bbb")
        let phoneNumber = E164("+16505550100")!

        let localProfile = buildUserProfile(serviceId: nil, phoneNumber: OWSUserProfile.Constants.localProfilePhoneNumber, profileKey: nil)
        let otherProfile = buildUserProfile(serviceId: Aci.randomForTesting(), phoneNumber: nil, profileKey: nil)

        userProfileStore.userProfiles = [
            localProfile,
            buildUserProfile(serviceId: aci, phoneNumber: nil, profileKey: Data(repeating: 1, count: 32)),
            buildUserProfile(serviceId: nil, phoneNumber: phoneNumber.stringValue, profileKey: Data(repeating: 2, count: 32)),
            buildUserProfile(serviceId: pni, phoneNumber: nil, profileKey: Data(repeating: 3, count: 32)),
            otherProfile
        ]

        MockDB().write { tx in
            userProfileMerger.didLearnAssociation(
                mergedRecipient: MergedRecipient(
                    isLocalRecipient: true,
                    oldRecipient: nil,
                    newRecipient: SignalRecipient(aci: aci, pni: pni, phoneNumber: phoneNumber)
                ),
                tx: tx
            )
        }

        XCTAssertEqual(userProfileStore.userProfiles, [localProfile, otherProfile])
    }

    func testMergeOther() {
        let aci = Aci.constantForTesting("00000000-0000-4000-8000-000000000aaa")
        let pni = Pni.constantForTesting("PNI:00000000-0000-4000-8000-000000000bbb")
        let phoneNumber = E164("+16505550100")!

        let localProfile = buildUserProfile(serviceId: nil, phoneNumber: OWSUserProfile.Constants.localProfilePhoneNumber, profileKey: nil)
        let otherAciProfile = buildUserProfile(serviceId: Aci.randomForTesting(), phoneNumber: phoneNumber.stringValue, profileKey: nil)
        let otherPniProfile = buildUserProfile(serviceId: pni, phoneNumber: "+16505550101", profileKey: nil)
        let finalProfile = buildUserProfile(serviceId: aci, phoneNumber: nil, profileKey: nil)

        userProfileStore.userProfiles = [
            localProfile,
            finalProfile,
            buildUserProfile(serviceId: aci, phoneNumber: phoneNumber.stringValue, profileKey: Data(repeating: 2, count: 32)),
            buildUserProfile(serviceId: nil, phoneNumber: phoneNumber.stringValue, profileKey: Data(repeating: 3, count: 32)),
            buildUserProfile(serviceId: pni, phoneNumber: phoneNumber.stringValue, profileKey: Data(repeating: 4, count: 32)),
            buildUserProfile(serviceId: pni, phoneNumber: nil, profileKey: Data(repeating: 5, count: 32)),
            otherAciProfile,
            otherPniProfile
        ]

        MockDB().write { tx in
            userProfileMerger.didLearnAssociation(
                mergedRecipient: MergedRecipient(
                    isLocalRecipient: false,
                    oldRecipient: nil,
                    newRecipient: SignalRecipient(aci: aci, pni: pni, phoneNumber: phoneNumber)
                ),
                tx: tx
            )
        }

        finalProfile.phoneNumber = phoneNumber.stringValue
        finalProfile.setValue(OWSAES256Key(data: Data(repeating: 2, count: 32))!, forKey: "profileKey")
        otherAciProfile.phoneNumber = nil
        otherPniProfile.serviceIdString = nil
        XCTAssertEqual(userProfileStore.userProfiles, [localProfile, finalProfile, otherAciProfile, otherPniProfile])
    }

    private func buildUserProfile(serviceId: ServiceId?, phoneNumber: String?, profileKey: Data?) -> OWSUserProfile {
        return OWSUserProfile(
            id: nil,
            uniqueId: UUID().uuidString,
            serviceIdString: serviceId?.serviceIdUppercaseString,
            phoneNumber: phoneNumber,
            avatarFileName: nil,
            avatarUrlPath: nil,
            profileKey: profileKey.map { OWSAES256Key(data: $0)! },
            givenName: nil,
            familyName: nil,
            bio: nil,
            bioEmoji: nil,
            badges: [],
            lastFetchDate: nil,
            lastMessagingDate: nil,
            isPniCapable: false
        )
    }
}
