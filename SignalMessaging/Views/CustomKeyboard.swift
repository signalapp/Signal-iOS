//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSCustomKeyboard)
open class CustomKeyboard: UIInputView {
    @objc public let contentView = UIView()

    @objc
    public init() {
        super.init(frame: .zero, inputViewStyle: .default)

        addSubview(contentView)
        contentView.autoPinEdgesToSuperviewEdges()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: UIDevice.current
        )

        translatesAutoresizingMaskIntoConstraints = false
        allowsSelfSizing = true
        resizeToSystemKeyboard()
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open func wasPresented() {}
    open func wasDismissed() {}

    @objc public func registerWithView(_ view: UIView) {
        view.addSubview(responder)
    }

    private lazy var responder = CustomKeyboardResponder(customKeyboard: self)
    override open var isFirstResponder: Bool { return responder.isFirstResponder }

    open override func becomeFirstResponder() -> Bool {
        return responder.becomeFirstResponder()
    }

    open override func resignFirstResponder() -> Bool {
        return responder.resignFirstResponder()
    }

    open override func didMoveToSuperview() {
        if superview == nil {
            wasDismissed()
        } else {
            wasPresented()
        }
    }

    // MARK: - Height Management

    private lazy var heightConstraint = autoSetDimension(.height, toSize: 0)

    private struct SystemKeyboardHeight {
        var landscape: CGFloat?
        var portrait: CGFloat?
        var current: CGFloat? {
            get {
                return CurrentAppContext().interfaceOrientation.isLandscape ? landscape : portrait
            }
            set {
                if CurrentAppContext().interfaceOrientation.isLandscape {
                    landscape = newValue
                } else {
                    portrait = newValue
                }
            }
        }
    }
    private var cachedSystemKeyboardHeight = SystemKeyboardHeight()

    @objc
    public func updateSystemKeyboardHeight(_ height: CGFloat) {
        cachedSystemKeyboardHeight.current = height
        resizeToSystemKeyboard()
    }

    @objc
    open func resizeToSystemKeyboard() {
        guard let cachedHeight = cachedSystemKeyboardHeight.current else {
            // We don't have a cached height for this orientation,
            // let the auto sizing do its best guess at what the
            // system keyboard height might be.
            heightConstraint.isActive = false
            allowsSelfSizing = false
            return
        }

        // We have a cached height so we want to size ourself. The system
        // sizing isn't a 100% match to the system keyboard's size and
        // does not account for things like the quicktype toolbar.
        allowsSelfSizing = true
        heightConstraint.isActive = true
        heightConstraint.constant = cachedHeight
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        resizeToSystemKeyboard()
    }

    @objc
    open func orientationDidChange() {
        resizeToSystemKeyboard()
    }
}

private class CustomKeyboardResponder: UIView {
    @objc public weak var customKeyboard: CustomKeyboard?

    init(customKeyboard: CustomKeyboard) {
        self.customKeyboard = customKeyboard
        super.init(frame: .zero)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var inputView: UIView? {
        return customKeyboard
    }

    public override var canBecomeFirstResponder: Bool {
        return true
    }
}
