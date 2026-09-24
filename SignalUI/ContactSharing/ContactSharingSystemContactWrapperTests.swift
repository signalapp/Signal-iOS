//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import Testing

@testable import SignalServiceKit
@testable import SignalUI

@MainActor
struct ContactSharingSystemContactWrapperTests {

    /// Pinned so that tests don't depend on the device's name-display settings.
    private let comparableValueConfig = DisplayName.ComparableValue.Config(
        displayNameConfig: DisplayName.Config(shouldUseSystemContactNicknames: false),
        shouldSortByGivenName: true,
    )

    @Test
    func testAPersonIsNamedAndAlphabetizedByTheirName() throws {
        let wrapper = try #require(makeWrapper(givenName: "Ada", familyName: "Lovelace"))

        #expect(wrapper.displayName == "Ada Lovelace")
        #expect(!wrapper.isGroupedAtEnd)
        #expect(wrapper.hasName)
        #expect(wrapper.avatarNameComponents.givenName == "Ada")
        #expect(wrapper.avatarNameComponents.familyName == "Lovelace")
    }

    @Test
    func testABusinessIsNamedByItsCompanyAndNotAlphabetized() throws {
        let wrapper = try #require(makeWrapper(organizationName: "Acme Plumbing"))

        #expect(wrapper.displayName == "Acme Plumbing")
        #expect(wrapper.isGroupedAtEnd)
        #expect(wrapper.hasName, "A company name is a name.")
        #expect(
            wrapper.avatarNameComponents.givenName == "Acme Plumbing",
            "The initials avatar has to match the name beside it.",
        )
    }

    @Test
    func testAMiddleNameOnlyCardIsAPerson() throws {
        let wrapper = try #require(makeWrapper(middleName: "Quincy"))

        #expect(wrapper.displayName == "Quincy")
        #expect(!wrapper.isGroupedAtEnd)
        #expect(wrapper.avatarNameComponents.givenName == "Quincy")
    }

    @Test
    func testAnEmailOnlyCardIsNotNamed() throws {
        let wrapper = try #require(makeWrapper(emailAddresses: ["plumber@example.com"]))

        #expect(wrapper.displayName == "plumber@example.com")
        #expect(wrapper.isGroupedAtEnd)
        #expect(!wrapper.hasName)
        #expect(wrapper.avatarNameComponents.givenName == "plumber@example.com")
    }

    @Test
    func testAPhoneOnlyCardFallsBackToItsNumber() throws {
        let wrapper = try #require(makeWrapper(phoneNumbers: ["+16505550101"]))

        #expect(wrapper.displayName == "+16505550101")
        #expect(wrapper.isGroupedAtEnd)
        #expect(!wrapper.hasName)
    }

    @Test
    func testACardWithNothingIsNotListable() {
        #expect(makeWrapper() == nil)
    }

    @Test
    func testTheOrganizationNameIsReadFromTheCard() throws {
        let wrapper = try #require(makeWrapper(givenName: "Ada", organizationName: "Acme Plumbing"))

        #expect(wrapper.displayName == "Ada", "A person's name wins over their employer.")
        #expect(wrapper.systemContact.organizationName == "Acme Plumbing")
    }

    private func makeWrapper(
        givenName: String = "",
        middleName: String = "",
        familyName: String = "",
        organizationName: String = "",
        phoneNumbers: [String] = [],
        emailAddresses: [String] = [],
    ) -> ContactSharingPickerViewModel.SystemContactWrapper? {
        let cnContact = CNMutableContact()
        cnContact.givenName = givenName
        cnContact.middleName = middleName
        cnContact.familyName = familyName
        cnContact.organizationName = organizationName
        cnContact.phoneNumbers = phoneNumbers.map {
            CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: $0))
        }
        cnContact.emailAddresses = emailAddresses.map {
            CNLabeledValue(label: CNLabelHome, value: $0 as NSString)
        }

        return ContactSharingPickerViewModel.SystemContactWrapper(
            systemContact: SystemContact(cnContact: cnContact),
            comparableValueConfig: comparableValueConfig,
        )
    }
}
