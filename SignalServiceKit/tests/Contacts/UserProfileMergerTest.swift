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
        let aci = Aci.constantForTesting("00000000-0000-4000-8000-000000000000")
        let phoneNumber = E164("+16505550100")!

        let localProfile = buildUserProfile(aci: nil, phoneNumber: kLocalProfileInvariantPhoneNumber, profileKey: nil)
        let otherProfile = buildUserProfile(aci: Aci.randomForTesting(), phoneNumber: nil, profileKey: nil)

        userProfileStore.userProfiles = [
            localProfile,
            buildUserProfile(aci: aci, phoneNumber: nil, profileKey: Data(repeating: 1, count: 32)),
            buildUserProfile(aci: nil, phoneNumber: phoneNumber.stringValue, profileKey: Data(repeating: 2, count: 32)),
            otherProfile
        ]

        MockDB().write { tx in
            userProfileMerger.didLearnAssociation(
                mergedRecipient: MergedRecipient(
                    aci: aci,
                    oldPhoneNumber: nil,
                    newPhoneNumber: phoneNumber,
                    isLocalRecipient: true,
                    signalRecipient: SignalRecipient(aci: aci, pni: nil, phoneNumber: phoneNumber)
                ),
                transaction: tx
            )
        }

        XCTAssertEqual(userProfileStore.userProfiles, [localProfile, otherProfile])
    }

    func testMergeOther() {
        let aci = Aci.constantForTesting("00000000-0000-4000-8000-000000000000")
        let phoneNumber = E164("+16505550100")!

        let localProfile = buildUserProfile(aci: nil, phoneNumber: kLocalProfileInvariantPhoneNumber, profileKey: nil)
        let otherProfile = buildUserProfile(aci: Aci.randomForTesting(), phoneNumber: phoneNumber.stringValue, profileKey: nil)
        let finalProfile = buildUserProfile(aci: aci, phoneNumber: nil, profileKey: nil)

        userProfileStore.userProfiles = [
            localProfile,
            finalProfile,
            buildUserProfile(aci: aci, phoneNumber: phoneNumber.stringValue, profileKey: Data(repeating: 2, count: 32)),
            buildUserProfile(aci: nil, phoneNumber: phoneNumber.stringValue, profileKey: Data(repeating: 3, count: 32)),
            otherProfile
        ]

        MockDB().write { tx in
            userProfileMerger.didLearnAssociation(
                mergedRecipient: MergedRecipient(
                    aci: aci,
                    oldPhoneNumber: nil,
                    newPhoneNumber: phoneNumber,
                    isLocalRecipient: false,
                    signalRecipient: SignalRecipient(aci: aci, pni: nil, phoneNumber: phoneNumber)
                ),
                transaction: tx
            )
        }

        finalProfile.recipientPhoneNumber = phoneNumber.stringValue
        finalProfile.setValue(OWSAES256Key(data: Data(repeating: 2, count: 32))!, forKey: "profileKey")
        otherProfile.recipientPhoneNumber = nil
        XCTAssertEqual(userProfileStore.userProfiles, [localProfile, finalProfile, otherProfile])
    }

    private func buildUserProfile(aci: Aci?, phoneNumber: String?, profileKey: Data?) -> OWSUserProfile {
        OWSUserProfile(
            grdbId: 0,
            uniqueId: UUID().uuidString,
            avatarFileName: nil,
            avatarUrlPath: nil,
            bio: nil,
            bioEmoji: nil,
            canReceiveGiftBadges: false,
            familyName: nil,
            isPniCapable: false,
            isStoriesCapable: false,
            lastFetchDate: nil,
            lastMessagingDate: nil,
            profileBadgeInfo: nil,
            profileKey: profileKey.map { OWSAES256Key(data: $0)! },
            profileName: nil,
            recipientPhoneNumber: phoneNumber,
            recipientUUID: aci?.serviceIdUppercaseString
        )
    }
}
