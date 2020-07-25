//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class MentionTextAttachment: NSTextAttachment {
    let mentionPadding: CGFloat = 3

    let address: SignalServiceAddress

    let label = UILabel()

    init(address: SignalServiceAddress) {
        self.address = address

        super.init(data: nil, ofType: nil)

        label.layer.cornerRadius = 4
        label.clipsToBounds = true

        label.font = .ows_dynamicTypeBody
        label.textAlignment = .center
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var attributedString: NSAttributedString { .init(attachment: self) }

    func calculateBounds() -> CGRect {
        label.text = MentionTextView.mentionPrefix + Environment.shared.contactsManager.displayName(for: address)
        label.sizeToFit()
        label.frame = label.frame.insetBy(dx: -mentionPadding, dy: -mentionPadding)

        return CGRect(
            origin: CGPoint(x: 0, y: label.font.ascender - label.font.lineHeight - mentionPadding),
            size: label.frame.size
        )
    }

    public override func image(
        forBounds imageBounds: CGRect,
        textContainer: NSTextContainer?,
        characterIndex charIndex: Int
    ) -> UIImage? {
        label.backgroundColor = #colorLiteral(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)
        label.textColor = Theme.primaryTextColor

        let renderer = UIGraphicsImageRenderer(size: imageBounds.size)
        return renderer.image { ctx in
            label.layer.render(in: ctx.cgContext)
        }
    }

    public override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        return calculateBounds()
    }
}
