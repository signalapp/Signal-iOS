//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

// MARK: - StickerKeyboard

public class StickerKeyboard: CustomKeyboard {

    public typealias StickerKeyboardDelegate = StickerPickerDelegate & StickerPacksToolbarDelegate
    public weak var delegate: StickerKeyboardDelegate?

    private let headerView = StickerPacksToolbar()
    private lazy var stickerPickerPageView = StickerPickerPageView(delegate: self)

    public override init() {
        super.init()

        let stackView = UIStackView()
        addSubview(stackView)
        stackView.addBackgroundView(withBackgroundColor: Theme.keyboardBackgroundColor)
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.addArrangedSubview(headerView)
        stackView.autoPinEdgesToSuperviewEdges()
        stackView.addArrangedSubview(stickerPickerPageView)
        stickerPickerPageView.autoPinEdge(toSuperviewSafeArea: .left)
        stickerPickerPageView.autoPinEdge(toSuperviewSafeArea: .right)

        headerView.delegate = self
    }

    required public init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func wasPresented() {
        super.wasPresented()
        stickerPickerPageView.wasPresented()
    }

}

// MARK: StickerPacksToolbarDelegate

extension StickerKeyboard: StickerPacksToolbarDelegate {
    public var shouldShowManageButton: Bool { true }

    public func manageButtonWasPressed() {
        AssertIsOnMainThread()

        Logger.verbose("")

        delegate?.presentManageStickersView()
    }
}

// MARK: StickerPickerPageViewDelegate

extension StickerKeyboard: StickerPickerPageViewDelegate {
    public func didSelectSticker(stickerInfo: StickerInfo) {
        self.delegate?.didSelectSticker(stickerInfo: stickerInfo)
    }

    public func presentManageStickersView() {
        self.delegate?.presentManageStickersView()
    }

    public func setItems(_ items: [StickerHorizontalListViewItem]) {
        headerView.packsCollectionView.items = items
    }

    public func updateSelections(scrollToSelectedItem: Bool) {
        headerView.packsCollectionView.updateSelections(scrollToSelectedItem: scrollToSelectedItem)
    }
}
