//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
open class ManualLayoutView: UIView {

    public typealias LayoutBlock = (UIView) -> Void

    private var layoutBlocks = [LayoutBlock]()

    public var name: String { accessibilityLabel ?? "Unknown" }

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

    // MARK: - Circles and Pills

    @objc
    public static func circleView(name: String) -> ManualLayoutView {
        let result = ManualLayoutView(name: name)
        result.addLayoutBlock { view in
            view.layer.cornerRadius = min(view.width, view.height) * 0.5
        }
        return result
    }

    @objc
    public static func pillView(name: String) -> ManualLayoutView {
        let result = ManualLayoutView(name: name)
        result.addLayoutBlock { view in
            view.layer.cornerRadius = min(view.width, view.height) * 0.5
        }
        return result
    }

    // MARK: - Sizing

    public var preferredSize: CGSize?

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
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
        layoutSubviews()
    }

    @objc
    public override func layoutSubviews() {
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

    static func setSubviewFrame(subview: UIView, frame: CGRect) {
        guard subview.frame != frame else {
            return
        }
        subview.frame = frame
        // TODO: Remove?
        subview.setNeedsLayout()
    }

    // MARK: - Reset

    open func reset() {
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
            let subviewFrame = CGRect(origin: CGPoint(x: siblingCenter.x - subview.width * 0.5,
                                                      y: siblingCenter.y - subview.height * 0.5),
                                      size: size)
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
            let subviewFrame = CGRect(origin: CGPoint(x: (superviewBounds.width - subview.width) * 0.5,
                                                      y: (superviewBounds.height - subview.height) * 0.5),
                                      size: size)
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
            let subviewFrame = CGRect(origin: CGPoint(x: (superviewBounds.width - size.width) * 0.5,
                                                      y: (superviewBounds.height - size.height) * 0.5),
                                      size: size)
            Self.setSubviewFrame(subview: subview, frame: subviewFrame)
        }
    }

    public func addSubviewToFillSuperviewEdges(_ subview: UIView) {
        owsAssertDebug(subview.superview == nil)

        addSubview(subview)

        layoutSubviewToFillSuperviewBounds(subview)
    }

    public func layoutSubviewToFillSuperviewBounds(_ subview: UIView) {
        owsAssertDebug(subview.superview != nil)

        subview.translatesAutoresizingMaskIntoConstraints = false

        addLayoutBlock { _ in
            guard let superview = subview.superview else {
                owsFailDebug("Missing superview.")
                return
            }

            Self.setSubviewFrame(subview: subview, frame: superview.bounds)
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

    // MARK: - Gestures

    // TODO: Ideally ManualLayoutView will be transparent by default.
    // But we should be able to disable transparency so that a separate
    // background view isn't necessary.
    @discardableResult
    public func addBackgroundView(backgroundColor: UIColor, cornerRadius: CGFloat = 0) -> UIView {
        let backgroundView = UIView()
        backgroundView.backgroundColor = backgroundColor
        backgroundView.layer.cornerRadius = cornerRadius
        addSubviewToFillSuperviewEdges(backgroundView)
        sendSubviewToBack(backgroundView)
        return backgroundView
    }
}
