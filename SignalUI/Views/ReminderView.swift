//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

open class ReminderView: UIView {
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

    private lazy var backgroundView = UIView()

    private lazy var textLabel: UILabel = {
        let result = UILabel()
        result.font = .dynamicTypeSubheadline
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        return result
    }()

    private lazy var actionLabel: UILabel = {
        let result = UILabel()
        result.font = .dynamicTypeSubheadline.semibold()
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        return result
    }()

    private lazy var textContainer: UIStackView = {
        let result = UIStackView()
        result.axis = .vertical
        result.spacing = 8
        result.alignment = .trailing
        return result
    }()

    private func initialRender() {
        self.layoutMargins = .init(hMargin: 18, vMargin: 12)
        self.addSubview(backgroundView)
        backgroundView.autoPinEdgesToSuperviewMargins()
        backgroundView.layer.cornerRadius = 12
        backgroundView.layoutMargins = .init(top: 14, leading: 16, bottom: 14, trailing: 16)

        backgroundView.addSubview(textContainer)
        textContainer.addArrangedSubview(textLabel)
        textContainer.autoPinEdgesToSuperviewMargins()
        textLabel.autoPinWidthToSuperviewMargins()

        render()
    }

    @objc
    private func render() {
        textLabel.text = text
        actionLabel.textColor = Theme.primaryTextColor

        textContainer.removeArrangedSubview(actionLabel)
        if let actionTitle {
            actionLabel.text = actionTitle
            textContainer.addArrangedSubview(actionLabel)
            layoutMargins.bottom = 10
        } else {
            layoutMargins.bottom = 14
        }

        self.backgroundColor = Theme.backgroundColor

        switch style {
        case .warning:
            if Theme.isDarkThemeEnabled {
                backgroundView.backgroundColor = .ows_gray75
                textLabel.textColor = .ows_gray05
            } else {
                backgroundView.backgroundColor = UIColor(rgbHex: 0xFCF0D9)
                textLabel.textColor = .ows_gray65
            }
        case .info:
            backgroundView.backgroundColor = Theme.secondaryBackgroundColor
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
