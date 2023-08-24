//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class EmojiPickerSheet: InteractiveSheetViewController {
    override var interactiveScrollViews: [UIScrollView] { [collectionView] }

    override var dismissesWithHighVelocitySwipe: Bool { false }

    override var shrinksWithHighVelocitySwipe: Bool { false }

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
        button.tintColor = Theme.primaryIconColor

        button.addTarget(self, action: #selector(didSelectConfigureButton), for: .touchUpInside)
        return button
    }()

    override var sheetBackgroundColor: UIColor {
        Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_white
    }

    init(
        message: TSMessage?,
        allowReactionConfiguration: Bool = true,
        completionHandler: @escaping (EmojiWithSkinTones?) -> Void
    ) {
        self.allowReactionConfiguration = allowReactionConfiguration
        self.completionHandler = completionHandler
        self.collectionView = EmojiPickerCollectionView(message: message)
        super.init()

        if !allowReactionConfiguration {
            self.backdropColor = .clear
        }

        super.allowsExpansion = true
    }

    public required init() {
        fatalError("init() has not been implemented")
    }

    override func willDismissInteractively() {
        super.willDismissInteractively()
        completionHandler(nil)
    }

    // MARK: -

    override public func viewDidLoad() {
        super.viewDidLoad()

        let topStackView = UIStackView()
        topStackView.axis = .horizontal
        topStackView.isLayoutMarginsRelativeArrangement = true
        topStackView.spacing = 8

        if allowReactionConfiguration {
            topStackView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 16)
            topStackView.addArrangedSubviews([searchBar, configureButton])
        } else {
            topStackView.addArrangedSubview(searchBar)
        }

        contentView.addSubview(topStackView)

        topStackView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)

        contentView.addSubview(collectionView)
        collectionView.autoPinEdge(.top, to: .bottom, of: searchBar)
        collectionView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .top)
        collectionView.pickerDelegate = self
        collectionView.alwaysBounceVertical = true

        // NOTE: the toolbar is a subview of the keyboard layout view so it
        // properly animates as the keyboard rises. making it part of the content view
        // cancels those animations and makes it pop into place which looks bad.
        // might be worth ripping apart at some point.
        keyboardLayoutGuideView.addSubview(sectionToolbar)
        sectionToolbar.autoPinEdge(.leading, to: .leading, of: contentView)
        sectionToolbar.autoPinEdge(.trailing, to: .trailing, of: contentView)
        sectionToolbar.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideView)
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
        let configVC = EmojiReactionPickerConfigViewController()
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
