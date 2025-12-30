//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol EmojiPickerSectionToolbarDelegate: AnyObject {
    func emojiPickerSectionToolbar(_ sectionToolbar: EmojiPickerSectionToolbar, didSelectSection: Int)
    func emojiPickerSectionToolbarShouldShowRecentsSection(_ sectionToolbar: EmojiPickerSectionToolbar) -> Bool
}

class EmojiPickerSectionToolbar: UIView, UICollectionViewDelegate {
    private var buttons = [UIButton]()

    private weak var delegate: EmojiPickerSectionToolbarDelegate?

    private enum Section {
        case main
    }

    private var dataSource: UICollectionViewDiffableDataSource<Section, ThemeIcon>!
    private var collectionView: UICollectionView!

    private static let collectionViewSectionMargin: CGFloat = 4

    private struct EmojiSectionCellContentViewConfiguration: UIContentConfiguration {
        let emojiSectionIcon: ThemeIcon
        var displayBackgroundView: Bool = false

        func makeContentView() -> UIView & UIContentView {
            return EmojiSectionCellContentView(configuration: self)
        }

        func updated(for state: any UIConfigurationState) -> EmojiSectionCellContentViewConfiguration {
            guard let cellState = state as? UICellConfigurationState else {
                return self
            }
            var configuration = self
            configuration.displayBackgroundView = cellState.isSelected
            return configuration
        }
    }

    private class EmojiSectionCellContentView: UIView, UIContentView {
        var configuration: UIContentConfiguration {
            didSet {
                configure()
            }
        }

        private let backgroundView = UIView()
        private let imageView = UIImageView()
        private static let imageSize: CGFloat = 22
        static let viewSize: CGFloat = 40

        init(configuration: EmojiSectionCellContentViewConfiguration) {
            self.configuration = configuration

            super.init(frame: .zero)

            // Use simple opaque UIView as part of the content view because
            // UIBackgroundConfiguration wasn't updating reliably.
            // Background will be using the color of images in unselected cells.
            addSubview(backgroundView)
            backgroundView.backgroundColor = UIColor.Signal.secondaryFill

            addSubview(imageView)
            imageView.contentMode = .scaleAspectFill
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: EmojiSectionCellContentView.imageSize),
                imageView.heightAnchor.constraint(equalToConstant: EmojiSectionCellContentView.imageSize),
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])

            configure()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            let circleSize = min(bounds.width, bounds.height)
            backgroundView.center = bounds.center
            backgroundView.bounds = CGRect(x: 0, y: 0, width: circleSize, height: circleSize)
            backgroundView.layer.cornerRadius = 0.5 * circleSize
        }

        private func configure() {
            guard let configuration = configuration as? EmojiSectionCellContentViewConfiguration else {
                return
            }
            backgroundView.isHidden = !configuration.displayBackgroundView
            imageView.image = Theme.iconImage(configuration.emojiSectionIcon)
            if #available(iOS 26, *), BuildFlags.iOS26SDKIsAvailable {
                imageView.tintColor = UIColor.Signal.label
            } else {
                imageView.tintColor = UIColor.Signal.secondaryLabel
            }
        }
    }

    init(
        delegate: EmojiPickerSectionToolbarDelegate,
    ) {
        self.delegate = delegate

        super.init(frame: .zero)

        // Prepare icons.
        var emojiSectionIcons: [ThemeIcon] = [
            .emojiSmiley,
            .emojiAnimal,
            .emojiFood,
            .emojiActivity,
            .emojiTravel,
            .emojiObject,
            .emojiSymbol,
            .emojiFlag,
        ]
        if delegate.emojiPickerSectionToolbarShouldShowRecentsSection(self) == true {
            emojiSectionIcons.insert(.emojiRecent, at: 0)
        }

        // Create and configure collection view.
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: Self.buildCollectionViewLayout(numberOfItems: emojiSectionIcons.count))
        collectionView.delegate = self
        collectionView.backgroundColor = .clear
        collectionView.allowsMultipleSelection = false
        collectionView.alwaysBounceVertical = false
        collectionView.insetsLayoutMarginsFromSafeArea = true
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        let collectionViewHeight = EmojiSectionCellContentView.viewSize + 2 * Self.collectionViewSectionMargin
        collectionView.addConstraint(collectionView.heightAnchor.constraint(equalToConstant: collectionViewHeight))

        // Prepare background.
        var backgroundConfigured = false
#if compiler(>=6.2)
        if #available(iOS 26, *) {
            // Floating glass panel that encapsulates emoji category strip.
            // Insets are carefully configured for best on-screen appearance.
            let glassEffectView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
            glassEffectView.translatesAutoresizingMaskIntoConstraints = false
            glassEffectView.cornerConfiguration = .capsule()
            addSubview(glassEffectView)
            NSLayoutConstraint.activate([
                glassEffectView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor, constant: -1),
                glassEffectView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor, constant: 1),
                glassEffectView.topAnchor.constraint(equalTo: topAnchor, constant: -2),
                glassEffectView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: 0),
            ])

            glassEffectView.clipsToBounds = true
            glassEffectView.contentView.addSubview(collectionView)
            NSLayoutConstraint.activate([
                collectionView.leadingAnchor.constraint(equalTo: glassEffectView.leadingAnchor),
                collectionView.trailingAnchor.constraint(equalTo: glassEffectView.trailingAnchor),
                collectionView.topAnchor.constraint(equalTo: glassEffectView.topAnchor),
                collectionView.bottomAnchor.constraint(equalTo: glassEffectView.bottomAnchor),
            ])
            backgroundConfigured = true
        }
#endif
        if !backgroundConfigured {
            // Background stretches 500 dp below bottom edge of the screen so that there's no gap where bottom safe area is.
            if UIAccessibility.isReduceTransparencyEnabled {
                let backgroundView = UIView()
                backgroundView.backgroundColor = UIColor.Signal.background
                addSubview(backgroundView)
                backgroundView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    backgroundView.topAnchor.constraint(equalTo: topAnchor),
                    backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
                    backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 500),
                    backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
                ])

                addSubview(collectionView)
            } else {
                let blurEffect = UIBlurEffect(style: .regular)
                let blurEffectView = UIVisualEffectView(effect: blurEffect)
                addSubview(blurEffectView)
                blurEffectView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    blurEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
                    blurEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
                    blurEffectView.topAnchor.constraint(equalTo: topAnchor),
                    blurEffectView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 500),
                ])
                blurEffectView.contentView.addSubview(collectionView)
            }

            NSLayoutConstraint.activate([
                collectionView.topAnchor.constraint(equalTo: topAnchor),
                collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
                collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
                collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }

        // Configure data source.
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        dataSource = UICollectionViewDiffableDataSource<Section, ThemeIcon>(
            collectionView: collectionView,
        ) { collectionView, indexPath, itemIdentifier -> UICollectionViewCell? in

            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
            cell.automaticallyUpdatesContentConfiguration = true
            cell.contentConfiguration = EmojiSectionCellContentViewConfiguration(emojiSectionIcon: itemIdentifier)

            return cell
        }

        // Populate collection view with data.
        var snapshot = NSDiffableDataSourceSnapshot<Section, ThemeIcon>()
        snapshot.appendSections([.main])
        snapshot.appendItems(emojiSectionIcons)
        dataSource.apply(snapshot, animatingDifferences: false)

        setSelectedSection(0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Collection View

    private class func buildCollectionViewLayout(numberOfItems: Int) -> UICollectionViewLayout {
        let cellSize = EmojiSectionCellContentView.viewSize

        let layout = UICollectionViewCompositionalLayout { _, environment in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .absolute(cellSize),
                heightDimension: .absolute(cellSize),
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let availableWidth = environment.container.effectiveContentSize.width - (collectionViewSectionMargin * 2)

            let totalSpacing = collectionViewSectionMargin * CGFloat(numberOfItems - 1)
            let minimumWidth = CGFloat(numberOfItems) * cellSize + totalSpacing

            if minimumWidth <= availableWidth {
                let groupSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(cellSize),
                )
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitem: item, count: numberOfItems)
                group.interItemSpacing = .fixed(collectionViewSectionMargin)

                let section = NSCollectionLayoutSection(group: group)
                section.orthogonalScrollingBehavior = .none
                section.contentInsets = NSDirectionalEdgeInsets(margin: collectionViewSectionMargin)
                return section
            } else {
                let groupSize = NSCollectionLayoutSize(
                    widthDimension: .absolute(cellSize),
                    heightDimension: .absolute(cellSize),
                )
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

                let section = NSCollectionLayoutSection(group: group)
                section.orthogonalScrollingBehavior = .continuous
                section.interGroupSpacing = collectionViewSectionMargin
                section.contentInsets = .init(
                    hMargin: collectionViewSectionMargin * 2,
                    vMargin: collectionViewSectionMargin,
                )
                return section
            }
        }

        return layout
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
        delegate?.emojiPickerSectionToolbar(self, didSelectSection: indexPath.item)
    }

    // MARK: Selection

    func setSelectedSection(_ section: Int) {
        collectionView.selectItem(
            at: IndexPath(item: section, section: 0),
            animated: true,
            scrollPosition: .centeredHorizontally,
        )
    }
}
