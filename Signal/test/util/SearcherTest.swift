//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import Signal
@testable import SignalMessaging

class ConversationSearcherTest: XCTestCase {

    // MARK: - Dependencies
    var searcher: ConversationSearcher {
        return ConversationSearcher.shared
    }

    var dbConnection: YapDatabaseConnection {
        return OWSPrimaryStorage.shared().dbReadWriteConnection
    }

    // MARK: - Test Life Cycle

    override func setUp() {
        super.setUp()

        FullTextSearchFinder.syncRegisterDatabaseExtension(storage: OWSPrimaryStorage.shared())

        TSContactThread.removeAllObjectsInCollection()
        TSGroupThread.removeAllObjectsInCollection()

        self.dbConnection.readWrite { transaction in
            let bookModel = TSGroupModel(title: "Book Club", memberIds: [], image: nil, groupId: Randomness.generateRandomBytes(16))
            let bookClubGroupThread = TSGroupThread.getOrCreateThread(with: bookModel, transaction: transaction)
            self.bookClubThread = ThreadViewModel(thread: bookClubGroupThread, transaction: transaction)

            let snackModel = TSGroupModel(title: "Snack Club", memberIds: [], image: nil, groupId: Randomness.generateRandomBytes(16))
            let snackClubGroupThread = TSGroupThread.getOrCreateThread(with: snackModel, transaction: transaction)
            self.snackClubThread = ThreadViewModel(thread: snackClubGroupThread, transaction: transaction)

            let aliceContactThread = TSContactThread.getOrCreateThread(withContactId: "+12345678900", transaction: transaction)
            self.aliceThread = ThreadViewModel(thread: aliceContactThread, transaction: transaction)

            let bobContactThread = TSContactThread.getOrCreateThread(withContactId: "+49030183000", transaction: transaction)
            self.bobThread = ThreadViewModel(thread: bobContactThread, transaction: transaction)
        }
    }

    // MARK: - Fixtures

    var bookClubThread: ThreadViewModel!
    var snackClubThread: ThreadViewModel!

    var aliceThread: ThreadViewModel!
    var bobThread: ThreadViewModel!

    // MARK: Tests

    func testSearchByGroupName() {

        var resultSet: SearchResultSet = .empty

        // No Match
        resultSet = getResultSet(searchText: "asdasdasd")
        XCTAssert(resultSet.conversations.isEmpty)

        // Partial Match
        resultSet = getResultSet(searchText: "Book")
        XCTAssert(resultSet.conversations.count == 1)
        if let foundThread: ThreadViewModel = resultSet.conversations.first?.thread {
            XCTAssertEqual(bookClubThread, foundThread)
        } else {
            XCTFail("no thread found")
        }

        resultSet = getResultSet(searchText: "Snack")
        XCTAssert(resultSet.conversations.count == 1)
        if let foundThread: ThreadViewModel = resultSet.conversations.first?.thread {
            XCTAssertEqual(snackClubThread, foundThread)
        } else {
            XCTFail("no thread found")
        }

        // Multiple Partial Matches
        resultSet = getResultSet(searchText: "Club")
        XCTAssertEqual(2, resultSet.conversations.count)
        XCTAssert(resultSet.conversations.map { $0.thread }.contains(bookClubThread))
        XCTAssert(resultSet.conversations.map { $0.thread }.contains(snackClubThread))

        // Match Name Exactly
        resultSet = getResultSet(searchText: "Book Club")
        XCTAssertEqual(1, resultSet.conversations.count)
        XCTAssertEqual(bookClubThread, resultSet.conversations.first!.thread)
    }

    func testSearchContactByNumber() {
        var resultSet: SearchResultSet = .empty

        // No match
        resultSet = getResultSet(searchText: "+5551239999")
        XCTAssertEqual(0, resultSet.conversations.count)

        // Exact match
        resultSet = getResultSet(searchText: "+12345678900")
        XCTAssertEqual(1, resultSet.conversations.count)
        XCTAssertEqual(aliceThread, resultSet.conversations.first?.thread)

        // Partial match
        resultSet = getResultSet(searchText: "+123456")
        XCTAssertEqual(1, resultSet.conversations.count)
        XCTAssertEqual(aliceThread, resultSet.conversations.first?.thread)

        // Prefixes
        resultSet = getResultSet(searchText: "12345678900")
        XCTAssertEqual(1, resultSet.conversations.count)
        XCTAssertEqual(aliceThread, resultSet.conversations.first?.thread)

        resultSet = getResultSet(searchText: "49")
        XCTAssertEqual(1, resultSet.conversations.count)
        XCTAssertEqual(bobThread, resultSet.conversations.first?.thread)

        resultSet = getResultSet(searchText: "1-234-56")
        XCTAssertEqual(1, resultSet.conversations.count)
        XCTAssertEqual(aliceThread, resultSet.conversations.first?.thread)

        resultSet = getResultSet(searchText: "123456")
        XCTAssertEqual(1, resultSet.conversations.count)
        XCTAssertEqual(aliceThread, resultSet.conversations.first?.thread)

        resultSet = getResultSet(searchText: "1.234.56")
        XCTAssertEqual(1, resultSet.conversations.count)
        XCTAssertEqual(aliceThread, resultSet.conversations.first?.thread)
    }

    // TODO
    func pending_testSearchContactByNumber() {
        var resultSet: SearchResultSet = .empty

        // Phone Number formatting should be forgiving
        resultSet = getResultSet(searchText: "234.56")
        XCTAssertEqual(1, resultSet.conversations.count)
        XCTAssertEqual(aliceThread, resultSet.conversations.first?.thread)

        resultSet = getResultSet(searchText: "234 56")
        XCTAssertEqual(1, resultSet.conversations.count)
        XCTAssertEqual(aliceThread, resultSet.conversations.first?.thread)
    }

    func testSearchContactByName() {
        var resultSet: SearchResultSet = .empty

        resultSet = getResultSet(searchText: "Alice")
        XCTAssertEqual(1, resultSet.conversations.count)
        XCTAssertEqual(aliceThread, resultSet.conversations.first?.thread)

        resultSet = getResultSet(searchText: "Bob")
        XCTAssertEqual(1, resultSet.conversations.count)
        XCTAssertEqual(bobThread, resultSet.conversations.first?.thread)

        resultSet = getResultSet(searchText: "Barker")
        XCTAssertEqual(1, resultSet.conversations.count)
        XCTAssertEqual(bobThread, resultSet.conversations.first?.thread)
    }

    // Mark: Helpers

    private func getResultSet(searchText: String) -> SearchResultSet {
        var results: SearchResultSet!
        self.dbConnection.read { transaction in
            results = self.searcher.results(searchText: searchText, transaction: transaction)
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
}
