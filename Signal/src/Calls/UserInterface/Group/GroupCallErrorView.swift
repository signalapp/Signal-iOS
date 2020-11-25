//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class GroupCallErrorView: UIView {

    // MARK: - Interface

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
        }
    }

    var userTapAction: ((GroupCallErrorView) -> Void)?

    func resetConfiguration() {
        iconImage = nil
        labelText = nil
        userTapAction = nil
    }

    // MARK: - Views

    private let iconView: UIImageView = {
        let view = UIImageView()
        view.setTemplateImageName("error-solid-16", tintColor: .ows_white)
        return view
    }()

    private let label: UILabel = {
        let label = UILabel()
        label.font = UIFont.ows_dynamicTypeSubheadline
        label.textAlignment = .center
        label.textColor = .ows_white
        label.numberOfLines = 0
        return label
    }()

    private let button: UIButton = {
        let buttonLabel = NSLocalizedString(
            "GROUP_CALL_ERROR_DETAILS",
            comment: "A button to receive more info about not seeing a participant in group call grid")

        let button = UIButton()
        button.backgroundColor = UIColor.darkGray
        button.layer.cornerRadius = 16
        button.titleLabel?.textAlignment = .center
        button.contentEdgeInsets = UIEdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12)
        button.clipsToBounds = true
        button.setTitle(buttonLabel, for: .normal)
        button.addTarget(self, action: #selector(didTapButton), for: .touchUpInside)
        return button
    }()
    
    private let miniButton: UIButton = {
        let button = UIButton()
        button.contentVerticalAlignment = .fill
        button.contentHorizontalAlignment = .fill
        button.setTemplateImageName("error-solid-16", tintColor: .ows_white)
        button.addTarget(self, action: #selector(didTapButton), for: .touchUpInside)
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let stackView = UIStackView(arrangedSubviews: [
            iconView,
            label,
            button,
        ])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.distribution = .fill

        stackView.setCustomSpacing(12, after: iconView)
        stackView.setCustomSpacing(16, after: label)

        addSubview(stackView)
        stackView.autoPinWidthToSuperviewMargins()
        stackView.autoVCenterInSuperview()
        stackView.autoPinEdge(toSuperviewMargin: .top, relation: .greaterThanOrEqual)
        stackView.autoPinEdge(toSuperviewMargin: .bottom, relation: .greaterThanOrEqual)

        iconView.autoSetDimensions(to: CGSize(width: 24, height: 24))

        addSubview(miniButton)
        miniButton.autoSetDimensions(to: CGSize(width: 24, height: 24))
        miniButton.autoCenterInSuperview()
        configure()
    }

    override var bounds: CGRect {
        didSet { configure() }
    }

    override var frame: CGRect {
        didSet { configure() }
    }

    private func configure() {
        let isCompact = (bounds.width < 100) || (bounds.height < 100) || forceCompactAppearance
        iconView.isHidden = isCompact
        label.isHidden = isCompact
        button.isHidden = isCompact
        miniButton.isHidden = !isCompact
    }

    @objc
    private func didTapButton() {
        userTapAction?(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
