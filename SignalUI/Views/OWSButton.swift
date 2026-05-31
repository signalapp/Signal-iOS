//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

open class OWSButton: UIButton {

    public var block: () -> Void = { }

    public var dimsWhenHighlighted = false {
        didSet { updateAlpha() }
    }

    override public var isHighlighted: Bool {
        didSet { updateAlpha() }
    }

    // MARK: -

    public init(block: @escaping () -> Void = { }) {
        super.init(frame: .zero)

        self.block = block
        addTarget(self, action: #selector(didTap), for: .touchUpInside)
    }

    public init(
        title: String,
        tintColor: UIColor? = nil,
        dimsWhenHighlighted: Bool = false,
        block: @escaping () -> Void = { },
    ) {
        self.dimsWhenHighlighted = dimsWhenHighlighted
        super.init(frame: .zero)

        self.block = block
        addTarget(self, action: #selector(didTap), for: .touchUpInside)
        setTitle(title, for: .normal)

        if let tintColor {
            self.tintColor = tintColor
        }
    }

    public init(
        imageName: String,
        tintColor: UIColor?,
        dimsWhenHighlighted: Bool = false,
        block: @escaping () -> Void = {},
    ) {
        self.dimsWhenHighlighted = dimsWhenHighlighted
        super.init(frame: .zero)

        self.block = block
        addTarget(self, action: #selector(didTap), for: .touchUpInside)

        setImage(imageName: imageName)
        self.tintColor = tintColor
    }

    public func setImage(imageName: String?) {
        guard let imageName else {
            setImage(nil, for: .normal)
            return
        }
        if let image = UIImage(named: imageName) {
            setImage(image.withRenderingMode(.alwaysTemplate), for: .normal)
        } else {
            owsFailDebug("Missing asset: \(imageName)")
        }
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Common Style Reuse

    public class func sendButton(imageName: String, block: @escaping () -> Void) -> OWSButton {
        let button = OWSButton(imageName: imageName, tintColor: .white, block: block)

        let buttonWidth: CGFloat = 40
        button.layer.cornerRadius = buttonWidth / 2
        button.autoSetDimensions(to: CGSize(square: buttonWidth))

        button.backgroundColor = .ows_accentBlue

        return button
    }

    // MARK: -

    @objc
    func didTap() {
        block()
    }

    private func updateAlpha() {
        let isDimmed = (dimsWhenHighlighted && isHighlighted)
        alpha = isDimmed ? 0.4 : 1
    }
}
