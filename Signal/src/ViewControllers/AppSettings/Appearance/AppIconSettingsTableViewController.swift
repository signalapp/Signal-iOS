//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol AppIconSettingsTableViewControllerDelegate: AnyObject {
    func didChangeIcon()
}

final class AppIconSettingsTableViewController: OWSViewController, UITextViewDelegate, UICollectionViewDelegate {

    // MARK: Static properties

    private static let appIcons: [AppIcon] = [
        .default,
        .white,
        .color,
        .night,
        .nightVariant,
        .chat,
        .bubbles,
        .yellow,
        .news,
        .notes,
        .weather,
        .waves,
    ]

    /// This URL itself is not used. The action is overridden in the text view delegate function.
    private static let learnMoreURL = URL(string: "https://support.signal.org/")!

    // MARK: Properties

    weak var iconDelegate: AppIconSettingsTableViewControllerDelegate?

    // MARK: View lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = OWSLocalizedString(
            "SETTINGS_APP_ICON_TITLE",
            comment: "The title for the app icon selection settings page.",
        )
        view.backgroundColor = .Signal.groupedBackground

        // Collection view.
        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: appIconCollectionViewGridLayout(),
        )
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.contentInset.top = 18 // add some padding below the navigation bar
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.collectionView = collectionView

        // Cells.
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewCell, AppIcon> { cell, indexPath, item in
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = AppIconCellContentConfiguration(appIcon: item).updated(for: state)
            }
        }
        dataSource = UICollectionViewDiffableDataSource<Section, AppIcon>(
            collectionView: collectionView,
        ) { collectionView, indexPath, itemIdentifier in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: itemIdentifier)
        }

        // Footer: added to an empty section so that it's displayed outside of first section's background.
        let footerRegistration = UICollectionView.SupplementaryRegistration<SectionFooterView>(elementKind: UICollectionView.elementKindSectionFooter) {
            [unowned self] supplementaryView, _, _ in
            let text = NSAttributedString.composed(of: [
                OWSLocalizedString(
                    "SETTINGS_APP_ICON_FOOTER",
                    comment: "The footer for the app icon selection settings page.",
                ),
                "\n",
                CommonStrings.learnMore.styled(with: .link(Self.learnMoreURL)),
            ])
            supplementaryView.configure(text: text, textViewDelegate: self)
        }
        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            guard kind == UICollectionView.elementKindSectionFooter, indexPath.section > 0 else { return nil }
            return collectionView.dequeueConfiguredReusableSupplementary(
                using: footerRegistration,
                for: indexPath,
            )
        }

        // Data.
        var snapshot = NSDiffableDataSourceSnapshot<Section, AppIcon>()
        snapshot.appendSections([.main, .empty])
        snapshot.appendItems(Self.appIcons, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: false)

        // Select current icon.
        updateSelection(animated: false)
    }

    private func didTapLearnMore() {
        let learnMoreViewController = AppIconLearnMoreTableViewController()
        let navigationController = OWSNavigationController(rootViewController: learnMoreViewController)
        presentFormSheet(navigationController, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let appIcon = dataSource.itemIdentifier(for: indexPath) else {
            owsFailDebug("Could not find app icon.")
            return
        }

        guard UIApplication.shared.currentAppIcon != appIcon else { return }

        UIApplication.shared.setAlternateIconName(appIcon.alternateIconName) { error in
            if let error {
                owsFailDebug("Failed to update app icon: \(error)")
                // Restore previous icon.
                self.updateSelection(animated: true)
            }
        }
        iconDelegate?.didChangeIcon()
    }

    private func updateSelection(animated: Bool) {
        guard let collectionView else { return }

        let snapshot = dataSource.snapshot()
        guard
            let sectionIndex = snapshot.indexOfSection(.main),
            let itemIndex = snapshot.indexOfItem(UIApplication.shared.currentAppIcon) else { return }

        collectionView.selectItem(
            at: IndexPath(item: itemIndex, section: sectionIndex),
            animated: animated,
            scrollPosition: .centeredVertically,
        )
    }

    private enum Section {
        case main
        case empty
    }

    private var collectionView: UICollectionView?

    private var dataSource: UICollectionViewDiffableDataSource<Section, AppIcon>!

    private func appIconCollectionViewGridLayout() -> UICollectionViewLayout {
        let spacing: CGFloat = 20
        let minColumns: Int = 4
        let approxIconSize: CGFloat = 68
        let sectionInsets = NSDirectionalEdgeInsets(hMargin: 20, vMargin: 20)

        let collectionViewLayout = UICollectionViewCompositionalLayout { sectionIndex, environment in
            // Empty section with a footer only.
            if sectionIndex > 0 {
                // Configuration doesn't really matter because there would be no items in these sections.
                let itemSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(44),
                )
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: itemSize, subitems: [item])
                let section = NSCollectionLayoutSection(group: group)

                // This section would only have a footer.
                let footerSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(36),
                )
                let footer = NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: footerSize,
                    elementKind: UICollectionView.elementKindSectionFooter,
                    alignment: .bottomLeading,
                )
                section.boundarySupplementaryItems = [footer]

                return section
            }

            // Calculate item size given that it's going to be approx. 68 pts and there would be at least 4 columns.
            let containerWidth = environment.container.effectiveContentSize.width - sectionInsets.totalWidth

            let rawColumns = ((containerWidth + spacing) / (approxIconSize + spacing)).rounded(.toNearestOrAwayFromZero)
            let columns = max(minColumns, Int(rawColumns))

            let totalSpacing = spacing * CGFloat(columns - 1)
            let itemWidth = (containerWidth - totalSpacing) / CGFloat(columns)

            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1 / CGFloat(columns)),
                heightDimension: .fractionalHeight(1),
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(itemWidth),
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            group.interItemSpacing = .fixed(spacing)

            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = spacing
            section.contentInsets = sectionInsets

            // Background
            let backgroundItem = NSCollectionLayoutDecorationItem.background(
                elementKind: SectionBackgroundView.elementKind,
            )
            section.decorationItems = [backgroundItem]

            return section
        }
        collectionViewLayout.register(SectionBackgroundView.self, forDecorationViewOfKind: SectionBackgroundView.elementKind)
        return collectionViewLayout
    }

    private struct AppIconCellContentConfiguration: UIContentConfiguration {
        let appIcon: AppIcon
        var showBorder: Bool = false

        func makeContentView() -> any UIView & UIContentView {
            AppIconCellContentView(configuration: self)
        }

        func updated(for state: any UIConfigurationState) -> AppIconCellContentConfiguration {
            guard let cellState = state as? UICellConfigurationState else {
                return self
            }
            var configuration = self
            configuration.showBorder = cellState.isSelected
            return configuration
        }
    }

    private class AppIconCellContentView: UIView, UIContentView {
        var configuration: UIContentConfiguration {
            didSet {
                configure()
            }
        }

        private let backgroundView = UIView()
        private let imageView = UIImageView()
        private static let imageSize: CGFloat = 22
        static let viewSize: CGFloat = 40

        init(configuration: AppIconCellContentConfiguration) {
            self.configuration = configuration

            super.init(frame: .zero)

            directionalLayoutMargins = .zero
            clipsToBounds = true
            layer.cornerCurve = .continuous

            addSubview(imageView)
            imageView.clipsToBounds = true
            imageView.contentMode = .scaleAspectFill
            imageView.layer.cornerCurve = .continuous
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
                imageView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            ])

            configure()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)

            if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
                configure()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            layer.cornerRadius = bounds.size.smallerAxis * 0.24 * (4 / 3)
            imageView.layer.cornerRadius = imageView.frame.size.smallerAxis * 0.24 * (4 / 3)
        }

        private func configure() {
            guard let configuration = configuration as? AppIconCellContentConfiguration else { return }

            imageView.image = UIImage(resource: configuration.appIcon.previewImageResource)
            directionalLayoutMargins = .init(margin: configuration.showBorder ? 4 : 0) // offset image from edges
            layer.borderWidth = configuration.showBorder ? 3 : 0
            layer.borderColor = UIColor(light: .black, dark: .ows_gray05).cgColor
        }
    }

    private class SectionBackgroundView: UICollectionReusableView {
        static let elementKind = "SectionBackgroundView"

        override init(frame: CGRect) {
            super.init(frame: frame)

            backgroundColor = .Signal.secondaryGroupedBackground
            layer.cornerRadius = OWSTableViewController2.cellRounding
            layer.masksToBounds = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    private class SectionFooterView: UICollectionReusableView {
        private let textView = LinkingTextView()

        override init(frame: CGRect) {
            super.init(frame: frame)

            textView.textColor = OWSTableViewController2.defaultFooterTextColor
            textView.font = OWSTableViewController2.defaultFooterFont
            textView.linkTextAttributes = [.foregroundColor: UIColor.Signal.label]
            textView.textContainerInset = UIEdgeInsets(
                hMargin: OWSTableViewController2.cellHInnerMargin,
                vMargin: 12,
            )
            textView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(textView)
            NSLayoutConstraint.activate([
                textView.topAnchor.constraint(equalTo: topAnchor),
                textView.leadingAnchor.constraint(equalTo: leadingAnchor),
                textView.trailingAnchor.constraint(equalTo: trailingAnchor),
                textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func configure(text: NSAttributedString, textViewDelegate: UITextViewDelegate) {
            textView.delegate = textViewDelegate
            textView.attributedText = text.styled(with: OWSTableViewController2.defaultFooterTextStyle)
        }
    }

    // MARK: UITextViewDelegate

    func textView(_ textView: UITextView, shouldInteractWith url: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        if url == Self.learnMoreURL {
            didTapLearnMore()
        }
        return false
    }
}
