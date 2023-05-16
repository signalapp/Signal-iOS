//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

open class ReminderView: UIStackView {
    public enum Style {
        case info
        case warning
    }
    private let style: Style
    public var text: String {
        didSet { render() }
    }
    public var actionTitle: String? {
        didSet { render() }
    }
    public var tapAction: () -> Void

    @available(*, unavailable, message: "use other constructor instead.")
    required public init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable, message: "use other constructor instead.")
    override init(frame: CGRect) {
        fatalError("init(frame:) has not been implemented")
    }

    public init(
        style: Style,
        text: String,
        actionTitle: String? = nil,
        tapAction: @escaping () -> Void = {}
    ) {
        self.style = style
        self.text = text
        self.tapAction = tapAction

        super.init(frame: .zero)

        self.actionTitle = actionTitle

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(render),
            name: .themeDidChange,
            object: nil
        )

        self.addGestureRecognizer(UITapGestureRecognizer(
            target: self,
            action: #selector(handleTap(gestureRecognizer:))
        ))

        initialRender()
    }

    // MARK: - Rendering

    private lazy var iconView: UIImageView = {
        let image = UIImage(named: "error-outline-24")
        let result = UIImageView(image: image?.withRenderingMode(.alwaysTemplate))
        result.contentMode = .scaleAspectFit
        result.autoSetDimensions(to: CGSize(square: 22))
        return result
    }()

    private lazy var textLabel: UILabel = {
        let result = UILabel()
        result.font = .dynamicTypeFootnote
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        return result
    }()

    private lazy var actionLabel: UILabel = {
        let result = UILabel()
        result.font = .dynamicTypeFootnote.semibold()
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        return result
    }()

    private lazy var textContainer: UIStackView = {
        let result = UIStackView()
        result.axis = .vertical
        result.spacing = 4
        return result
    }()

    private func initialRender() {
        switch style {
        case .info: break
        case .warning: addArrangedSubview(iconView)
        }

        textContainer.addArrangedSubview(textLabel)
        addArrangedSubview(textContainer)

        spacing = 16
        alignment = .leading
        isLayoutMarginsRelativeArrangement = true
        layoutMargins = .init(top: 14, leading: 16, bottom: 14, trailing: 16)

        render()
    }

    @objc
    private func render() {
        textLabel.text = text

        textContainer.removeArrangedSubview(actionLabel)
        if let actionTitle {
            actionLabel.text = actionTitle
            textContainer.addArrangedSubview(actionLabel)
            layoutMargins.bottom = 10
        } else {
            layoutMargins.bottom = 14
        }

        switch style {
        case .warning:
            if Theme.isDarkThemeEnabled {
                backgroundColor = .ows_gray75
                textLabel.textColor = .ows_gray05
            } else {
                backgroundColor = UIColor(rgbHex: 0xFCF0D9)
                textLabel.textColor = .ows_gray65
            }
            actionLabel.textColor = Theme.accentBlueColor
            iconView.tintColor = Theme.secondaryTextAndIconColor
        case .info:
            backgroundColor = Theme.washColor
            textLabel.textColor = Theme.primaryTextColor
        }
    }

    @objc
    private func handleTap(gestureRecognizer: UIGestureRecognizer) {
        guard gestureRecognizer.state == .recognized else {
            return
        }
        tapAction()
    }
}
