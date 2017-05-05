//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

class NotificationView: UIView {

    let TAG = "[NotificationView]"
    let label = UILabel()

    let defaultTapAction = {
        Logger.debug("[NotificationView] tapped.")
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

    convenience init(tapAction: @escaping () -> Void) {
        self.init(frame: .zero)
        self.tapAction = tapAction
    }

    func setupSubviews() {
        self.backgroundColor = UIColor.ows_infoMessageBorder().withAlphaComponent(0.20)
        self.clipsToBounds = true

        let container = UIView()

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(gestureRecognizer:)))
        container.addGestureRecognizer(tapGesture)

        self.addSubview(container)
        container.autoPinWidthToSuperview(withMargin: 16)
        container.autoPinHeightToSuperview(withMargin: 16)

        // Label
        label.font = UIFont.ows_regularFont(withSize: 14)
        container.addSubview(label)
        label.numberOfLines = 0
        label.autoPinEdge(toSuperviewEdge: .top)
        label.autoPinEdge(toSuperviewEdge: .left)
        label.autoPinEdge(toSuperviewEdge: .bottom)
        label.textColor = UIColor.black.withAlphaComponent(0.9)

        // Icon

        // TODO proper "push" image rather than this hack.
        let sourceIconImage = #imageLiteral(resourceName: "NavBarBack")
        let iconImage = UIImage(cgImage:sourceIconImage.cgImage!,
                                  scale: sourceIconImage.scale,
                                  orientation: .upMirrored).withRenderingMode(.alwaysTemplate)
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
