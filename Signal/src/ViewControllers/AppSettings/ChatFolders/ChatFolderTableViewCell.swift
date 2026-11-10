//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class ChatFolderTableViewCell: UITableViewCell, ReusableTableViewCell {
    static let reuseIdentifier = "ChatFolderTableViewCell"

    private static let iconCircleSize = CGFloat(AvatarBuilder.smallAvatarSizePoints)
    private static let iconSize: CGFloat = 22
    private static let iconTitleSpacing = ContactCellView.avatarTextHSpacing

    private let iconLabel: UILabel = {
        let iconLabel = UILabel()
        iconLabel.textColor = .Signal.label
        return iconLabel
    }()

    private lazy var iconCircle: UIView = {
        let iconCircle = UIView()
        iconCircle.backgroundColor = .Signal.quaternaryFill
        iconCircle.layer.cornerRadius = Self.iconCircleSize / 2
        iconCircle.autoSetDimensions(to: CGSize(square: Self.iconCircleSize))
        iconCircle.setContentHuggingHorizontalHigh()
        iconCircle.setCompressionResistanceHorizontalHigh()

        iconCircle.addSubview(iconLabel)
        iconLabel.autoCenterInSuperview()
        iconCircle.accessibilityElementsHidden = true

        return iconCircle
    }()

    private let titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.font = .dynamicTypeBodyClamped
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .Signal.label
        titleLabel.numberOfLines = 0
        return titleLabel
    }()

    private let subtitleLabel: UILabel = {
        let subtitleLabel = UILabel()
        subtitleLabel.font = .dynamicTypeCaption1Clamped
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .Signal.secondaryLabel
        subtitleLabel.numberOfLines = 0
        return subtitleLabel
    }()

    private let stackView = UIStackView()

    private var trailingView: UIView?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .Signal.secondaryGroupedBackground

        let selectedBackgroundView = UIView()
        selectedBackgroundView.backgroundColor = .Signal.primaryFill
        self.selectedBackgroundView = selectedBackgroundView

        let labelStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labelStack.axis = .vertical
        labelStack.spacing = 2

        stackView.axis = .horizontal
        stackView.spacing = Self.iconTitleSpacing
        stackView.alignment = .center
        stackView.addArrangedSubview(iconCircle)
        stackView.addArrangedSubview(labelStack)

        contentView.preservesSuperviewLayoutMargins = true
        contentView.addSubview(stackView)
        stackView.autoPinWidthToSuperviewMargins()
        stackView.autoPinHeightToSuperview(withMargin: 10)
    }

    required init?(coder: NSCoder) {
        owsFail("Not implemented!")
    }

    func configure(
        symbol: SignalSymbol,
        title: String,
        subtitle: String? = nil,
        trailingView: UIView? = nil,
    ) {
        iconLabel.attributedText = symbol.attributedString(staticFontSize: Self.iconSize)
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil

        self.trailingView?.removeFromSuperview()
        self.trailingView = trailingView
        if let trailingView {
            trailingView.setContentHuggingHorizontalHigh()
            trailingView.setCompressionResistanceHorizontalHigh()
            stackView.addArrangedSubview(trailingView)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let separatorLeading = contentView.directionalLayoutMargins.leading
            + Self.iconCircleSize
            + Self.iconTitleSpacing
        if separatorInset.left != separatorLeading {
            separatorInset.left = separatorLeading
        }
    }
}
