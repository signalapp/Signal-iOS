//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

class GroupCallErrorView: UIView {

    var forceCompactAppearance: Bool = false {
        didSet { configure() }
    }

    var iconImage: UIImage? {
        didSet {
            if let iconImage = iconImage {
                iconView.setTemplateImage(iconImage, tintColor: .ows_white)
                miniButton.setTemplateImage(iconImage, tintColor: .ows_white)
            } else {
                iconView.image = nil
                miniButton.setImage(nil, for: .normal)
            }
        }
    }

    var labelText: String? {
        didSet {
            label.text = labelText
            configure()
        }
    }

    var userTapAction: ((GroupCallErrorView) -> Void)?

    // MARK: - Views

    private let iconView: UIImageView = UIImageView()

    private let label: UILabel = {
        let label = UILabel()
        label.font = UIFont.ows_dynamicTypeSubheadline
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.textColor = .ows_white
        label.numberOfLines = 0
        return label
    }()

    private lazy var button: UIButton = {
        let buttonLabel = NSLocalizedString(
            "GROUP_CALL_ERROR_DETAILS",
            comment: "A button to receive more info about not seeing a participant in group call grid")

        let button = UIButton()
        button.backgroundColor = .ows_gray75

        button.contentEdgeInsets = UIEdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12)
        button.layer.cornerRadius = 12
        button.clipsToBounds = true

        button.titleLabel?.textAlignment = .center
        button.titleLabel?.font = UIFont.ows_dynamicTypeSubheadline.ows_semibold
        button.setTitle(buttonLabel, for: .normal)

        button.addTarget(self, action: #selector(didTapButton), for: .touchUpInside)
        return button
    }()

    private lazy var miniButton: UIButton = {
        let button = UIButton()
        button.contentVerticalAlignment = .fill
        button.contentHorizontalAlignment = .fill

        button.addTarget(self, action: #selector(didTapButton), for: .touchUpInside)
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let stackView = UIStackView(arrangedSubviews: [
            iconView,
            label,
            button
        ])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.distribution = .fill

        stackView.setCustomSpacing(12, after: iconView)
        stackView.setCustomSpacing(16, after: label)

        insetsLayoutMarginsFromSafeArea = false

        addSubview(miniButton)
        addSubview(stackView)

        stackView.autoPinWidthToSuperviewMargins()
        stackView.autoVCenterInSuperview()
        stackView.autoPinEdge(toSuperviewMargin: .top, relation: .greaterThanOrEqual)
        stackView.autoPinEdge(toSuperviewMargin: .bottom, relation: .greaterThanOrEqual)
        miniButton.autoCenterInSuperview()

        iconView.setCompressionResistanceHigh()
        button.setCompressionResistanceHigh()

        iconView.autoSetDimensions(to: CGSize(width: 24, height: 24))
        button.autoSetDimension(.height, toSize: 24, relation: .greaterThanOrEqual)
        miniButton.autoSetDimensions(to: CGSize(width: 24, height: 24))

        configure()
    }

    override var bounds: CGRect {
        didSet {
            let didChange = bounds != oldValue
            if didChange {
                configure()
            }
        }
    }

    override var frame: CGRect {
        didSet {
            let didChange = frame != oldValue
            if didChange {
                configure()
            }
        }
    }

    private func configure() {
        let isCompact = (bounds.width < 100) || (bounds.height < 100) || forceCompactAppearance
        iconView.isHidden = isCompact
        label.isHidden = isCompact
        button.isHidden = isCompact
        miniButton.isHidden = !isCompact

        layoutIfNeeded()

        // The error text is easily truncated in small cells with large dynamic type.
        // If the label gets truncated, just hide it.
        if !label.isHidden {
            let widthBox = CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)
            let labelDesiredHeight = label.sizeThatFits(widthBox).height
            label.isHidden = (labelDesiredHeight > label.bounds.height)
        }
    }

    @objc
    private func didTapButton() {
        userTapAction?(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
