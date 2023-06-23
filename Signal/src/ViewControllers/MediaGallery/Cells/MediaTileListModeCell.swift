//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI

@objc
class MediaTileListModeCellSeparator: UIView { }

// This is a base class for cells in All Media that have a wide, one-per-row
// appearance, as opposed to square or grid.
class MediaTileListModeCell: UICollectionViewCell, MediaTileCell {
    // This determines whether corners are rounded.
    private var isFirstInGroup: Bool = false
    private var isLastInGroup: Bool = false

    // We have to mess with constraints when toggling selection mode.
    private var constraintWithSelectionButton: NSLayoutConstraint!
    private var constraintWithoutSelectionButton: NSLayoutConstraint!

    var item: AllMediaItem?

    /// Since UICollectionView doesn't support separators, we have to do it ourselves. Show the
    /// separator at the bottom of each item except when last in a section.
    let separator: MediaTileListModeCellSeparator = {
        let view = MediaTileListModeCellSeparator()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.borderWidth = 1.0
        if #available(iOS 13, *) {
            view.layer.borderColor = UIColor.separator.cgColor
        } else {
            view.layer.borderColor = UIColor(rgbHex: 0x3c3c43).withAlphaComponent(0.3).cgColor
        }
        return view
    }()

    let selectionButton = SelectionButton()

    private let selectedMaskView = UIView()

    // TODO(george): This will change when dynamic text support is added.
    class var desiredHeight: CGFloat { 64.0 }

    private var dynamicDesiredSelectionOutlineColor: UIColor {
        return UIColor { _ in
            Theme.isDarkThemeEnabled ? UIColor.ows_gray25 : UIColor.ows_gray20
        }
    }

    private lazy var selectionMaskColor: UIColor = {
        if #available(iOS 13, *) {
            return UIColor { _ in
                Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray15
            }
        } else {
            return .ows_gray15
        }
    }()

    func willSetupViews() {
        contentView.addSubview(selectedMaskView)
        contentView.addSubview(selectionButton)
        contentView.addSubview(separator)
    }

    func setupViews(constraintWithSelectionButton: NSLayoutConstraint,
                    constraintWithoutSelectionButton: NSLayoutConstraint) {
        self.constraintWithSelectionButton = constraintWithSelectionButton
        self.constraintWithoutSelectionButton = constraintWithoutSelectionButton

        selectionButton.outlineColor = dynamicDesiredSelectionOutlineColor

        if #available(iOS 13.0, *) {
            contentView.backgroundColor = UIColor(dynamicProvider: { _ in
                Theme.isDarkThemeEnabled ? .ows_gray80 : .white
            })
        } else {
            contentView.backgroundColor = .white
        }

        selectedMaskView.alpha = 0.3
        selectedMaskView.backgroundColor = selectionMaskColor
        selectedMaskView.isHidden = true

        NSLayoutConstraint.activate([
            constraintWithoutSelectionButton,

            selectionButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            selectionButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            selectionButton.widthAnchor.constraint(equalToConstant: 24),
            selectionButton.heightAnchor.constraint(equalToConstant: 24),

            separator.topAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -1),
            separator.heightAnchor.constraint(equalToConstant: 0.33),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
        selectedMaskView.autoPinEdgesToSuperviewEdges()
    }

    override public func prepareForReuse() {
        super.prepareForReuse()

        selectedMaskView.isHidden = true
        selectionButton.reset()
    }

    var cellsAbut: Bool { true }

    func indexPathDidChange(_ indexPath: IndexPath, itemCount: Int) {
        isFirstInGroup = (indexPath.item == 0)
        isLastInGroup = (indexPath.item + 1 == itemCount)

        if cellsAbut {
            let topCorners = isFirstInGroup ? [CACornerMask.layerMinXMinYCorner, CACornerMask.layerMaxXMinYCorner] : []
            let bottomCorners = isLastInGroup ? [CACornerMask.layerMinXMaxYCorner, CACornerMask.layerMaxXMaxYCorner] : []
            let corners = topCorners + bottomCorners

            let radius = CGFloat(10.0)
            contentView.layer.maskedCorners = CACornerMask(corners)
            contentView.layer.cornerRadius = radius

            selectedMaskView.layer.maskedCorners = CACornerMask(corners)
            selectedMaskView.layer.cornerRadius = radius

            separator.isHidden = isLastInGroup
        } else {
            separator.isHidden = true
        }
    }

    private var _allowsMultipleSelection = false
    var allowsMultipleSelection: Bool { _allowsMultipleSelection }

    func setAllowsMultipleSelection(_ allowed: Bool, animated: Bool) {
        _allowsMultipleSelection = allowed
        updateSelectionState(animated: animated)
    }

    override public var isSelected: Bool {
        didSet {
            updateSelectionState(animated: false)
        }
    }

    private func updateSelectionState(animated: Bool) {
        selectedMaskView.isHidden = !isSelected
        selectionButton.isSelected = isSelected
        if !_allowsMultipleSelection {
            selectionButton.allowsMultipleSelection = false
        }
        if animated {
            UIView.animate(withDuration: 0.15) {
                self.updateLayoutForSelectionStateChange()
            } completion: { _ in
                self.didUpdateLayoutForSelectionStateChange()
            }
        } else {
            updateLayoutForSelectionStateChange()
            didUpdateLayoutForSelectionStateChange()
        }
    }

    private func updateLayoutForSelectionStateChange() {
        if contentView.subviews.isEmpty {
            return
        }
        if _allowsMultipleSelection {
            NSLayoutConstraint.deactivate([constraintWithoutSelectionButton])
            NSLayoutConstraint.activate([constraintWithSelectionButton])
        } else {
            NSLayoutConstraint.deactivate([constraintWithSelectionButton])
            NSLayoutConstraint.activate([constraintWithoutSelectionButton])
        }
        self.layoutIfNeeded()
    }

    private func didUpdateLayoutForSelectionStateChange() {
        if _allowsMultipleSelection {
            self.selectionButton.allowsMultipleSelection = true
        }
    }

    func makePlaceholder() {
        owsFail("Subclass must override")
    }

    func configure(item: AllMediaItem, spoilerReveal: SpoilerRevealState) {
        self.item = item
    }

    func mediaPresentationContext(collectionView: UICollectionView, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
        return nil
    }
}
