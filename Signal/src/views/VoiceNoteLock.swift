//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class VoiceMemoLockView: UIView {

    private var offsetConstraint: NSLayoutConstraint!

    private let offsetFromToolbar: CGFloat = 42
    private let backgroundViewInitialHeight: CGFloat = 72
    private var chevronTravel: CGFloat {
        return -1 * (backgroundViewInitialHeight - 50)
    }

    @objc
    public override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(backgroundView)
        backgroundView.addSubview(lockIconView)
        backgroundView.addSubview(chevronView)

        layoutMargins = UIEdgeInsets(top: 0, leading: 0, bottom: offsetFromToolbar, trailing: 0)

        backgroundView.autoPinEdges(toSuperviewMarginsExcludingEdge: .bottom)
        self.offsetConstraint = backgroundView.autoPinEdge(toSuperviewMargin: .bottom)
        // we anchor the top so that the bottom "slides up" to meet it as the user slides the lock
        backgroundView.autoPinEdge(.top, to: .bottom, of: self, withOffset: -offsetFromToolbar - backgroundViewInitialHeight)

        backgroundView.layoutMargins = UIEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)

        lockIconView.autoPinEdges(toSuperviewMarginsExcludingEdge: .bottom)
        chevronView.autoPinEdges(toSuperviewMarginsExcludingEdge: .top)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    @objc
    public func update(ratioComplete: CGFloat) {
        offsetConstraint.constant = CGFloatLerp(0, chevronTravel, ratioComplete)
    }

    // MARK: - Subviews

    private lazy var lockIconView: UIImageView = {
        let imageTemplate = #imageLiteral(resourceName: "lock-solid-24").withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: imageTemplate)
        imageView.tintColor = Theme.isDarkThemeEnabled ? .ows_gray15 : .ows_gray75
        imageView.autoSetDimensions(to: CGSize(square: 24))
        return imageView
    }()

    private lazy var chevronView: UIView = {
        let label = UILabel()
        label.text = "\u{2303}"
        label.textColor = Theme.ternaryTextColor
        label.textAlignment = .center
        return label
    }()

    private lazy var backgroundView: UIView = {
        let view = UIView()

        let width: CGFloat = 40
        view.autoSetDimension(.width, toSize: width)
        view.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray02
        view.layer.cornerRadius = width / 2
        view.layer.borderColor = Theme.washColor.cgColor
        view.layer.borderWidth = CGHairlineWidth()

        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.layer.shadowRadius = 12
        view.layer.shadowOpacity = 0.3
        view.layer.shadowColor = UIColor.black.cgColor

        return view
    }()

}
