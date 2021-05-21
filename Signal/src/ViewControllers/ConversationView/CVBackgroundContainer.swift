//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol CVBackgroundContainerDelegate: AnyObject {
    func updateSelectionHighlight()
    func updateScrollingContent()
}

// MARK: -

@objc
public class CVBackgroundContainer: ManualLayoutViewWithLayer {

    private enum ZPositioning: CGFloat {
        case wallpaperContent = 0
        case wallpaperDimming = 1
        case selectionHighlight = 2
    }

    fileprivate var wallpaperView: WallpaperView?

    public let selectionHighlightView = SelectionHighlightView()

    @objc
    public weak var delegate: CVBackgroundContainerDelegate?

    public init() {
        super.init(name: "CVBackgroundContainer")

        self.shouldDeactivateConstraints = false
        self.isUserInteractionEnabled = false
        // Render all background views behind the collection view.
        self.layer.zPosition = -1

        selectionHighlightView.isUserInteractionEnabled = false
        addSubview(selectionHighlightView)
        selectionHighlightView.layer.zPosition = ZPositioning.selectionHighlight.rawValue
        #if TESTABLE_BUILD
        selectionHighlightView.accessibilityIdentifier = "selectionHighlightView"
        #endif
    }

    @available(*, unavailable, message: "use other constructor instead.")
    @objc
    public required init(name: String) {
        notImplemented()
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

        let shouldUpdateSelectionHighlight = selectionHighlightView.frame != bounds

        wallpaperView?.contentView?.frame = bounds
        wallpaperView?.dimmingView?.frame = bounds
        selectionHighlightView.frame = bounds

        delegate?.updateScrollingContent()
        if shouldUpdateSelectionHighlight {
            delegate?.updateSelectionHighlight()
        }
    }
}

// MARK: -

@objc
extension CVBackgroundContainer: WallpaperBlurProvider {
    public var wallpaperBlurState: WallpaperBlurState? {
        wallpaperView?.blurProvider?.wallpaperBlurState
    }
}

// MARK: -

extension ConversationViewController: CVBackgroundContainerDelegate {
    var selectionHighlightView: SelectionHighlightView {
        backgroundContainer.selectionHighlightView
    }

    @objc
    public func updateScrollingContent() {
        AssertIsOnMainThread()

        for cell in collectionView.visibleCells {
            guard let cell = cell as? CVCell else {
                owsFailDebug("Invalid cell.")
                continue
            }
            cell.updateScrollingContent()
        }

        updateSelectionHighlight()
    }
}
