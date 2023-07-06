//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI

// This is a base class for cells in All Media that have a wide, one-per-row
// appearance, as opposed to square or grid.
class MediaTileListModeCell: UICollectionViewCell, MediaGalleryCollectionViewCell {
    // This determines whether corners are rounded.
    private var isFirstInGroup: Bool = false
    private var isLastInGroup: Bool = false

    // We have to mess with constraints when toggling selection mode.
    private var constraintWithSelectionButton: NSLayoutConstraint!
    private var constraintWithoutSelectionButton: NSLayoutConstraint!

    var item: MediaGalleryCellItem?

    /// Since UICollectionView doesn't support separators, we have to do it ourselves. Show the
    /// separator at the bottom of each item except when last in a section.
    let separator: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(dynamicProvider: { _ in Theme.cellSeparatorColor })
        view.autoSetDimension(.height, toSize: .hairlineWidth)
        return view
    }()

    let selectionButton: SelectionButton = {
        let button = SelectionButton()
        button.outlineColor = UIColor(dynamicProvider: { _ in Theme.isDarkThemeEnabled ? .ows_gray25 : .ows_gray22 })
        button.hidesOutlineWhenSelected = true
        return button
    }()

    private let selectedMaskView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(selectedMaskView)
        contentView.addSubview(selectionButton)
        contentView.addSubview(separator)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupViews(constraintWithSelectionButton: NSLayoutConstraint, constraintWithoutSelectionButton: NSLayoutConstraint) {
        self.constraintWithSelectionButton = constraintWithSelectionButton
        self.constraintWithoutSelectionButton = constraintWithoutSelectionButton

        contentView.backgroundColor = UIColor(dynamicProvider: { _ in Theme.tableCell2PresentedBackgroundColor })

        selectedMaskView.backgroundColor = UIColor(dynamicProvider: { _ in
            Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray15
        })
        selectedMaskView.isHidden = true

        NSLayoutConstraint.activate([
            constraintWithoutSelectionButton,

            selectionButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            selectionButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            selectionButton.widthAnchor.constraint(equalToConstant: 24),
            selectionButton.heightAnchor.constraint(equalToConstant: 24),

            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
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

    var allowsMultipleSelection: Bool {
        get { _allowsMultipleSelection }
        set { setAllowsMultipleSelection(newValue, animated: false) }
    }

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
        if !allowsMultipleSelection {
            selectionButton.allowsMultipleSelection = false
        }
        if animated {
            UIView.animate(withDuration: 0.2) {
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
        guard !contentView.subviews.isEmpty else { return }

        if allowsMultipleSelection {
            NSLayoutConstraint.deactivate([constraintWithoutSelectionButton])
            NSLayoutConstraint.activate([constraintWithSelectionButton])
        } else {
            NSLayoutConstraint.deactivate([constraintWithSelectionButton])
            NSLayoutConstraint.activate([constraintWithoutSelectionButton])
        }
        layoutIfNeeded()
    }

    private func didUpdateLayoutForSelectionStateChange() {
        if allowsMultipleSelection {
            selectionButton.allowsMultipleSelection = true
        }
    }

    func makePlaceholder() {
        owsFail("Subclass must override")
    }

    func configure(item: MediaGalleryCellItem, spoilerState: SpoilerRenderState) {
        self.item = item
    }

    func mediaPresentationContext(collectionView: UICollectionView, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
        return nil
    }
}
