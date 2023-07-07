//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreServices
import SignalServiceKit
import SignalUI

class SetWallpaperViewController: OWSTableViewController2 {
    lazy var collectionView = WallpaperCollectionView(container: self, shouldDimInDarkMode: shouldDimInDarkMode) { [weak self] wallpaper in
        guard let self = self else { return }
        let vc = PreviewWallpaperViewController(
            mode: .preset(selectedWallpaper: wallpaper),
            thread: self.thread,
            delegate: self
        )
        self.presentFullScreen(UINavigationController(rootViewController: vc), animated: true)
    }

    static func load(thread: TSThread?, tx: SDSAnyReadTransaction) -> SetWallpaperViewController {
        return SetWallpaperViewController(
            thread: thread,
            shouldDimInDarkMode: Wallpaper.dimInDarkMode(for: thread, transaction: tx)
        )
    }

    private let thread: TSThread?
    private let shouldDimInDarkMode: Bool

    init(thread: TSThread?, shouldDimInDarkMode: Bool) {
        self.thread = thread
        self.shouldDimInDarkMode = shouldDimInDarkMode
        super.init()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SET_WALLPAPER_TITLE", comment: "Title for the set wallpaper settings view.")

        updateTableContents()
    }

    private var previousReferenceSize: CGSize = .zero
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        let referenceSize = view.bounds.size
        guard referenceSize != previousReferenceSize else { return }
        previousReferenceSize = referenceSize
        updateCollectionViewSize(reference: referenceSize)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate { _ in
            self.updateCollectionViewSize(reference: size)
        } completion: { _ in

        }
    }

    func updateCollectionViewSize(reference: CGSize) {
        collectionView.updateLayout(reference: reference)
        tableView.reloadRows(at: [IndexPath(row: 0, section: 1)], with: .none)
    }

    @objc
    private func updateTableContents() {
        let contents = OWSTableContents()

        let photosSection = OWSTableSection()
        photosSection.customHeaderHeight = 14

        let choosePhotoItem = OWSTableItem.disclosureItem(
            icon: .buttonPhotoLibrary,
            name: OWSLocalizedString("SET_WALLPAPER_CHOOSE_PHOTO",
                                    comment: "Title for the wallpaper choose from photos option"),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "choose_photo")
        ) { [weak self] in
            guard let self = self else { return }
            let vc = UIImagePickerController()
            vc.delegate = self
            vc.sourceType = .photoLibrary
            vc.mediaTypes = [kUTTypeImage as String]
            self.presentFormSheet(vc, animated: true)
        }
        photosSection.add(choosePhotoItem)

        contents.add(photosSection)

        let presetsSection = OWSTableSection()
        presetsSection.headerTitle = OWSLocalizedString("SET_WALLPAPER_PRESETS",
                                                       comment: "Title for the wallpaper presets section")

        let presetsItem = OWSTableItem { [weak self] in
            let cell = OWSTableItem.newCell()
            guard let self = self else { return cell }
            cell.contentView.addSubview(self.collectionView)
            self.collectionView.autoPinEdgesToSuperviewMargins()
            return cell
        } actionBlock: {}
        presetsSection.add(presetsItem)

        contents.add(presetsSection)

        self.contents = contents
    }
}

extension SetWallpaperViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        guard let rawImage = info[.originalImage] as? UIImage else {
            return owsFailDebug("Missing image")
        }

        let vc = PreviewWallpaperViewController(
            mode: .photo(selectedPhoto: rawImage),
            thread: thread,
            delegate: self
        )

        picker.dismiss(animated: true) {
            self.presentFullScreen(UINavigationController(rootViewController: vc), animated: true)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
}

extension SetWallpaperViewController: PreviewWallpaperDelegate {
    func previewWallpaperDidCancel(_ vc: PreviewWallpaperViewController) {
        presentedViewController?.dismiss(animated: true)
    }

    func previewWallpaperDidComplete(_ vc: PreviewWallpaperViewController) {
        presentedViewController?.dismiss(animated: true)
        navigationController?.popViewController(animated: true)
    }
}

class WallpaperCollectionView: UICollectionView {
    private let shouldDimInDarkMode: Bool
    private let flowLayout = UICollectionViewFlowLayout()
    private let selectionHandler: (Wallpaper) -> Void
    private lazy var heightConstraint = autoSetDimension(.height, toSize: 0)
    private weak var container: OWSTableViewController2!

    init(
        container: OWSTableViewController2,
        shouldDimInDarkMode: Bool,
        selectionHandler: @escaping (Wallpaper) -> Void
    ) {
        self.container = container
        self.shouldDimInDarkMode = shouldDimInDarkMode
        self.selectionHandler = selectionHandler

        flowLayout.minimumLineSpacing = 4
        flowLayout.minimumInteritemSpacing = 2

        super.init(frame: .zero, collectionViewLayout: flowLayout)

        delegate = self
        dataSource = self
        contentInset = UIEdgeInsets(hMargin: 0, vMargin: 8)
        isScrollEnabled = false
        backgroundColor = .clear

        register(WallpaperCell.self, forCellWithReuseIdentifier: WallpaperCell.reuseIdentifier)
    }

    func updateLayout(reference: CGSize) {
        AssertIsOnMainThread()

        let numberOfColumns: CGFloat = 3
        let numberOfRows = CGFloat(Wallpaper.defaultWallpapers.count) / numberOfColumns

        let availableWidth = reference.width -
            ((OWSTableViewController2.cellHInnerMargin * 2) + container.cellOuterInsets.totalWidth + 8 + safeAreaInsets.totalWidth)

        let itemWidth = availableWidth / numberOfColumns
        let itemHeight = itemWidth / CurrentAppContext().frame.size.aspectRatio

        flowLayout.itemSize = CGSize(width: itemWidth, height: itemHeight)
        flowLayout.invalidateLayout()

        heightConstraint.constant = numberOfRows * itemHeight + ((numberOfRows - 1) * flowLayout.minimumLineSpacing) + contentInset.totalHeight
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension WallpaperCollectionView: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        Wallpaper.defaultWallpapers.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: WallpaperCell.reuseIdentifier,
            for: indexPath
        )

        guard let wallpaperCell = cell as? WallpaperCell else {
            owsFailDebug("Dequeued unexpected cell")
            return cell
        }

        guard let wallpaper = Wallpaper.defaultWallpapers[safe: indexPath.row] else {
            owsFailDebug("Missing wallpaper for index \(indexPath.row)")
            return cell
        }

        wallpaperCell.configure(for: wallpaper, shouldDimInDarkMode: shouldDimInDarkMode)

        return wallpaperCell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let wallpaper = Wallpaper.defaultWallpapers[safe: indexPath.row] else {
            return owsFailDebug("Missing wallpaper for index \(indexPath.row)")
        }

        selectionHandler(wallpaper)
    }
}

class WallpaperCell: UICollectionViewCell {
    static let reuseIdentifier = "WallpaperCell"

    var wallpaperView: UIView?
    var wallpaper: Wallpaper?

    func configure(for wallpaper: Wallpaper, shouldDimInDarkMode: Bool) {
        guard wallpaper != self.wallpaper else { return }

        self.wallpaper = wallpaper
        wallpaperView?.removeFromSuperview()
        wallpaperView = Wallpaper.viewBuilder(
            for: wallpaper,
            customPhoto: { nil },
            shouldDimInDarkTheme: shouldDimInDarkMode
        )?.build().asPreviewView()

        guard let wallpaperView = wallpaperView else {
            return owsFailDebug("Missing wallpaper view")
        }

        contentView.addSubview(wallpaperView)
        contentView.clipsToBounds = true
        wallpaperView.autoPinEdgesToSuperviewEdges()
    }
}
