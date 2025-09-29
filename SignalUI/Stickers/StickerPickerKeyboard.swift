//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

// MARK: - StickerKeyboard

final public class StickerKeyboard: CustomKeyboard {

    public typealias StickerKeyboardDelegate = StickerPickerDelegate & StickerPacksToolbarDelegate
    public weak var delegate: StickerKeyboardDelegate?

    private let headerView = StickerPacksToolbar()
    private lazy var stickerPickerPageView = StickerPickerPageView(delegate: self)

    public override init() {
        super.init()

        var backgroundColor = UIColor.Signal.background
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            backgroundColor = .clear
            headerView.layoutMargins.top = 0
        }
#endif
        self.backgroundColor = backgroundColor

        let stackView = UIStackView(arrangedSubviews: [ headerView, stickerPickerPageView ])
        contentView.addSubview(stackView)
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.autoPinEdgesToSuperviewEdges()

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

        delegate?.presentManageStickersView()
    }
}

// MARK: StickerPickerPageViewDelegate

extension StickerKeyboard: StickerPickerPageViewDelegate {
    public func didSelectSticker(stickerInfo: StickerInfo) {
        self.delegate?.didSelectSticker(stickerInfo: stickerInfo)
    }

    public var storyStickerConfiguration: StoryStickerConfiguration {
        .hide
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
