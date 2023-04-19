//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A checkmark in a circle to indicate an item (typically in a table view or collection view) is
/// selected.
class SelectionButton: UIView {
    private let outlineBadgeView: UIView
    private let selectedBadgeView: UIView

    private let selectionBadgeSize: CGFloat = 22
    private static let selectedBadgeImage = UIImage(named: "media-composer-checkmark")

    var isSelected: Bool = false {
        didSet {
            updateHidden()
        }
    }

    var allowsMultipleSelection: Bool = false {
        didSet {
            updateHidden()
        }
    }

    var outlineColor: UIColor = UIColor.ows_white {
        didSet {
            outlineBadgeView.layer.borderColor = outlineColor.cgColor
        }
    }

    init() {
        selectedBadgeView = CircleView(diameter: selectionBadgeSize)
        selectedBadgeView.backgroundColor = .ows_accentBlue
        selectedBadgeView.isHidden = true

        let checkmarkImageView = UIImageView(image: Self.selectedBadgeImage)
        checkmarkImageView.tintColor = .white
        selectedBadgeView.addSubview(checkmarkImageView)
        checkmarkImageView.autoCenterInSuperview()

        outlineBadgeView = CircleView()
        outlineBadgeView.backgroundColor = .clear
        outlineBadgeView.layer.borderWidth = 1.5
        outlineBadgeView.layer.borderColor = UIColor.ows_white.cgColor
        selectedBadgeView.isHidden = true

        super.init(frame: CGRect(x: 0.0, y: 0.0, width: selectionBadgeSize, height: selectionBadgeSize))

        addSubview(selectedBadgeView)
        addSubview(outlineBadgeView)

        outlineBadgeView.autoSetDimensions(to: CGSize(square: selectionBadgeSize))

        selectedBadgeView.autoSetDimensions(to: CGSize(square: selectionBadgeSize))
        selectedBadgeView.autoAlignAxis(.vertical, toSameAxisOf: outlineBadgeView)
        selectedBadgeView.autoAlignAxis(.horizontal, toSameAxisOf: outlineBadgeView)

        autoSetDimensions(to: CGSize(square: selectionBadgeSize))
        reset()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateHidden() {
        if isSelected {
            outlineBadgeView.isHidden = false
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
