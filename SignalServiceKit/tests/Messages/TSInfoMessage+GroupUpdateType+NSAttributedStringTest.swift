//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit
import XCTest

class NSAttributedStringInGroupUpdateCopyTest: SSKBaseTestSwift {
    private func assertEqual(_ one: NSAttributedString, _ two: NSAttributedString) {
        XCTAssertEqual(one, two)
    }

    func test_XMadeYAnAdmin() {
        assertEqual(.aliceMadeBobAdmin, NSAttributedString.make(firstUser: .alice, madeAdmin: .bob))
        assertEqual(.aliceHMadeAliceAdmin, NSAttributedString.make(firstUser: .aliceH, madeAdmin: .alice))
        assertEqual(.aliceMadeMadeAdmin, NSAttributedString.make(firstUser: .alice, madeAdmin: .made))
        assertEqual(.aliceMadeAnotherAliceAdmin, NSAttributedString.make(firstUser: .alice, madeAdmin: .anotherAlice))
        assertEqual(.aliceMadeSingleArgFormatSpecifierAdmin, NSAttributedString.make(firstUser: .alice, madeAdmin: .singleArgFormatSpecifier))
        assertEqual(.aliceMadeMultiArgFormatSpecifierAdmin, NSAttributedString.make(firstUser: .alice, madeAdmin: .multiArgFormatSpecifier))
        assertEqual(.aliceMadeEmptyAdmin, NSAttributedString.make(firstUser: .alice, madeAdmin: .empty))
    }

    func test_XMadeYAnAdmin_ArabicNameInEnglishString() {
        assertEqual(.aliceMadeFatimaInArabicAnAdmin, NSAttributedString.make(firstUser: .alice, madeAdmin: .fatima))
    }

    func test_XMadeYAnAdmin_EnglishNameInArabicString() {
        assertEqual(.aliceMadeBobAdmin_Arabic, NSAttributedString.makeArabic(firstUser: .alice, madeAdmin: .bob))
    }

    func test_XMadeYAnAdmin_ChineseNameInEnglishString() {
        assertEqual(.qiInChineseMadeAliceAdmin, NSAttributedString.make(firstUser: .qi, madeAdmin: .alice))
    }

    func test_XMadeYAnAdmin_ChineseAndArabicNamesInArabicString() {
        assertEqual(.qiInChineseMadeFatimaInArabicAdmin_Arabic, NSAttributedString.makeArabic(firstUser: .qi, madeAdmin: .fatima))
    }

    /// Note that this test involves formatting numbers into a format string,
    /// which is done in the guts of Signal using the "current locale".
    /// Therefore, running this test outside of the "United States" locale in
    /// English will fail due to substitution errors.
    func test_XInvitedNPeople() throws {
        try XCTSkipIf(Locale.current.identifier != "en_US", "This test requires the en_US locale for number formatting.")

        assertEqual(.aliceInvitedOnePerson, NSAttributedString.make(user: .alice, invitedNPeople: 1))
        assertEqual(.aliceInvitedTwoPeople, NSAttributedString.make(user: .alice, invitedNPeople: 2))
        assertEqual(.aliceInvitedOneMillionPeople, NSAttributedString.make(user: .alice, invitedNPeople: 1000000))
        assertEqual(.emptyInvitedThreePeople, NSAttributedString.make(user: .empty, invitedNPeople: 3))
    }

    /// Technically this tests a string that is never used in group updates.
    /// However, we don't have any relevant strings that have the name at the
    /// end of the string, and I wanted to test that.
    func test_NameAtEndOfString() {
        assertEqual(
            .aliceSomethingWithBobsNameAtEndOfString,
            NSAttributedString.makeWithNameAtEndOfString(firstUser: .alice, userAtEndOfString: .bob, lang: "en")
        )

        assertEqual(
            .aliceSomethingWithBobsNameAtEndOfString_Arabic,
            NSAttributedString.makeWithNameAtEndOfString(firstUser: .alice, userAtEndOfString: .bob, lang: "ar")
        )
    }

    /// Some localized strings invert the "expected order" of format args, e.g.
    /// `%2$@` may be placed before `%1$@` for a given language simply based on
    /// the grammar of that language. This tests for that, using a string that
    /// is known to have this behavior in Malayalam.
    func test_LocalizedStringInvertsFormatArgOrder() {
        assertEqual(
            .aliceSomethingBobWithInvertedNameOrder,
            NSAttributedString.makeWithInvertedFormatArgOrder(firstUser: .alice, secondUser: .bob)
        )
    }
}

// MARK: - "X made Y an admin"

private extension NSAttributedString {
    static let aliceMadeBobAdmin: NSAttributedString = {
        let mutable = NSMutableAttributedString(string: "\(user: .alice) made \(user: .bob) an admin.")
        mutable.addAddress(.alice, toRange: NSRange(location: 0, length: 7))
        mutable.addAddress(.bob, toRange: NSRange(location: 13, length: 5))

        return mutable
    }()

    static let aliceHMadeAliceAdmin: NSAttributedString = {
        let mutable = NSMutableAttributedString(string: "\(user: .aliceH) made \(user: .alice) an admin.")
        mutable.addAddress(.aliceH, toRange: NSRange(location: 0, length: 9))
        mutable.addAddress(.alice, toRange: NSRange(location: 15, length: 7))

        return mutable
    }()

    static let aliceMadeMadeAdmin: NSAttributedString = {
        let mutable = NSMutableAttributedString(string: "\(user: .alice) made \(user: .made) an admin.")
        mutable.addAddress(.alice, toRange: NSRange(location: 0, length: 7))
        mutable.addAddress(.made, toRange: NSRange(location: 13, length: 6))

        return mutable
    }()

    static let aliceMadeAnotherAliceAdmin: NSAttributedString = {
        let mutable = NSMutableAttributedString(string: "\(user: .alice) made \(user: .anotherAlice) an admin.")
        mutable.addAddress(.alice, toRange: NSRange(location: 0, length: 7))
        mutable.addAddress(.anotherAlice, toRange: NSRange(location: 13, length: 7))

        return mutable
    }()

    static let aliceMadeSingleArgFormatSpecifierAdmin: NSAttributedString = {
        let mutable = NSMutableAttributedString(string: "\(user: .alice) made \(user: .singleArgFormatSpecifier) an admin.")
        mutable.addAddress(.alice, toRange: NSRange(location: 0, length: 7))
        mutable.addAddress(.singleArgFormatSpecifier, toRange: NSRange(location: 13, length: 4))

        return mutable
    }()

    static let aliceMadeMultiArgFormatSpecifierAdmin: NSAttributedString = {
        let mutable = NSMutableAttributedString(string: "\(user: .alice) made \(user: .multiArgFormatSpecifier) an admin.")
        mutable.addAddress(.alice, toRange: NSRange(location: 0, length: 7))
        mutable.addAddress(.multiArgFormatSpecifier, toRange: NSRange(location: 13, length: 6))

        return mutable
    }()

    /// This should theoretically be impossible - we should never in practice
    /// have an empty substitution. However, if we do, we don't want to fail
    /// here :)
    static let aliceMadeEmptyAdmin: NSAttributedString = {
        let mutable = NSMutableAttributedString(string: "\(user: .alice) made \(user: .empty) an admin.")
        mutable.addAddress(.alice, toRange: NSRange(location: 0, length: 7))
        mutable.addAddress(.empty, toRange: NSRange(location: 13, length: 2))

        return mutable
    }()

    static func make(firstUser: ReferencedUser, madeAdmin secondUser: ReferencedUser) -> NSAttributedString {
        make(
            fromFormat: .xMadeYAnAdminFormat,
            groupUpdateFormatArgs: [
                .name(firstUser.name, firstUser.address),
                .name(secondUser.name, secondUser.address)
            ]
        )
    }
}

// MARK: - "X made Y an admin", but using non-English languages

private extension NSAttributedString {
    static let aliceMadeBobAdmin_Arabic: NSAttributedString = {
        let mutable = NSMutableAttributedString(string: "إنَّ \(user: .alice) قد جعلَ \(user: .bob) مُشرفاً.")
        mutable.addAddress(.alice, toRange: NSRange(location: 5, length: 7))
        mutable.addAddress(.bob, toRange: NSRange(location: 21, length: 5))

        return mutable
    }()

    static let aliceMadeFatimaInArabicAnAdmin: NSAttributedString = {
        let mutable = NSMutableAttributedString(string: "\(user: .alice) made \(user: .fatima) an admin.")
        mutable.addAddress(.alice, toRange: NSRange(location: 0, length: 7))
        mutable.addAddress(.fatima, toRange: NSRange(location: 13, length: 10))

        return mutable
    }()

    static let qiInChineseMadeAliceAdmin: NSAttributedString = {
        let mutable = NSMutableAttributedString(string: "\(user: .qi) made \(user: .alice) an admin.")
        mutable.addAddress(.qi, toRange: NSRange(location: 0, length: 3))
        mutable.addAddress(.alice, toRange: NSRange(location: 9, length: 7))

        return mutable
    }()

    static let qiInChineseMadeFatimaInArabicAdmin_Arabic: NSAttributedString = {
        let mutable = NSMutableAttributedString(string: "إنَّ \(user: .qi) قد جعلَ \(user: .fatima) مُشرفاً.")
        mutable.addAddress(.qi, toRange: NSRange(location: 5, length: 3))
        mutable.addAddress(.fatima, toRange: NSRange(location: 17, length: 10))

        return mutable
    }()

    static func makeArabic(firstUser: ReferencedUser, madeAdmin secondUser: ReferencedUser) -> NSAttributedString {
        make(
            fromFormat: .xMadeYAnAdminFormat_Arabic,
            groupUpdateFormatArgs: [
                .name(firstUser.name, firstUser.address),
                .name(secondUser.name, secondUser.address)
            ]
        )
    }
}

// MARK: - "X invited N people"

private extension NSAttributedString {
    static let aliceInvitedOnePerson: NSAttributedString = {
        let mutable = NSMutableAttributedString(string: "\(user: .alice) invited 1 person to the group.")
        mutable.addAddress(.alice, toRange: NSRange(location: 0, length: 7))

        return mutable
    }()

    static let aliceInvitedTwoPeople: NSAttributedString = {
        let mutable = NSMutableAttributedString(string: "\(user: .alice) invited 2 people to the group.")
        mutable.addAddress(.alice, toRange: NSRange(location: 0, length: 7))

        return mutable
    }()

    static let aliceInvitedOneMillionPeople: NSAttributedString = {
        let mutable = NSMutableAttributedString(string: "\(user: .alice) invited 1,000,000 people to the group.")
        mutable.addAddress(.alice, toRange: NSRange(location: 0, length: 7))

        return mutable
    }()

    static let emptyInvitedThreePeople: NSAttributedString = {
        let mutable = NSMutableAttributedString(string: "\(user: .empty) invited 3 people to the group.")
        mutable.addAddress(.empty, toRange: NSRange(location: 0, length: 2))

        return mutable
    }()

    static func make(user: ReferencedUser, invitedNPeople: Int) -> NSAttributedString {
        make(
            fromFormat: .xInvitedNPeopleFormat,
            groupUpdateFormatArgs: [.raw(invitedNPeople), .name(user.name, user.address)]
        )
    }
}

// MARK: - Name at end of string

private extension NSAttributedString {
    static let aliceSomethingWithBobsNameAtEndOfString: NSAttributedString = {
        let mutable = NSMutableAttributedString(string: "\(user: .alice) to \(user: .bob)")
        mutable.addAddress(.alice, toRange: NSRange(location: 0, length: 7))
        mutable.addAddress(.bob, toRange: NSRange(location: 11, length: 5))

        return mutable
    }()

    static let aliceSomethingWithBobsNameAtEndOfString_Arabic: NSAttributedString = {
        let mutable = NSMutableAttributedString(string: "\(user: .alice) إلى \(user: .bob)")
        mutable.addAddress(.alice, toRange: NSRange(location: 0, length: 7))
        mutable.addAddress(.bob, toRange: NSRange(location: 12, length: 5))

        return mutable
    }()

    static func makeWithNameAtEndOfString(
        firstUser: ReferencedUser,
        userAtEndOfString otherUser: ReferencedUser,
        lang: String
    ) -> NSAttributedString {
        make(
            fromFormat: String.newGroupMessageNotificationTitleFormat(lang: lang),
            groupUpdateFormatArgs: [.name(firstUser.name, firstUser.address), .name(otherUser.name, otherUser.address)]
        )
    }
}

// MARK: - Localized string inverts format arg order

private extension NSAttributedString {
    static let aliceSomethingBobWithInvertedNameOrder: NSAttributedString = {
        let mutable = NSMutableAttributedString(string: "“\(user: .bob)”-এ “\(user: .alice)” যোগ করবেন?")
        mutable.addAddress(.bob, toRange: NSRange(location: 1, length: 5))
        mutable.addAddress(.alice, toRange: NSRange(location: 11, length: 7))

        return mutable
    }()

    /// The returned string formats the "second" user passed before the "first"
    /// user, simply as a result of the format string.
    static func makeWithInvertedFormatArgOrder(firstUser: ReferencedUser, secondUser: ReferencedUser) -> NSAttributedString {
        make(
            fromFormat: .addToGroupActionSheetMessage_Bangla,
            groupUpdateFormatArgs: [.name(firstUser.name, firstUser.address), .name(secondUser.name, secondUser.address)]
        )
    }
}

// MARK: - Add addresses

private extension NSMutableAttributedString {
    func addAddress(_ address: SignalServiceAddress, toRange range: NSRange) {
        addAttribute(.addressOfName, value: address, range: range)
    }
}

// MARK: - Users

private extension SignalServiceAddress {
    static let alice = SignalServiceAddress(phoneNumber: "+17735550100")
    static let aliceH = SignalServiceAddress(phoneNumber: "+17735550101")
    static let bob = SignalServiceAddress(phoneNumber: "+17735550102")
    static let made = SignalServiceAddress(phoneNumber: "+17735550103")
    static let anotherAlice = SignalServiceAddress(phoneNumber: "+17735550104")
    static let singleArgFormatSpecifier = SignalServiceAddress(phoneNumber: "+17735550105")
    static let multiArgFormatSpecifier = SignalServiceAddress(phoneNumber: "+17735550106")
    static let empty = SignalServiceAddress(phoneNumber: "+17735550107")
    static let fatima = SignalServiceAddress(phoneNumber: "+17735550108")
    static let qi = SignalServiceAddress(phoneNumber: "+17735550109")
}

private struct ReferencedUser {
    static let alice: ReferencedUser = ReferencedUser(name: "Alice", address: .alice)
    static let aliceH: ReferencedUser = ReferencedUser(name: "Alice H", address: .aliceH)
    static let bob: ReferencedUser = ReferencedUser(name: "Bob", address: .bob)
    static let made: ReferencedUser = ReferencedUser(name: "made", address: .made)
    static let anotherAlice: ReferencedUser = ReferencedUser(name: "Alice", address: .anotherAlice)
    static let singleArgFormatSpecifier: ReferencedUser = ReferencedUser(name: "%@", address: .singleArgFormatSpecifier)
    static let multiArgFormatSpecifier: ReferencedUser = ReferencedUser(name: "%1$@", address: .multiArgFormatSpecifier)
    static let empty: ReferencedUser = ReferencedUser(name: "", address: .empty)
    static let fatima: ReferencedUser = ReferencedUser(name: "فَاطِمَة", address: .fatima)
    static let qi: ReferencedUser = ReferencedUser(name: "琦", address: .qi)

    let name: String
    let address: SignalServiceAddress
}

private extension String.StringInterpolation {
    /// We wrap all formatted names in Unicode isolates.
    mutating func appendInterpolation(user: ReferencedUser) {
        appendLiteral("\u{2068}\(user.name)\u{2069}")
    }
}

// MARK: - Localized format strings

/// We should ideally use ``OWSLocalizedString`` for this, but it doesn't
/// support specifying the locale (uses the current).
private extension String {
    static let xMadeYAnAdminFormat: String = {
        try! localized(key: "GROUP_REMOTE_USER_GRANTED_ADMINISTRATOR_BY_REMOTE_USER_FORMAT")
    }()

    static let xMadeYAnAdminFormat_Arabic: String = {
        try! localized(key: "GROUP_REMOTE_USER_GRANTED_ADMINISTRATOR_BY_REMOTE_USER_FORMAT", lang: "ar")
    }()

    static let xInvitedNPeopleFormat: String = {
        try! localized(key: "GROUP_REMOTE_USER_INVITED_BY_REMOTE_USER_%d", tableName: "PluralAware")
    }()

    static func newGroupMessageNotificationTitleFormat(lang: String) -> String {
        try! localized(key: "NEW_GROUP_MESSAGE_NOTIFICATION_TITLE", lang: lang)
    }

    static let addToGroupActionSheetMessage_Bangla: String = {
        try! localized(key: "ADD_TO_GROUP_ACTION_SHEET_MESSAGE_FORMAT", lang: "bn")
    }()

    static func localized(
        key: String,
        tableName: String? = nil,
        lang: String = "en"
    ) throws -> String {
        guard
            let bundlePath = Bundle.main.path(forResource: lang, ofType: "lproj"),
            let bundle = Bundle(path: bundlePath)
        else {
            throw OWSAssertionError("Failed to find bundle for lang code \(lang)")
        }

        return NSLocalizedString(
            key,
            tableName: tableName,
            bundle: bundle,
            value: "",
            comment: ""
        )
    }
}
