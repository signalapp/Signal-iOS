//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

public protocol CVBackgroundContainerDelegate: AnyObject {
    func updateScrollingContent()
}

// MARK: -

public class CVBackgroundContainer: ManualLayoutViewWithLayer {

    private enum ZPositioning: CGFloat {
        case wallpaperContent = 0
        case wallpaperDimming = 1
        case selectionHighlight = 2
    }

    fileprivate var wallpaperView: WallpaperView?

    public weak var delegate: CVBackgroundContainerDelegate?

    public init() {
        super.init(name: "CVBackgroundContainer")

        self.shouldDeactivateConstraints = false
        self.isUserInteractionEnabled = false
        // Render all background views behind the collection view.
        self.layer.zPosition = -1
    }

    @available(*, unavailable, message: "use other constructor instead.")
    public required init(name: String) {
        fatalError("init(name:) has not been implemented")
    }

    public func set(wallpaperView: WallpaperView?) {
        self.wallpaperView?.contentView?.removeFromSuperview()
        self.wallpaperView?.dimmingView?.removeFromSuperview()
        self.wallpaperView = wallpaperView

        if let wallpaperView = wallpaperView {
            self.backgroundColor = .clear

            if let contentView = wallpaperView.contentView {
                addSubview(contentView)
                contentView.layer.zPosition = ZPositioning.wallpaperContent.rawValue
            }
            if let dimmingView = wallpaperView.dimmingView {
                addSubview(dimmingView)
                dimmingView.layer.zPosition = ZPositioning.wallpaperDimming.rawValue
            }

            setNeedsLayout()
        } else {
            self.backgroundColor = Theme.backgroundColor
        }
    }

    public override func layoutSubviews() {
        AssertIsOnMainThread()

        super.layoutSubviews()

        wallpaperView?.contentView?.frame = bounds
        wallpaperView?.dimmingView?.frame = bounds

        delegate?.updateScrollingContent()
    }
}

// MARK: -

extension CVBackgroundContainer: WallpaperBlurProvider {
    public var wallpaperBlurState: WallpaperBlurState? {
        wallpaperView?.blurProvider?.wallpaperBlurState
    }
}

// MARK: -

extension ConversationViewController: CVBackgroundContainerDelegate {

    public func updateScrollingContent() {
        AssertIsOnMainThread()

        UIView.performWithoutAnimation {
            for cell in collectionView.visibleCells {
                guard let cell = cell as? CVCell else {
                    owsFailDebug("Invalid cell.")
                    continue
                }
                cell.updateScrollingContent()
            }
        }
    }
}
