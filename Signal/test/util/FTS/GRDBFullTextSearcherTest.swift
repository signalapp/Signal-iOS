//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import Signal
@testable import SignalMessaging

// TODO: We might be able to merge this with OWSFakeContactsManager.
@objc
class GRDBFullTextSearcherContactsManager: NSObject, ContactsManagerProtocol {
    func displayName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        return self.displayName(for: address)
    }

    func displayName(for address: SignalServiceAddress) -> String {
        if address == aliceRecipient {
            return "Alice"
        } else if address == bobRecipient {
            return "Bob Barker"
        } else {
            return ""
        }
    }

    public func displayName(for signalAccount: SignalAccount) -> String {
        return "Fake name"
    }

    public func displayName(for thread: TSThread, transaction: SDSAnyReadTransaction) -> String {
        return "Fake name"
    }

    public func displayNameWithSneakyTransaction(thread: TSThread) -> String {
        return "Fake name"
    }

    func signalAccounts() -> [SignalAccount] {
        return []
    }

    func isSystemContact(phoneNumber: String) -> Bool {
        return true
    }

    func isSystemContact(address: SignalServiceAddress) -> Bool {
        return true
    }

    func isSystemContact(withSignalAccount recipientId: String) -> Bool {
        return true
    }

    func compare(signalAccount left: SignalAccount, with right: SignalAccount) -> ComparisonResult {
        owsFailDebug("if this method ends up being used by the tests, we should provide a better implementation.")

        return .orderedAscending
    }

    func cnContact(withId contactId: String?) -> CNContact? {
        return nil
    }

    func avatarData(forCNContactId contactId: String?) -> Data? {
        return nil
    }

    func avatarImage(forCNContactId contactId: String?) -> UIImage? {
        return nil
    }
}

private let bobRecipient = SignalServiceAddress(phoneNumber: "+49030183000")
private let aliceRecipient = SignalServiceAddress(phoneNumber: "+12345678900")

// MARK: -

class GRDBFullTextSearcherTest: SignalBaseTest {

    // MARK: - Dependencies

    var searcher: FullTextSearcher {
        return FullTextSearcher.shared
    }

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    // MARK: - Test Life Cycle

    override func tearDown() {
        super.tearDown()

        SDSDatabaseStorage.shouldLogDBQueries = true
    }

    override func setUp() {
        super.setUp()

        // Replace this singleton.
        SSKEnvironment.shared.contactsManager = GRDBFullTextSearcherContactsManager()

        self.write { transaction in
            let bookModel = TSGroupModel(title: "Book Club", members: [aliceRecipient, bobRecipient], image: nil, groupId: Randomness.generateRandomBytes(kGroupIdLength))
            let bookClubGroupThread = TSGroupThread.getOrCreateThread(with: bookModel, transaction: transaction)
            self.bookClubThread = ThreadViewModel(thread: bookClubGroupThread, transaction: transaction)

            let snackModel = TSGroupModel(title: "Snack Club", members: [aliceRecipient], image: nil, groupId: Randomness.generateRandomBytes(kGroupIdLength))
            let snackClubGroupThread = TSGroupThread.getOrCreateThread(with: snackModel, transaction: transaction)
            self.snackClubThread = ThreadViewModel(thread: snackClubGroupThread, transaction: transaction)

            let aliceContactThread = TSContactThread.getOrCreateThread(withContactAddress: aliceRecipient, transaction: transaction)
            self.aliceThread = ThreadViewModel(thread: aliceContactThread, transaction: transaction)

            let bobContactThread = TSContactThread.getOrCreateThread(withContactAddress: bobRecipient, transaction: transaction)
            self.bobEmptyThread = ThreadViewModel(thread: bobContactThread, transaction: transaction)

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
            let groupModel = TSGroupModel(title: "Lifecycle", members: [aliceRecipient, bobRecipient], image: nil, groupId: Randomness.generateRandomBytes(kGroupIdLength))
            thread = TSGroupThread.getOrCreateThread(with: groupModel, transaction: transaction)
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
            let groupModel = TSGroupModel(title: "Lifecycle", members: [aliceRecipient, bobRecipient], image: nil, groupId: Randomness.generateRandomBytes(kGroupIdLength))
            let thread = TSGroupThread.getOrCreateThread(with: groupModel, transaction: transaction)

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
            let groupModel = TSGroupModel(title: "Lifecycle", members: [aliceRecipient, bobRecipient], image: nil, groupId: Randomness.generateRandomBytes(kGroupIdLength))
            let thread = TSGroupThread.getOrCreateThread(with: groupModel, transaction: transaction)

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
            let groupModel = TSGroupModel(title: "Lifecycle", members: [aliceRecipient, bobRecipient], image: nil, groupId: Randomness.generateRandomBytes(kGroupIdLength))
            let thread = TSGroupThread.getOrCreateThread(with: groupModel, transaction: transaction)

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
            let groupModel = TSGroupModel(title: "Lifecycle", members: [aliceRecipient, bobRecipient], image: nil, groupId: Randomness.generateRandomBytes(kGroupIdLength))
            thread = TSGroupThread.getOrCreateThread(with: groupModel, transaction: transaction)
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
                let groupModel = TSGroupModel(title: "Perf", members: [aliceRecipient, bobRecipient], image: nil, groupId: Randomness.generateRandomBytes(kGroupIdLength))
                let thread = TSGroupThread.getOrCreateThread(with: groupModel, transaction: transaction)

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
                let finder = FullTextSearchFinder()

                let getMatchCount = { (searchText: String) -> UInt in
                    var count: UInt = 0
                    finder.enumerateObjects(searchText: searchText, transaction: transaction) { (match, snippet, _) in
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
        return results.conversations.map { $0.thread }
    }

    private func getResultSet(searchText: String) -> HomeScreenSearchResultSet {
        var results: HomeScreenSearchResultSet!
        self.read { transaction in
            results = self.searcher.searchForHomeScreen(searchText: searchText, transaction: transaction)
        }
        return results
    }
}
