//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

// MARK: -

public struct EmojiItem {
    let emoji: String
    let count: Int

    let didSelect: () -> Void
}

public class EmojiCountsCollectionView: UICollectionView {

    let itemHeight: CGFloat = 36

    public var items = [EmojiItem]() {
        didSet {
            AssertIsOnMainThread()
            reloadData()
        }
    }

    public required init() {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.estimatedItemSize = CGSize(square: itemHeight)
        layout.scrollDirection = .horizontal
        super.init(frame: .zero, collectionViewLayout: layout)

        delegate = self
        dataSource = self
        showsHorizontalScrollIndicator = false
        backgroundColor = .clear

        register(EmojiCountCell.self, forCellWithReuseIdentifier: EmojiCountCell.reuseIdentifier)

        contentInset = UIEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        autoSetDimension(.height, toSize: itemHeight + contentInset.top + contentInset.bottom)
    }

    func setSelectedIndex(_ index: Int) {
        selectItem(at: IndexPath(item: index, section: 0), animated: true, scrollPosition: .centeredHorizontally)
    }

    required public init(coder: NSCoder) {
        notImplemented()
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension EmojiCountsCollectionView: UICollectionViewDelegateFlowLayout {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Logger.debug("")

        guard let item = items[safe: indexPath.row] else {
            owsFailDebug("Invalid index path: \(indexPath)")
            return
        }

        item.didSelect()
    }
}

// MARK: - UICollectionViewDataSource

extension EmojiCountsCollectionView: UICollectionViewDataSource {

    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection sectionIdx: Int) -> Int {
        return items.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCountCell.reuseIdentifier, for: indexPath)

        guard let item = items[safe: indexPath.row] else {
            owsFailDebug("Invalid index path: \(indexPath)")
            return cell
        }

        guard let emojiCell = cell as? EmojiCountCell else {
            owsFailDebug("unexpected cell type")
            return cell
        }

        emojiCell.configure(with: item)

        return emojiCell
    }
}

class EmojiCountCell: UICollectionViewCell {
    let emoji = UILabel()
    let count = UILabel()

    static let reuseIdentifier = "EmojiCountCell"

    override init(frame: CGRect) {
        super.init(frame: .zero)

        contentView.layoutMargins = UIEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)

        let selectedBackground = UIView()
        selectedBackground.backgroundColor = (Theme.isDarkThemeEnabled
            ? UIColor.ows_gray60
            : UIColor.ows_gray05)
        selectedBackgroundView = selectedBackground

        emoji.font = .systemFont(ofSize: 22)
        emoji.setContentHuggingHigh()
        emoji.setCompressionResistanceHigh()
        contentView.addSubview(emoji)
        emoji.autoPinLeadingToSuperviewMargin()
        emoji.autoPinHeightToSuperviewMargins()

        count.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold().ows_monospaced()
        count.textColor = Theme.primaryTextColor
        count.setContentHuggingHigh()
        count.setCompressionResistanceHigh()
        contentView.addSubview(count)
        count.autoPinLeading(toTrailingEdgeOf: emoji, offset: 4)
        count.autoPinTrailingToSuperviewMargin()
        count.autoPinHeightToSuperviewMargins()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with item: EmojiItem) {
        emoji.text = item.emoji
        count.text = item.count.abbreviatedString
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        selectedBackgroundView?.layer.cornerRadius = height() / 2
    }
}
