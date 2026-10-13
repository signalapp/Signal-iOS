//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SDWebImage
import SignalServiceKit
import SignalUI

class StickerDetailSheet: OWSTableSheetViewController {

    struct Action {
        let icon: ThemeIcon?
        let title: String
        let handler: () -> Void
    }

    // MARK: -

    private let db: DB
    private let stickerMetadata: any StickerMetadata
    private let actions: [Action]

    init(
        db: DB,
        stickerMetadata: any StickerMetadata,
        actions: [Action],
    ) {
        self.db = db
        self.stickerMetadata = stickerMetadata
        self.actions = actions
        super.init()
    }

    // MARK: Sticker preview image

    private func buildPreviewCard() -> UIView? {
        var stickerData: Data
        do {
            stickerData = try stickerMetadata.readStickerData()
        } catch {
            Logger.error("Failure to read sticker metadata")
            return nil
        }

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8

        let animatedImage = SDAnimatedImage(data: stickerData)
        let stickerView = SDAnimatedImageView()
        stickerView.contentMode = .scaleAspectFit
        stickerView.image = animatedImage

        stack.addArrangedSubview(stickerView)

        stickerView.autoSetDimensions(to: .square(240))

        if let subtitleText = fetchSubtitle() {
            let subtitleLabel = UILabel()
            subtitleLabel.text = subtitleText
            subtitleLabel.font = .dynamicTypeSubheadline
            subtitleLabel.textColor = .Signal.secondaryLabel
            subtitleLabel.textAlignment = .center
            subtitleLabel.numberOfLines = 0

            stack.addArrangedSubview(subtitleLabel)
        }

        stack.addArrangedSubview(SpacerView(preferredHeight: 12))

        return stack
    }

    private func fetchSubtitle() -> String? {
        if
            let packRecord = db.read(
                block: { tx in
                    StickerManager.fetchStickerPack(
                        stickerPackInfo: stickerMetadata.packInfo,
                        transaction: tx,
                    )
                },
            ),
            let title = packRecord.title,
            let author = packRecord.author
        {
            return title + " · " + author
        }
        return nil
    }

    // MARK: -

    override func tableContents() -> OWSTableContents {
        let contents = OWSTableContents()

        let section = OWSTableSection()
        section.customHeaderView = buildPreviewCard()
        contents.add(section)

        for action in actions {
            section.add(
                .item(
                    icon: action.icon,
                    tintColor: .Signal.label,
                    name: action.title,
                    textColor: .Signal.label,
                    actionBlock: { [weak self] in
                        self?.dismiss(animated: true) {
                            action.handler()
                        }
                    },
                ),
            )
        }

        return contents
    }
}
