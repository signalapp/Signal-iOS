//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc class OWSFlatButton: UIView {
    let TAG = "[OWSFlatButton]"

    private var button: UIButton?

    private var pressedBlock : (() -> Void)?

    private var upColor: UIColor?
    private var downColor: UIColor?

    init() {
        AssertIsOnMainThread()

        super.init(frame:CGRect.zero)

        createContent()
    }

    @available(*, unavailable, message:"use default constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        owsFail("\(self.TAG) invalid constructor")
    }

    private func createContent() {
        let button = UIButton(type:.custom)
        self.button = button
        self.addSubview(button)
        button.addTarget(self, action:#selector(buttonPressed), for:.touchUpInside)
        button.autoPinWidthToSuperview()
        button.autoPinHeightToSuperview()
    }

    public class func button(title: String,
                             font: UIFont,
                             titleColor: UIColor,
                             backgroundColor: UIColor,
                             width: CGFloat,
                             height: CGFloat,
                             target:Any,
                             selector: Selector) -> OWSFlatButton {
        let button = OWSFlatButton()
        button.setTitle(title:title,
                        font: font,
                        titleColor: titleColor )
        button.setBackgroundColors(backgroundColor)
        button.useDefaultCornerRadius()
        button.setSize(width:width, height:height)
        button.addTarget(target:target, selector:selector)
        return button
    }

    public class func button(title: String,
                             titleColor: UIColor,
                             backgroundColor: UIColor,
                             width: CGFloat,
                             height: CGFloat,
                             target:Any,
                             selector: Selector) -> OWSFlatButton {
        return OWSFlatButton.button(title:title,
                                    font:fontForHeight(height),
                                    titleColor:titleColor,
                                    backgroundColor:backgroundColor,
                                    width:width,
                                    height:height,
                                    target:target,
                                    selector:selector)
    }

    public class func button(title: String,
                             font: UIFont,
                             titleColor: UIColor,
                             backgroundColor: UIColor,
                             target:Any,
                             selector: Selector) -> OWSFlatButton {
        let button = OWSFlatButton()
        button.setTitle(title:title,
                        font: font,
                        titleColor: titleColor )
        button.setBackgroundColors(backgroundColor)
        button.useDefaultCornerRadius()
        button.addTarget(target:target, selector:selector)
        return button
    }

    public class func fontForHeight(_ height: CGFloat) -> UIFont {
        let fontPointSize = round(height * 0.45)
        return UIFont.ows_mediumFont(withSize:fontPointSize)!
    }

    // MARK: Methods

    public func setTitle(title: String, font: UIFont,
                         titleColor: UIColor ) {
        guard let button = self.button else {
            owsFail("Missing button")
            return
        }
        button.setTitle(title, for: .normal)
        button.setTitleColor(titleColor, for: .normal)
        button.titleLabel!.font = font
    }

    public func setBackgroundColors(upColor: UIColor,
                                    downColor: UIColor ) {
        guard let button = self.button else {
            owsFail("Missing button")
            return
        }
        button.setBackgroundImage(UIImage(color:upColor), for: .normal)
        button.setBackgroundImage(UIImage(color:downColor), for: .highlighted)
    }

    public func setBackgroundColors(_ backgroundColor: UIColor ) {
        setBackgroundColors(upColor: backgroundColor,
                            downColor: backgroundColor.withAlphaComponent(0.7) )
    }

    public func setSize(width: CGFloat, height: CGFloat) {
        guard let button = self.button else {
            owsFail("Missing button")
            return
        }
        button.autoSetDimension(.width, toSize:width)
        button.autoSetDimension(.height, toSize:height)
    }

    public func useDefaultCornerRadius() {
        guard let button = self.button else {
            owsFail("Missing button")
            return
        }
        button.layer.cornerRadius = ScaleFromIPhone5To7Plus(4, 5)
        button.clipsToBounds = true
    }

    public func setEnabled(_ isEnabled: Bool) {
        guard let button = self.button else {
            owsFail("Missing button")
            return
        }
        button.isEnabled = isEnabled
    }

    public func addTarget(target:Any,
                          selector: Selector) {
        guard let button = self.button else {
            owsFail("Missing button")
            return
        }
        button.addTarget(target, action:selector, for:.touchUpInside)
    }

    public func setPressedBlock(_ pressedBlock: @escaping () -> Void) {
        guard self.pressedBlock == nil else {
            owsFail("Button already has pressed block.")
            return
        }
        self.pressedBlock = pressedBlock
    }

    internal func buttonPressed() {
        guard let pressedBlock = pressedBlock else {
            return
        }
        pressedBlock()
    }
}
