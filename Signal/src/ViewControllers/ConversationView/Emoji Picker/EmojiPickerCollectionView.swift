//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol EmojiPickerCollectionViewDelegate: class {
    func emojiPicker(_ emojiPicker: EmojiPickerCollectionView, didSelectEmoji emoji: Emoji)
    func emojiPicker(_ emojiPicker: EmojiPickerCollectionView, didScrollToSection section: Int)
}

class EmojiPickerCollectionView: UICollectionView {
    let layout: UICollectionViewFlowLayout

    private static let keyValueStore = SDSKeyValueStore(collection: "EmojiPickerCollectionView")
    private static let recentEmojiKey = "recentEmoji"

    weak var pickerDelegate: EmojiPickerCollectionViewDelegate?

    private let recentEmoji: [Emoji]
    var hasRecentEmoji: Bool { !recentEmoji.isEmpty }

    static let emojiWidth: CGFloat = 38
    static let margins: CGFloat = 16
    static let minimumSpacing: CGFloat = 10

    init() {
        layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(square: EmojiPickerCollectionView.emojiWidth)
        layout.minimumInteritemSpacing = EmojiPickerCollectionView.minimumSpacing
        layout.sectionInset = UIEdgeInsets(top: 0, leading: EmojiPickerCollectionView.margins, bottom: 0, trailing: EmojiPickerCollectionView.margins)

        recentEmoji = SDSDatabaseStorage.shared.uiRead { transaction in
            let rawEmoji = EmojiPickerCollectionView.keyValueStore.getObject(
                forKey: EmojiPickerCollectionView.recentEmojiKey,
                transaction: transaction
            ) as? [String] ?? []
            return rawEmoji.compactMap { Emoji(rawValue: $0) }
        }

        super.init(frame: .zero, collectionViewLayout: layout)

        delegate = self
        dataSource = self

        register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.reuseIdentifier)
        register(
            EmojiSectionHeader.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: EmojiSectionHeader.reuseIdentifier
        )

        backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_white
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // This is not an exact calculation, but is simple and works for our purposes.
    var numberOfColumns: Int { Int((width) / (EmojiPickerCollectionView.emojiWidth + EmojiPickerCollectionView.minimumSpacing)) }

    // At max, we show 3 rows of recent emoji
    private var maxRecentEmoji: Int { numberOfColumns * 3 }
    private var categoryIndexOffset: Int { hasRecentEmoji ? 1 : 0}

    func emojiForSection(_ section: Int) -> [Emoji] {
        guard section > 0 || !hasRecentEmoji else { return Array(recentEmoji[0..<min(maxRecentEmoji, recentEmoji.count)]) }

        guard let category = Emoji.Category.allCases[safe: section - categoryIndexOffset] else {
            owsFailDebug("Unexpectedly missing category for section \(section)")
            return []
        }

        return category.emoji.filter { $0.available }
    }

    func emojiForIndexPath(_ indexPath: IndexPath) -> Emoji? {
        return emojiForSection(indexPath.section)[safe: indexPath.row]
    }

    func nameForSection(_ section: Int) -> String? {
        guard section > 0 || !hasRecentEmoji else {
            return NSLocalizedString("EMOJI_CATEGORY_RECENTS_NAME",
                                     comment: "The name for the emoji category 'Recents'")
        }

        guard let category = Emoji.Category.allCases[safe: section - categoryIndexOffset] else {
            owsFailDebug("Unexpectedly missing category for section \(section)")
            return nil
        }

        return category.localizedName
    }

    func recordRecentEmoji(_ emoji: Emoji) {
        guard recentEmoji.first != emoji else { return }

        var newRecentEmoji = recentEmoji

        // Remove any existing entries for this emoji
        newRecentEmoji.removeAll { emoji == $0 }
        // Insert the selected emoji at the start of the list
        newRecentEmoji.insert(emoji, at: 0)
        // Truncate the recent emoji list to a maximum of 50 stored
        newRecentEmoji = Array(newRecentEmoji[0..<min(50, newRecentEmoji.count)])

        SDSDatabaseStorage.shared.asyncWrite { transaction in
            EmojiPickerCollectionView.keyValueStore.setObject(
                newRecentEmoji.map { $0.rawValue },
                key: EmojiPickerCollectionView.recentEmojiKey,
                transaction: transaction
            )
        }
    }

    var lowestVisibleSection = 0
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let newLowestVisibleSection = indexPathsForVisibleItems.reduce(into: Set<Int>()) { $0.insert($1.section) }.min() ?? 0

        guard scrollingToSection == nil || newLowestVisibleSection == scrollingToSection else { return }

        scrollingToSection = nil

        if lowestVisibleSection != newLowestVisibleSection {
            pickerDelegate?.emojiPicker(self, didScrollToSection: newLowestVisibleSection)
            lowestVisibleSection = newLowestVisibleSection
        }
    }

    var scrollingToSection: Int?
    func scrollToSectionHeader(_ section: Int, animated: Bool) {
        guard let attributes = layoutAttributesForSupplementaryElement(
            ofKind: UICollectionView.elementKindSectionHeader,
            at: IndexPath(item: 0, section: section)
        ) else { return }
        scrollingToSection = section
        setContentOffset(CGPoint(x: 0, y: attributes.frame.minY), animated: animated)
    }
}

extension EmojiPickerCollectionView: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let emoji = emojiForIndexPath(indexPath) else {
            return owsFailDebug("Missing emoji for indexPath \(indexPath)")
        }

        recordRecentEmoji(emoji)

        pickerDelegate?.emojiPicker(self, didSelectEmoji: emoji)
    }
}

extension EmojiPickerCollectionView: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return emojiForSection(section).count
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return Emoji.Category.allCases.count + categoryIndexOffset
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = dequeueReusableCell(withReuseIdentifier: EmojiCell.reuseIdentifier, for: indexPath)

        guard let emojiCell = cell as? EmojiCell else {
            owsFailDebug("unexpected cell type")
            return cell
        }

        guard let emoji = emojiForIndexPath(indexPath) else {
            owsFailDebug("unexpected indexPath")
            return cell
        }

        emojiCell.configure(emoji: emoji)

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {

        let supplementaryView = dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: EmojiSectionHeader.reuseIdentifier,
            for: indexPath
        )

        guard let sectionHeader = supplementaryView as? EmojiSectionHeader else {
            owsFailDebug("unexpected supplementary view type")
            return supplementaryView
        }

        sectionHeader.label.text = nameForSection(indexPath.section)

        return sectionHeader
    }
}

extension EmojiPickerCollectionView: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView,
                          layout collectionViewLayout: UICollectionViewLayout,
                          referenceSizeForHeaderInSection section: Int) -> CGSize {
        let measureCell = EmojiSectionHeader()
        measureCell.label.text = nameForSection(section)
        return measureCell.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}

private class EmojiCell: UICollectionViewCell {
    static let reuseIdentifier = "EmojiCell"

    let emojiLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .clear

        emojiLabel.font = .boldSystemFont(ofSize: 32)
        contentView.addSubview(emojiLabel)
        emojiLabel.autoPinEdgesToSuperviewEdges()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(emoji: Emoji) {
        emojiLabel.text = emoji.rawValue
    }
}

private class EmojiSectionHeader: UICollectionReusableView {
    static let reuseIdentifier = "EmojiSectionHeader"

    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        layoutMargins = UIEdgeInsets(
            top: 16,
            leading: EmojiPickerCollectionView.margins,
            bottom: 6,
            trailing: EmojiPickerCollectionView.margins
        )

        label.font = UIFont.ows_dynamicTypeFootnoteClamped.ows_semibold()
        label.textColor = Theme.secondaryTextAndIconColor
        addSubview(label)
        label.autoPinEdgesToSuperviewMargins()
        label.setCompressionResistanceHigh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        var labelSize = label.sizeThatFits(size)
        labelSize.width += layoutMargins.left + layoutMargins.right
        labelSize.height += layoutMargins.top + layoutMargins.bottom
        return labelSize
    }
}
