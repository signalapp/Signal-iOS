//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

private let strokeHeight: CGFloat = 4

@objc(OWSUnreadIndicatorCell)
public class UnreadIndicatorCell: ConversationViewCell {

    // MARK: -

    @objc
    public static let cellReuseIdentifier = "UnreadIndicatorCell"

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

        self.stackView = UIStackView(arrangedSubviews: [strokeView, titleLabel])
        stackView.axis = .vertical
        stackView.spacing = 2
        contentView.addSubview(stackView)
        stackView.autoPinEdges(toSuperviewMarginsExcludingEdge: .bottom)
    }

    var stackView: UIStackView!

    let titleLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    let strokeView: UIView = {
        let stroke = UIView()
        stroke.autoSetDimension(.height, toSize: strokeHeight)
        stroke.layer.cornerRadius = strokeHeight / 2
        return stroke
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
        guard let interaction = viewItem.interaction as? UnreadIndicatorInteraction else {
            owsFailDebug("unexpected interaction type")
            return
        }

        titleLabel.font = UIFont.ows_dynamicTypeBody2.ows_semibold()
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.numberOfLines = 0

        let date = Date(millisecondsSince1970: viewItem.interaction.timestamp)
        let dateString = DateUtil.formatDate(forConversationDateBreaks: date)

        var title = NSLocalizedString("MESSAGES_VIEW_UNREAD_INDICATOR", comment: "Indicator that separates read from unread messages.")
        if interaction.shouldShowDate {
            title = dateString.appending(" \u{00B7} ").appending(title)
        }
        titleLabel.text = title.localizedUppercase

        strokeView.backgroundColor = Theme.secondaryTextAndIconColor

        self.contentView.layoutMargins = UIEdgeInsets(top: conversationStyle.headerViewDateHeaderVMargin/2,
                                                      leading: conversationStyle.headerGutterLeading,
                                                      bottom: conversationStyle.headerViewDateHeaderVMargin/2,
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

        height += labelSize.height + stackView.spacing

        return CGSizeCeil(CGSize(width: viewWidth, height: height))
    }
}
