//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

public class ConversationScrollButton: UIButton {

    let iconName: String

    var unreadCount: UInt = 0 {
        didSet {
            unreadCountLabel.text = String.localizedStringWithFormat("%u", unreadCount)
            unreadBadge.isHidden = unreadCount == 0
        }
    }

    init(iconName: String) {
        self.iconName = iconName
        super.init(frame: .zero)
        createContents()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange(notification:)),
            name: .ThemeDidChange,
            object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private class var circleSize: CGFloat { ScaleFromIPhone5To7Plus(35, 40) }

    class var buttonSize: CGFloat { circleSize + 2 * 15 }

    private lazy var iconView = UIImageView()

    private lazy var unreadCountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .white
        label.textAlignment = .center
        return label
    }()

    private lazy var unreadBadge: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.layer.cornerRadius = 8
        view.clipsToBounds = true
        return view
    }()

    private lazy var shadowView: UIView = {
        let circleSize = ConversationScrollButton.circleSize
        let view = CircleView(diameter: circleSize)
        view.isUserInteractionEnabled = false
        view.layer.shadowOffset = .zero
        view.layer.shadowRadius = 4
        view.layer.shadowOpacity = 0.05
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowPath = UIBezierPath(ovalIn: CGRect(origin: .zero, size: CGSize(square: circleSize))).cgPath
        return view
    }()

    private lazy var circleView: UIView = {
        let circleSize = ConversationScrollButton.circleSize
        let view = CircleView(diameter: circleSize)
        view.isUserInteractionEnabled = false
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.layer.shadowRadius = 12
        view.layer.shadowOpacity = 0.3
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowPath = UIBezierPath(ovalIn: CGRect(origin: .zero, size: CGSize(square: circleSize))).cgPath
        return view
    }()

    private func createContents() {
        circleView.addSubview(iconView)
        iconView.autoCenterInSuperview()
        addSubview(shadowView)
        addSubview(circleView)
        circleView.autoHCenterInSuperview()
        circleView.autoPinEdge(toSuperviewEdge: .bottom)
        shadowView.autoPinEdges(toEdgesOf: circleView)

        unreadBadge.addSubview(unreadCountLabel)
        unreadCountLabel.autoPinHeightToSuperview()
        unreadCountLabel.autoPinWidthToSuperview(withMargin: 3)
        addSubview(unreadBadge)
        unreadBadge.autoPinEdge(.bottom, to: .top, of: circleView, withOffset: 8)
        unreadBadge.autoHCenterInSuperview()
        unreadBadge.autoSetDimension(.height, toSize: 16)
        unreadBadge.autoSetDimension(.width, toSize: 16, relation: .greaterThanOrEqual)
        unreadBadge.autoMatch(.width, to: .width, of: self, withOffset: 0, relation: .lessThanOrEqual)
        unreadBadge.autoPinEdge(toSuperviewEdge: .top)

        updateColors()
    }

    private func updateColors() {
        unreadBadge.backgroundColor = .ows_accentBlue
        circleView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray02
        iconView.setTemplateImageName(iconName, tintColor: Theme.isDarkThemeEnabled ? .ows_gray15 : .ows_gray75)
    }

    @objc
    private func themeDidChange(notification: Notification) {
        updateColors()
    }
}
