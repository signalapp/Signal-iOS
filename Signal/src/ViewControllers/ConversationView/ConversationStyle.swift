//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class ConversationStyle: NSObject {

    private let thread: TSThread

    private let isRTL: Bool

    // The width of the collection view.
    @objc public var viewWidth: CGFloat = 0 {
        didSet {
            SwiftAssertIsOnMainThread(#function)

            updateProperties()
        }
    }

    @objc public let contentMarginTop: CGFloat = 24
    @objc public let contentMarginBottom: CGFloat = 24

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
    // TODO: Can we eliminate this after moving timestamps and
    //       message status inside the message bubbles.
    @objc public var maxFooterWidth: CGFloat = 0

    @objc public var textInsetTop: CGFloat = 0
    @objc public var textInsetBottom: CGFloat = 0
    @objc public var textInsetHorizontal: CGFloat = 0

    // We want to align "group sender" avatars with the v-center of the
    // "last line" of the message body text - or where it would be for
    // non-text content.
    //
    // This is the distance from that v-center to the bottom of the
    // message bubble.
    @objc public var lastTextLineAxis: CGFloat = 0

    @objc
    public required init(thread: TSThread) {

        self.thread = thread
        self.isRTL = CurrentAppContext().isRTL

        super.init()

        updateProperties()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(uiContentSizeCategoryDidChange),
                                               name: NSNotification.Name.UIContentSizeCategoryDidChange,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func uiContentSizeCategoryDidChange() {
        SwiftAssertIsOnMainThread(#function)

        updateProperties()
    }

    // MARK: -

    private func updateProperties() {
        if thread.isGroupThread() {
            gutterLeading = 40
            gutterTrailing = 20
        } else {
            gutterLeading = 16
            gutterTrailing = 20
        }
        fullWidthGutterLeading = gutterLeading
        fullWidthGutterTrailing = gutterTrailing

        contentWidth = viewWidth - (gutterLeading + gutterTrailing)

        fullWidthContentWidth = viewWidth - (fullWidthGutterLeading + fullWidthGutterTrailing)

        maxMessageWidth = floor(contentWidth - 48)
        // TODO: Should this be different?
        maxFooterWidth = maxMessageWidth - 10

        let messageTextFont = UIFont.ows_dynamicTypeBody
        // Don't include the distance from the "cap height" to the top of the UILabel
        // in the top margin.
        textInsetTop = max(0, 12 - (messageTextFont.ascender - messageTextFont.capHeight))
        // Don't include the distance from the "baseline" to the bottom of the UILabel
        // (e.g. the descender) in the top margin. Note that UIFont.descender is a
        // negative value.
        textInsetBottom = max(0, 12 - abs(messageTextFont.descender))
        textInsetHorizontal = 12

        lastTextLineAxis = CGFloat(round(12 + messageTextFont.capHeight * 0.5))
    }
}
