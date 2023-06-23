//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import UIKit

// MARK: - SpacerView

public class SpacerView: UIView {
    private var preferredSize: CGSize

    override open class var layerClass: AnyClass {
        CATransformLayer.self
    }

    convenience public init(preferredWidth: CGFloat = UIView.noIntrinsicMetric, preferredHeight: CGFloat = UIView.noIntrinsicMetric) {
        self.init(preferredSize: CGSize(width: preferredWidth, height: preferredHeight))
    }

    public init(preferredSize: CGSize = CGSize(square: UIView.noIntrinsicMetric)) {
        self.preferredSize = preferredSize
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var intrinsicContentSize: CGSize {
        get { preferredSize }
        set { preferredSize = newValue }
    }
}

// MARK: -

public extension UIView {

    class func spacer(withWidth width: CGFloat) -> UIView {
        let view = TransparentView()
        view.autoSetDimension(.width, toSize: width)
        return view
    }

    class func spacer(withHeight height: CGFloat) -> UIView {
        let view = TransparentView()
        view.autoSetDimension(.height, toSize: height)
        return view
    }

    class func spacer(matchingHeightOf matchView: UIView, withMultiplier multiplier: CGFloat) -> UIView {
        let spacer = TransparentView()
        spacer.autoMatch(.height, to: .height, of: matchView, withMultiplier: multiplier)
        return spacer
    }

    class func hStretchingSpacer() -> UIView {
        let view = TransparentView()
        view.setContentHuggingHorizontalLow()
        view.setCompressionResistanceHorizontalLow()
        return view
    }

    class func vStretchingSpacer(minHeight: CGFloat? = nil, maxHeight: CGFloat? = nil) -> UIView {
        let view = TransparentView()
        view.setContentHuggingVerticalLow()
        view.setCompressionResistanceVerticalLow()

        if let minHeight = minHeight {
            view.autoSetDimension(.height, toSize: minHeight, relation: .greaterThanOrEqual)
        }
        if let maxHeight = maxHeight {
            NSLayoutConstraint.autoSetPriority(.defaultLow) {
                view.autoSetDimension(.height, toSize: maxHeight)
            }
        }

        return view
    }

    class func transparentSpacer() -> UIView {
        let view = TransparentView()
        view.setContentHuggingHorizontalLow()
        view.setCompressionResistanceHorizontalLow()
        return view
    }

    class TransparentView: UIView {
        override open class var layerClass: AnyClass {
            CATransformLayer.self
        }
    }

    func setShadow(radius: CGFloat = 2.0, opacity: Float = 0.66, offset: CGSize = .zero, color: UIColor = UIColor.black) {
        layer.shadowRadius = radius
        layer.shadowOpacity = opacity
        layer.shadowOffset = offset
        layer.shadowColor = color.cgColor
    }

    class func accessibilityIdentifier(in container: NSObject, name: String) -> String {
        "\(type(of: container)).\(name)"
    }

    class func accessibilityIdentifier(containerName: String, name: String) -> String {
        "\(containerName).\(name)"
    }

    func setAccessibilityIdentifier(in container: NSObject, name: String) {
        self.accessibilityIdentifier = UIView.accessibilityIdentifier(in: container, name: name)
    }

    func removeAllSubviews() {
        for subview in subviews {
            subview.removeFromSuperview()
        }
    }

    var sizeThatFitsMaxSize: CGSize {
        sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude))
    }

    static func container() -> UIView {
        let view = UIView()
        view.layoutMargins = .zero
        return view
    }

    // If the container doesn't need a background color, it's
    // more efficient to use a non-rendering view.
    static func transparentContainer() -> UIView {
        let view = TransparentView()
        view.layoutMargins = .zero
        return view
    }

    func addBorder(with color: UIColor) {
        layer.borderColor = color.cgColor
        layer.borderWidth = 1
    }

    func addRedBorder() {
        addBorder(with: .red)
    }
}

// MARK: - Manual Layout

public extension UIView {

    var left: CGFloat { frame.minX }

    var right: CGFloat { frame.maxX }

    var top: CGFloat { frame.minY }

    var bottom: CGFloat { frame.maxY }

    var width: CGFloat { frame.width }

    var height: CGFloat { frame.height }
}

// MARK: - Debug

#if DEBUG

public extension UIView {

    func logFrame(withLabel label: String = "") {
        Logger.verbose("\(label) \(Self.self) \(accessibilityLabel ?? "") frame: \(frame), hidden: \(isHidden), opacity: \(layer.opacity), layoutMargins: \(layoutMargins)")
    }

    func logFrameLater(withLabel label: String = "") {
        DispatchQueue.main.async {
            self.logFrame(withLabel: label)
        }
    }

    func logHierarchyUpward(withLabel label: String) {
        let prefix = "\(label) ----"
        DispatchQueue.main.async {
            Logger.verbose(prefix)
        }
        traverseHierarchyUpward { view in
            view.logFrame(withLabel: prefix.appending("\t"))
        }
    }

    func logHierarchyUpwardLater(withLabel label: String) {
        let prefix = "\(label) ----"
        DispatchQueue.main.async {
            Logger.verbose(prefix)
        }
        traverseHierarchyUpward { view in
            view.logFrameLater(withLabel: prefix.appending("\t"))
        }
    }

    func logHierarchyDownward(withLabel label: String) {
        let prefix = "\(label) ----"
        DispatchQueue.main.async {
            Logger.verbose(prefix)
        }
        traverseHierarchyDownward { view in
            view.logFrame(withLabel: prefix.appending("\t"))
        }
    }

    func logHierarchyDownwardLater(withLabel label: String) {
        let prefix = "\(label) ----"
        DispatchQueue.main.async {
            Logger.verbose(prefix)
        }
        traverseHierarchyDownward { view in
            view.logFrameLater(withLabel: prefix.appending("\t"))
        }
    }
}

#endif

// MARK: - Misc

public extension UIView {

    typealias UIViewVisitorBlock = (UIView) -> Void

    func traverseHierarchyUpward(with visitor: UIViewVisitorBlock) {
        AssertIsOnMainThread()

        visitor(self)

        var responder: UIResponder? = self
        while responder != nil {
            if let view = responder as? UIView {
                visitor(view)
            }
            responder = responder?.next
        }
    }

    func traverseHierarchyDownward(with visitor: UIViewVisitorBlock) {
        AssertIsOnMainThread()

        visitor(self)

        for subview in subviews {
            subview.traverseHierarchyDownward(with: visitor)
        }
    }

    func firstAncestor<T>(ofType type: T.Type) -> T? {
        guard let superview else { return nil }
        return superview as? T ?? superview.firstAncestor(ofType: type)
    }

    func containsGestureLocation(_ gestureRecognizer: UIGestureRecognizer,
                                 hotAreaAdjustment: CGFloat? = nil) -> Bool {
        let location = gestureRecognizer.location(in: self)
        var hotArea = bounds
        if let hotAreaAdjustment = hotAreaAdjustment {
            owsAssertDebug(hotAreaAdjustment > 0)
            // Permissive hot area to make it easier to perform gesture.
            hotArea = hotArea.insetBy(dx: -hotAreaAdjustment, dy: -hotAreaAdjustment)
        }
        return hotArea.contains(location)
    }
}

// MARK: -

public extension UIApplication {
    func hideKeyboard() {
        sendAction(#selector(UIView.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
