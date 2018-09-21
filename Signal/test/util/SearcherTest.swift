//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import Signal
@testable import SignalMessaging

// TODO: We might be able to merge this with OWSFakeContactsManager.
@objc
class ConversationSearcherContactsManager: NSObject, ContactsManagerProtocol {

    func displayName(forPhoneIdentifier phoneNumber: String?) -> String {
        if phoneNumber == aliceRecipientId {
            return "Alice"
        } else if phoneNumber == bobRecipientId {
            return "Bob Barker"
        } else {
            return ""
        }
    }

    func signalAccounts() -> [SignalAccount] {
        return []
    }

    func isSystemContact(_ recipientId: String) -> Bool {
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

let bobRecipientId = "+49030183000"
let aliceRecipientId = "+12345678900"

class ConversationSearcherTest: SignalBaseTest {

    // MARK: - Dependencies
    var searcher: ConversationSearcher {
        return ConversationSearcher.shared
    }

    var dbConnection: YapDatabaseConnection {
        return OWSPrimaryStorage.shared().dbReadWriteConnection
    }

    // MARK: - Test Life Cycle

    override func tearDown() {
        super.tearDown()
    }

    override func setUp() {
        super.setUp()

        FullTextSearchFinder.ensureDatabaseExtensionRegistered(storage: OWSPrimaryStorage.shared())

        // Replace this singleton.
        SSKEnvironment.shared.contactsManager = ConversationSearcherContactsManager()

        self.dbConnection.readWrite { transaction in
            let bookModel = TSGroupModel(title: "Book Club", memberIds: [aliceRecipientId, bobRecipientId], image: nil, groupId: Randomness.generateRandomBytes(16))
            let bookClubGroupThread = TSGroupThread.getOrCreateThread(with: bookModel, transaction: transaction)
            self.bookClubThread = ThreadViewModel(thread: bookClubGroupThread, transaction: transaction)

            let snackModel = TSGroupModel(title: "Snack Club", memberIds: [aliceRecipientId], image: nil, groupId: Randomness.generateRandomBytes(16))
            let snackClubGroupThread = TSGroupThread.getOrCreateThread(with: snackModel, transaction: transaction)
            self.snackClubThread = ThreadViewModel(thread: snackClubGroupThread, transaction: transaction)

            let aliceContactThread = TSContactThread.getOrCreateThread(withContactId: aliceRecipientId, transaction: transaction)
            self.aliceThread = ThreadViewModel(thread: aliceContactThread, transaction: transaction)

            let bobContactThread = TSContactThread.getOrCreateThread(withContactId: bobRecipientId, transaction: transaction)
            self.bobEmptyThread = ThreadViewModel(thread: bobContactThread, transaction: transaction)

            let helloAlice = TSOutgoingMessage(in: aliceContactThread, messageBody: "Hello Alice", attachmentId: nil)
            helloAlice.save(with: transaction)

            let goodbyeAlice = TSOutgoingMessage(in: aliceContactThread, messageBody: "Goodbye Alice", attachmentId: nil)
            goodbyeAlice.save(with: transaction)

            let helloBookClub = TSOutgoingMessage(in: bookClubGroupThread, messageBody: "Hello Book Club", attachmentId: nil)
            helloBookClub.save(with: transaction)

            let goodbyeBookClub = TSOutgoingMessage(in: bookClubGroupThread, messageBody: "Goodbye Book Club", attachmentId: nil)
            goodbyeBookClub.save(with: transaction)

            let bobsPhoneNumber = TSOutgoingMessage(in: bookClubGroupThread, messageBody: "My phone number is: 321-321-4321", attachmentId: nil)
            bobsPhoneNumber.save(with: transaction)

            let bobsFaxNumber = TSOutgoingMessage(in: bookClubGroupThread, messageBody: "My fax is: 222-333-4444", attachmentId: nil)
            bobsFaxNumber.save(with: transaction)
        }
    }

    // MARK: - Fixtures

    var bookClubThread: ThreadViewModel!
    var snackClubThread: ThreadViewModel!

    var aliceThread: ThreadViewModel!
    var bobEmptyThread: ThreadViewModel!

    // MARK: Tests

    func testSearchByGroupName() {
        var threads: [ThreadViewModel] = []

        // No Match
        threads = searchConversations(searchText: "asdasdasd")
        XCTAssert(threads.isEmpty)

        // Partial Match
        threads = searchConversations(searchText: "Book")
        XCTAssertEqual(1, threads.count)
        XCTAssertEqual([bookClubThread], threads)

        threads = searchConversations(searchText: "Snack")
        XCTAssertEqual(1, threads.count)
        XCTAssertEqual([snackClubThread], threads)

        // Multiple Partial Matches
        threads = searchConversations(searchText: "Club")
        XCTAssertEqual(2, threads.count)
        XCTAssertEqual([bookClubThread, snackClubThread], threads)

        // Match Name Exactly
        threads = searchConversations(searchText: "Book Club")
        XCTAssertEqual(1, threads.count)
        XCTAssertEqual([bookClubThread], threads)
    }

    func testSearchContactByNumber() {
        var threads: [ThreadViewModel] = []

        // No match
        threads = searchConversations(searchText: "+5551239999")
        XCTAssertEqual(0, threads.count)

        // Exact match
        threads = searchConversations(searchText: aliceRecipientId)
        XCTAssertEqual(3, threads.count)
        XCTAssertEqual([bookClubThread, aliceThread, snackClubThread], threads)

        // Partial match
        threads = searchConversations(searchText: "+123456")
        XCTAssertEqual(3, threads.count)
        XCTAssertEqual([bookClubThread, aliceThread, snackClubThread], threads)

        // Prefixes
        threads = searchConversations(searchText: "12345678900")
        XCTAssertEqual(3, threads.count)
        XCTAssertEqual([bookClubThread, aliceThread, snackClubThread], threads)

        threads = searchConversations(searchText: "49")
        XCTAssertEqual(1, threads.count)
        XCTAssertEqual([bookClubThread], threads)

        threads = searchConversations(searchText: "1-234-56")
        XCTAssertEqual(3, threads.count)
        XCTAssertEqual([bookClubThread, aliceThread, snackClubThread], threads)

        threads = searchConversations(searchText: "123456")
        XCTAssertEqual(3, threads.count)
        XCTAssertEqual([bookClubThread, aliceThread, snackClubThread], threads)

        threads = searchConversations(searchText: "1.234.56")
        XCTAssertEqual(3, threads.count)
        XCTAssertEqual([bookClubThread, aliceThread, snackClubThread], threads)

        threads = searchConversations(searchText: "1 234 56")
        XCTAssertEqual(3, threads.count)
        XCTAssertEqual([bookClubThread, aliceThread, snackClubThread], threads)
    }

    func testSearchContactByNumberWithoutCountryCode() {
        var threads: [ThreadViewModel] = []
        // Phone Number formatting should be forgiving
        threads = searchConversations(searchText: "234.56")
        XCTAssertEqual(3, threads.count)
        XCTAssertEqual([bookClubThread, aliceThread, snackClubThread], threads)

        threads = searchConversations(searchText: "234 56")
        XCTAssertEqual(3, threads.count)
        XCTAssertEqual([bookClubThread, aliceThread, snackClubThread], threads)
    }

    func testSearchConversationByContactByName() {
        var threads: [ThreadViewModel] = []

        threads = searchConversations(searchText: "Alice")
        XCTAssertEqual(3, threads.count)
        XCTAssertEqual([bookClubThread, aliceThread, snackClubThread], threads)

        threads = searchConversations(searchText: "Bob")
        XCTAssertEqual(1, threads.count)
        XCTAssertEqual([bookClubThread], threads)

        threads = searchConversations(searchText: "Barker")
        XCTAssertEqual(1, threads.count)
        XCTAssertEqual([bookClubThread], threads)

        threads = searchConversations(searchText: "Bob B")
        XCTAssertEqual(1, threads.count)
        XCTAssertEqual([bookClubThread], threads)
    }

    func testSearchMessageByBodyContent() {
        var resultSet: SearchResultSet = .empty

        resultSet = getResultSet(searchText: "Hello Alice")
        XCTAssertEqual(1, resultSet.messages.count)
        XCTAssertEqual(aliceThread, resultSet.messages.first?.thread)

        resultSet = getResultSet(searchText: "Hello")
        XCTAssertEqual(2, resultSet.messages.count)
        XCTAssert(resultSet.messages.map { $0.thread }.contains(aliceThread))
        XCTAssert(resultSet.messages.map { $0.thread }.contains(bookClubThread))
    }

    func testSearchEdgeCases() {
        var resultSet: SearchResultSet = .empty

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

    func bodies(forMessageResults messageResults: [ConversationSearchResult]) -> [String] {
        var result = [String]()

        self.dbConnection.read { transaction in
            for messageResult in messageResults {
                guard let messageId = messageResult.messageId else {
                    owsFailDebug("message result missing message id")
                    continue
                }
                guard let interaction = TSInteraction.fetch(uniqueId: messageId, transaction: transaction) else {
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

    // MARK: Helpers

    private func searchConversations(searchText: String) -> [ThreadViewModel] {
        let results = getResultSet(searchText: searchText)
        return results.conversations.map { $0.thread }
    }

    private func getResultSet(searchText: String) -> SearchResultSet {
        var results: SearchResultSet!
        self.dbConnection.read { transaction in
            results = self.searcher.results(searchText: searchText, transaction: transaction, contactsManager: SSKEnvironment.shared.contactsManager)
        }
        return results
    }
}

class SearcherTest: SignalBaseTest {

    struct TestCharacter {
        let name: String
        let description: String
        let phoneNumber: String?
    }

    let smerdyakov = TestCharacter(name: "Pavel Fyodorovich Smerdyakov", description: "A rusty hue in the sky", phoneNumber: nil)
    let stinkingLizaveta = TestCharacter(name: "Stinking Lizaveta", description: "object of pity", phoneNumber: "+13235555555")
    let regularLizaveta = TestCharacter(name: "Lizaveta", description: "", phoneNumber: "1 (415) 555-5555")

    let indexer = { (character: TestCharacter) in
        return "\(character.name) \(character.description) \(character.phoneNumber ?? "")"
    }

    var searcher: Searcher<TestCharacter> {
        return Searcher(indexer: indexer)
    }

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testSimple() {
        XCTAssert(searcher.matches(item: smerdyakov, query: "Pavel"))
        XCTAssert(searcher.matches(item: smerdyakov, query: "pavel"))
        XCTAssertFalse(searcher.matches(item: smerdyakov, query: "asdf"))
        XCTAssertFalse(searcher.matches(item: smerdyakov, query: ""))
        XCTAssert(searcher.matches(item: stinkingLizaveta, query: "Pity"))
    }

    func testRepeats() {
        XCTAssert(searcher.matches(item: smerdyakov, query: "pavel pavel"))
        XCTAssertFalse(searcher.matches(item: smerdyakov, query: "pavelpavel"))
    }

    func testSplitWords() {
        XCTAssert(searcher.matches(item: stinkingLizaveta, query: "Lizaveta"))
        XCTAssert(searcher.matches(item: regularLizaveta, query: "Lizaveta"))

        XCTAssert(searcher.matches(item: stinkingLizaveta, query: "Stinking Lizaveta"))
        XCTAssertFalse(searcher.matches(item: regularLizaveta, query: "Stinking Lizaveta"))

        XCTAssert(searcher.matches(item: stinkingLizaveta, query: "Lizaveta Stinking"))
        XCTAssert(searcher.matches(item: stinkingLizaveta, query: "Lizaveta St"))
        XCTAssert(searcher.matches(item: stinkingLizaveta, query: "  Lizaveta St "))
    }

    func testFormattingChars() {
        XCTAssert(searcher.matches(item: stinkingLizaveta, query: "323"))
        XCTAssert(searcher.matches(item: stinkingLizaveta, query: "1-323-555-5555"))
        XCTAssert(searcher.matches(item: stinkingLizaveta, query: "13235555555"))
        XCTAssert(searcher.matches(item: stinkingLizaveta, query: "+1-323"))
        XCTAssert(searcher.matches(item: stinkingLizaveta, query: "Liza +1-323"))

        // Sanity check, match both by names
        XCTAssert(searcher.matches(item: stinkingLizaveta, query: "Liza"))
        XCTAssert(searcher.matches(item: regularLizaveta, query: "Liza"))

        // Disambiguate the two Liza's by area code
        XCTAssert(searcher.matches(item: stinkingLizaveta, query: "Liza 323"))
        XCTAssertFalse(searcher.matches(item: regularLizaveta, query: "Liza 323"))
    }

    func testSearchQuery() {
        XCTAssertEqual(FullTextSearchFinder.query(searchText: "Liza"), "\"Liza\"*")
        XCTAssertEqual(FullTextSearchFinder.query(searchText: "Liza +1-323"), "\"1323\"* \"Liza\"*")
        XCTAssertEqual(FullTextSearchFinder.query(searchText: "\"\\ `~!@#$%^&*()_+-={}|[]:;'<>?,./Liza +1-323"), "\"1323\"* \"Liza\"*")
        XCTAssertEqual(FullTextSearchFinder.query(searchText: "renaldo RENALDO reñaldo REÑALDO"), "\"RENALDO\"* \"REÑALDO\"* \"renaldo\"* \"reñaldo\"*")
        XCTAssertEqual(FullTextSearchFinder.query(searchText: "😏"), "\"😏\"*")
        XCTAssertEqual(FullTextSearchFinder.query(searchText: "alice 123 bob 456"), "\"123456\"* \"alice\"* \"bob\"*")
        XCTAssertEqual(FullTextSearchFinder.query(searchText: "Li!za"), "\"Liza\"*")
        XCTAssertEqual(FullTextSearchFinder.query(searchText: "Liza Liza"), "\"Liza\"*")
        XCTAssertEqual(FullTextSearchFinder.query(searchText: "Liza liza"), "\"Liza\"* \"liza\"*")
    }

    func testTextNormalization() {
        XCTAssertEqual(FullTextSearchFinder.normalize(text: "Liza"), "Liza")
        XCTAssertEqual(FullTextSearchFinder.normalize(text: "Liza +1-323"), "Liza 1323")
        XCTAssertEqual(FullTextSearchFinder.normalize(text: "\"\\ `~!@#$%^&*()_+-={}|[]:;'<>?,./Liza +1-323"), "Liza 1323")
        XCTAssertEqual(FullTextSearchFinder.normalize(text: "renaldo RENALDO reñaldo REÑALDO"), "renaldo RENALDO reñaldo REÑALDO")
        XCTAssertEqual(FullTextSearchFinder.normalize(text: "😏"), "😏")
    }
}
