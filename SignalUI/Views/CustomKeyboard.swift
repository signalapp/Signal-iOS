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

        translatesAutoresizingMaskIntoConstraints = false
        allowsSelfSizing = false
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open func willPresent() {}
    open func wasPresented() {}
    open func willDismiss() {}
    open func wasDismissed() {}

    override open func willMove(toSuperview newSuperview: UIView?) {
        if newSuperview != nil {
            self.willPresent()
        } else {
            self.willDismiss()
        }
    }

    override open func didMoveToSuperview() {
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

    public class func setSystemKeyboardHeight(
        _ height: CGFloat,
        forTraitCollection traitCollection: UITraitCollection,
    ) {
        // Only respect this height if it's reasonable, we don't want
        // to have a tiny keyboard.
        guard height > 170 else {
            Logger.warn("Ignoring suspicious keyboard height: \(height)")
            return
        }

        let key = SizeClassKey(
            horizontal: traitCollection.horizontalSizeClass,
            vertical: traitCollection.verticalSizeClass,
        )
        Logger.debug(
            "Keyboard height: \(height). Horizontal: \(traitCollection.horizontalSizeClass) " +
                "Vertical: \(traitCollection.verticalSizeClass) Size: \(key.screenSize)",
        )
        if cachedKeyboardHeights[key] == nil {
            cachedKeyboardHeights[key] = height
        }
    }

    public func updateHeightForPresentation() {
        updateHeightConstraint()
    }

    public class func hasCachedHeight(forTraitCollection traitCollection: UITraitCollection) -> Bool {
        let key = SizeClassKey(
            horizontal: traitCollection.horizontalSizeClass,
            vertical: traitCollection.verticalSizeClass,
        )
        return cachedKeyboardHeights[key] != nil
    }

    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 0)

    private struct SizeClassKey: Hashable {
        let horizontal: UIUserInterfaceSizeClass
        let vertical: UIUserInterfaceSizeClass
        let screenSize: CGSize

        init(horizontal: UIUserInterfaceSizeClass, vertical: UIUserInterfaceSizeClass) {
            self.horizontal = horizontal
            self.vertical = vertical
            self.screenSize = UIScreen.main.bounds.size
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(horizontal.rawValue)
            hasher.combine(vertical.rawValue)
            if #available(iOS 18, *) {
                hasher.combine(screenSize)
            } else {
                hasher.combine(screenSize.width)
                hasher.combine(screenSize.height)
            }
        }

    }

    private static var cachedKeyboardHeights = [SizeClassKey: CGFloat]()

    private func updateHeightConstraint() {
        let key = SizeClassKey(
            horizontal: traitCollection.horizontalSizeClass,
            vertical: traitCollection.verticalSizeClass,
        )
        guard let cachedHeight = CustomKeyboard.cachedKeyboardHeights[key] else {
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

    override open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
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
