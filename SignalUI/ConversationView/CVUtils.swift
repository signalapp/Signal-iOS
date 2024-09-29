//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit
public import YYImage

public class CVUtils {

    @available(*, unavailable, message: "use other init() instead.")
    private init() {}

    private static let workQueue_userInitiated: DispatchQueue = {
        DispatchQueue(label: "org.signal.conversation-view.user-initiated",
                      qos: .userInitiated,
                      autoreleaseFrequency: .workItem)
    }()

    private static let workQueue_userInteractive: DispatchQueue = {
        DispatchQueue(label: "org.signal.conversation-view.user-interactive",
                      qos: .userInteractive,
                      autoreleaseFrequency: .workItem)
    }()

    public static func workQueue(isInitialLoad: Bool) -> DispatchQueue {
        isInitialLoad ? workQueue_userInteractive : workQueue_userInitiated
    }
}

// MARK: -

public protocol CVView: UIView {
    func reset()
}

// MARK: -

open class CVLabel: UILabel, CVView {
    public override func updateConstraints() {
        super.updateConstraints()

        deactivateAllConstraints()
    }

    public func reset() {
        // NOTE: we have to reset the attributed text and then the text;
        // this is the magic incantation that prevents properties from
        // a previously-set attributed string from applying to subsequent
        // attributed strings.
        self.attributedText = nil
        self.text = nil
    }
}

open class CVButton: OWSButton, CVView {
    open override func updateConstraints() {
        super.updateConstraints()
        deactivateAllConstraints()
    }

    public func reset() {
        self.block = {}
        self.dimsWhenDisabled = false
        self.dimsWhenHighlighted = false
        self.ows_contentEdgeInsets = .zero
        self.ows_titleEdgeInsets = .zero
        [
            UIControl.State.normal,
            .highlighted,
            .disabled,
            .selected,
            .focused,
            .application,
            .reserved,
        ].forEach { controlState in
            self.setAttributedTitle(nil, for: controlState)
            self.setTitle(nil, for: controlState)
            self.setImage(nil, for: controlState)
        }
    }
}

// MARK: -

open class CVImageView: UIImageView, CVView {

    // MARK: - Properties

    public typealias LayoutBlock = (UIView) -> Void

    private var layoutBlocks = [LayoutBlock]()

    private var spinningAnimation: UIViewPropertyAnimator?

    // MARK: -

    public override func updateConstraints() {
        super.updateConstraints()

        deactivateAllConstraints()
    }

    public func reset() {
        self.image = nil
        stopSpinning()
    }

    // MARK: - Layout

    public func addLayoutBlock(_ layoutBlock: @escaping LayoutBlock) {
        layoutBlocks.append(layoutBlock)
    }

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

    open override func layoutSubviews() {
        layoutSubviews(skipLayoutBlocks: false)
    }

    public func layoutSubviews(skipLayoutBlocks: Bool = false) {
        AssertIsOnMainThread()

        super.layoutSubviews()

        if !skipLayoutBlocks {
            applyLayoutBlocks()
        }
    }

    public func applyLayoutBlocks() {
        AssertIsOnMainThread()

        for layoutBlock in layoutBlocks {
            layoutBlock(self)
        }
    }

    // MARK: - Circles

    public static func circleView() -> CVImageView {
        let result = CVImageView()
        result.addLayoutBlock { view in
            view.layer.cornerRadius = min(view.width, view.height) * 0.5
        }
        return result
    }

    // MARK: - Animation

    public func startSpinning() {
        if spinningAnimation != nil {
            stopSpinning()
        }
        spinningAnimation = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
            self?.transform = .init(rotationAngle: .pi)
        }
        // UIViewPropertyAnimator aggressively drops animations it thinks aren't needed;
        // if we animate to 2pi it won't spin because 2pi == 0, we have to do half
        // and half in two parts to get it to animate at all.
        spinningAnimation?.addAnimations  { [weak self] in
            self?.transform = .init(rotationAngle: .pi * 2)
        }
        spinningAnimation?.addCompletion { [weak self] _ in
            self?.transform = .identity
            self?.startSpinning()
        }
        spinningAnimation?.startAnimation()
    }

    public func stopSpinning() {
        guard let animation = spinningAnimation else {
            return
        }
        self.spinningAnimation = nil
        animation.stopAnimation(true)
        self.transform = .identity
    }
}

// MARK: -

open class CVAnimatedImageView: YYAnimatedImageView, CVView {
    public override func updateConstraints() {
        super.updateConstraints()

        deactivateAllConstraints()
    }

    public func reset() {
        self.image = nil
    }
}
