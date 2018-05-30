//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

class ReminderView: UIView {

    let TAG = "[ReminderView]"
    let label = UILabel()

    static let defaultTapAction = {
        Logger.debug("[ReminderView] tapped.")
    }

    var tapAction: () -> Void

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
        fatalError("\(#function) is unimplemented.")
    }

    @available(*, unavailable, message:"use other constructor instead.")
    override init(frame: CGRect) {
        fatalError("\(#function) is unimplemented.")
    }

    private init(mode: ReminderViewMode,
         text: String, tapAction: @escaping () -> Void) {
        self.mode = mode
        self.tapAction = tapAction

        super.init(frame: .zero)

        self.text = text

        setupSubviews()
    }

    @objc public class func nag(text: String, tapAction: @escaping () -> Void) -> ReminderView {
        return ReminderView(mode: .nag, text: text, tapAction: tapAction)
    }

    @objc public class func explanation(text: String) -> ReminderView {
        return ReminderView(mode: .explanation, text: text, tapAction: ReminderView.defaultTapAction)
    }

    func setupSubviews() {
        switch (mode) {
        case .nag:
            self.backgroundColor = UIColor.ows_reminderYellow
        case .explanation:
            self.backgroundColor = UIColor(rgbHex: 0xf5f5f5)
        }
        self.clipsToBounds = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(gestureRecognizer:)))
        self.addGestureRecognizer(tapGesture)

        let container = UIView()

        self.addSubview(container)
        container.autoPinWidthToSuperview(withMargin: 16)
        switch (mode) {
        case .nag:
            container.autoPinHeightToSuperview(withMargin: 16)
        case .explanation:
            container.autoPinHeightToSuperview(withMargin: 12)
        }

        // Margin: top and bottom 12 left and right 16.

        // Label
        switch (mode) {
        case .nag:
            label.font = UIFont.ows_regularFont(withSize: 14)
        case .explanation:
            label.font = UIFont.ows_dynamicTypeSubheadline
        }
        container.addSubview(label)
        label.textColor = UIColor.black.withAlphaComponent(0.9)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.autoPinLeadingToSuperviewMargin()
        label.autoPinEdge(toSuperviewEdge: .top)
        label.autoPinEdge(toSuperviewEdge: .bottom)

        guard mode == .nag else {
            label.autoPinTrailingToSuperviewMargin()
            return
        }

        // Icon
        let iconName = (self.isRTL() ? "system_disclosure_indicator_rtl" : "system_disclosure_indicator")
        guard let iconImage = UIImage(named: iconName) else {
            owsFail("\(logTag) missing icon.")
            return
        }
        let iconView = UIImageView(image: iconImage.withRenderingMode(.alwaysTemplate))
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = UIColor.black.withAlphaComponent(0.6)
        container.addSubview(iconView)

        iconView.autoPinLeading(toTrailingEdgeOf: label, offset: 28)
        iconView.autoPinTrailingToSuperviewMargin()
        iconView.autoVCenterInSuperview()
        iconView.autoSetDimension(.width, toSize: 13)
    }

    @objc func handleTap(gestureRecognizer: UIGestureRecognizer) {
        tapAction()
    }
}
