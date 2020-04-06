//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class VoiceMemoLockView: UIView {

    private var offsetConstraint: NSLayoutConstraint!

    private let offsetFromToolbar: CGFloat = 40
    private let backgroundViewInitialHeight: CGFloat = 80
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

        backgroundView.layoutMargins = UIEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)

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
        let imageTemplate = #imageLiteral(resourceName: "ic_lock_outline").withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: imageTemplate)
        imageView.tintColor = .ows_accentRed
        imageView.autoSetDimensions(to: CGSize(square: 24))
        return imageView
    }()

    private lazy var chevronView: UIView = {
        let label = UILabel()
        label.text = "\u{2303}"
        label.textColor = .ows_accentRed
        label.textAlignment = .center
        return label
    }()

    private lazy var backgroundView: UIView = {
        let view = UIView()

        let width: CGFloat = 36
        view.autoSetDimension(.width, toSize: width)
        view.backgroundColor = Theme.scrollButtonBackgroundColor
        view.layer.cornerRadius = width / 2
        view.layer.borderColor = Theme.washColor.cgColor
        view.layer.borderWidth = CGHairlineWidth()

        return view
    }()

}
