//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public class StickerPackInfoHeaderView: UICollectionReusableView {

    // MARK: - subviews

    private let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 12
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.preservesSuperviewLayoutMargins = true
        stackView.layoutMargins.bottom += 20
        return stackView
    }()

    private let coverView = StickerReusableView()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = .Signal.label
        label.font = .dynamicTypeTitle1.semibold()
        label.numberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let defaultPackIconView: UIImageView = {
        let imageView = UIImageView(image: Theme.iconImage(.official))
        return imageView
    }()

    private let authorLabel: UILabel = {
        let label = UILabel()
        label.textColor = .Signal.secondaryLabel
        label.font = .dynamicTypeSubheadlineClamped
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let countAndSizeLabel: UILabel = {
        let label = UILabel()
        label.textColor = .Signal.secondaryLabel
        label.font = .dynamicTypeSubheadlineClamped
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private lazy var sendButton = SettingsHeaderButton(
        title: OWSLocalizedString(
            "STICKER_PACK_SEND",
            comment: "Label for a button to send a sticker pack",
        ),
        icon: .buttonForward,
    )

    private lazy var linkButton = SettingsHeaderButton(
        title: OWSLocalizedString(
            "STICKER_PACK_LINK",
            comment: "Label for a button to copy the link of a sticker pack",
        ),
        icon: .buttonLink,
    )

    private lazy var uninstallButton = SettingsHeaderButton(
        title: OWSLocalizedString(
            "STICKER_PACK_REMOVE",
            comment: "Label for a button to uninstall a sticker pack",
        ),
        icon: .groupMemberRemoveFromGroup,
    )

    override init(frame: CGRect) {
        super.init(frame: frame)

        preservesSuperviewLayoutMargins = true

        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        let topRow = UIStackView(arrangedSubviews: [titleLabel, defaultPackIconView])
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = 6

        defaultPackIconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            defaultPackIconView.widthAnchor.constraint(equalToConstant: 26),
            defaultPackIconView.heightAnchor.constraint(equalToConstant: 26),
        ])

        let textRowsView = UIStackView(arrangedSubviews: [topRow, authorLabel, countAndSizeLabel])
        textRowsView.axis = .vertical
        textRowsView.alignment = .center

        let buttonStackView = UIStackView(arrangedSubviews: [sendButton, linkButton, uninstallButton])
        buttonStackView.axis = .horizontal
        buttonStackView.spacing = 16

        stackView.addArrangedSubview(coverView)
        stackView.addArrangedSubview(textRowsView)
        stackView.addArrangedSubview(buttonStackView)

        coverView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            coverView.widthAnchor.constraint(equalToConstant: 88),
            coverView.heightAnchor.constraint(equalToConstant: 88),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configuration

    // Helper to hide the header view if we can't load
    // the sticker pack for whatever reason.
    public func setContentHidden(_ hidden: Bool) {
        stackView.arrangedSubviews.forEach { $0.isHidden = hidden }
    }

    public func configure(
        stickerPack: StickerPackRecord,
        dataSource: StickerPackDataSource,
        stickerCount: Int,
        isInstalled: Bool,
        onTapSend: @escaping () -> Void,
        onTapLink: @escaping () -> Void,
        onTapUninstall: @escaping () -> Void,
    ) {
        setContentHidden(false)

        sendButton.addActionHandler(onTapSend)
        linkButton.addActionHandler(onTapLink)
        uninstallButton.addActionHandler(onTapUninstall)

        let defaultTitle = OWSLocalizedString(
            "STICKERS_PACK_VIEW_DEFAULT_TITLE",
            comment: "The default title for the 'sticker pack' view.",
        )
        if let title = stickerPack.title?.ows_stripped(), !title.isEmpty {
            titleLabel.text = title.filterForDisplay
        } else {
            titleLabel.text = defaultTitle
        }

        authorLabel.text = stickerPack.author?.filterForDisplay

        let stickerCountString = String.localizedStringWithFormat(
            OWSLocalizedString(
                "STICKER_PACK_STICKER_COUNT_%d",
                tableName: "PluralAware",
                comment: "Subtitle for sticker pack view. Embeds {{ the number of stickers in the pack }}.",
            ),
            stickerCount,
        )
        var bottomRowString = stickerCountString
        if let byteCount = Self.totalByteCount(stickerPack: stickerPack, dataSource: dataSource) {
            bottomRowString += " · " + byteCount.formatted(.owsByteCount())
        }
        countAndSizeLabel.text = bottomRowString

        let isDefaultStickerPack = StickerManager.isDefaultStickerPack(packId: stickerPack.info.packId)
        defaultPackIconView.isHidden = !isDefaultStickerPack

        uninstallButton.isHidden = !isInstalled

        updateCover(stickerPack: stickerPack, dataSource: dataSource)
    }

    private func updateCover(stickerPack: StickerPackRecord, dataSource: StickerPackDataSource) {
        guard !coverView.hasStickerView else { return }
        let coverInfo = stickerPack.coverInfo
        guard
            let stickerView = StickerView.stickerView(
                forStickerInfo: coverInfo,
                dataSource: dataSource,
            )
        else {
            coverView.showPlaceholder(color: .ows_blackAlpha60)
            return
        }
        coverView.configure(with: stickerView)
    }

    private static func totalByteCount(
        stickerPack: StickerPackRecord,
        dataSource: StickerPackDataSource,
    ) -> Int64? {
        let stickerInfos = stickerPack.stickerInfos()
        var total: Int64 = 0
        for info in stickerInfos {
            guard let url = (dataSource.metadata(forSticker: info) as? DecryptedStickerMetadata)?.stickerDataUrl else {
                return nil
            }
            guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64 else {
                return nil
            }
            total += size
        }
        return total
    }

    override public func sizeThatFits(_ size: CGSize) -> CGSize {
        let targetSize = CGSize(width: size.width, height: UIView.layoutFittingCompressedSize.height)
        let fittingSize = systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
        )
        return CGSize(width: size.width, height: fittingSize.height)
    }
}
