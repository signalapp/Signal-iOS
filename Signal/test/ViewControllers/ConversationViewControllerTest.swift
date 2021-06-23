//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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
