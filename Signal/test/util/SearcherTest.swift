//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import Signal
@testable import SignalMessaging

@objc
class StubbableEnvironment: TextSecureKitEnv {
    let proxy: TextSecureKitEnv

    init(proxy: TextSecureKitEnv) {
        self.proxy = proxy
        super.init(callMessageHandler: proxy.callMessageHandler, contactsManager: proxy.contactsManager, messageSender: proxy.messageSender, notificationsManager: proxy.notificationsManager, profileManager: proxy.profileManager)
    }

    var stubbedCallMessageHandler: OWSCallMessageHandler?
    override var callMessageHandler: OWSCallMessageHandler {
        return stubbedCallMessageHandler ?? proxy.callMessageHandler
    }

    var stubbedContactsManager: ContactsManagerProtocol?
    override var contactsManager: ContactsManagerProtocol {
        return stubbedContactsManager ?? proxy.contactsManager
    }

    var stubbedMessageSender: MessageSender?
    override var messageSender: MessageSender {
        return stubbedMessageSender ?? proxy.messageSender
    }

    var stubbedNotificationsManager: NotificationsProtocol?
    override var notificationsManager: NotificationsProtocol {
        return stubbedNotificationsManager ?? proxy.notificationsManager
    }

    var stubbedProfileManager: ProfileManagerProtocol?
    override var profileManager: ProfileManagerProtocol {
        return stubbedProfileManager ?? proxy.profileManager
    }
}

@objc
class FakeContactsManager: NSObject, ContactsManagerProtocol {
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
        owsFail("\(logTag) if this method ends up being used by the tests, we should provide a better implementation.")

        return .orderedAscending
    }
}

let bobRecipientId = "+49030183000"
let aliceRecipientId = "+12345678900"

class ConversationSearcherTest: XCTestCase {

    // MARK: - Dependencies
    var searcher: ConversationSearcher {
        return ConversationSearcher.shared
    }

    var dbConnection: YapDatabaseConnection {
        return OWSPrimaryStorage.shared().dbReadWriteConnection
    }

    // MARK: - Test Life Cycle

    var originalEnvironment: TextSecureKitEnv?

    override func tearDown() {
        super.tearDown()

        TextSecureKitEnv.setShared(originalEnvironment!)
    }

    override func setUp() {
        super.setUp()

        FullTextSearchFinder.syncRegisterDatabaseExtension(storage: OWSPrimaryStorage.shared())

        TSContactThread.removeAllObjectsInCollection()
        TSGroupThread.removeAllObjectsInCollection()
        TSMessage.removeAllObjectsInCollection()

        originalEnvironment = TextSecureKitEnv.shared()

        let testEnvironment: StubbableEnvironment = StubbableEnvironment(proxy: originalEnvironment!)
        testEnvironment.stubbedContactsManager = FakeContactsManager()
        TextSecureKitEnv.setShared(testEnvironment)

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
        XCTAssertEqual([bookClubThread, snackClubThread, aliceThread], threads)

        // Partial match
        threads = searchConversations(searchText: "+123456")
        XCTAssertEqual(3, threads.count)
        XCTAssertEqual([bookClubThread, snackClubThread, aliceThread], threads)

        // Prefixes
        threads = searchConversations(searchText: "12345678900")
        XCTAssertEqual(3, threads.count)
        XCTAssertEqual([bookClubThread, snackClubThread, aliceThread], threads)

        threads = searchConversations(searchText: "49")
        XCTAssertEqual(1, threads.count)
        XCTAssertEqual([bookClubThread], threads)

        threads = searchConversations(searchText: "1-234-56")
        XCTAssertEqual(3, threads.count)
        XCTAssertEqual([bookClubThread, snackClubThread, aliceThread], threads)

        threads = searchConversations(searchText: "123456")
        XCTAssertEqual(3, threads.count)
        XCTAssertEqual([bookClubThread, snackClubThread, aliceThread], threads)

        threads = searchConversations(searchText: "1.234.56")
        XCTAssertEqual(3, threads.count)
        XCTAssertEqual([bookClubThread, snackClubThread, aliceThread], threads)
    }

    func testSearchContactByNumberWithoutCountryCode() {
        var threads: [ThreadViewModel] = []
        // Phone Number formatting should be forgiving
        threads = searchConversations(searchText: "234.56")
        XCTAssertEqual(3, threads.count)
        XCTAssertEqual([bookClubThread, snackClubThread, aliceThread], threads)

        threads = searchConversations(searchText: "234 56")
        XCTAssertEqual(3, threads.count)
        XCTAssertEqual([bookClubThread, snackClubThread, aliceThread], threads)
    }

    func testSearchConversationByContactByName() {
        var threads: [ThreadViewModel] = []

        threads = searchConversations(searchText: "Alice")
        XCTAssertEqual(3, threads.count)
        XCTAssertEqual([bookClubThread, snackClubThread, aliceThread], threads)

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

    // Mark: Helpers

    private func searchConversations(searchText: String) -> [ThreadViewModel] {
        let results = getResultSet(searchText: searchText)
        return results.conversations.map { $0.thread }
    }

    private func getResultSet(searchText: String) -> SearchResultSet {
        var results: SearchResultSet!
        self.dbConnection.read { transaction in
            results = self.searcher.results(searchText: searchText, transaction: transaction, contactsManager: TextSecureKitEnv.shared().contactsManager)
        }
        return results
    }
}

class SearcherTest: XCTestCase {

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
        XCTAssertEqual(FullTextSearchFinder.query(searchText: "alice 123 bob 456"), "\"123\"* \"123456\"* \"456\"* \"alice\"* \"bob\"*")
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
