//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
@testable import Signal

class ConverstationViewControllerTest: SignalBaseTest {
    private func Assert(indexPaths: [(Int, Int)],
                        expecectedGroups: [[(Int, Int)]],
                file: StaticString = #file,
                line: UInt = #line) {

        let indexPaths = indexPaths.map { IndexPath(row: $0.1, section: $0.0) }
        let actual = ConversationViewController.consecutivelyGrouped(indexPaths: indexPaths)
        let expected = expecectedGroups.map { $0.map { IndexPath(row: $0.1, section: $0.0) } }

        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    func test_consecutiveGroups_empty() {
        Assert(indexPaths: [], expecectedGroups: [])
    }

    func test_consecutiveGroups_happyPath() {
        Assert(indexPaths: [(0, 0)], expecectedGroups: [[(0, 0)]])

        Assert(indexPaths: [(0, 0), (0, 1)],
               expecectedGroups: [[(0, 0), (0, 1)]])

        Assert(indexPaths: [(0, 0), (0, 1), (0, 3)],
               expecectedGroups: [
                [(0, 0), (0, 1)],
                [(0, 3)]
        ])

        Assert(indexPaths: [(0, 0), (0, 1), (0, 3), (1, 0), (1, 1), (1, 2)],
               expecectedGroups: [
                [(0, 0), (0, 1)],
                [(0, 3)],
                [(1, 0), (1, 1), (1, 2)]
        ])
    }

    func test_consecutiveGroups_differentSections() {
        // different sections are not considered consecutive
        // that's fine for our current use case
        Assert(indexPaths: [(0, 0), (1, 0)],
                      expecectedGroups: [
                       [(0, 0)],
                       [(1, 0)]
               ])
    }

    func test_consecutiveGroups_outOfOrder() {
        Assert(indexPaths: [(0, 3), (0, 2), (0, 0), (0, 1)],
               expecectedGroups: [[(0, 0), (0, 1), (0, 2), (0, 3)]]
        )
    }

    func testCVCBottomViewType() {
        XCTAssertEqual(CVCBottomViewType.none, CVCBottomViewType.none)
        XCTAssertNotEqual(CVCBottomViewType.none, CVCBottomViewType.inputToolbar)
        XCTAssertEqual(CVCBottomViewType.inputToolbar, CVCBottomViewType.inputToolbar)
        XCTAssertNotEqual(CVCBottomViewType.none, CVCBottomViewType.memberRequestView)
        XCTAssertNotEqual(CVCBottomViewType.memberRequestView,
                          CVCBottomViewType.messageRequestView(messageRequestType: MessageRequestType(isGroupV1Thread: true,
                                                                                                      isGroupV2Thread: true,
                                                                                                      isThreadBlocked: true,
                                                                                                      hasSentMessages: true)))
        XCTAssertEqual(CVCBottomViewType.messageRequestView(messageRequestType: MessageRequestType(isGroupV1Thread: true,
                                                                                                      isGroupV2Thread: true,
                                                                                                      isThreadBlocked: true,
                                                                                                      hasSentMessages: true)),
                          CVCBottomViewType.messageRequestView(messageRequestType: MessageRequestType(isGroupV1Thread: true,
                                                                                                      isGroupV2Thread: true,
                                                                                                      isThreadBlocked: true,
                                                                                                      hasSentMessages: true)))
        XCTAssertNotEqual(CVCBottomViewType.messageRequestView(messageRequestType: MessageRequestType(isGroupV1Thread: true,
                                                                                                      isGroupV2Thread: true,
                                                                                                      isThreadBlocked: true,
                                                                                                      hasSentMessages: true)),
                          CVCBottomViewType.messageRequestView(messageRequestType: MessageRequestType(isGroupV1Thread: true,
                                                                                                      isGroupV2Thread: false,
                                                                                                      isThreadBlocked: true,
                                                                                                      hasSentMessages: true)))
        XCTAssertEqual(CVCBottomViewType.messageRequestView(messageRequestType: MessageRequestType(isGroupV1Thread: true,
                                                                                                   isGroupV2Thread: false,
                                                                                                   isThreadBlocked: true,
                                                                                                   hasSentMessages: true)),
                       CVCBottomViewType.messageRequestView(messageRequestType: MessageRequestType(isGroupV1Thread: true,
                                                                                                   isGroupV2Thread: false,
                                                                                                   isThreadBlocked: true,
                                                                                                   hasSentMessages: true)))
        XCTAssertNotEqual(CVCBottomViewType.messageRequestView(messageRequestType: MessageRequestType(isGroupV1Thread: true,
                                                                                                      isGroupV2Thread: true,
                                                                                                      isThreadBlocked: true,
                                                                                                      hasSentMessages: false)),
                          CVCBottomViewType.messageRequestView(messageRequestType: MessageRequestType(isGroupV1Thread: true,
                                                                                                      isGroupV2Thread: false,
                                                                                                      isThreadBlocked: true,
                                                                                                      hasSentMessages: true)))
    }
}
