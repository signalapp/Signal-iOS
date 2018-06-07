//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import Signal
@testable import SignalMessaging

class ConversationSearcherTest: XCTestCase {

    // Mark: Dependencies
    var searcher: ConversationSearcher {
        return ConversationSearcher.shared
    }

    var dbConnection: YapDatabaseConnection {
        return OWSPrimaryStorage.shared().dbReadWriteConnection
    }

    // Mark: Test Life Cycle

    override func setUp() {
        super.setUp()

        ConversationFullTextSearchFinder.syncRegisterDatabaseExtension(storage: OWSPrimaryStorage.shared())
    }

    // Mark: Tests

    func testSearchByGroupName() {

        TSGroupThread.removeAllObjectsInCollection()

        var bookClubThread: ThreadViewModel!
        var snackClubThread: ThreadViewModel!
        self.dbConnection.readWrite { transaction in
            let bookModel = TSGroupModel(title: "Book Club", memberIds: [], image: nil, groupId: Randomness.generateRandomBytes(16))
            let bookClubGroupThread = TSGroupThread.getOrCreateThread(with: bookModel, transaction: transaction)
            bookClubThread = ThreadViewModel(thread: bookClubGroupThread, transaction: transaction)

            let snackModel = TSGroupModel(title: "Snack Club", memberIds: [], image: nil, groupId: Randomness.generateRandomBytes(16))
            let snackClubGroupThread = TSGroupThread.getOrCreateThread(with: snackModel, transaction: transaction)
            snackClubThread = ThreadViewModel(thread: snackClubGroupThread, transaction: transaction)
        }

        // No Match
        let noMatch = results(searchText: "asdasdasd")
        XCTAssert(noMatch.conversations.isEmpty)

        // Partial Match
        let bookMatch = results(searchText: "Book")
        XCTAssert(bookMatch.conversations.count == 1)
        if let foundThread: ThreadViewModel = bookMatch.conversations.first?.thread {
            XCTAssertEqual(bookClubThread, foundThread)
        } else {
            XCTFail("no thread found")
        }

        let snackMatch = results(searchText: "Snack")
        XCTAssert(snackMatch.conversations.count == 1)
        if let foundThread: ThreadViewModel = snackMatch.conversations.first?.thread {
            XCTAssertEqual(snackClubThread, foundThread)
        } else {
            XCTFail("no thread found")
        }

        // Multiple Partial Matches
        let multipleMatch = results(searchText: "Club")
        XCTAssert(multipleMatch.conversations.count == 2)
        XCTAssert(multipleMatch.conversations.map { $0.thread }.contains(bookClubThread))
        XCTAssert(multipleMatch.conversations.map { $0.thread }.contains(snackClubThread))

        // Match Name Exactly
        let exactMatch = results(searchText: "Book Club")
        XCTAssert(exactMatch.conversations.count == 1)
        XCTAssertEqual(bookClubThread, exactMatch.conversations.first!.thread)
    }

    // Mark: Helpers

    private func results(searchText: String) -> ConversationSearchResults {
        var results: ConversationSearchResults!
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
