//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

class ReminderView: UIView {

    let TAG = "[ReminderView]"
    let label = UILabel()

    let defaultTapAction = {
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

    required init?(coder: NSCoder) {
        self.tapAction = defaultTapAction

        super.init(coder: coder)

        setupSubviews()
    }

    override init(frame: CGRect) {
        self.tapAction = defaultTapAction

        super.init(frame: frame)

        setupSubviews()
    }

    convenience init(text: String, tapAction: @escaping () -> Void) {
        self.init(frame: .zero)
        self.text = text
        self.tapAction = tapAction
    }

    func setupSubviews() {
        self.backgroundColor = UIColor.ows_reminderYellow()
        self.clipsToBounds = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(gestureRecognizer:)))
        self.addGestureRecognizer(tapGesture)

        let container = UIView()

        self.addSubview(container)
        container.autoPinWidthToSuperview(withMargin: 16)
        container.autoPinHeightToSuperview(withMargin: 16)

        // Label
        label.font = UIFont.ows_regularFont(withSize: 14)
        container.addSubview(label)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.autoPinEdge(toSuperviewEdge: .top)
        label.autoPinEdge(toSuperviewEdge: .left)
        label.autoPinEdge(toSuperviewEdge: .bottom)
        label.textColor = UIColor.black.withAlphaComponent(0.9)

        // Icon
        let iconImage = #imageLiteral(resourceName: "system_disclosure_indicator").withRenderingMode(.alwaysTemplate)
        let iconView = UIImageView(image: iconImage)
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = UIColor.black.withAlphaComponent(0.6)
        container.addSubview(iconView)

        iconView.autoPinEdge(toSuperviewEdge: .right)
        iconView.autoPinEdge(.left, to: .right, of: label, withOffset: 28)
        iconView.autoVCenterInSuperview()
        iconView.autoSetDimension(.width, toSize: 13)
    }

    func handleTap(gestureRecognizer: UIGestureRecognizer) {
        tapAction()
    }
}
