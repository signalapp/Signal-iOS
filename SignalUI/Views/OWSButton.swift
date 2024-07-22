//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalServiceKit

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

    public init(
        title: String,
        tintColor: UIColor? = nil,
        dimsWhenHighlighted: Bool = false,
        block: @escaping () -> Void = { }
    ) {
        self.dimsWhenHighlighted = dimsWhenHighlighted
        super.init(frame: .zero)

        self.block = block
        addTarget(self, action: #selector(didTap), for: .touchUpInside)
        setTitle(title, for: .normal)

        if let tintColor {
            self.tintColor = tintColor
        }
    }

    public init(
        imageName: String,
        tintColor: UIColor?,
        dimsWhenHighlighted: Bool = false,
        block: @escaping () -> Void = {}
    ) {
        self.dimsWhenHighlighted = dimsWhenHighlighted
        super.init(frame: .zero)

        self.block = block
        addTarget(self, action: #selector(didTap), for: .touchUpInside)

        setImage(imageName: imageName)
        self.tintColor = tintColor
    }

    /// Creates a button with a title and image.
    /// - Parameters:
    ///   - title: The title for the button label.
    ///   - imageName: The image for the button.
    ///   - tintColor: The tint color for the image.
    ///   Note that this does not tint the text.
    ///   - spacing: The spacing between the image and title.
    ///   - block: The action to perform on tap.
    public init(
        title: String,
        imageName: String,
        tintColor: UIColor?,
        spacing: CGFloat,
        block: @escaping () -> Void = {}
    ) {
        super.init(frame: .zero)

        setTitle(title, for: .normal)

        setImage(imageName: imageName)
        self.tintColor = tintColor

        addImageTitleSpacing(spacing)

        self.block = block
        addTarget(self, action: #selector(didTap), for: .touchUpInside)
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

    /// Adds spacing between the image and title.
    ///
    /// Does so by modifying `contentEdgeInsets` and `titleEdgeInsets`,
    /// so call this after setting those.
    public func addImageTitleSpacing(_ spacing: CGFloat) {
        ows_contentEdgeInsets.trailing += spacing
        ows_titleEdgeInsets.leading += spacing
        ows_titleEdgeInsets.trailing -= spacing
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
