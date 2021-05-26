//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// ManualLayoutView uses a CATransformLayer by default.
// CATransformLayer does not render.
//
// If you need to use properties like backgroundColor, border,
// masksToBounds, shadow, etc. you should use this subclass instead.
//
// See: https://developer.apple.com/documentation/quartzcore/catransformlayer
@objc
open class ManualLayoutViewWithLayer: ManualLayoutView {
    override open class var layerClass: AnyClass {
        CALayer.self
    }
}

// MARK: -

@objc
open class ManualLayoutView: UIView {

    public typealias LayoutBlock = (UIView) -> Void

    private var layoutBlocks = [LayoutBlock]()

    public var name: String { accessibilityLabel ?? "Unknown" }

    override open class var layerClass: AnyClass {
        CATransformLayer.self
    }

    @objc
    public required init(name: String) {
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false

        #if TESTABLE_BUILD
        self.accessibilityLabel = name
        #endif
    }

    @available(*, unavailable, message: "use other constructor instead.")
    @objc
    public required init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    deinit {
        AssertIsOnMainThread()
    }

    @objc
    public var shouldDeactivateConstraints = true

    public override func updateConstraints() {
        super.updateConstraints()

        if shouldDeactivateConstraints {
            deactivateAllConstraints()
        }
    }

    // MARK: - Circles and Pills

    @objc
    public static func circleView(name: String) -> ManualLayoutView {
        let result = ManualLayoutViewWithLayer(name: name)
        result.addPillBlock()
        return result
    }

    @objc
    public static func pillView(name: String) -> ManualLayoutView {
        let result = ManualLayoutViewWithLayer(name: name)
        result.addPillBlock()
        return result
    }

    // MARK: - Sizing

    public var preferredSize: CGSize?

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        preferredSize ?? .zero
    }

    public override var intrinsicContentSize: CGSize {
        return sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude,
                                   height: CGFloat.greatestFiniteMagnitude))
    }

    // MARK: - Layout

    public override var bounds: CGRect {
        didSet {
            if oldValue.size != bounds.size {
                viewSizeDidChange()
            }
        }
    }

    public override var frame: CGRect {
        didSet {
            if oldValue.size != frame.size {
                viewSizeDidChange()
            }
        }
    }

    func viewSizeDidChange() {
        AssertIsOnMainThread()

        layoutSubviews()
    }

    @objc
    open override func layoutSubviews() {
        layoutSubviews(skipLayoutBlocks: false)
    }

    @objc
    public func layoutSubviews(skipLayoutBlocks: Bool = false) {
        AssertIsOnMainThread()

        super.layoutSubviews()

        if !skipLayoutBlocks {
            applyLayoutBlocks()
        }
    }

    @objc
    public func applyLayoutBlocks() {
        AssertIsOnMainThread()

        for layoutBlock in layoutBlocks {
            layoutBlock(self)
        }
    }

    public static func setSubviewFrame(subview: UIView, frame: CGRect) {
        guard subview.frame != frame else {
            return
        }
        subview.frame = frame
    }

    // MARK: - Reset

    open func reset() {
        AssertIsOnMainThread()

        removeAllSubviews()
        layoutBlocks.removeAll()

        invalidateIntrinsicContentSize()
        setNeedsLayout()

        self.tapBlock = nil
        if let gestureRecognizers = self.gestureRecognizers {
            for gestureRecognizer in gestureRecognizers {
                removeGestureRecognizer(gestureRecognizer)
            }
        }
    }

    // MARK: - Convenience Methods

    public func addPillBlock() {
        addLayoutBlock { view in
            view.layer.cornerRadius = view.bounds.size.smallerAxis * 0.5
        }
    }

    public func addSubview(_ subview: UIView,
                           withLayoutBlock layoutBlock: @escaping LayoutBlock) {
        owsAssertDebug(subview.superview == nil)

        subview.translatesAutoresizingMaskIntoConstraints = false

        addSubview(subview)

        addLayoutBlock(layoutBlock)
    }

    public func addLayoutBlock(_ layoutBlock: @escaping LayoutBlock) {
        layoutBlocks.append(layoutBlock)
    }

    public func centerSubviewWithLayoutBlock(_ subview: UIView,
                                             onSiblingView siblingView: UIView,
                                             size: CGSize) {
        owsAssertDebug(subview.superview != nil)
        owsAssertDebug(subview.superview == siblingView.superview)

        subview.translatesAutoresizingMaskIntoConstraints = false

        addLayoutBlock { _ in
            guard let superview = subview.superview else {
                owsFailDebug("Missing superview.")
                return
            }
            owsAssertDebug(superview == siblingView.superview)

            let siblingCenter = superview.convert(siblingView.center,
                                                  from: siblingView.superview)
            let subviewOrigin = siblingCenter - (size.asPoint * 0.5)
            let subviewFrame = CGRect(origin: subviewOrigin, size: size)
            Self.setSubviewFrame(subview: subview, frame: subviewFrame)
        }
    }

    public func addSubviewToCenterOnSuperview(_ subview: UIView, size: CGSize) {
        owsAssertDebug(subview.superview == nil)

        addSubview(subview)

        centerSubviewOnSuperview(subview, size: size)
    }

    public func centerSubviewOnSuperview(_ subview: UIView, size: CGSize) {
        owsAssertDebug(subview.superview != nil)

        subview.translatesAutoresizingMaskIntoConstraints = false

        addLayoutBlock { _ in
            guard let superview = subview.superview else {
                owsFailDebug("Missing superview.")
                return
            }

            let superviewBounds = superview.bounds
            let subviewOrigin = ((superviewBounds.size - size) * 0.5).asPoint
            let subviewFrame = CGRect(origin: subviewOrigin, size: size)
            Self.setSubviewFrame(subview: subview, frame: subviewFrame)
        }
    }

    public func addSubviewToCenterOnSuperviewWithDesiredSize(_ subview: UIView) {
        owsAssertDebug(subview.superview == nil)

        addSubview(subview)

        centerSubviewOnSuperviewWithDesiredSize(subview)
    }

    public func centerSubviewOnSuperviewWithDesiredSize(_ subview: UIView) {
        owsAssertDebug(subview.superview != nil)

        subview.translatesAutoresizingMaskIntoConstraints = false

        addLayoutBlock { _ in
            guard let superview = subview.superview else {
                owsFailDebug("Missing superview.")
                return
            }

            let size = subview.sizeThatFitsMaxSize
            let superviewBounds = superview.bounds
            let subviewOrigin = ((superviewBounds.size - size) * 0.5).asPoint
            let subviewFrame = CGRect(origin: subviewOrigin, size: size)
            Self.setSubviewFrame(subview: subview, frame: subviewFrame)
        }
    }

    public func addSubviewToFillSuperviewEdges(_ subview: UIView) {
        owsAssertDebug(subview.superview == nil)

        addSubview(subview)

        layoutSubviewToFillSuperviewEdges(subview)
    }

    public func layoutSubviewToFillSuperviewEdges(_ subview: UIView) {
        layoutSubviewToFillSuperview(subview, honorLayoutsMargins: false)
    }

    public func addSubviewToFillSuperviewMargins(_ subview: UIView) {
        owsAssertDebug(subview.superview == nil)

        addSubview(subview)

        layoutSubviewToFillSuperviewMargins(subview)
    }

    public func layoutSubviewToFillSuperviewMargins(_ subview: UIView) {
        layoutSubviewToFillSuperview(subview, honorLayoutsMargins: true)
    }

    public func layoutSubviewToFillSuperview(_ subview: UIView,
                                             honorLayoutsMargins: Bool) {
        owsAssertDebug(subview.superview != nil)

        subview.translatesAutoresizingMaskIntoConstraints = false

        addLayoutBlock { _ in
            guard let superview = subview.superview else {
                owsFailDebug("Missing superview.")
                return
            }

            var subviewFrame = superview.bounds
            if honorLayoutsMargins {
                subviewFrame = subviewFrame.inset(by: superview.layoutMargins)
            }
            Self.setSubviewFrame(subview: subview, frame: subviewFrame)
        }
    }

    // MARK: - Gestures

    public typealias TapBlock = () -> Void
    private var tapBlock: TapBlock?

    public func addTapGesture(_ tapBlock: @escaping TapBlock) {
        self.tapBlock = tapBlock
        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap)))
    }

    @objc
    private func didTap() {
        guard let tapBlock = tapBlock else {
            owsFailDebug("Missing tapBlock.")
            return
        }
        tapBlock()
    }
}

// MARK: -

@objc
public extension ManualLayoutView {

    static func wrapSubviewUsingIOSAutoLayout(_ subview: UIView,
                                              isWrapperRendering: Bool = false,
                                              wrapperName: String = "iOS auto layout wrapper") -> UIView {
        let wrapper: ManualLayoutView
        if isWrapperRendering {
            wrapper = ManualLayoutViewWithLayer(name: wrapperName)
        } else {
            wrapper = ManualLayoutView(name: wrapperName)
        }
        wrapper.addSubviewToFillSuperviewEdges(subview)

        // blurView will be arranged by manual layout, but if we don't
        // constrain its width and height, its internal constraints will
        // be ambiguous.
        let widthConstraint = subview.autoSetDimension(.width, toSize: 0)
        let heightConstraint = subview.autoSetDimension(.height, toSize: 0)
        wrapper.addLayoutBlock { _ in
            widthConstraint.constant = subview.width
            heightConstraint.constant = subview.height
        }

        return wrapper
    }
}
