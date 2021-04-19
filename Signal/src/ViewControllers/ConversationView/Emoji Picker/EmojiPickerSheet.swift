//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class EmojiPickerSheet: InteractiveSheetViewController {
    override var interactiveScrollViews: [UIScrollView] { [collectionView] }

    let completionHandler: (EmojiWithSkinTones?) -> Void

    let collectionView = EmojiPickerCollectionView()
    lazy var sectionToolbar = EmojiPickerSectionToolbar(delegate: self)

    init(completionHandler: @escaping (EmojiWithSkinTones?) -> Void) {
        self.completionHandler = completionHandler
        super.init()
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

        contentView.addSubview(collectionView)
        collectionView.autoPinEdgesToSuperviewEdges()
        collectionView.pickerDelegate = self

        contentView.addSubview(sectionToolbar)
        sectionToolbar.autoPinWidthToSuperview()
        sectionToolbar.autoPinEdge(toSuperviewEdge: .bottom)
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
        collectionView.contentInset = UIEdgeInsets(top: 0, leading: 0, bottom: sectionToolbar.height, trailing: 0)
    }
}

extension EmojiPickerSheet: EmojiPickerSectionToolbarDelegate {
    func emojiPickerSectionToolbar(_ sectionToolbar: EmojiPickerSectionToolbar, didSelectSection section: Int) {
        collectionView.scrollToSectionHeader(section, animated: false)

        guard heightConstraint?.constant != maximizedHeight else { return }

        UIView.animate(withDuration: maxAnimationDuration, delay: 0, options: .curveEaseOut, animations: {
            self.heightConstraint?.constant = self.maximizedHeight
            self.view.layoutIfNeeded()
            self.backdropView?.alpha = 1
        })
    }

    func emojiPickerSectionToolbarShouldShowRecentsSection(_ sectionToolbar: EmojiPickerSectionToolbar) -> Bool {
        return collectionView.hasRecentEmoji
    }
}

extension EmojiPickerSheet: EmojiPickerCollectionViewDelegate {
    func emojiPicker(_ emojiPicker: EmojiPickerCollectionView, didSelectEmoji emoji: EmojiWithSkinTones) {
        completionHandler(emoji)
        dismiss(animated: true)
    }

    func emojiPicker(_ emojiPicker: EmojiPickerCollectionView, didScrollToSection section: Int) {
        sectionToolbar.setSelectedSection(section)
    }
}
