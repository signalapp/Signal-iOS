//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// MARK: - StickerKeyboard

protocol StickerKeyboardDelegate: AnyObject {

    func stickerKeyboardDidRequestPresentManageStickersView(_ stickerKeyboard: StickerKeyboard)

    func stickerKeyboard(_: StickerKeyboard, didSelect stickerInfo: StickerInfo)
}

class StickerKeyboard: CustomKeyboard, StickerPickerViewDelegate {

    weak var delegate: StickerKeyboardDelegate?

    private lazy var stickerPickerView = StickerPickerView(delegate: self)

    init(delegate: StickerKeyboardDelegate?) {
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

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func willPresent() {
        super.willPresent()
        stickerPickerView.willBePresented()
    }

    override func wasPresented() {
        super.wasPresented()
        stickerPickerView.wasPresented()
    }

    override func willDismiss() {
        super.willDismiss()
    }

    // MARK: StickerPickerViewDelegate

    func presentManageStickersView(for stickerPickerView: StickerPickerView) {
        delegate?.stickerKeyboardDidRequestPresentManageStickersView(self)
    }

    func didSelectSticker(_ stickerMetadata: any StickerMetadata) {
        delegate?.stickerKeyboard(self, didSelect: stickerMetadata.stickerInfo)
    }

    func select(page: StickerPickerPage, bouncingSticker: StickerInfo? = nil) {
        stickerPickerView.select(page: page, bouncingSticker: bouncingSticker)
    }
}
