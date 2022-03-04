//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest
@testable import SignalServiceKit

class RefineryTest: SSKBaseTestSwift {

    func testBasic() {
        let keys = [1, 2, 3]
        let refinery = Refinery<Int, String>(keys).refine { values in
            return values.lazy.map {
                if $0 == 1 {
                    return "one"
                }
                return nil
            }
        }.refine { values in
            return values.lazy.map {
                XCTAssertFalse($0 == 1)  // Already handled 1 and we shouldn't be called again.
                if $0 == 3 {
                    return "three"
                }
                return nil
            }
        }

        let actual = refinery.values
        let expected = ["one", nil, "three"]
        XCTAssertEqual(actual, expected)
    }

    func testConditional() {
        let keys = [1, 2, 3, 4]
        let refinery = Refinery<Int, String>(keys).refine(condition: {
            $0 % 2 == 0
        }, then: { values in
            return values.lazy.map {
                XCTAssertFalse($0 == 1)
                XCTAssertFalse($0 == 3)
                if $0 == 2 {
                    return nil
                }
                return "even: \($0)"
            }
        }, otherwise: { values in
            return values.lazy.map {
                XCTAssertFalse($0 == 0)
                XCTAssertFalse($0 == 2)
                return "odd: \($0)"
            }
        })

        let actual = refinery.values
        let expected = ["odd: 1", nil, "odd: 3", "even: 4"]
        XCTAssertEqual(actual, expected)
    }

    func testDuplicateKey() {
        let keys = [1, 2, 3, 1]
        let refinery = Refinery<Int, String>(keys).refine { values in
            return values.lazy.map {
                if $0 == 1 {
                    return "one"
                }
                return nil
            }
        }.refine { values in
            return values.lazy.map {
                XCTAssertFalse($0 == 1)  // Already handled 1 and we shouldn't be called again.
                if $0 == 3 {
                    return "three"
                }
                return nil
            }
        }

        let actual = refinery.values
        let expected = ["one", nil, "three", "one"]
        XCTAssertEqual(actual, expected)
    }

    func testOnePass() {
        let keys = [1, 2, 3]
        let refinery = Refinery<Int, String>(keys).refine { values in
            return values.lazy.map {
                switch $0 {
                case 1:
                    return "one"
                case 2:
                    return "two"
                case 3:
                    return "three"
                default:
                    return nil
                }
            }
        }

        let actual = refinery.values
        let expected = ["one", "two", "three"]
        XCTAssertEqual(actual, expected)
    }
}
