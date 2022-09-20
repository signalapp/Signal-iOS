//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import YYImage

public class CVUtils {

    @available(*, unavailable, message: "use other init() instead.")
    private init() {}

    private static let workQueue_userInitiated: DispatchQueue = {
        DispatchQueue(label: OWSDispatch.createLabel("conversationView.workQueue_userInitiated"),
                      qos: .userInitiated,
                      autoreleaseFrequency: .workItem)
    }()

    private static let workQueue_userInteractive: DispatchQueue = {
        DispatchQueue(label: OWSDispatch.createLabel("conversationView.workQueue_userInteractive"),
                      qos: .userInteractive,
                      autoreleaseFrequency: .workItem)
    }()

    public static func workQueue(isInitialLoad: Bool) -> DispatchQueue {
        isInitialLoad ? workQueue_userInteractive : workQueue_userInitiated
    }

    public static let landingQueue: DispatchQueue = {
        DispatchQueue(label: OWSDispatch.createLabel("conversationView.landingQueue"),
                      qos: .userInitiated,
                      autoreleaseFrequency: .workItem)
    }()
}

// MARK: -

public protocol CVView: UIView {
    func reset()
}

// MARK: -

@objc
open class CVLabel: UILabel, CVView {
    public override func updateConstraints() {
        super.updateConstraints()

        deactivateAllConstraints()
    }

    public func reset() {
        self.text = nil
    }
}

// MARK: -

@objc
open class CVImageView: UIImageView, CVView {
    public override func updateConstraints() {
        super.updateConstraints()

        deactivateAllConstraints()
    }

    public func reset() {
        self.image = nil
    }

    // MARK: - Layout

    public typealias LayoutBlock = (UIView) -> Void

    private var layoutBlocks = [LayoutBlock]()

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

    @objc
    public static func circleView() -> CVImageView {
        let result = CVImageView()
        result.addLayoutBlock { view in
            view.layer.cornerRadius = min(view.width, view.height) * 0.5
        }
        return result
    }
}

// MARK: -

@objc
open class CVAnimatedImageView: YYAnimatedImageView, CVView {
    public override func updateConstraints() {
        super.updateConstraints()

        deactivateAllConstraints()
    }

    public func reset() {
        self.image = nil
    }
}
