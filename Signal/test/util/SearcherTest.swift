//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import Signal
@testable import SignalMessaging

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
        XCTAssert(searcher.matches(item: stinkingLizaveta, query:"323"))
        XCTAssert(searcher.matches(item: stinkingLizaveta, query:"1-323-555-5555"))
        XCTAssert(searcher.matches(item: stinkingLizaveta, query:"13235555555"))
        XCTAssert(searcher.matches(item: stinkingLizaveta, query:"+1-323"))
        XCTAssert(searcher.matches(item: stinkingLizaveta, query:"Liza +1-323"))

        // Sanity check, match both by names
        XCTAssert(searcher.matches(item: stinkingLizaveta, query:"Liza"))
        XCTAssert(searcher.matches(item: regularLizaveta, query:"Liza"))

        // Disambiguate the two Liza's by area code
        XCTAssert(searcher.matches(item: stinkingLizaveta, query:"Liza 323"))
        XCTAssertFalse(searcher.matches(item: regularLizaveta, query:"Liza 323"))
    }
}
