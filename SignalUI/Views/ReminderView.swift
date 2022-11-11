//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

open class ReminderView: UIView {

    private let label = UILabel()

    private let actionLabel = UILabel()

    private var disclosureImageView: UIImageView?

    public typealias Action = () -> Void

    public var tapAction: Action?

    public var text: String? {
        get {
            return label.text
        }

        set(newText) {
            label.text = newText
        }
    }

    public var actionTitle: String? {
        get {
            return actionLabel.text
        }

        set(newText) {
            actionLabel.text = newText
        }
    }

    public enum ReminderViewMode {
        // Nags are urgent interactive prompts, bidding for the user's attention.
        case nag
        // Explanations are not interactive or urgent.
        case explanation
    }
    public let mode: ReminderViewMode

    @available(*, unavailable, message: "use other constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable, message: "use other constructor instead.")
    override init(frame: CGRect) {
        fatalError("init(frame:) has not been implemented")
    }

    public init(mode: ReminderViewMode, text: String, tapAction: Action?, actionTitle: String? = nil) {
        self.mode = mode
        self.tapAction = tapAction

        super.init(frame: .zero)

        self.text = text
        self.actionTitle = actionTitle

        setupSubviews()
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .ThemeDidChange, object: nil)
    }

    @objc
    public class func nag(text: String, tapAction: Action?) -> ReminderView {
        return ReminderView(mode: .nag, text: text, tapAction: tapAction)
    }

    @objc
    public class func nag(text: String, tapAction: Action?, actionTitle: String) -> ReminderView {
        return ReminderView(mode: .nag, text: text, tapAction: tapAction, actionTitle: actionTitle)
    }

    @objc
    public class func explanation(text: String) -> ReminderView {
        return ReminderView(mode: .explanation, text: text, tapAction: nil)
    }

    private func setupSubviews() {
        self.clipsToBounds = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(gestureRecognizer:)))
        self.addGestureRecognizer(tapGesture)

        let container = UIStackView()
        container.isLayoutMarginsRelativeArrangement = true

        switch actionTitle {
        case .some:
            container.axis = .vertical
            container.alignment = .fill
        default:
            container.axis = .horizontal
            container.alignment = .center
        }

        self.addSubview(container)
        container.layoutMargins = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        container.autoPinEdgesToSuperviewEdges()

        // Label
        label.font = UIFont.ows_dynamicTypeSubheadline
        container.addArrangedSubview(label)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping

        switch (actionTitle, tapAction) {
        case (nil, .some):
            // Show the disclosure indicator if this nag has a tap action and no action title
            let iconName = (CurrentAppContext().isRTL ? "system_disclosure_indicator_rtl" : "system_disclosure_indicator")
            guard let iconImage = UIImage(named: iconName) else {
                owsFailDebug("missing icon.")
                return
            }
            let iconView = UIImageView(image: iconImage.withRenderingMode(.alwaysTemplate))
            iconView.contentMode = .scaleAspectFit
            iconView.autoSetDimension(.width, toSize: 13)
            container.addArrangedSubview(iconView)
            disclosureImageView = iconView
        case (.some, .some):
            // Show the disclosure indicator if this nag has a tap action and an action title
            actionLabel.font = UIFont.ows_dynamicTypeSubheadline.ows_semibold
            container.addArrangedSubview(actionLabel)
            actionLabel.numberOfLines = 1
            actionLabel.textAlignment = .right
        default:
            {}()
        }
    }

    @objc
    private func applyTheme() {
        let textColor: UIColor
        let iconColor: UIColor
        switch mode {
        case .nag:
            self.backgroundColor = UIColor.ows_reminderYellow
            textColor = UIColor.ows_gray90
            iconColor = UIColor.ows_gray60
        case .explanation:
            // TODO: Theme, review with design.
            self.backgroundColor = Theme.washColor
            textColor = Theme.primaryTextColor
            iconColor = Theme.secondaryTextAndIconColor
        }
        label.textColor = textColor
        actionLabel.textColor = textColor
        disclosureImageView?.tintColor = iconColor
    }

    @objc
    func handleTap(gestureRecognizer: UIGestureRecognizer) {
        guard gestureRecognizer.state == .recognized else {
            return
        }
        tapAction?()
    }
}
