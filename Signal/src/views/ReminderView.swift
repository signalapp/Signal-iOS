//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

class ReminderView: UIView {

    let label = UILabel()

    typealias Action = () -> Void

    var tapAction: Action?

    var text: String? {
        get {
            return label.text
        }

        set(newText) {
            label.text = newText
        }
    }

    enum ReminderViewMode {
        // Nags are urgent interactive prompts, bidding for the user's attention.
        case nag
        // Explanations are not interactive or urgent.
        case explanation
    }
    let mode: ReminderViewMode

    @available(*, unavailable, message:"use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @available(*, unavailable, message:"use other constructor instead.")
    override init(frame: CGRect) {
        notImplemented()
    }

    private init(mode: ReminderViewMode,
         text: String, tapAction: Action?) {
        self.mode = mode
        self.tapAction = tapAction

        super.init(frame: .zero)

        self.text = text

        setupSubviews()
    }

    @objc public class func nag(text: String, tapAction: Action?) -> ReminderView {
        return ReminderView(mode: .nag, text: text, tapAction: tapAction)
    }

    @objc public class func explanation(text: String) -> ReminderView {
        return ReminderView(mode: .explanation, text: text, tapAction: nil)
    }

    func setupSubviews() {
        let textColor: UIColor
        let iconColor: UIColor
        switch (mode) {
        case .nag:
            self.backgroundColor = UIColor.ows_reminderYellow
            textColor = UIColor.ows_gray90
            iconColor = UIColor.ows_gray60
        case .explanation:
            // TODO: Theme, review with design.
            self.backgroundColor = Theme.offBackgroundColor
            textColor = Theme.primaryColor
            iconColor = Theme.secondaryColor
        }
        self.clipsToBounds = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(gestureRecognizer:)))
        self.addGestureRecognizer(tapGesture)

        let container = UIStackView()
        container.axis = .horizontal
        container.alignment = .center
        container.isLayoutMarginsRelativeArrangement = true

        self.addSubview(container)
        container.layoutMargins = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        container.ows_autoPinToSuperviewEdges()

        // Label
        label.font = UIFont.ows_dynamicTypeSubheadline
        container.addArrangedSubview(label)
        label.textColor = textColor
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping

        // Show the disclosure indicator if this reminder has a tap action.
        if tapAction != nil {
            // Icon
            let iconName = (CurrentAppContext().isRTL ? "system_disclosure_indicator_rtl" : "system_disclosure_indicator")
            guard let iconImage = UIImage(named: iconName) else {
                owsFailDebug("missing icon.")
                return
            }
            let iconView = UIImageView(image: iconImage.withRenderingMode(.alwaysTemplate))
            iconView.contentMode = .scaleAspectFit
            iconView.tintColor = iconColor
            iconView.autoSetDimension(.width, toSize: 13)
            container.addArrangedSubview(iconView)
        }
    }

    @objc func handleTap(gestureRecognizer: UIGestureRecognizer) {
        guard gestureRecognizer.state == .recognized else {
            return
        }
        tapAction?()
    }
}
