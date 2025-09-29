//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

open class CustomKeyboard: UIInputView {

    public let contentView = UIView()

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

    open func willPresent() {}
    open func wasPresented() {}
    open func wasDismissed() {}

    public func registerWithView(_ view: UIView) {
        view.addSubview(responder)
    }

    private lazy var responder = CustomKeyboardResponder(customKeyboard: self)
    override open var isFirstResponder: Bool { return responder.isFirstResponder }

    open override func becomeFirstResponder() -> Bool {
        let result = responder.becomeFirstResponder()
        if result { willPresent() }
        return result
    }

    open override func resignFirstResponder() -> Bool {
        return responder.resignFirstResponder()
    }

    open override func didMoveToSuperview() {
        // Call wasPresented/wasDismissed on the next run loop,
        // once this view hierarchy change has finished.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.superview == nil {
                self.wasDismissed()
            } else {
                self.wasPresented()
            }
        }
    }

    // MARK: - Height Management

    private lazy var heightConstraint = autoSetDimension(.height, toSize: 0)

    private struct SystemKeyboardHeight {
        var landscape: CGFloat?
        var portrait: CGFloat?
    }
    private var cachedSystemKeyboardHeight = SystemKeyboardHeight()

    private var currentSystemKeyboardHeight: CGFloat? {
        get {
            let interfaceOrientation = window?.windowScene?.interfaceOrientation ?? .unknown
            return interfaceOrientation.isLandscape ? cachedSystemKeyboardHeight.landscape : cachedSystemKeyboardHeight.portrait
        }
        set {
            let interfaceOrientation = window?.windowScene?.interfaceOrientation ?? .unknown
            let orientationKey = interfaceOrientation.isLandscape ? \SystemKeyboardHeight.landscape : \.portrait
            cachedSystemKeyboardHeight[keyPath: orientationKey] = newValue
        }
    }

    public func updateSystemKeyboardHeight(_ height: CGFloat) {
        // Only respect this height if it's reasonable, we don't want
        // to have a tiny keyboard.
        guard height > 170 else { return }
        currentSystemKeyboardHeight = height
        resizeToSystemKeyboard()
    }

    open func resizeToSystemKeyboard() {
        guard var keyboardHeight = currentSystemKeyboardHeight else {
            // We don't have a cached height for this orientation,
            // let the auto sizing do its best guess at what the
            // system keyboard height might be.
            heightConstraint.isActive = false
            allowsSelfSizing = false
            return
        }

        if let window {
            // App frame height changes based on orientation (i.e. its the smaller dimension when landscape).
            // Cap the height for custom keyboard because our layout breaks if we extend too tall.
            let maxHeight = window.frame.height * 0.75
            if keyboardHeight > maxHeight {
                keyboardHeight = maxHeight
            }
        }

        // We have a cached height so we want to size ourself. The system
        // sizing isn't a 100% match to the system keyboard's size and
        // does not account for things like the quicktype toolbar.
        allowsSelfSizing = true
        heightConstraint.isActive = true
        heightConstraint.constant = keyboardHeight
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

final private class CustomKeyboardResponder: UITextView {

    public weak var customKeyboard: CustomKeyboard?

    init(customKeyboard: CustomKeyboard) {
        self.customKeyboard = customKeyboard
        super.init(frame: .zero, textContainer: nil)

        self.disableAiWritingTools()

        autocorrectionType = .no
        keyboardAppearance = Theme.keyboardAppearance
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
    }

    override var inputView: UIView? {
        get { customKeyboard }
        set {}
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var canBecomeFirstResponder: Bool {
        return true
    }
}
