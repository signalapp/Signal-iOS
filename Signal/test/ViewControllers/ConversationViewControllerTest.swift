//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import Signal

class ConverstationViewControllerTest: SignalBaseTest {

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
