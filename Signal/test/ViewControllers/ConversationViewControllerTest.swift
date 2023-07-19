//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal

class ConversationViewControllerTest: SignalBaseTest {

    func testCVCBottomViewType() {
        XCTAssertEqual(CVCBottomViewType.none, CVCBottomViewType.none)
        XCTAssertNotEqual(CVCBottomViewType.none, CVCBottomViewType.inputToolbar)
        XCTAssertEqual(CVCBottomViewType.inputToolbar, CVCBottomViewType.inputToolbar)
        XCTAssertNotEqual(CVCBottomViewType.none, CVCBottomViewType.memberRequestView)
        XCTAssertNotEqual(CVCBottomViewType.memberRequestView,
                          CVCBottomViewType.messageRequestView(messageRequestType: MessageRequestType(isGroupV1Thread: true,
                                                                                                      isGroupV2Thread: true,
                                                                                                      isThreadBlocked: true,
                                                                                                      hasSentMessages: true,
                                                                                                      isThreadFromHiddenRecipient: false)))
        XCTAssertEqual(CVCBottomViewType.messageRequestView(messageRequestType: MessageRequestType(isGroupV1Thread: true,
                                                                                                      isGroupV2Thread: true,
                                                                                                      isThreadBlocked: true,
                                                                                                      hasSentMessages: true,
                                                                                                      isThreadFromHiddenRecipient: false)),
                          CVCBottomViewType.messageRequestView(messageRequestType: MessageRequestType(isGroupV1Thread: true,
                                                                                                      isGroupV2Thread: true,
                                                                                                      isThreadBlocked: true,
                                                                                                      hasSentMessages: true,
                                                                                                      isThreadFromHiddenRecipient: false)))
        XCTAssertNotEqual(CVCBottomViewType.messageRequestView(messageRequestType: MessageRequestType(isGroupV1Thread: true,
                                                                                                      isGroupV2Thread: true,
                                                                                                      isThreadBlocked: true,
                                                                                                      hasSentMessages: true,
                                                                                                      isThreadFromHiddenRecipient: false)),
                          CVCBottomViewType.messageRequestView(messageRequestType: MessageRequestType(isGroupV1Thread: true,
                                                                                                      isGroupV2Thread: false,
                                                                                                      isThreadBlocked: true,
                                                                                                      hasSentMessages: true,
                                                                                                      isThreadFromHiddenRecipient: false)))
        XCTAssertEqual(CVCBottomViewType.messageRequestView(messageRequestType: MessageRequestType(isGroupV1Thread: true,
                                                                                                   isGroupV2Thread: false,
                                                                                                   isThreadBlocked: true,
                                                                                                   hasSentMessages: true,
                                                                                                   isThreadFromHiddenRecipient: false)),
                       CVCBottomViewType.messageRequestView(messageRequestType: MessageRequestType(isGroupV1Thread: true,
                                                                                                   isGroupV2Thread: false,
                                                                                                   isThreadBlocked: true,
                                                                                                   hasSentMessages: true,
                                                                                                   isThreadFromHiddenRecipient: false)))
        XCTAssertNotEqual(CVCBottomViewType.messageRequestView(messageRequestType: MessageRequestType(isGroupV1Thread: true,
                                                                                                      isGroupV2Thread: true,
                                                                                                      isThreadBlocked: true,
                                                                                                      hasSentMessages: false,
                                                                                                      isThreadFromHiddenRecipient: false)),
                          CVCBottomViewType.messageRequestView(messageRequestType: MessageRequestType(isGroupV1Thread: true,
                                                                                                      isGroupV2Thread: false,
                                                                                                      isThreadBlocked: true,
                                                                                                      hasSentMessages: true,
                                                                                                      isThreadFromHiddenRecipient: false)))
    }
}
