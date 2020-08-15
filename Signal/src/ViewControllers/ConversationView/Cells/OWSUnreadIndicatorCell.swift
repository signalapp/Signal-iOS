//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

private let strokeHeight: CGFloat = 1

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
        stackView.spacing = 12
        contentView.addSubview(stackView)
        stackView.autoPinEdges(toSuperviewMarginsExcludingEdge: .bottom)

        titleLabel.text = NSLocalizedString("MESSAGES_VIEW_UNREAD_INDICATOR",
                                            comment: "Indicator that separates read from unread messages.")
        titleLabel.numberOfLines = 0
        titleLabel.font = UIFont.ows_dynamicTypeFootnote.ows_semibold()
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
        stroke.backgroundColor = UIColor.ows_gray45
        return stroke
    }()

    override public func loadForDisplay() {
        titleLabel.textColor = Theme.primaryTextColor
        contentView.layoutMargins = UIEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
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
