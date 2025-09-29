//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class EmojiPickerSheet: InteractiveSheetViewController {
    override var interactiveScrollViews: [UIScrollView] { [collectionView] }

    let completionHandler: (EmojiWithSkinTones?) -> Void

    let collectionView: EmojiPickerCollectionView
    lazy var sectionToolbar = EmojiPickerSectionToolbar(
        delegate: self,
        forceDarkTheme: self.forceDarkTheme
    )

    let allowReactionConfiguration: Bool

    lazy var searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = OWSLocalizedString("HOME_VIEW_CONVERSATION_SEARCHBAR_PLACEHOLDER", comment: "Placeholder text for search bar which filters conversations.")
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        return searchBar
    }()

    lazy var configureButton: UIButton = {
        let button = UIButton()

        button.setImage(Theme.iconImage(.emojiSettings), for: .normal)
        button.tintColor = self.forceDarkTheme ? Theme.darkThemeNavbarIconColor : Theme.primaryIconColor

        button.addTarget(self, action: #selector(didSelectConfigureButton), for: .touchUpInside)
        return button
    }()

    private let forceDarkTheme: Bool

    private let reactionPickerConfigurationListener: ReactionPickerConfigurationListener?

    override var sheetBackgroundColor: UIColor {
        (Theme.isDarkThemeEnabled || forceDarkTheme) ? .ows_gray80 : .ows_white
    }

    init(
        message: TSMessage?,
        allowReactionConfiguration: Bool = true,
        forceDarkTheme: Bool = false,
        reactionPickerConfigurationListener: ReactionPickerConfigurationListener? = nil,
        completionHandler: @escaping (EmojiWithSkinTones?) -> Void
    ) {
        self.allowReactionConfiguration = allowReactionConfiguration
        self.forceDarkTheme = forceDarkTheme
        self.reactionPickerConfigurationListener = reactionPickerConfigurationListener
        self.completionHandler = completionHandler
        self.collectionView = EmojiPickerCollectionView(
            message: message,
            forceDarkTheme: forceDarkTheme
        )
        super.init()

        if !allowReactionConfiguration {
            self.backdropColor = .clear
        }

        self.animationsShouldBeInterruptible = true
        super.allowsExpansion = true
    }

    override func willDismissInteractively() {
        super.willDismissInteractively()
        completionHandler(nil)
    }

    // MARK: -

    override public func viewDidLoad() {
        super.viewDidLoad()

        if self.forceDarkTheme {
            self.overrideUserInterfaceStyle = .dark
        }

        let topStackView = UIStackView()
        topStackView.axis = .horizontal
        topStackView.isLayoutMarginsRelativeArrangement = true
        topStackView.spacing = 8
        if allowReactionConfiguration {
            topStackView.layoutMargins = UIEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16)
            topStackView.addArrangedSubviews([searchBar, configureButton])
        } else {
            topStackView.addArrangedSubview(searchBar)
        }
        contentView.addSubview(topStackView)
        topStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topStackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            topStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            topStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        collectionView.pickerDelegate = self
        collectionView.alwaysBounceVertical = true
        contentView.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topStackView.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        contentView.addSubview(sectionToolbar)
        sectionToolbar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sectionToolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sectionToolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            sectionToolbar.bottomAnchor.constraint(equalTo: contentView.keyboardLayoutGuide.topAnchor),
        ])

#if compiler(>=6.2)
        // Obscures content underneath the emoji section toolbar to improve legibility.
        if #available(iOS 26, *), FeatureFlags.iOS26SDKIsAvailable {
            let scrollInteraction = UIScrollEdgeElementContainerInteraction()
            scrollInteraction.scrollView = collectionView
            scrollInteraction.edge = .bottom
            sectionToolbar.addInteraction(scrollInteraction)
        }
#endif
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.collectionView.reloadData()
        }, completion: nil)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Ensure the scrollView's layout has completed
        // as we're about to use its bounds to calculate
        // the masking view and contentOffset.
        contentView.layoutIfNeeded()

        // Ensure you can scroll to the last emoji without
        // them being stuck behind the toolbar.
        let bottomInset = sectionToolbar.height - sectionToolbar.safeAreaInsets.bottom
        let contentInset = UIEdgeInsets(top: 0, leading: 0, bottom: bottomInset, trailing: 0)
        collectionView.contentInset = contentInset
        collectionView.scrollIndicatorInsets = contentInset
    }

    @objc
    private func didSelectConfigureButton(sender: UIButton) {
        let configVC = EmojiReactionPickerConfigViewController(
            forceDarkTheme: self.forceDarkTheme,
            reactionPickerConfigurationListener: self.reactionPickerConfigurationListener
        )
        let navController = UINavigationController(rootViewController: configVC)
        self.present(navController, animated: true)
    }
}

extension EmojiPickerSheet: EmojiPickerSectionToolbarDelegate {
    func emojiPickerSectionToolbar(_ sectionToolbar: EmojiPickerSectionToolbar, didSelectSection section: Int) {
        let finalSection: EmojiPickerSection
        if section == 0, collectionView.hasRecentEmoji {
            finalSection = .recentEmoji
        } else {
            finalSection = .emojiCategory(categoryIndex: section - (collectionView.hasRecentEmoji ? 1 : 0))
        }
        if let searchText = collectionView.searchText, !searchText.isEmpty {
            searchBar.text = nil
            collectionView.searchText = nil

            // Collection view needs a moment to reload.
            // Do empty batch of updates to postpone scroll until collection view has updated.
            collectionView.performBatchUpdates(nil) { _ in
                self.collectionView.scrollToSectionHeader(finalSection, animated: false)
            }
        } else {
            collectionView.scrollToSectionHeader(finalSection, animated: false)
        }

        maximizeHeight()
    }

    func emojiPickerSectionToolbarShouldShowRecentsSection(_ sectionToolbar: EmojiPickerSectionToolbar) -> Bool {
        return collectionView.hasRecentEmoji
    }

    func emojiPickerWillBeginDragging(_ emojiPicker: EmojiPickerCollectionView) {
        searchBar.resignFirstResponder()
    }
}

extension EmojiPickerSheet: EmojiPickerCollectionViewDelegate {
    func emojiPicker(_ emojiPicker: EmojiPickerCollectionView, didSelectEmoji emoji: EmojiWithSkinTones) {
        ImpactHapticFeedback.impactOccurred(style: .light)
        completionHandler(emoji)
        dismiss(animated: true)
    }

    func emojiPicker(_ emojiPicker: EmojiPickerCollectionView, didScrollToSection section: EmojiPickerSection) {
        switch section {
        case .messageEmoji:
            // No section for message emoji; just select the recent emoji.
            sectionToolbar.setSelectedSection(0)
        case .recentEmoji:
            sectionToolbar.setSelectedSection(0)
        case .emojiCategory(let categoryIndex):
            sectionToolbar.setSelectedSection(categoryIndex + (emojiPicker.hasRecentEmoji ? 1 : 0))
        }
    }
}

extension EmojiPickerSheet: UISearchBarDelegate {
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        maximizeHeight()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        collectionView.searchText = searchText
    }
}
