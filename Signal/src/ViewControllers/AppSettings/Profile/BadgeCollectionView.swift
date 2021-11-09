//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import SignalUI
import UIKit

protocol BadgeCollectionDataSource: AnyObject {
    var availableBadges: [ProfileBadge] { get }
    var selectedBadgeIndex: Int? { get set }
}

class BadgeCollectionView: UICollectionView {
    weak private var badgeDataSource: BadgeCollectionDataSource?

    private let reuseIdentifier = "BadgeCollectionViewCell"
    private let flowLayout: UICollectionViewFlowLayout = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 12
        layout.minimumInteritemSpacing = 2
        layout.scrollDirection = .vertical
        return layout
    }()

    init(dataSource: BadgeCollectionDataSource) {
        super.init(frame: .zero, collectionViewLayout: flowLayout)
        register(BadgeCollectionViewCell.self, forCellWithReuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        badgeDataSource = dataSource
        self.dataSource = self
        self.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Sizing
    // For now, the number of badges is small enough that there's no need to enable scrolling
    // Instead, let's just pin the intrinsic height to the size of its content so autolayout
    // sizes us appropriately.

    override func reloadData() {
        super.reloadData()
        _cellSize = nil
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize { contentSize }
    override var contentSize: CGSize {
        didSet {
            if contentSize != oldValue {
                _cellSize = nil
                invalidateIntrinsicContentSize()
            }
        }
    }
    override var bounds: CGRect {
        didSet {
            if bounds != oldValue {
                _cellSize = nil
                invalidateIntrinsicContentSize()
            }
        }
    }

    var _cellSize: CGSize?
    var cellSize: CGSize {
        return _cellSize ?? {
            let badges = badgeDataSource?.availableBadges ?? []

            // If we only have one cell, its width can be the size of the view
            let availableWidth = bounds.inset(by: layoutMargins).size.width
            let cellWidth: CGFloat = (badges.count > 1) ? 78 : availableWidth

            // For the height, some cells may have a multiline name label. In that case, we want
            // the cells to all size to match the largest height
            let testCell = BadgeCollectionViewCell(frame: .zero)
            let cellHeights: [CGFloat] = badges.map {
                testCell.prepareForReuse()
                testCell.applyBadge($0)
                let fittingSize = testCell.sizeThatFits(.init(width: cellWidth, height: .infinity))
                return fittingSize.height
            }
            let maxHeight = cellHeights.max() ?? 0
            let size = CGSize(width: cellWidth, height: maxHeight)
            _cellSize = size
            return size
        }()
    }
}

extension BadgeCollectionView: UICollectionViewDelegateFlowLayout, UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView === self, section == 0 {
            return badgeDataSource?.availableBadges.count ?? 0
        } else {
            return 0
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard collectionView === self else {
            owsFailDebug("Incorrect collection view")
            return collectionView.dequeueReusableCell(withReuseIdentifier: "unknown", for: indexPath)
        }

        let newCell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath)
        if let badgeCell = newCell as? BadgeCollectionViewCell,
           let badge = badgeDataSource?.availableBadges[safe: indexPath.item] {
            badgeCell.applyBadge(badge)
        } else {
            owsFailDebug("Invalid badge")
        }
        return newCell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        guard collectionView === self, collectionViewLayout === self.flowLayout else {
            owsFailDebug("Unexpected collection view")
            return .zero
        }
        return cellSize
    }
}

class BadgeCollectionViewCell: UICollectionViewCell {
    let badgeImageViewSize = CGSize.square(64)
    let badgeImageOffset: CGFloat = 8

    lazy var badgeImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.layer.minificationFilter = .trilinear
        imageView.autoSetDimensions(to: badgeImageViewSize)
        return imageView
    }()
    let badgeSubtitleView: UILabel = {
        let subtitle = UILabel()
        subtitle.font = .ows_dynamicTypeCaption1Clamped
        subtitle.numberOfLines = 3
        return subtitle
    }()

    override init(frame: CGRect) {
        super.init(frame: .zero)
        contentView.addSubview(badgeImageView)
        contentView.addSubview(badgeSubtitleView)

        badgeImageView.autoPinEdge(toSuperviewEdge: .top)
        badgeSubtitleView.autoPinEdge(.top, to: .bottom, of: badgeImageView, withOffset: badgeImageOffset)
        badgeSubtitleView.autoPinEdge(toSuperviewEdge: .bottom)

        badgeImageView.autoHCenterInSuperview()
        badgeImageView.autoPinWidthToSuperview(relation: .lessThanOrEqual)
        badgeSubtitleView.autoHCenterInSuperview()
        badgeSubtitleView.autoPinWidthToSuperview(relation: .lessThanOrEqual)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyBadge(_ badge: ProfileBadge) {
        badgeImageView.image = badge.assets?.universal160
        badgeSubtitleView.text = badge.localizedName
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        badgeImageView.image = nil
        badgeSubtitleView.text = nil
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let imageSize = badgeImageViewSize
        let labelFittingSize = badgeSubtitleView.sizeThatFits(size)

        let desiredWidth = max(imageSize.width, labelFittingSize.width)
        let fittingWidth = min(desiredWidth, size.width)

        let desiredHeight = imageSize.height + badgeImageOffset + labelFittingSize.height
        let fittingHeight = min(desiredHeight, size.height)

        return CGSize(width: fittingWidth, height: fittingHeight)
    }
}
