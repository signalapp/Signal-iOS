//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class ConversationLayoutInfo: NSObject {

    private let thread: TSThread

    private let isRTL: Bool

    // The width of the collection view.
    @objc public var viewWidth: CGFloat = 0 {
        didSet {
            SwiftAssertIsOnMainThread(#function)

            updateProperties()
        }
    }

    @objc public let contentMarginTop: CGFloat = 10
    @objc public let contentMarginBottom: CGFloat = 10

    @objc public var gutterLeading: CGFloat = 0
    @objc public var gutterTrailing: CGFloat = 0
    // These are the gutters used by "full width" views
    // like "date headers" and "unread indicator".
    @objc public var fullWidthGutterLeading: CGFloat = 0
    @objc public var fullWidthGutterTrailing: CGFloat = 0

    // viewWidth - (gutterLeading + gutterTrailing)
    @objc public var contentWidth: CGFloat = 0

    // viewWidth - (gutterfullWidthGutterLeadingLeading + fullWidthGutterTrailing)
    // TODO: Is this necessary?
    @objc public var fullWidthContentWidth: CGFloat = 0

    @objc public var maxMessageWidth: CGFloat = 0
    @objc public var maxFooterWidth: CGFloat = 0

    @objc
    public required init(thread: TSThread) {

        self.thread = thread
        self.isRTL = CurrentAppContext().isRTL

        super.init()

        updateProperties()
    }

    private func updateProperties() {
        if thread.isGroupThread() {
            gutterLeading = 40
            gutterTrailing = 20
        } else {
            gutterLeading = 16
            gutterTrailing = 20
        }
        // TODO: Should these be symmetric? Should they reflect the other gutters?
        fullWidthGutterLeading = 20
        fullWidthGutterTrailing = 20

        contentWidth = viewWidth - (gutterLeading + gutterTrailing)

        fullWidthContentWidth = viewWidth - (fullWidthGutterLeading + fullWidthGutterTrailing)

        maxMessageWidth = floor(contentWidth * 0.8)
        // TODO: Should this be different?
        maxFooterWidth = maxMessageWidth - 10
    }
}
