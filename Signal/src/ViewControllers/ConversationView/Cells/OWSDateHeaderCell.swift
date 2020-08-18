//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

private let strokeHeight: CGFloat = 1

@objc(OWSDateHeaderCell)
public class DateHeaderCell: ConversationViewCell {

    // MARK: -

    @objc
    public static let cellReuseIdentifier = "DateHeaderCell"

    @available(*, unavailable, message:"use other constructor instead.")
    @objc
    public required init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.contentView.layoutMargins = .zero

        // Intercept touches.
        // Date breaks and unread indicators are not interactive.
        self.isUserInteractionEnabled = true

        contentView.addSubview(titleLabel)
        titleLabel.autoPinEdgesToSuperviewMargins()
    }

    let titleLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    override public func loadForDisplay() {
        guard let viewItem = viewItem else {
            owsFailDebug("viewItem was unexpectedly nil")
            return
        }
        guard let conversationStyle = conversationStyle else {
            owsFailDebug("conversationStyle was unexpectedly nil")
            return
        }

        titleLabel.font = UIFont.ows_dynamicTypeFootnote.ows_semibold()
        titleLabel.textColor = Theme.secondaryTextAndIconColor

        let date = Date(millisecondsSince1970: viewItem.interaction.timestamp)
        let dateString = DateUtil.formatDate(forConversationDateBreaks: date)

        titleLabel.text = dateString

        self.contentView.layoutMargins = UIEdgeInsets(top: 8,
                                                      leading: conversationStyle.headerGutterLeading,
                                                      bottom: 8,
                                                      trailing: conversationStyle.headerGutterTrailing)
    }

    @objc
    public override func cellSize() -> CGSize {
        guard let conversationStyle = self.conversationStyle else {
            owsFailDebug("Missing conversationStyle")
            return .zero
        }

        loadForDisplay()

        let viewWidth = conversationStyle.viewWidth
        var height: CGFloat = strokeHeight
        height += contentView.layoutMargins.top + contentView.layoutMargins.bottom

        let availableWidth = viewWidth - contentView.layoutMargins.left - contentView.layoutMargins.right
        let availableSize = CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
        let labelSize = titleLabel.sizeThatFits(availableSize)

        height += labelSize.height

        return CGSizeCeil(CGSize(width: viewWidth, height: height))
    }
}
