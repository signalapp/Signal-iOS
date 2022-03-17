//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

class StoryPlaybackProgressView: UIView {
    var playedColor: UIColor = .ows_white {
        didSet {
            playedShapeLayer.fillColor = playedColor.cgColor
        }
    }

    var unplayedColor: UIColor = .ows_whiteAlpha40 {
        didSet {
            unplayedShapeLayer.fillColor = unplayedColor.cgColor
        }
    }

    public override var bounds: CGRect {
        didSet {
            guard bounds != oldValue else { return }
            setNeedsDisplay()
        }
    }

    public override var frame: CGRect {
        didSet {
            guard frame != oldValue else { return }
            setNeedsDisplay()
        }
    }

    public override var center: CGPoint {
        didSet {
            guard center != oldValue else { return }
            setNeedsDisplay()
        }
    }

    struct ItemState: Equatable {
        let index: Int
        let value: CGFloat
    }
    var itemState: ItemState = .init(index: 0, value: 0) {
        didSet {
            guard itemState != oldValue else { return }
            setNeedsDisplay()
        }
    }
    var numberOfItems: Int = 0 {
        didSet {
            guard numberOfItems != oldValue else { return }
            setNeedsDisplay()
        }
    }

    init() {
        super.init(frame: .zero)

        playedShapeLayer.fillColor = playedColor.cgColor
        layer.addSublayer(playedShapeLayer)

        unplayedShapeLayer.fillColor = unplayedColor.cgColor
        layer.addSublayer(unplayedShapeLayer)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let playedShapeLayer = CAShapeLayer()
    private let unplayedShapeLayer = CAShapeLayer()

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        guard numberOfItems > 0 else {
            playedShapeLayer.path = nil
            unplayedShapeLayer.path = nil
            return
        }

        guard width > 0 else { return }

        let idealSpacing: CGFloat = 2
        let numberOfSpacers = numberOfItems - 1
        let maxItemWidth: CGFloat = (width - (idealSpacing * CGFloat(numberOfSpacers))) / CGFloat(numberOfItems)
        let minItemWidth: CGFloat = 2
        let itemWidth: CGFloat = max(maxItemWidth, minItemWidth)
        let itemSpacing: CGFloat = numberOfSpacers > 0 ? (width - (itemWidth * CGFloat(numberOfItems))) / CGFloat(numberOfSpacers) : 0
        let itemHeight: CGFloat = 2

        let playedBezierPath = UIBezierPath()
        let unplayedBezierPath = UIBezierPath()

        playedShapeLayer.frame = bounds
        unplayedShapeLayer.frame = bounds

        defer {
            playedShapeLayer.path = playedBezierPath.cgPath
            unplayedShapeLayer.path = unplayedBezierPath.cgPath
        }

        for x in 0..<numberOfItems {
            if itemState.index == x, itemState.value < 1, itemState.value > 0 {
                let playedItemFrame = CGRect(
                    x: CGFloat(x) * (itemWidth + itemSpacing),
                    y: 0,
                    width: itemWidth * itemState.value,
                    height: itemHeight
                )
                playedBezierPath.append(UIBezierPath(roundedRect: playedItemFrame, byRoundingCorners: [.topLeft, .bottomLeft], cornerRadii: CGSize(square: itemHeight / 2)))
                let unplayedItemFrame = CGRect(
                    x: playedItemFrame.x + playedItemFrame.width,
                    y: 0,
                    width: itemWidth * (1 - itemState.value),
                    height: itemHeight
                )
                unplayedBezierPath.append(UIBezierPath(roundedRect: unplayedItemFrame, byRoundingCorners: [.topRight, .bottomRight], cornerRadii: CGSize(square: itemHeight / 2)))
            } else {
                let path: UIBezierPath
                if itemState.index < x || (itemState.index == x && itemState.value <= 0) {
                    path = unplayedBezierPath
                } else {
                    owsAssertDebug(itemState.index > x || (itemState.index == x && itemState.value >= 1))
                    path = playedBezierPath
                }
                let itemFrame = CGRect(
                    x: CGFloat(x) * (itemWidth + itemSpacing),
                    y: 0,
                    width: itemWidth,
                    height: itemHeight
                )
                path.append(UIBezierPath(roundedRect: itemFrame, cornerRadius: itemHeight / 2))
            }
        }
    }
}
