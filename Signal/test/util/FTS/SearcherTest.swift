//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import Signal
@testable import SignalMessaging

class SearcherTest: SignalBaseTest {

    struct TestCharacter {
        let name: String
        let description: String
        let phoneNumber: String?
    }

    let smerdyakov = TestCharacter(name: "Pavel Fyodorovich Smerdyakov", description: "A rusty hue in the sky", phoneNumber: nil)
    let stinkingLizaveta = TestCharacter(name: "Stinking Lizaveta", description: "object of pity", phoneNumber: "+13235555555")
    let regularLizaveta = TestCharacter(name: "Lizaveta", description: "", phoneNumber: "1 (415) 555-5555")

    let indexer = { (character: TestCharacter, transaction: SDSAnyReadTransaction) in
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
        read { transaction in
            XCTAssert(self.searcher.matches(item: self.smerdyakov, query: "Pavel", transaction: transaction))
            XCTAssert(self.searcher.matches(item: self.smerdyakov, query: "pavel", transaction: transaction))
            XCTAssertFalse(self.searcher.matches(item: self.smerdyakov, query: "asdf", transaction: transaction))
            XCTAssertFalse(self.searcher.matches(item: self.smerdyakov, query: "", transaction: transaction))
            XCTAssert(self.searcher.matches(item: self.stinkingLizaveta, query: "Pity", transaction: transaction))
        }
    }

    func testRepeats() {
        read { transaction in
            XCTAssert(self.searcher.matches(item: self.smerdyakov, query: "pavel pavel", transaction: transaction))
            XCTAssertFalse(self.searcher.matches(item: self.smerdyakov, query: "pavelpavel", transaction: transaction))
        }
    }

    func testSplitWords() {
        read { transaction in
            XCTAssert(self.searcher.matches(item: self.stinkingLizaveta, query: "Lizaveta", transaction: transaction))
            XCTAssert(self.searcher.matches(item: self.regularLizaveta, query: "Lizaveta", transaction: transaction))

            XCTAssert(self.searcher.matches(item: self.stinkingLizaveta, query: "Stinking Lizaveta", transaction: transaction))
            XCTAssertFalse(self.searcher.matches(item: self.regularLizaveta, query: "Stinking Lizaveta", transaction: transaction))

            XCTAssert(self.searcher.matches(item: self.stinkingLizaveta, query: "Lizaveta Stinking", transaction: transaction))
            XCTAssert(self.searcher.matches(item: self.stinkingLizaveta, query: "Lizaveta St", transaction: transaction))
            XCTAssert(self.searcher.matches(item: self.stinkingLizaveta, query: "  Lizaveta St ", transaction: transaction))
        }
    }

    func testFormattingChars() {
        read { transaction in
            XCTAssert(self.searcher.matches(item: self.stinkingLizaveta, query: "323", transaction: transaction))
            XCTAssert(self.searcher.matches(item: self.stinkingLizaveta, query: "1-323-555-5555", transaction: transaction))
            XCTAssert(self.searcher.matches(item: self.stinkingLizaveta, query: "13235555555", transaction: transaction))
            XCTAssert(self.searcher.matches(item: self.stinkingLizaveta, query: "+1-323", transaction: transaction))
            XCTAssert(self.searcher.matches(item: self.stinkingLizaveta, query: "Liza +1-323", transaction: transaction))

            // Sanity check, match both by names
            XCTAssert(self.searcher.matches(item: self.stinkingLizaveta, query: "Liza", transaction: transaction))
            XCTAssert(self.searcher.matches(item: self.regularLizaveta, query: "Liza", transaction: transaction))

            // Disambiguate the two Liza's by area code
            XCTAssert(self.searcher.matches(item: self.stinkingLizaveta, query: "Liza 323", transaction: transaction))
            XCTAssertFalse(self.searcher.matches(item: self.regularLizaveta, query: "Liza 323", transaction: transaction))
        }
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
