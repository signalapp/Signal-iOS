//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class StickerPackShareSheetViewController: OWSTableSheetViewController {

    private let stickerPack: StickerPackRecord
    private let stickerPackDataSource: StickerPackDataSource
    private let onSendInSignal: () -> Void
    private let onCopyLink: () -> Void
    private let onShare: () -> Void

    init(
        stickerPack: StickerPackRecord,
        stickerPackDataSource: StickerPackDataSource,
        onSendInSignal: @escaping () -> Void,
        onCopyLink: @escaping () -> Void,
        onShare: @escaping () -> Void,
    ) {
        self.stickerPack = stickerPack
        self.stickerPackDataSource = stickerPackDataSource
        self.onSendInSignal = onSendInSignal
        self.onCopyLink = onCopyLink
        self.onShare = onShare
    }

    override func tableContents() -> OWSTableContents {
        let contents = OWSTableContents()

        let packPreviewSection = OWSTableSection(
            items: [
                OWSTableItem(
                    customCellBlock: { [weak self] in
                        self?.buildPreviewCell() ?? UITableViewCell()
                    },
                    actionBlock: nil,
                ),
            ],
            headerView: buildDescriptionHeader(),
        )

        let actionsSection = OWSTableSection(items: [
            .item(
                icon: .buttonForward,
                name: OWSLocalizedString(
                    "STICKER_PACK_SHARE_SHEET_SEND_IN_SIGNAL",
                    comment: "Label for a button on a sticker-pack share sheet that sends the pack in Signal.",
                ),
                actionBlock: { [weak self] in
                    guard let self else { return }
                    self.dismiss(animated: true) {
                        self.onSendInSignal()
                    }
                },
            ),
            .item(
                icon: .buttonCopy,
                name: OWSLocalizedString(
                    "STICKER_PACK_SHARE_SHEET_COPY_LINK",
                    comment: "Label for a button on a sticker-pack share sheet that copies the pack's share link.",
                ),
                actionBlock: { [weak self] in
                    guard let self else { return }
                    self.dismiss(animated: true) {
                        self.onCopyLink()
                    }
                },
            ),
            .item(
                icon: .buttonShare,
                name: CommonStrings.shareButton,
                actionBlock: { [weak self] in
                    self?.dismiss(animated: true) {
                        self?.onShare()
                    }
                },
            ),
        ])

        contents.add(sections: [packPreviewSection, actionsSection])
        return contents
    }

    private func buildDescriptionHeader() -> UIView {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.font = .dynamicTypeSubheadline
        label.textColor = .Signal.secondaryLabel
        label.textAlignment = .center
        label.text = OWSLocalizedString(
            "STICKER_PACK_SHARE_SHEET_HEADER",
            comment: "Text describing what you can do with a sticker pack link, on a sheet for sharing it.",
        )

        let wrapper = UIView()
        wrapper.layoutMargins = UIEdgeInsets(hMargin: 24, vMargin: 16)
        wrapper.addSubview(label)
        label.autoPinEdgesToSuperviewMargins()
        return wrapper
    }

    private func buildPreviewCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        cell.selectionStyle = .none

        let coverView = StickerReusableView()
        coverView.translatesAutoresizingMaskIntoConstraints = false
        if
            let stickerView = StickerView.stickerView(
                forStickerInfo: stickerPack.coverInfo,
                dataSource: stickerPackDataSource,
            )
        {
            coverView.configure(with: stickerView)
        } else {
            coverView.showPlaceholder(color: .ows_blackAlpha60)
        }
        NSLayoutConstraint.activate([
            coverView.widthAnchor.constraint(equalToConstant: 56),
            coverView.heightAnchor.constraint(equalToConstant: 56),
        ])

        let titleLabel = UILabel()
        titleLabel.font = .dynamicTypeHeadline
        titleLabel.textColor = .Signal.label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        if let title = stickerPack.title?.ows_stripped(), !title.isEmpty {
            titleLabel.text = title.filterForDisplay
        } else {
            titleLabel.text = OWSLocalizedString(
                "STICKERS_PACK_VIEW_DEFAULT_TITLE",
                comment: "The default title for the 'sticker pack' view.",
            )
        }

        let authorLabel = UILabel()
        authorLabel.font = .dynamicTypeFootnote
        authorLabel.textColor = .Signal.label
        authorLabel.numberOfLines = 1
        authorLabel.lineBreakMode = .byTruncatingTail
        authorLabel.text = stickerPack.author?.filterForDisplay

        let urlLabel = UILabel()
        urlLabel.font = .dynamicTypeFootnote
        urlLabel.textColor = .Signal.secondaryLabel
        urlLabel.numberOfLines = 2
        urlLabel.lineBreakMode = .byTruncatingTail
        urlLabel.text = stickerPack.info.shareUrl()

        let textStack = UIStackView(arrangedSubviews: [titleLabel, authorLabel, urlLabel])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let hStack = UIStackView(arrangedSubviews: [coverView, textStack])
        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.spacing = 12
        hStack.translatesAutoresizingMaskIntoConstraints = false

        cell.contentView.addSubview(hStack)
        NSLayoutConstraint.activate([
            hStack.topAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.topAnchor),
            hStack.bottomAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.bottomAnchor),
            hStack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: OWSTableViewController2.cellHInnerMargin),
            hStack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -OWSTableViewController2.cellHInnerMargin),
        ])

        return cell
    }
}
