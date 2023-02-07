//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// The view next to the scroll indicator that shows the currently visible month.
class MediaTileScrollFlag: UIView {
    private let label = UILabel()
    private let inset = CGSize(width: 12.0, height: 6.0)
    var stringValue: String {
        get {
            return label.text ?? ""
        }
        set {
            label.text = newValue
        }
    }

    init() {
        super.init(frame: .zero)

        addSubview(label)

        layer.cornerRadius = 14.0
        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func sizeToFit() {
        label.sizeToFit()
        var bounds = self.bounds
        bounds.size = label.frame.insetBy(dx: -inset.width, dy: -inset.height).size
        self.bounds = bounds
    }

    override func layoutSubviews() {
        label.frame = bounds.insetBy(dx: inset.width, dy: inset.height)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        updateColors()
        super.traitCollectionDidChange(previousTraitCollection)
    }

    private func updateColors() {
        if Theme.isDarkThemeEnabled {
            label.textColor = .ows_gray02
            layer.backgroundColor = UIColor(rgbHex: 0x3b3b3b).withAlphaComponent(0.8).cgColor
        } else {
            label.textColor = UIColor.ows_gray90
            layer.backgroundColor = UIColor(rgbHex: 0xfafafa).withAlphaComponent(0.8).cgColor
        }
    }
}
