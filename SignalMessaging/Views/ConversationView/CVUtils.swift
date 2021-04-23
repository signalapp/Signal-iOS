//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import YYImage

public class CVUtils {

    @available(*, unavailable, message: "use other init() instead.")
    private init() {}

    public static let workQueue: DispatchQueue = {
        // Note that we use the highest qos.
        DispatchQueue(label: "org.whispersystems.signal.conversationView",
                             qos: .userInteractive,
                             autoreleaseFrequency: .workItem)
    }()
}

// MARK: -

@objc
open class CVLabel: UILabel {
    public override func updateConstraints() {
        super.updateConstraints()

        deactivateAllConstraints()
    }
}

// MARK: -

@objc
open class CVImageView: UIImageView {
    public override func updateConstraints() {
        super.updateConstraints()

        deactivateAllConstraints()
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
open class CVAnimatedImageView: YYAnimatedImageView {
    public override func updateConstraints() {
        super.updateConstraints()

        deactivateAllConstraints()
    }
}
