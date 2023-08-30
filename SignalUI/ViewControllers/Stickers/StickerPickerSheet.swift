//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalMessaging

// MARK: - StickerPickerSheetDelegate

public protocol StickerPickerSheetDelegate: AnyObject {
    func makeManageStickersViewController() -> UIViewController
}

// MARK: - StickerPickerSheet

public class StickerPickerSheet: InteractiveSheetViewController {
    public override var interactiveScrollViews: [UIScrollView] { stickerPicker.stickerPackCollectionViews }
    public override var sheetBackgroundColor: UIColor { .clear }

    /// Used for presenting the sticker manager from the toolbar.
    ///
    /// This delegate is optional. If it is not set, the picker sheet will
    /// still function, but the manage stickers button will not appear
    /// on the toolbar.
    public weak var sheetDelegate: StickerPickerSheetDelegate? {
        didSet {
            // The toolbar only shows the manage button if it has a delegate
            // If the sheet doesn't have a delegate, it can't present the
            // manage stickers view controller, so only set the toolbar
            // delegate if there is a sheet delegate.
            stickerPacksToolbar.delegate = sheetDelegate == nil ? nil : self
        }
    }
    /// Used for handling sticker selection.
    public weak var pickerDelegate: StickerPickerDelegate?
    private let stickerPacksToolbar = StickerPacksToolbar(forceDarkTheme: true)
    private lazy var stickerPicker = StickerPickerPageView(delegate: self, forceDarkTheme: true)

    override init(blurEffect: UIBlurEffect? = nil) {
        super.init(blurEffect: blurEffect)
    }

    init(backgroundColor: UIColor) {
        super.init()
        stickerPicker.backgroundColor = backgroundColor
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        contentView.addSubview(stickerPicker)
        stickerPicker.autoPinEdgesToSuperviewEdges()
        stickerPicker.stickerPackCollectionViews.forEach { $0.alwaysBounceVertical = true }

        view.addSubview(stickerPacksToolbar)
        stickerPacksToolbar.autoPinEdges(toSuperviewEdgesExcludingEdge: .top)
        stickerPacksToolbar.backgroundColor = .ows_gray90
    }

    private var viewHasAppeared = false
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewHasAppeared = true
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Ensure the scrollView's layout has completed
        // as we're about to use its bounds to calculate
        // the masking view and contentOffset.
        contentView.layoutIfNeeded()

        // Ensure you can scroll to the last sticker without
        // them being stuck behind the toolbar.
        let bottomInset = stickerPacksToolbar.height - stickerPacksToolbar.safeAreaInsets.bottom
        let contentInset = UIEdgeInsets(top: 0, leading: 0, bottom: bottomInset, trailing: 0)
        stickerPicker.stickerPackCollectionViews.forEach { collectionView in
            collectionView.contentInset = contentInset
            collectionView.scrollIndicatorInsets = contentInset
        }

        guard !viewHasAppeared else { return }
        stickerPicker.wasPresented()
    }
}

// MARK: StickerPacksToolbarDelegate

extension StickerPickerSheet: StickerPacksToolbarDelegate {
    public func presentManageStickersView() {
        guard let sheetDelegate else { return }
        let manageStickersViewController = sheetDelegate.makeManageStickersViewController()
        presentFormSheet(manageStickersViewController, animated: true)
    }
}

// MARK: StickerPickerPageViewDelegate

extension StickerPickerSheet: StickerPickerPageViewDelegate {
    public func didSelectSticker(stickerInfo: StickerInfo) {
        self.pickerDelegate?.didSelectSticker(stickerInfo: stickerInfo)
    }

    public var storyStickerConfiguration: StoryStickerConfiguration {
        self.pickerDelegate?.storyStickerConfiguration ?? .hide
    }

    public func setItems(_ items: [StickerHorizontalListViewItem]) {
        stickerPacksToolbar.packsCollectionView.items = items
    }

    public func updateSelections(scrollToSelectedItem: Bool) {
        stickerPacksToolbar.packsCollectionView.updateSelections(scrollToSelectedItem: scrollToSelectedItem)
    }
}
