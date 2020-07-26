//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public enum MentionStyle: Int {
    case incoming
    case outgoing

    public static var composing: MentionStyle = .incoming
}

class MentionTextAttachment: NSTextAttachment {
    let address: SignalServiceAddress
    let text: String
    let style: MentionStyle

    private let mentionPadding: CGFloat = 3
    private let label = UILabel()

    init(address: SignalServiceAddress, style: MentionStyle) {
        self.address = address
        self.style = style

        // TODO: Maybe don't lookup the display name here..
        self.text = MentionTextView.mentionPrefix + Environment.shared.contactsManager.displayName(for: address)

        super.init(data: nil, ofType: nil)

        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.text = text

        label.font = .ows_dynamicTypeBody
        label.textAlignment = .center
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var cachedBounds: CGRect?
    private var cachedProposedWidth: CGFloat?
    func calculateBounds(proposedWidth: CGFloat) -> CGRect {
        if let cachedBounds = cachedBounds, cachedProposedWidth == proposedWidth { return cachedBounds }

        let maxWidth = proposedWidth - mentionPadding * 2

        label.sizeToFit()

        label.frame.size.width += mentionPadding * 2
        label.frame.size.height += mentionPadding * 2

        if label.width > maxWidth {
            label.frame.size.width = maxWidth
        }

        let bounds = CGRect(
            origin: CGPoint(x: 0, y: label.font.ascender - label.font.lineHeight - mentionPadding),
            size: label.frame.size
        )
        cachedBounds = bounds
        cachedProposedWidth = proposedWidth
        cachedImage = nil
        return bounds
    }

    private var cachedImage: UIImage?
    override func image(
        forBounds imageBounds: CGRect,
        textContainer: NSTextContainer?,
        characterIndex charIndex: Int
    ) -> UIImage? {
        if let cachedImage = cachedImage { return cachedImage }

        switch style {
        case .incoming:
            label.backgroundColor = Theme.isDarkThemeEnabled ? .ows_blackAlpha20 : UIColor(rgbHex: 0xCCCCCC)
            label.textColor = ConversationStyle.bubbleTextColorIncoming
        case .outgoing:
            label.backgroundColor = Theme.isDarkThemeEnabled ? .ows_blackAlpha20 : .ows_signalBlueDark
            label.textColor = ConversationStyle.bubbleTextColorOutgoing
        }

        let renderer = UIGraphicsImageRenderer(size: imageBounds.size)
        let image = renderer.image { ctx in
            label.layer.render(in: ctx.cgContext)
        }
        cachedImage = image
        return image
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        return calculateBounds(proposedWidth: lineFrag.width)
    }
}
