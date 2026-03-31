//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

/// A torus, whose ring is filled up to `percentComplete` with blue. Useful as a
/// square-aspect-ratio progress indicator.
class ArcView: UIView {
    var percentComplete: Float = 0 {
        didSet {
            setNeedsDisplay()
        }
    }

    init() {
        super.init(frame: .zero)
        self.isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Unimplemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let lineWidth: CGFloat = 3
        let radius = min(rect.width, rect.height) / 2 - lineWidth / 2

        context.setStrokeColor(UIColor.Signal.tertiaryLabel.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)

        context.addArc(
            center: center,
            radius: radius,
            startAngle: 0,
            endAngle: 2 * .pi,
            clockwise: false,
        )

        context.strokePath()

        let startAngle: CGFloat = -.pi / 2
        let endAngle = 2 * .pi * CGFloat(percentComplete)
        let color: UIColor = if #available(iOS 26, *) { .Signal.label } else { .Signal.ultramarine }
        context.setStrokeColor(color.cgColor)

        context.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle + startAngle,
            clockwise: false,
        )

        context.strokePath()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsDisplay()
    }
}
