//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

open class ReminderView: UIView {
    public enum Style {
        case info
        case warning

        var textColor: UIColor {
            switch self {
            case .info:
                UIColor.Signal.label
            case .warning:
                UIColor(
                    light: .Signal.label,
                    dark: UIColor(rgbHex: 0xC79869),
                )
            }
        }

        public var backgroundColor: UIColor {
            switch self {
            case .info:
                UIColor.Signal.secondaryBackground
            case .warning:
                UIColor(
                    light: UIColor(rgbHex: 0xFBF2E9),
                    dark: UIColor(rgbHex: 0x26221D),
                )
            }
        }

        var buttonBackgroundColor: UIColor {
            switch self {
            case .info:
                UIColor.Signal.secondaryFill
            case .warning:
                UIColor(
                    light: UIColor(rgbHex: 0xF4DDC7),
                    dark: UIColor(rgbHex: 0x392D22),
                )
            }
        }
    }

    private let style: Style
    public var text: String {
        didSet { render() }
    }

    public var actionTitle: String? {
        didSet { render() }
    }

    public var tapAction: () -> Void

    private let renderInCell: Bool

    @available(*, unavailable, message: "use other constructor instead.")
    public required init(coder: NSCoder) {
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
        tapAction: @escaping () -> Void = {},
        renderInCell: Bool = false,
    ) {
        self.style = style
        self.text = text
        self.tapAction = tapAction

        self.renderInCell = renderInCell

        super.init(frame: .zero)

        self.actionTitle = actionTitle

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(render),
            name: .themeDidChange,
            object: nil,
        )

        // The action view is meant to look like a button,
        // but you can actually tap anywhere on the reminder.
        self.addGestureRecognizer(UITapGestureRecognizer(
            target: self,
            action: #selector(handleTap(gestureRecognizer:)),
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

    private lazy var actionBackground = {
        let view = UIView()

        if #available(iOS 26, *) {
            view.cornerConfiguration = .capsule()
            view.layoutMargins = .init(hMargin: 16, vMargin: 6)
        } else {
            view.layoutMargins = .zero
        }

        view.addSubview(actionLabel)
        actionLabel.autoPinEdgesToSuperviewMargins()
        return view
    }()

    private lazy var actionLabel: UILabel = {
        let result = UILabel()
        result.font = if #available(iOS 26, *) {
            .dynamicTypeSubheadline.medium()
        } else {
            .dynamicTypeSubheadline.semibold()
        }
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        return result
    }()

    private lazy var textContainer: UIStackView = {
        let result = UIStackView()
        result.axis = .vertical
        result.spacing = if #available(iOS 26, *) { 12 } else { 8 }
        result.alignment = .trailing
        return result
    }()

    private func initialRender() {
        if renderInCell {
            self.layoutMargins = .zero
            backgroundView.layer.cornerRadius = 0
        } else {
            self.layoutMargins = .init(hMargin: 18, vMargin: 12)
            let radius: CGFloat = if #available(iOS 26, *) { 26 } else { 12 }
            backgroundView.layer.cornerRadius = radius
        }

        self.addSubview(backgroundView)
        backgroundView.autoPinEdgesToSuperviewMargins()
        backgroundView.layoutMargins = if #available(iOS 26, *) {
            .init(hMargin: 20, vMargin: 16)
        } else {
            .init(hMargin: 16, vMargin: 14)
        }

        backgroundView.addSubview(textContainer)
        textContainer.addArrangedSubview(textLabel)
        textContainer.autoPinEdgesToSuperviewMargins()
        textLabel.autoPinWidthToSuperviewMargins()

        render()
    }

    @objc
    private func render() {
        textLabel.text = text
        textLabel.textColor = self.style.textColor

        textContainer.removeArrangedSubview(actionBackground)
        if let actionTitle {
            actionLabel.text = actionTitle
            actionLabel.textColor = self.style.textColor
            textContainer.addArrangedSubview(actionBackground)
            if #available(iOS 26, *) {
                textContainer.layoutMargins.bottom = 20
                actionBackground.backgroundColor = self.style.buttonBackgroundColor
            } else {
                textContainer.layoutMargins.bottom = 10
                actionBackground.backgroundColor = .clear
            }
        } else {
            textContainer.layoutMargins.bottom = 14
        }

        backgroundView.backgroundColor = self.style.backgroundColor
    }

    @objc
    private func handleTap(gestureRecognizer: UIGestureRecognizer) {
        guard gestureRecognizer.state == .recognized else {
            return
        }
        tapAction()
    }
}
