//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalMessaging

open class OWSButton: UIButton {

    public var block: () -> Void = { }

    public var dimsWhenHighlighted = false {
        didSet { updateAlpha() }
    }

    public var dimsWhenDisabled = false {
        didSet { updateAlpha() }
    }

    public override var isHighlighted: Bool {
        didSet { updateAlpha() }
    }

    public override var isEnabled: Bool {
        didSet { updateAlpha() }
    }

    // MARK: -

    public init(block: @escaping () -> Void = { }) {
        super.init(frame: .zero)

        self.block = block
        addTarget(self, action: #selector(didTap), for: .touchUpInside)
    }

    public init(title: String, block: @escaping () -> Void = { }) {
        super.init(frame: .zero)

        self.block = block
        addTarget(self, action: #selector(didTap), for: .touchUpInside)
        setTitle(title, for: .normal)
    }

    public init(
        imageName: String,
        tintColor: UIColor?,
        block: @escaping () -> Void = {}
    ) {
        super.init(frame: .zero)

        self.block = block
        addTarget(self, action: #selector(didTap), for: .touchUpInside)

        setImage(imageName: imageName)
        self.tintColor = tintColor
    }

    public func setImage(imageName: String?) {
        guard let imageName = imageName else {
            setImage(nil, for: .normal)
            return
        }
        if let image = UIImage(named: imageName) {
            setImage(image.withRenderingMode(.alwaysTemplate), for: .normal)
        } else {
            owsFailDebug("Missing asset: \(imageName)")
        }
    }

    /// Configure the button for a potentially multiline label.
    ///
    /// UIButton's intrinsic content size won't respect a multiline label, and
    /// consequently the label might grow outside the bounds of the button.
    ///
    /// Note that this method uses autolayout.
    public func configureForMultilineTitle(lineBreakMode: NSLineBreakMode = .byCharWrapping) {
        titleLabel!.numberOfLines = 0
        titleLabel!.lineBreakMode = lineBreakMode

        // Without this, the label may grow taller than the button, which won't
        // grow its intrinsic content size to compensate for a multiline label.
        autoPinHeight(toHeightOf: titleLabel!, relation: .greaterThanOrEqual)
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Common Style Reuse

    public class func sendButton(imageName: String, block: @escaping () -> Void) -> OWSButton {
        let button = OWSButton(imageName: imageName, tintColor: .white, block: block)

        let buttonWidth: CGFloat = 40
        button.layer.cornerRadius = buttonWidth / 2
        button.autoSetDimensions(to: CGSize(square: buttonWidth))

        button.backgroundColor = .ows_accentBlue

        return button
    }

    /// Mimics a UIBarButtonItem of type .cancel, but with a shadow.
    public class func shadowedCancelButton(block: @escaping () -> Void) -> OWSButton {
        let cancelButton = OWSButton(title: CommonStrings.cancelButton, block: block)
        cancelButton.setTitleColor(.white, for: .normal)
        if let titleLabel = cancelButton.titleLabel {
            titleLabel.font = UIFont.systemFont(ofSize: 18.0)
            titleLabel.layer.shadowColor = UIColor.black.cgColor
            titleLabel.setShadow()
        } else {
            owsFailDebug("Missing titleLabel.")
        }
        cancelButton.sizeToFit()
        return cancelButton
    }

    public class func navigationBarButton(imageName: String, block: @escaping () -> Void) -> OWSButton {
        let button = OWSButton(imageName: imageName, tintColor: .white, block: block)
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowRadius = 2
        button.layer.shadowOpacity = 0.66
        button.layer.shadowOffset = .zero
        return button
    }

    // MARK: -

    @objc
    func didTap() {
        block()
    }

    private func updateAlpha() {
        let isDimmed = (
            (dimsWhenHighlighted && isHighlighted) ||
            (dimsWhenDisabled && !isEnabled)
        )
        alpha = isDimmed ? 0.4 : 1
    }
}

/// A button whose leading and trailing edges are round.
open class OWSRoundedButton: OWSButton {
    override open func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = height / 2
    }
}
