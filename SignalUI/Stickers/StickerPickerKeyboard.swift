//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

// MARK: - StickerKeyboard

public protocol StickerKeyboardDelegate: AnyObject {

    func stickerKeyboardDidRequestPresentManageStickersView(_ stickerKeyboard: StickerKeyboard)

    func stickerKeyboard(_: StickerKeyboard, didSelect stickerInfo: StickerInfo)
}

public class StickerKeyboard: CustomKeyboard {

    public weak var delegate: StickerKeyboardDelegate?

    private lazy var stickerPickerView = StickerPickerView(delegate: self)

    public init(delegate: StickerKeyboardDelegate?) {
        self.delegate = delegate

        super.init()

        backgroundColor = if #available(iOS 26, *) { .clear } else { .Signal.background }

        // Match rounded corners of the keyboard backdrop view.
        if #available(iOS 26, *) {
            contentView.clipsToBounds = true
            contentView.cornerConfiguration = .uniformTopRadius(.fixed(26))
        }

        // Need to set horizontal margins explicitly because they can't be inherited from the parent.
        let hMargin = OWSTableViewController2.cellHInnerMargin
        stickerPickerView.directionalLayoutMargins = .init(margin: hMargin)
        stickerPickerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stickerPickerView)
        NSLayoutConstraint.activate([
            stickerPickerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stickerPickerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stickerPickerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stickerPickerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    public required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func willPresent() {
        super.willPresent()
        stickerPickerView.willBePresented()
    }

    override public func wasPresented() {
        super.wasPresented()
        stickerPickerView.wasPresented()
    }
}

// MARK: StickerPacksToolbarDelegate

extension StickerKeyboard: StickerPickerViewDelegate {

    func presentManageStickersView(for stickerPickerView: StickerPickerView) {
        delegate?.stickerKeyboardDidRequestPresentManageStickersView(self)
    }

    public func didSelectSticker(_ stickerInfo: StickerInfo) {
        delegate?.stickerKeyboard(self, didSelect: stickerInfo)
    }
}
