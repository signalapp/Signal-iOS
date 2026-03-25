//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// A picker for emoji and sticker reactions. If you want just emoji, use ``EmojiPickerSheet``.
class ReactionPickerSheet: OWSViewController, StickerPickerViewDelegate {

    private let message: TSMessage?
    private let completionHandler: (CustomReactionItem?) -> Void
    private let allowReactionConfiguration: Bool
    private let reactionPickerConfigurationListener: ReactionPickerConfigurationListener?

    private lazy var stickerPickerView = StickerPickerView(delegate: self)
    private lazy var emojiCollectionView = EmojiPickerCollectionView(message: message)
    private lazy var sectionToolbar = EmojiPickerSectionToolbar(delegate: self)

    private lazy var emojiSearchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = OWSLocalizedString(
            "SEARCH_FIELD_PLACE_HOLDER_TEXT",
            comment: "placeholder text in an empty search field"
        )
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        return searchBar
    }()

    private lazy var configureButton: UIButton = {
        let button = UIButton()
        button.setImage(Theme.iconImage(.emojiSettings), for: .normal)
        button.tintColor = .Signal.label
        button.addTarget(self, action: #selector(didSelectConfigureButton), for: .touchUpInside)
        return button
    }()

    private lazy var segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: [
            OWSLocalizedString(
                "REACTION_PICKER_EMOJI_TAB",
                comment: "Title for the emoji tab in the reaction picker."
            ),
            OWSLocalizedString(
                "REACTION_PICKER_STICKERS_TAB",
                comment: "Title for the stickers tab in the reaction picker."
            ),
        ])
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        return control
    }()

    private var emojiContainerView = UIView()
    private var stickerContainerView = UIView()

    init(
        message: TSMessage?,
        allowReactionConfiguration: Bool = true,
        reactionPickerConfigurationListener: ReactionPickerConfigurationListener? = nil,
        completionHandler: @escaping (CustomReactionItem?) -> Void,
    ) {
        self.message = message
        self.allowReactionConfiguration = allowReactionConfiguration
        self.reactionPickerConfigurationListener = reactionPickerConfigurationListener
        self.completionHandler = completionHandler
        super.init()

        sheetPresentationController?.detents = [.medium(), .large()]
        sheetPresentationController?.prefersGrabberVisible = true
        sheetPresentationController?.delegate = self
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if #available(iOS 17.0, *), self.overrideUserInterfaceStyle == .dark {
            sheetPresentationController?.traitOverrides.userInterfaceStyle = .dark
        }

        if #available(iOS 26, *) {
            view.backgroundColor = nil
        } else {
            view.backgroundColor = .tertiarySystemBackground
        }

        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmentedControl)
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(
                equalTo: view.topAnchor,
                constant: 20
            ),
            segmentedControl.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: 16
            ),
            segmentedControl.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -16
            ),
        ])

        emojiContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emojiContainerView)
        NSLayoutConstraint.activate([
            emojiContainerView.topAnchor.constraint(
                equalTo: segmentedControl.bottomAnchor,
                constant: 8
            ),
            emojiContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emojiContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emojiContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let topBarView = UIStackView()
        topBarView.axis = .horizontal
        topBarView.isLayoutMarginsRelativeArrangement = true
        topBarView.spacing = 8
        if allowReactionConfiguration {
            topBarView.layoutMargins = UIEdgeInsets(
                top: 0,
                leading: 0,
                bottom: 0,
                trailing: 16
            )
            topBarView.addArrangedSubviews([emojiSearchBar, configureButton])
        } else {
            topBarView.addArrangedSubview(emojiSearchBar)
        }
        topBarView.translatesAutoresizingMaskIntoConstraints = false
        emojiContainerView.addSubview(topBarView)
        NSLayoutConstraint.activate([
            topBarView.topAnchor.constraint(equalTo: emojiContainerView.topAnchor),
            topBarView.leadingAnchor.constraint(
                equalTo: emojiContainerView.leadingAnchor,
                constant: 8
            ),
            topBarView.trailingAnchor.constraint(
                equalTo: emojiContainerView.trailingAnchor,
                constant: -8
            ),
        ])

        emojiCollectionView.pickerDelegate = self
        emojiCollectionView.alwaysBounceVertical = true
        emojiCollectionView.translatesAutoresizingMaskIntoConstraints = false
        emojiContainerView.addSubview(emojiCollectionView)
        NSLayoutConstraint.activate([
            emojiCollectionView.topAnchor.constraint(equalTo: topBarView.bottomAnchor),
            emojiCollectionView.leadingAnchor.constraint(
                equalTo: emojiContainerView.leadingAnchor
            ),
            emojiCollectionView.trailingAnchor.constraint(
                equalTo: emojiContainerView.trailingAnchor
            ),
            emojiCollectionView.bottomAnchor.constraint(
                equalTo: emojiContainerView.bottomAnchor
            ),
        ])

        emojiContainerView.addSubview(sectionToolbar)
        sectionToolbar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sectionToolbar.leadingAnchor.constraint(equalTo: emojiContainerView.leadingAnchor),
            sectionToolbar.trailingAnchor.constraint(equalTo: emojiContainerView.trailingAnchor),
            sectionToolbar.bottomAnchor.constraint(
                equalTo: keyboardLayoutGuide.topAnchor,
                constant: -8
            ),
        ])

        // Obscures content underneath the emoji section toolbar to improve legibility.
        if #available(iOS 26, *) {
            let scrollInteraction = UIScrollEdgeElementContainerInteraction()
            scrollInteraction.scrollView = emojiCollectionView
            scrollInteraction.edge = .bottom
            sectionToolbar.addInteraction(scrollInteraction)
        }

        stickerContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stickerContainerView)
        NSLayoutConstraint.activate([
            stickerContainerView.topAnchor.constraint(
                equalTo: segmentedControl.bottomAnchor,
                constant: 8
            ),
            stickerContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stickerContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stickerContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let hMargin = OWSTableViewController2.cellHInnerMargin
        stickerPickerView.directionalLayoutMargins = .init(margin: hMargin)
        stickerPickerView.translatesAutoresizingMaskIntoConstraints = false
        stickerContainerView.addSubview(stickerPickerView)
        NSLayoutConstraint.activate([
            stickerPickerView.topAnchor.constraint(equalTo: stickerContainerView.topAnchor),
            stickerPickerView.leadingAnchor.constraint(
                equalTo: stickerContainerView.leadingAnchor
            ),
            stickerPickerView.trailingAnchor.constraint(
                equalTo: stickerContainerView.trailingAnchor
            ),
            stickerPickerView.bottomAnchor.constraint(
                equalTo: stickerContainerView.bottomAnchor
            ),
        ])

        // Set initial state.
        segmentChanged()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.layoutIfNeeded()

        let bottomInset = sectionToolbar.height - sectionToolbar.safeAreaInsets.bottom
        let contentInset = UIEdgeInsets(top: 0, leading: 0, bottom: bottomInset, trailing: 0)
        emojiCollectionView.contentInset = contentInset
        emojiCollectionView.scrollIndicatorInsets = contentInset
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        stickerPickerView.willBePresented()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        stickerPickerView.wasPresented()
    }

    @objc
    private func didSelectConfigureButton(sender: UIButton) {
        let configVC = CustomReactionPickerConfigViewController(
            reactionPickerConfigurationListener: self.reactionPickerConfigurationListener,
        )
        let navController = UINavigationController(rootViewController: configVC)
        if overrideUserInterfaceStyle == .dark {
            navController.overrideUserInterfaceStyle = .dark
        }
        self.present(navController, animated: true)
    }

    @objc
    private func segmentChanged() {
        let showStickers = segmentedControl.selectedSegmentIndex == 1
        emojiContainerView.isHidden = showStickers
        stickerContainerView.isHidden = !showStickers
        if showStickers {
            emojiSearchBar.resignFirstResponder()
        }
    }

    private func maximizeHeight() {
        sheetPresentationController?.animateChanges {
            sheetPresentationController?.selectedDetentIdentifier = .large
        }
    }

    // MARK: StickerPickerViewDelegate

    func didSelectSticker(_ stickerInfo: StickerInfo) {
        ImpactHapticFeedback.impactOccurred(style: .light)
        // Look up the sticker's associated emoji so we can build a complete CustomReactionItem.
        let emoji: String = SSKEnvironment.shared.databaseStorageRef.read { tx in
            StickerManager.installedStickerMetadata(
                stickerInfo: stickerInfo,
                transaction: tx
            )?.firstEmoji?.nilIfEmpty
        } ?? StickerManager.fallbackStickerEmoji
        let item = CustomReactionItem(emoji: emoji, sticker: stickerInfo)
        completionHandler(item)
        dismiss(animated: true)
    }

    func presentManageStickersView(for stickerPickerView: StickerPickerView) {
        let manageStickersView = ManageStickersViewController()
        let navigationController = OWSNavigationController(rootViewController: manageStickersView)
        present(navigationController, animated: true)
    }
}

// MARK: - EmojiPickerCollectionViewDelegate

extension ReactionPickerSheet: EmojiPickerCollectionViewDelegate {
    func emojiPicker(_ emojiPicker: EmojiPickerCollectionView, didSelectEmoji emoji: EmojiWithSkinTones) {
        completionHandler(CustomReactionItem(emoji: emoji.rawValue, sticker: nil))
        dismiss(animated: true)
    }

    func emojiPicker(_ emojiPicker: EmojiPickerCollectionView, didScrollToSection section: EmojiPickerSection) {
        switch section {
        case .messageEmoji:
            sectionToolbar.setSelectedSection(0)
        case .recentEmoji:
            sectionToolbar.setSelectedSection(0)
        case .emojiCategory(let categoryIndex):
            sectionToolbar.setSelectedSection(categoryIndex + (emojiPicker.hasRecentEmoji ? 1 : 0))
        }
    }
}

// MARK: - EmojiPickerSectionToolbarDelegate

extension ReactionPickerSheet: EmojiPickerSectionToolbarDelegate {
    func emojiPickerSectionToolbar(_ sectionToolbar: EmojiPickerSectionToolbar, didSelectSection section: Int) {
        let finalSection: EmojiPickerSection
        if section == 0, emojiCollectionView.hasRecentEmoji {
            finalSection = .recentEmoji
        } else {
            finalSection = .emojiCategory(categoryIndex: section - (emojiCollectionView.hasRecentEmoji ? 1 : 0))
        }
        if let searchText = emojiCollectionView.searchText, !searchText.isEmpty {
            emojiSearchBar.text = nil
            emojiCollectionView.searchText = nil
            emojiCollectionView.performBatchUpdates(nil) { _ in
                self.emojiCollectionView.scrollToSectionHeader(finalSection, animated: false)
            }
        } else {
            emojiCollectionView.scrollToSectionHeader(finalSection, animated: false)
        }
        maximizeHeight()
    }

    func emojiPickerSectionToolbarShouldShowRecentsSection(_ sectionToolbar: EmojiPickerSectionToolbar) -> Bool {
        return emojiCollectionView.hasRecentEmoji
    }

    func emojiPickerWillBeginDragging(_ emojiPicker: EmojiPickerCollectionView) {
        emojiSearchBar.resignFirstResponder()
    }
}

// MARK: - UISheetPresentationControllerDelegate

extension ReactionPickerSheet: UISheetPresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        completionHandler(nil)
    }
}

// MARK: - UISearchBarDelegate

extension ReactionPickerSheet: UISearchBarDelegate {
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        maximizeHeight()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        emojiCollectionView.searchText = searchText
    }
}
