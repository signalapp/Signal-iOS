//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

@objc
public class OWSFlatButton: UIView {

    public let button: UIButton

    private var pressedBlock: (() -> Void)?

    private var upColor: UIColor?
    private var downColor: UIColor?

    @objc
    public var cornerRadius: CGFloat {
        get {
            button.layer.cornerRadius
        }
        set {
            button.layer.cornerRadius = newValue
            button.clipsToBounds = newValue > 0
        }
    }

    @objc
    public override var accessibilityIdentifier: String? {
        didSet {
            guard let accessibilityIdentifier = self.accessibilityIdentifier else {
                return
            }
            button.accessibilityIdentifier = "\(accessibilityIdentifier).button"
        }
    }

    override public var backgroundColor: UIColor? {
        willSet {
            owsFailDebug("Use setBackgroundColors(upColor:) instead.")
        }
    }

    public var titleEdgeInsets: UIEdgeInsets {
        get {
            return button.titleEdgeInsets
        }
        set {
            button.titleEdgeInsets = newValue
        }
    }

    public var contentEdgeInsets: UIEdgeInsets {
        get {
            return button.contentEdgeInsets
        }
        set {
            button.contentEdgeInsets = newValue
        }
    }

    public override var tintColor: UIColor! {
        get {
            return button.tintColor
        }
        set {
            button.tintColor = newValue
        }
    }

    @objc
    public init() {
        AssertIsOnMainThread()

        button = UIButton(type: .custom)

        super.init(frame: CGRect.zero)

        createContent()
    }

    @available(*, unavailable, message: "use other constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func createContent() {
        self.addSubview(button)
        button.addTarget(self, action: #selector(buttonPressed), for: .touchUpInside)
        button.autoPinEdgesToSuperviewEdges()
    }

    @objc
    public class func button(title: String,
                             font: UIFont,
                             titleColor: UIColor,
                             backgroundColor: UIColor,
                             width: CGFloat,
                             height: CGFloat,
                             target: Any,
                             selector: Selector) -> OWSFlatButton {
        let button = OWSFlatButton()
        button.setTitle(title: title,
                        font: font,
                        titleColor: titleColor )
        button.setBackgroundColors(upColor: backgroundColor)
        button.useDefaultCornerRadius()
        button.setSize(width: width, height: height)
        button.addTarget(target: target, selector: selector)
        return button
    }

    @objc
    public class func button(title: String,
                             titleColor: UIColor,
                             backgroundColor: UIColor,
                             width: CGFloat,
                             height: CGFloat,
                             target: Any,
                             selector: Selector) -> OWSFlatButton {
        return OWSFlatButton.button(title: title,
                                    font: fontForHeight(height),
                                    titleColor: titleColor,
                                    backgroundColor: backgroundColor,
                                    width: width,
                                    height: height,
                                    target: target,
                                    selector: selector)
    }

    @objc
    public class func button(title: String,
                             font: UIFont,
                             titleColor: UIColor,
                             backgroundColor: UIColor,
                             target: Any,
                             selector: Selector) -> OWSFlatButton {
        return OWSFlatButton.button(
            title: title,
            font: font,
            titleColor: titleColor,
            backgroundColor: backgroundColor,
            target: target,
            selector: selector,
            cornerRadius: .defaultCornerStyle
        )
    }

    @objc
    public class func insetButton(
        title: String,
        font: UIFont,
        titleColor: UIColor,
        backgroundColor: UIColor,
        target: Any,
        selector: Selector
    ) -> OWSFlatButton {
        return OWSFlatButton.button(
            title: title,
            font: font,
            titleColor: titleColor,
            backgroundColor: backgroundColor,
            target: target,
            selector: selector,
            cornerRadius: .insetCornerStyle
        )
    }

    public class func button(
        title: String,
        font: UIFont,
        titleColor: UIColor,
        backgroundColor: UIColor,
        target: Any,
        selector: Selector,
        cornerRadius: CGFloat
    ) -> OWSFlatButton {
        let button = OWSFlatButton()
        button.setTitle(title: title,
                        font: font,
                        titleColor: titleColor )
        button.setBackgroundColors(upColor: backgroundColor)
        button.addTarget(target: target, selector: selector)
        button.layer.cornerRadius = cornerRadius
        button.clipsToBounds = true
        return button
    }

    @objc
    public class func fontForHeight(_ height: CGFloat) -> UIFont {
        // Cap the "button height" at 40pt or button text can look
        // excessively large.
        let fontPointSize = round(min(40, height) * 0.45)
        return UIFont.ows_semiboldFont(withSize: fontPointSize)
    }

    public class func heightForFont(_ font: UIFont) -> CGFloat {
        font.lineHeight * 2.5
    }

    // MARK: Methods

    @objc
    public func setTitleColor(_ color: UIColor) {
        button.setTitleColor(color, for: .normal)
    }

    @objc
    public func setTitle(title: String? = nil, font: UIFont? = nil, titleColor: UIColor? = nil) {
        title.map { button.setTitle($0, for: .normal) }
        font.map { button.titleLabel?.font = $0 }
        titleColor.map { setTitleColor($0) }
    }

    @objc
    public func setAttributedTitle(_ title: NSAttributedString) {
        button.setAttributedTitle(title, for: .normal)
    }

    @objc
    public func setImage(_ image: UIImage) {
        button.setImage(image, for: .normal)
    }

    @objc
    public func setBackgroundColors(upColor: UIColor,
                                    downColor: UIColor ) {
        button.setBackgroundImage(UIImage(color: upColor), for: .normal)
        button.setBackgroundImage(UIImage(color: downColor), for: .highlighted)
    }

    @objc
    public func setBackgroundColors(upColor: UIColor) {
        let downColor = upColor == .clear ? upColor : upColor.withAlphaComponent(0.7)
        setBackgroundColors(upColor: upColor, downColor: downColor)
    }

    @objc
    public func setSize(width: CGFloat, height: CGFloat) {
        button.autoSetDimension(.width, toSize: width)
        button.autoSetDimension(.height, toSize: height)
    }

    @objc
    public func useDefaultCornerRadius() {
        // To my eye, this radius tends to look right regardless of button size
        // (within reason) or device size. 
        button.layer.cornerRadius = 5
        button.clipsToBounds = true
    }

    @objc
    public func useInsetCornerRadius() {
        button.layer.cornerRadius = 14
        button.clipsToBounds = true
    }

    @objc
    public func setEnabled(_ isEnabled: Bool) {
        button.isEnabled = isEnabled
    }

    @objc
    public func addTarget(target: Any,
                          selector: Selector) {
        button.addTarget(target, action: selector, for: .touchUpInside)
    }

    @objc
    public func setPressedBlock(_ pressedBlock: @escaping () -> Void) {
        guard self.pressedBlock == nil else { return }
        self.pressedBlock = pressedBlock
    }

    @objc
    internal func buttonPressed() {
        pressedBlock?()
    }

    @objc
    public func enableMultilineLabel() {
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.lineBreakMode = .byWordWrapping
        button.titleLabel?.textAlignment = .center
    }

    @objc
    public var font: UIFont? {
        return button.titleLabel?.font
    }

    public func autoSetHeightUsingFont(extraVerticalInsets: CGFloat = 0) {
        guard let font = font else {
            owsFailDebug("Missing button font.")
            return
        }
        autoSetDimension(.height, toSize: Self.heightForFont(font) + CGFloat(extraVerticalInsets * 2.0))
    }

    override public var intrinsicContentSize: CGSize {
        button.intrinsicContentSize
    }
}

fileprivate extension CGFloat {
    static var defaultCornerStyle = 5.0
    static var insetCornerStyle = 14.0
}
