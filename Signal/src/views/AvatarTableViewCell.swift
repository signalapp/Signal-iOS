//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSAvatarTableViewCell)
public class AvatarTableViewCell: UITableViewCell {

    private let columns: UIStackView
    private let textRows: UIStackView
    private let avatarView: AvatarImageView

    private let _textLabel: UILabel
    override public var textLabel: UILabel? {
        get {
            return _textLabel
        }
    }

    private let _detailTextLabel: UILabel
    override public var detailTextLabel: UILabel? {
        get {
            return _detailTextLabel
        }
    }

    @objc
    public override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        self.avatarView =  AvatarImageView()
        avatarView.autoSetDimensions(to: CGSize(width: CGFloat(kStandardAvatarSize), height: CGFloat(kStandardAvatarSize)))

        self._textLabel = UILabel()
        self._detailTextLabel = UILabel()

        self.textRows = UIStackView(arrangedSubviews: [_textLabel, _detailTextLabel])
        textRows.axis = .vertical

        self.columns = UIStackView(arrangedSubviews: [avatarView, textRows])
        columns.axis = .horizontal
        columns.spacing = CGFloat(kContactCellAvatarTextMargin)

        super.init(style: style, reuseIdentifier: reuseIdentifier)

        self.contentView.addSubview(columns)
        columns.autoPinEdgesToSuperviewMargins()

        OWSTableItem.configureCell(self)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    public func configure(image: UIImage?, text: String?, detailText: String?) {
        self.avatarView.image = image
        self.textLabel?.text = text
        self.detailTextLabel?.text = detailText

        OWSTableItem.configureCell(self)
    }

    @objc
    public override func prepareForReuse() {
        super.prepareForReuse()

        self.avatarView.image = nil
        self.textLabel?.text = nil
        self.detailTextLabel?.text = nil
    }
}
