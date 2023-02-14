//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import Contacts
@testable import Signal
@testable import SignalMessaging
@testable import SignalServiceKit

// TODO: We might be able to merge this with OWSFakeContactsManager.
@objc
class GRDBFullTextSearcherContactsManager: NSObject, ContactsManagerProtocol {
    func fetchSignalAccount(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> SignalAccount? {
        nil
    }

    func isSystemContactWithSignalAccount(_ address: SignalServiceAddress) -> Bool {
        false
    }

    func isSystemContactWithSignalAccount(_ address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        false
    }

    func hasNameInSystemContacts(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        false
    }

    private var mockDisplayNameMap = [SignalServiceAddress: String]()

    func setMockDisplayName(_ name: String, for address: SignalServiceAddress) {
        mockDisplayNameMap[address] = name
    }

    func comparableName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        self.displayName(for: address)
    }

    func comparableName(for signalAccount: SignalAccount, transaction: SDSAnyReadTransaction) -> String {
        self.displayName(for: signalAccount.recipientAddress)
    }

    func displayName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        self.displayName(for: address)
    }

    func displayNames(forAddresses addresses: [SignalServiceAddress], transaction: SDSAnyReadTransaction) -> [String] {
        return addresses.map { displayName(for: $0) }
    }

    func shortDisplayName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        self.displayName(for: address)
    }

    func displayName(for address: SignalServiceAddress) -> String {
        mockDisplayNameMap[address] ?? ""
    }

    public func displayName(for signalAccount: SignalAccount) -> String {
        "Fake name"
    }

    public func displayName(for thread: TSThread, transaction: SDSAnyReadTransaction) -> String {
        "Fake name"
    }

    public func displayNameWithSneakyTransaction(thread: TSThread) -> String {
        "Fake name"
    }

    func nameComponents(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> PersonNameComponents? {
        PersonNameComponents()
    }

    func signalAccounts() -> [SignalAccount] {
        []
    }

    func isSystemContactWithSneakyTransaction(phoneNumber: String) -> Bool {
        return true
    }

    func isSystemContact(phoneNumber: String, transaction: SDSAnyReadTransaction) -> Bool {
        return true
    }

    func isSystemContactWithSneakyTransaction(address: SignalServiceAddress) -> Bool {
        return true
    }

    func isSystemContact(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        return true
    }

    func isSystemContact(withSignalAccount recipientId: String) -> Bool {
        true
    }

    func isSystemContact(withSignalAccount phoneNumber: String, transaction: SDSAnyReadTransaction) -> Bool {
        true
    }

    func compare(signalAccount left: SignalAccount, with right: SignalAccount) -> ComparisonResult {
        owsFailDebug("if this method ends up being used by the tests, we should provide a better implementation.")

        return .orderedAscending
    }

    public func sortSignalServiceAddresses(_ addresses: [SignalServiceAddress],
                                           transaction: SDSAnyReadTransaction) -> [SignalServiceAddress] {
        addresses
    }

    func cnContact(withId contactId: String?) -> CNContact? {
        nil
    }

    func avatarData(forCNContactId contactId: String?) -> Data? {
        nil
    }

    func avatarImage(forCNContactId contactId: String?) -> UIImage? {
        nil
    }

    func leaseCacheSize(_ size: Int) -> ModelReadCacheSizeLease? {
        return nil
    }

    var unknownUserLabel: String = "unknown"
}

// MARK: -

class GRDBFullTextSearcherTest: SignalBaseTest {

    // MARK: - Dependencies

    var searcher: FullTextSearcher {
        FullTextSearcher.shared
    }

    // MARK: - Test Life Cycle

    override func tearDown() {
        super.tearDown()

        SDSDatabaseStorage.shouldLogDBQueries = DebugFlags.logSQLQueries
    }

    private var bobRecipient: SignalServiceAddress!
    private var aliceRecipient: SignalServiceAddress!

    override func setUp() {
        super.setUp()

        // We need to create new instances of SignalServiceAddress
        // for each test because we're using a new
        // SignalServiceAddressCache for each test and we need
        // consistent backingHashValue.
        aliceRecipient = SignalServiceAddress(phoneNumber: "+12345678900")
        bobRecipient = SignalServiceAddress(phoneNumber: "+49030183000")

        // Replace this singleton.
        let fakeContactsManager = GRDBFullTextSearcherContactsManager()
        fakeContactsManager.setMockDisplayName("Alice", for: aliceRecipient)
        fakeContactsManager.setMockDisplayName("Bob Barker", for: bobRecipient)
        SSKEnvironment.shared.contactsManagerRef = fakeContactsManager

        // ensure local client has necessary "registered" state
        let localE164Identifier = "+13235551234"
        let localUUID = UUID()
        tsAccountManager.registerForTests(withLocalNumber: localE164Identifier, uuid: localUUID)

        self.write { transaction in
            let bookClubGroupThread = try! GroupManager.createGroupForTests(members: [self.aliceRecipient, self.bobRecipient, self.tsAccountManager.localAddress!],
                                                                            name: "Book Club",
                                                                            transaction: transaction)
            self.bookClubThread = ThreadViewModel(thread: bookClubGroupThread,
                                                  forChatList: true,
                                                  transaction: transaction)

            let snackClubGroupThread = try! GroupManager.createGroupForTests(members: [self.aliceRecipient],
                                                                             name: "Snack Club",
                                                                             transaction: transaction)
            self.snackClubThread = ThreadViewModel(thread: snackClubGroupThread,
                                                   forChatList: true,
                                                   transaction: transaction)

            let aliceContactThread = TSContactThread.getOrCreateThread(withContactAddress: self.aliceRecipient, transaction: transaction)
            self.aliceThread = ThreadViewModel(thread: aliceContactThread,
                                               forChatList: true,
                                               transaction: transaction)

            let bobContactThread = TSContactThread.getOrCreateThread(withContactAddress: self.bobRecipient, transaction: transaction)
            self.bobEmptyThread = ThreadViewModel(thread: bobContactThread,
                                                  forChatList: true,
                                                  transaction: transaction)

            let helloAlice = TSOutgoingMessage(in: aliceContactThread, messageBody: "Hello Alice", attachmentId: nil)
            helloAlice.anyInsert(transaction: transaction)

            let goodbyeAlice = TSOutgoingMessage(in: aliceContactThread, messageBody: "Goodbye Alice", attachmentId: nil)
            goodbyeAlice.anyInsert(transaction: transaction)

            let helloBookClub = TSOutgoingMessage(in: bookClubGroupThread, messageBody: "Hello Book Club", attachmentId: nil)
            helloBookClub.anyInsert(transaction: transaction)

            let goodbyeBookClub = TSOutgoingMessage(in: bookClubGroupThread, messageBody: "Goodbye Book Club", attachmentId: nil)
            goodbyeBookClub.anyInsert(transaction: transaction)

            let bobsPhoneNumber = TSOutgoingMessage(in: bookClubGroupThread, messageBody: "My phone number is: 321-321-4321", attachmentId: nil)
            bobsPhoneNumber.anyInsert(transaction: transaction)

            let bobsFaxNumber = TSOutgoingMessage(in: bookClubGroupThread, messageBody: "My fax is: 222-333-4444", attachmentId: nil)
            bobsFaxNumber.anyInsert(transaction: transaction)
        }
    }

    // MARK: - Fixtures

    var bookClubThread: ThreadViewModel!
    var snackClubThread: ThreadViewModel!

    var aliceThread: ThreadViewModel!
    var bobEmptyThread: ThreadViewModel!

    // MARK: Tests

    private func AssertEqualThreadLists(_ left: [ThreadViewModel], _ right: [ThreadViewModel], file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(left.count, right.count, file: file, line: line)
        guard left.count != right.count else {
            return
        }
        // Only bother comparing uniqueIds.
        let leftIds = left.map { $0.threadRecord.uniqueId }
        let rightIds = right.map { $0.threadRecord.uniqueId }
        XCTAssertEqual(leftIds, rightIds, file: file, line: line)
    }

    func testSearchByGroupName() {
        var threads: [ThreadViewModel] = []

        // No Match
        threads = searchConversations(searchText: "asdasdasd")
        XCTAssert(threads.isEmpty)

        // Partial Match
        threads = searchConversations(searchText: "Book")
        XCTAssertEqual(1, threads.count)
        AssertEqualThreadLists([bookClubThread], threads)

        threads = searchConversations(searchText: "Snack")
        XCTAssertEqual(1, threads.count)
        AssertEqualThreadLists([snackClubThread], threads)

        // Multiple Partial Matches
        threads = searchConversations(searchText: "Club")
        XCTAssertEqual(2, threads.count)
        AssertEqualThreadLists([bookClubThread, snackClubThread], threads)

        // Match Name Exactly
        threads = searchConversations(searchText: "Book Club")
        XCTAssertEqual(1, threads.count)
        AssertEqualThreadLists([bookClubThread], threads)
    }

    func testSearchContactByNumber() {
        var threads: [ThreadViewModel] = []

        // No match
        threads = searchConversations(searchText: "+5551239999")
        XCTAssertEqual(0, threads.count)

        // Exact match
        threads = searchConversations(searchText: aliceRecipient.phoneNumber!)
        XCTAssertEqual(3, threads.count)
        AssertEqualThreadLists([bookClubThread, aliceThread, snackClubThread], threads)

        // Partial match
        threads = searchConversations(searchText: "+123456")
        XCTAssertEqual(3, threads.count)
        AssertEqualThreadLists([bookClubThread, aliceThread, snackClubThread], threads)

        // Prefixes
        threads = searchConversations(searchText: "12345678900")
        XCTAssertEqual(3, threads.count)
        AssertEqualThreadLists([bookClubThread, aliceThread, snackClubThread], threads)

        threads = searchConversations(searchText: "49")
        XCTAssertEqual(1, threads.count)
        AssertEqualThreadLists([bookClubThread], threads)

        threads = searchConversations(searchText: "1-234-56")
        XCTAssertEqual(3, threads.count)
        AssertEqualThreadLists([bookClubThread, aliceThread, snackClubThread], threads)

        threads = searchConversations(searchText: "123456")
        XCTAssertEqual(3, threads.count)
        AssertEqualThreadLists([bookClubThread, aliceThread, snackClubThread], threads)

        threads = searchConversations(searchText: "1.234.56")
        XCTAssertEqual(3, threads.count)
        AssertEqualThreadLists([bookClubThread, aliceThread, snackClubThread], threads)

        threads = searchConversations(searchText: "1 234 56")
        XCTAssertEqual(3, threads.count)
        AssertEqualThreadLists([bookClubThread, aliceThread, snackClubThread], threads)
    }

    func testSearchContactByNumberWithoutCountryCode() {
        var threads: [ThreadViewModel] = []
        // Phone Number formatting should be forgiving
        threads = searchConversations(searchText: "234.56")
        XCTAssertEqual(3, threads.count)
        AssertEqualThreadLists([bookClubThread, aliceThread, snackClubThread], threads)

        threads = searchConversations(searchText: "234 56")
        XCTAssertEqual(3, threads.count)
        AssertEqualThreadLists([bookClubThread, aliceThread, snackClubThread], threads)
    }

    func testSearchConversationByContactByName() {
        var threads: [ThreadViewModel] = []

        threads = searchConversations(searchText: "Alice")
        XCTAssertEqual(3, threads.count)
        AssertEqualThreadLists([bookClubThread, aliceThread, snackClubThread], threads)

        threads = searchConversations(searchText: "Bob")
        XCTAssertEqual(1, threads.count)
        AssertEqualThreadLists([bookClubThread], threads)

        threads = searchConversations(searchText: "Barker")
        XCTAssertEqual(1, threads.count)
        AssertEqualThreadLists([bookClubThread], threads)

        threads = searchConversations(searchText: "Bob B")
        XCTAssertEqual(1, threads.count)
        AssertEqualThreadLists([bookClubThread], threads)
    }

    func testSearchMessageByBodyContent() {
        var resultSet: HomeScreenSearchResultSet = .empty

        resultSet = getResultSet(searchText: "Hello Alice")
        XCTAssertEqual(1, resultSet.messages.count)
        AssertEqualThreadLists([aliceThread], resultSet.messages.map { $0.thread })

        resultSet = getResultSet(searchText: "Hello")
        XCTAssertEqual(2, resultSet.messages.count)
        AssertEqualThreadLists([aliceThread, bookClubThread], resultSet.messages.map { $0.thread })
    }

    func testSearchEdgeCases() {
        var resultSet: HomeScreenSearchResultSet = .empty

        resultSet = getResultSet(searchText: "Hello Alice")
        XCTAssertEqual(1, resultSet.messages.count)
        XCTAssertEqual(["Hello Alice"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "hello alice")
        XCTAssertEqual(1, resultSet.messages.count)
        XCTAssertEqual(["Hello Alice"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "Hel")
        XCTAssertEqual(2, resultSet.messages.count)
        XCTAssertEqual(["Hello Alice", "Hello Book Club"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "Hel Ali")
        XCTAssertEqual(1, resultSet.messages.count)
        XCTAssertEqual(["Hello Alice"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "Hel Ali Alic")
        XCTAssertEqual(1, resultSet.messages.count)
        XCTAssertEqual(["Hello Alice"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "Ali Hel")
        XCTAssertEqual(1, resultSet.messages.count)
        XCTAssertEqual(["Hello Alice"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "CLU")
        XCTAssertEqual(2, resultSet.messages.count)
        XCTAssertEqual(["Goodbye Book Club", "Hello Book Club"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "hello !@##!@#!$^@!@#! alice")
        XCTAssertEqual(1, resultSet.messages.count)
        XCTAssertEqual(["Hello Alice"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "3213 phone")
        XCTAssertEqual(1, resultSet.messages.count)
        XCTAssertEqual(["My phone number is: 321-321-4321"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "PHO 3213")
        XCTAssertEqual(1, resultSet.messages.count)
        XCTAssertEqual(["My phone number is: 321-321-4321"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "fax")
        XCTAssertEqual(1, resultSet.messages.count)
        XCTAssertEqual(["My fax is: 222-333-4444"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "fax 2223")
        XCTAssertEqual(1, resultSet.messages.count)
        XCTAssertEqual(["My fax is: 222-333-4444"], bodies(forMessageResults: resultSet.messages))
    }

    // MARK: - More Tests

    func testModelLifecycle1() {

        var thread: TSGroupThread! = nil
        self.write { transaction in
            thread = try! GroupManager.createGroupForTests(members: [self.aliceRecipient, self.bobRecipient, self.tsAccountManager.localAddress!],
                                                           name: "Lifecycle",
                                                           transaction: transaction)
        }

        let message1 = TSOutgoingMessage(in: thread, messageBody: "This world contains glory and despair.", attachmentId: nil)
        let message2 = TSOutgoingMessage(in: thread, messageBody: "This world contains hope and despair.", attachmentId: nil)

        XCTAssertEqual(0, getResultSet(searchText: "GLORY").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "HOPE").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "DESPAIR").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "DEFEAT").messages.count)

        self.write { transaction in
            message1.anyInsert(transaction: transaction)
            message2.anyInsert(transaction: transaction)
        }

        XCTAssertEqual(1, getResultSet(searchText: "GLORY").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "HOPE").messages.count)
        XCTAssertEqual(2, getResultSet(searchText: "DESPAIR").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "DEFEAT").messages.count)

        self.write { transaction in
            message1.update(withMessageBody: "This world contains glory and defeat.", transaction: transaction)
        }

        XCTAssertEqual(1, getResultSet(searchText: "GLORY").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "HOPE").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "DESPAIR").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "DEFEAT").messages.count)

        self.write { transaction in
            message1.anyRemove(transaction: transaction)
        }

        XCTAssertEqual(0, getResultSet(searchText: "GLORY").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "HOPE").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "DESPAIR").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "DEFEAT").messages.count)

        self.write { transaction in
            message2.anyRemove(transaction: transaction)
        }

        XCTAssertEqual(0, getResultSet(searchText: "GLORY").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "HOPE").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "DESPAIR").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "DEFEAT").messages.count)
    }

    func testModelLifecycle2() {

        self.write { transaction in
            let thread = try! GroupManager.createGroupForTests(members: [self.aliceRecipient, self.bobRecipient, self.tsAccountManager.localAddress!],
                                                               name: "Lifecycle",
                                                               transaction: transaction)

            let message1 = TSOutgoingMessage(in: thread, messageBody: "This world contains glory and despair.", attachmentId: nil)
            let message2 = TSOutgoingMessage(in: thread, messageBody: "This world contains hope and despair.", attachmentId: nil)

            message1.anyInsert(transaction: transaction)
            message2.anyInsert(transaction: transaction)
        }

        XCTAssertEqual(1, getResultSet(searchText: "GLORY").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "HOPE").messages.count)
        XCTAssertEqual(2, getResultSet(searchText: "DESPAIR").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "DEFEAT").messages.count)

        self.write { transaction in
            TSInteraction.anyRemoveAllWithInstantation(transaction: transaction)
        }

        XCTAssertEqual(0, getResultSet(searchText: "GLORY").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "HOPE").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "DESPAIR").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "DEFEAT").messages.count)
    }

    func testModelLifecycle3() {

        self.write { transaction in
            let thread = try! GroupManager.createGroupForTests(members: [self.aliceRecipient, self.bobRecipient, self.tsAccountManager.localAddress!],
                                                               name: "Lifecycle",
                                                               transaction: transaction)

            let message1 = TSOutgoingMessage(in: thread, messageBody: "This world contains glory and despair.", attachmentId: nil)
            let message2 = TSOutgoingMessage(in: thread, messageBody: "This world contains hope and despair.", attachmentId: nil)

            message1.anyInsert(transaction: transaction)
            message2.anyInsert(transaction: transaction)
        }

        XCTAssertEqual(1, getResultSet(searchText: "GLORY").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "HOPE").messages.count)
        XCTAssertEqual(2, getResultSet(searchText: "DESPAIR").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "DEFEAT").messages.count)

        self.write { transaction in
            TSInteraction.anyRemoveAllWithoutInstantation(transaction: transaction)
        }

        XCTAssertEqual(0, getResultSet(searchText: "GLORY").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "HOPE").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "DESPAIR").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "DEFEAT").messages.count)
    }

    func testDiacritics() {

        self.write { transaction in
            let thread = try! GroupManager.createGroupForTests(members: [self.aliceRecipient, self.bobRecipient, self.tsAccountManager.localAddress!],
                                                               name: "Lifecycle",
                                                               transaction: transaction)

            TSOutgoingMessage(in: thread, messageBody: "NOËL and SØRINA and ADRIÁN and FRANÇOIS and NUÑEZ and Björk.", attachmentId: nil).anyInsert(transaction: transaction)
        }

        XCTAssertEqual(1, getResultSet(searchText: "NOËL").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "noel").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "SØRINA").messages.count)
        // I guess Ø isn't a diacritical mark but a separate letter.
        XCTAssertEqual(0, getResultSet(searchText: "sorina").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "ADRIÁN").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "adrian").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "FRANÇOIS").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "francois").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "NUÑEZ").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "nunez").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "Björk").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "Bjork").messages.count)
    }

    private func AssertValidResultSet(query: String, expectedResultCount: Int, file: StaticString = #file, line: UInt = #line) {
        // For these simple test cases, the snippet should contain the entire query.
        let expectedSnippetContent: String = query

        let resultSet = getResultSet(searchText: query)
        XCTAssertEqual(expectedResultCount, resultSet.messages.count, file: file, line: line)
        for result in resultSet.messages {
            guard let snippet = result.snippet else {
                XCTFail("Missing snippet.", file: file, line: line)
                continue
            }
            XCTAssertTrue(snippet.lowercased().contains(expectedSnippetContent.lowercased()), file: file, line: line)
        }
    }

    func testSnippets() {

        var thread: TSGroupThread! = nil
        self.write { transaction in
            thread = try! GroupManager.createGroupForTests(members: [self.aliceRecipient, self.bobRecipient, self.tsAccountManager.localAddress!],
                                                           name: "Lifecycle",
                                                           transaction: transaction)
        }

        let message1 = TSOutgoingMessage(in: thread, messageBody: "This world contains glory and despair.", attachmentId: nil)
        let message2 = TSOutgoingMessage(in: thread, messageBody: "This world contains hope and despair.", attachmentId: nil)

        AssertValidResultSet(query: "GLORY", expectedResultCount: 0)
        AssertValidResultSet(query: "HOPE", expectedResultCount: 0)
        AssertValidResultSet(query: "DESPAIR", expectedResultCount: 0)
        AssertValidResultSet(query: "DEFEAT", expectedResultCount: 0)

        self.write { transaction in
            message1.anyInsert(transaction: transaction)
            message2.anyInsert(transaction: transaction)
        }

        AssertValidResultSet(query: "GLORY", expectedResultCount: 1)
        AssertValidResultSet(query: "HOPE", expectedResultCount: 1)
        AssertValidResultSet(query: "DESPAIR", expectedResultCount: 2)
        AssertValidResultSet(query: "DEFEAT", expectedResultCount: 0)
    }

    // MARK: - Perf

    func testPerf() {
        // Logging queries is expensive and affects the results of this test.
        // This is restored in tearDown().
        SDSDatabaseStorage.shouldLogDBQueries = false

        let aliceE164 = "+13213214321"
        let aliceUuid = UUID()
        tsAccountManager.registerForTests(withLocalNumber: aliceE164, uuid: aliceUuid)

        let string1 = "krazy"
        let string2 = "kat"
        let messageCount: UInt = 100

        Bench(title: "Populate Index", memorySamplerRatio: 1) { _ in
            self.write { transaction in
                let thread = try! GroupManager.createGroupForTests(members: [self.aliceRecipient, self.bobRecipient, self.tsAccountManager.localAddress!],
                                                                   name: "Perf",
                                                                   transaction: transaction)

                TSOutgoingMessage(in: thread, messageBody: string1, attachmentId: nil).anyInsert(transaction: transaction)

                for _ in 0...messageCount {
                    let message = TSOutgoingMessage(in: thread, messageBody: UUID().uuidString, attachmentId: nil)
                    message.anyInsert(transaction: transaction)
                    message.update(withMessageBody: UUID().uuidString, transaction: transaction)
                }

                TSOutgoingMessage(in: thread, messageBody: string2, attachmentId: nil).anyInsert(transaction: transaction)
            }
        }

        Bench(title: "Search", memorySamplerRatio: 1) { _ in
            self.read { transaction in
                let getMatchCount = { (searchText: String) -> UInt in
                    var count: UInt = 0
                    FullTextSearchFinder.enumerateObjects(
                        searchText: searchText,
                        collections: [TSMessage.collection()],
                        maxResults: 500,
                        transaction: transaction
                    ) { (match, snippet, _) in
                        Logger.verbose("searchText: \(searchText), match: \(match), snippet: \(snippet)")
                        count += 1
                    }
                    return count
                }
                XCTAssertEqual(1, getMatchCount(string1))
                XCTAssertEqual(1, getMatchCount(string2))
                XCTAssertEqual(0, getMatchCount(UUID().uuidString))
            }
        }
    }

    // MARK: - Helpers

    func bodies<T>(forMessageResults messageResults: [ConversationSearchResult<T>]) -> [String] {
        var result = [String]()

        self.read { transaction in
            for messageResult in messageResults {
                guard let messageId = messageResult.messageId else {
                    owsFailDebug("message result missing message id")
                    continue
                }
                guard let interaction = TSInteraction.anyFetch(uniqueId: messageId, transaction: transaction) else {
                    owsFailDebug("couldn't load interaction for message result")
                    continue
                }
                guard let message = interaction as? TSMessage else {
                    owsFailDebug("invalid message for message result")
                    continue
                }
                guard let messageBody = message.body else {
                    owsFailDebug("message result missing message body")
                    continue
                }
                result.append(messageBody)
            }
        }

        return result.sorted()
    }

    private func searchConversations(searchText: String) -> [ThreadViewModel] {
        let results = getResultSet(searchText: searchText)
        let contactThreads = results.contactThreads.map { $0.thread }
        let groupThreads = results.groupThreads.map { $0.thread }
        return contactThreads + groupThreads
    }

    private func getResultSet(searchText: String) -> HomeScreenSearchResultSet {
        var results: HomeScreenSearchResultSet!
        self.read { transaction in
            results = self.searcher.searchForHomeScreen(searchText: searchText, transaction: transaction)
        }
        return results
    }
}
