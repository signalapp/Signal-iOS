//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
public import UIKit

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

        var configuration: UIButton.Configuration?
#if compiler(>=6.2)
        if #available(iOS 26, *) {
            configuration = .glass()
            configuration?.imageColorTransformer = UIConfigurationColorTransformer { _ in
                return .Signal.label
            }
        }
#endif
        if configuration == nil {
            configuration = .gray()
            configuration?.imageColorTransformer = UIConfigurationColorTransformer { _ in
                return UIColor { traitCollection in
                    return traitCollection.userInterfaceStyle == .dark ? .ows_gray15 : .ows_gray75
                }
            }
            configuration?.background.backgroundColorTransformer = UIConfigurationColorTransformer { _ in
                return UIColor { traitCollection in
                    return traitCollection.userInterfaceStyle == .dark ? .ows_gray65 : .ows_gray02
                }
            }
            if #available(iOS 18, *) {
                configuration?.background.shadowProperties.offset = CGSize(width: 0, height: 4)
                configuration?.background.shadowProperties.color = .black
                configuration?.background.shadowProperties.radius = 12
                configuration?.background.shadowProperties.opacity = 0.3
            }
        }
        configuration?.cornerStyle = .capsule
        configuration?.image = UIImage(named: iconName)
        self.configuration = configuration

        addUnreadLabel()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var intrinsicContentSize: CGSize {
        .square(ConversationScrollButton.circleDiameter)
    }

    private class var circleDiameter: CGFloat { 40 }

    private lazy var unreadCountLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeFootnoteClamped.semibold()
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var unreadBadge: UIView = {
        let view = PillView()
        view.isUserInteractionEnabled = false
        view.clipsToBounds = true
        view.backgroundColor = .Signal.accent
        view.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(unreadCountLabel)
        NSLayoutConstraint.activate([
            unreadCountLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            unreadCountLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            unreadCountLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            unreadCountLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            view.widthAnchor.constraint(greaterThanOrEqualTo: view.heightAnchor, multiplier: 1),
        ])

        return view
    }()

    private func addUnreadLabel() {
        let pillViewOverlap: CGFloat = 8 // how much unread badge pill overlaps circle
        addSubview(unreadBadge)
        NSLayoutConstraint.activate([
            unreadBadge.centerXAnchor.constraint(equalTo: centerXAnchor),
            unreadBadge.bottomAnchor.constraint(equalTo: topAnchor, constant: pillViewOverlap),
        ])
    }
}
