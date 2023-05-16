//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

public class AvatarTableViewCell: UITableViewCell {

    private let columns: UIStackView
    private let textRows: UIStackView
    private let avatarView: AvatarImageView

    private let _textLabel: UILabel
    override public var textLabel: UILabel? { _textLabel }

    private let _detailTextLabel: UILabel
    override public var detailTextLabel: UILabel? { _detailTextLabel }

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        self.avatarView =  AvatarImageView()
        avatarView.autoSetDimensions(to: CGSize(square: CGFloat(AvatarBuilder.standardAvatarSizePoints)))

        self._textLabel = UILabel()
        self._detailTextLabel = UILabel()

        self.textRows = UIStackView(arrangedSubviews: [_textLabel, _detailTextLabel])
        textRows.axis = .vertical

        self.columns = UIStackView(arrangedSubviews: [avatarView, textRows])
        columns.axis = .horizontal
        columns.spacing = ContactCellView.avatarTextHSpacing

        super.init(style: style, reuseIdentifier: reuseIdentifier)

        self.contentView.addSubview(columns)
        columns.autoPinEdgesToSuperviewMargins()

        OWSTableItem.configureCell(self)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(image: UIImage?, text: String?, detailText: String? = nil) {
        self.avatarView.image = image
        self.textLabel?.text = text
        self.detailTextLabel?.text = detailText

        OWSTableItem.configureCell(self)
    }

    public override func prepareForReuse() {
        super.prepareForReuse()

        self.avatarView.image = nil
        self.textLabel?.text = nil
        self.detailTextLabel?.text = nil
    }
}
