//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

/// A checkmark in a circle to indicate an item (typically in a table view or collection view) is
/// selected.
class SelectionButton: UIView {
    private let outlineBadgeView: UIView = {
        let imageView = UIImageView(image: UIImage(imageLiteralResourceName: "circle"))
        imageView.contentMode = .center
        imageView.tintColor = .white
        imageView.isHidden = true
        return imageView
    }()
    private let selectedBadgeView: UIView = {
        let imageView = UIImageView(image: UIImage(imageLiteralResourceName: "check-circle-fill"))
        imageView.contentMode = .center
        imageView.tintColor = .ows_accentBlue

        // This will give checkmark it's color.
        let backgroundView = CircleView(diameter: 18)
        backgroundView.backgroundColor = .white

        let containerView = UIView(frame: imageView.bounds)
        containerView.isHidden = true

        containerView.addSubview(backgroundView)
        backgroundView.autoCenterInSuperview()

        containerView.addSubview(imageView)
        imageView.autoPinEdgesToSuperviewEdges()

        return containerView
    }()

    var isSelected: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    var allowsMultipleSelection: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    var outlineColor: UIColor = .white {
        didSet {
            outlineBadgeView.tintColor = outlineColor
        }
    }

    var hidesOutlineWhenSelected: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    init() {
        super.init(frame: .zero)

        addSubview(selectedBadgeView)
        selectedBadgeView.autoCenterInSuperview()

        addSubview(outlineBadgeView)
        outlineBadgeView.autoCenterInSuperview()

        autoSetDimensions(to: .square(24))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateAppearance() {
        if isSelected {
            outlineBadgeView.isHidden = hidesOutlineWhenSelected
            selectedBadgeView.isHidden = false
        } else if allowsMultipleSelection {
            outlineBadgeView.isHidden = false
            selectedBadgeView.isHidden = true
        } else {
            outlineBadgeView.isHidden = true
            selectedBadgeView.isHidden = true
        }
    }

    func reset() {
        selectedBadgeView.isHidden = true
        outlineBadgeView.isHidden = true
    }
}
