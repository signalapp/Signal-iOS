//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// MARK: - EmojiPickerSheet

class EmojiPickerSheet: OWSViewController {
    let completionHandler: (EmojiWithSkinTones?) -> Void

    let collectionView: EmojiPickerCollectionView
    lazy var sectionToolbar = EmojiPickerSectionToolbar(delegate: self)

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
        button.tintColor = UIColor.Signal.label

        button.addTarget(self, action: #selector(didSelectConfigureButton), for: .touchUpInside)
        return button
    }()

    private let reactionPickerConfigurationListener: ReactionPickerConfigurationListener?

    init(
        message: TSMessage?,
        allowReactionConfiguration: Bool = true,
        reactionPickerConfigurationListener: ReactionPickerConfigurationListener? = nil,
        completionHandler: @escaping (EmojiWithSkinTones?) -> Void,
    ) {
        self.allowReactionConfiguration = allowReactionConfiguration
        self.reactionPickerConfigurationListener = reactionPickerConfigurationListener
        self.completionHandler = completionHandler
        self.collectionView = EmojiPickerCollectionView(message: message)
        super.init()

        sheetPresentationController?.detents = [.medium(), .large()]
        sheetPresentationController?.prefersGrabberVisible = true
        sheetPresentationController?.delegate = self

        if #available(iOS 17.0, *), self.overrideUserInterfaceStyle == .dark {
            sheetPresentationController?.traitOverrides.userInterfaceStyle = .dark
        }
    }

    // MARK: -

    override func viewDidLoad() {
        super.viewDidLoad()

        if #available(iOS 26, *), BuildFlags.iOS26SDKIsAvailable {
            view.backgroundColor = nil
        } else {
            view.backgroundColor = .tertiarySystemBackground
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

        view.addSubview(topStackView)
        topStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topStackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 23),
            topStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            topStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
        ])

        collectionView.pickerDelegate = self
        collectionView.alwaysBounceVertical = true
        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        view.addSubview(sectionToolbar)
        sectionToolbar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sectionToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sectionToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sectionToolbar.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor, constant: -8),
        ])

#if compiler(>=6.2)
        // Obscures content underneath the emoji section toolbar to improve legibility.
        if #available(iOS 26, *) {
            let scrollInteraction = UIScrollEdgeElementContainerInteraction()
            scrollInteraction.scrollView = collectionView
            scrollInteraction.edge = .bottom
            sectionToolbar.addInteraction(scrollInteraction)
        }
#endif
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Ensure the scrollView's layout has completed
        // as we're about to use its bounds to calculate
        // the masking view and contentOffset.
        view.layoutIfNeeded()

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
            reactionPickerConfigurationListener: self.reactionPickerConfigurationListener,
        )
        let navController = UINavigationController(rootViewController: configVC)
        if overrideUserInterfaceStyle == .dark {
            navController.overrideUserInterfaceStyle = .dark
        }
        self.present(navController, animated: true)
    }

    private func maximizeHeight() {
        sheetPresentationController?.animateChanges {
            sheetPresentationController?.selectedDetentIdentifier = .large
        }
    }
}

// MARK: - EmojiPickerSectionToolbarDelegate

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

// MARK: - EmojiPickerCollectionViewDelegate

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

// MARK: - UISheetPresentationControllerDelegate

extension EmojiPickerSheet: UISheetPresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        completionHandler(nil)
    }
}

// MARK: - UISearchBarDelegate

extension EmojiPickerSheet: UISearchBarDelegate {
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        maximizeHeight()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        collectionView.searchText = searchText
    }
}
