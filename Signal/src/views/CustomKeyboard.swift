//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

class CustomKeyboard: UIInputView {

    let contentView = UIView()

    init() {
        super.init(frame: .zero, inputViewStyle: .default)

        addSubview(contentView)
        contentView.autoPinEdgesToSuperviewEdges()

        translatesAutoresizingMaskIntoConstraints = false
        allowsSelfSizing = false
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func willPresent() {}
    func wasPresented() {}
    func willDismiss() {}
    func wasDismissed() {}

    override func willMove(toSuperview newSuperview: UIView?) {
        if newSuperview != nil {
            self.willPresent()
        } else {
            self.willDismiss()
        }
    }

    override func didMoveToSuperview() {
        // Call wasPresented/wasDismissed on the next run loop,
        // once this view hierarchy change has finished.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.superview == nil {
                self.wasDismissed()
            } else {
                self.wasPresented()
            }
        }
    }

    // MARK: - Height Management

    class func setSystemKeyboardHeight(
        _ height: CGFloat,
        for window: UIWindow,
    ) {
        // Only respect this height if it's reasonable, we don't want
        // to have a tiny keyboard.
        guard height > 170 else {
            Logger.warn("Ignoring suspicious keyboard height: \(height)")
            return
        }

        guard let key = SizeClassKey(window: window) else { return }
        Logger.debug(
            "Keyboard height: \(height). Interface: \(window.traitCollection.userInterfaceIdiom) " +
                "Horizontal: \(window.traitCollection.horizontalSizeClass) Vertical: \(window.traitCollection.verticalSizeClass) " +
                "Screen size: \(key.screenSize)",
        )
        if cachedKeyboardHeights[key] == nil {
            cachedKeyboardHeights[key] = height
        }
    }

    func updateHeightForPresentation() {
        updateHeightConstraint()
    }

    class func hasCachedHeight(for window: UIWindow) -> Bool {
        guard let key = SizeClassKey(window: window) else { return false }
        return cachedKeyboardHeights[key] != nil
    }

    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 0)

    private struct SizeClassKey: Hashable {
        let horizontal: UIUserInterfaceSizeClass
        let vertical: UIUserInterfaceSizeClass
        let userInterfaceIdiom: UIUserInterfaceIdiom
        let screenSize: CGSize // orientation dependent
        private let nativeScreenSize: CGSize // fixed

        init?(window: UIWindow) {
            guard let screen = window.windowScene?.screen else {
                owsFailBeta("Window is not connected to a window screne.")
                return nil
            }

            self.horizontal = window.traitCollection.horizontalSizeClass
            self.vertical = window.traitCollection.verticalSizeClass
            self.userInterfaceIdiom = window.traitCollection.userInterfaceIdiom
            self.screenSize = screen.bounds.size
            self.nativeScreenSize = screen.nativeBounds.size
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(horizontal.rawValue)
            hasher.combine(vertical.rawValue)
            if #available(iOS 18, *) {
                hasher.combine(screenSize)
                hasher.combine(nativeScreenSize)
            } else {
                hasher.combine(screenSize.width)
                hasher.combine(screenSize.height)
                hasher.combine(nativeScreenSize.width)
                hasher.combine(nativeScreenSize.height)
            }
        }

        private func knownHeightForVerticalRegularInterface() -> CGFloat? {
            switch nativeScreenSize.height {
            case
                1136, // iPhone 5 or 5S or 5C
                1334, // iPhone 6/6S/7/8
                1792, // iPhone XR
                1920, 2208 // iPhone 6+/6S+/7+/8+//
                : 260

            case
                2340, // iPhone 12 Mini
                2436, // iPhone X, iPhone XS
                2532, // iPhone 12 Pro
                2556, // iPhone 14 Pro, iPhone 16
                2622 // iPhone 16 Pro
                : 335

            case
                2688, // iPhone X Max
                2736, // iPhone Air
                2778, // iPhone 12 Pro Max
                2796, // iPhone 14 Pro Max, iPhone 16 Plus
                2868 // iPhone 16-17-18 Pro Max
                : 345

            case
                2034 // iPhone Duo outer screen
                : 304

            case
                2853 // iPhone Duo inner screen
                : screenSize.isPortrait ? 350 : 264

            default
                : nil
                }
        }

        func estimatedKeyboardHeight() -> CGFloat? {
            // iOS 26.4.1 dimensions.
            switch userInterfaceIdiom {
            case .phone:
                switch vertical {
                case .compact:
                    // iPhone SE: 206
                    // iPhone 12/13 Mini: 214
                    // iPhone 17: 208
                    // iPhone 17e: 208
                    // iPhone 17 Pro: 208
                    // iPhone 17 Pro Max: 208
                    // iPhone Air: 208
                    //
                    // Few points difference are not worth implementing any per-device logic,
                    // especially given that there's no easy way to distinguish those devices.
                    return 208

                case .regular:
                    // iPhone SE: 260
                    // iPhone 12/13 Mini: 344
                    // iPhone 17: 335
                    // iPhone 17e: 335
                    // iPhone 17 Pro: 335
                    // iPhone 17 Pro Max: 345
                    // iPhone Air: 345
                    // iPhone Duo Outer: 304
                    // iPhone Duo Inner Landscape: 264
                    // iPhone Duo Inner portrait: 350
                    if let height = knownHeightForVerticalRegularInterface() {
                        return height
                    }
                    owsFailDebug("Unknown screen size. Size:[\(screenSize)] Native:[\(nativeScreenSize)]")
                    return nil

                default:
                    owsFailDebug("Invalid size classes: H:\(horizontal), V:\(vertical)")
                    return nil
                }

            case .pad:
                return screenSize.isPortrait ? 337 : 422

            default:
                owsFailDebug("Invalid userInterfaceIdiom: \(userInterfaceIdiom)")
                return nil
            }
        }
    }

    private static var cachedKeyboardHeights = [SizeClassKey: CGFloat]()

    private func updateHeightConstraint() {
        guard
            let window = CurrentAppContext().mainWindow,
            let key = SizeClassKey(window: window),
            let keyboardHeight = CustomKeyboard.cachedKeyboardHeights[key] ?? key.estimatedKeyboardHeight()
        else {
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
        heightConstraint.constant = keyboardHeight
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        // We only care about changes in size classes, which would be triggered by interface rotation.
        guard
            previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass ||
            previousTraitCollection?.verticalSizeClass != traitCollection.verticalSizeClass
        else {
            return
        }

        updateHeightConstraint()
    }
}
