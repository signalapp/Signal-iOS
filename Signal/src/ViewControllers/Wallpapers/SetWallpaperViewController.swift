//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreServices
import SignalServiceKit
import SignalUI
import UniformTypeIdentifiers

class SetWallpaperViewController: OWSTableViewController2, UIImagePickerControllerDelegate, UINavigationControllerDelegate,
    PreviewWallpaperDelegate
{
    private lazy var collectionView = WallpaperCollectionView(shouldDimInDarkMode: shouldDimInDarkMode) { [weak self] wallpaper in
        guard let self else { return }
        let vc = PreviewWallpaperViewController(
            mode: .preset(selectedWallpaper: wallpaper),
            thread: self.thread,
            delegate: self,
        )
        self.presentFullScreen(UINavigationController(rootViewController: vc), animated: true)
    }

    static func load(thread: TSThread?, tx: DBReadTransaction) -> SetWallpaperViewController {
        return SetWallpaperViewController(
            thread: thread,
            shouldDimInDarkMode: DependenciesBridge.shared.wallpaperStore.fetchDimInDarkModeForRendering(
                for: thread?.uniqueId,
                tx: tx,
            ),
        )
    }

    private let thread: TSThread?
    private let shouldDimInDarkMode: Bool

    init(thread: TSThread?, shouldDimInDarkMode: Bool) {
        self.thread = thread
        self.shouldDimInDarkMode = shouldDimInDarkMode
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SET_WALLPAPER_TITLE", comment: "Title for the set wallpaper settings view.")

        updateTableContents()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCollectionViewSizeIfNecessary()
    }

    private var currentReferenceWidth: CGFloat = 0

    private func updateCollectionViewSizeIfNecessary() {
        let referenceWidth = tableViewContentWidth
        guard referenceWidth != currentReferenceWidth else { return }

        collectionView.updateLayout(referenceWidth: referenceWidth)
        tableView.reloadRows(at: [IndexPath(row: 0, section: 1)], with: .none)
        currentReferenceWidth = referenceWidth
    }

    private func updateTableContents() {
        let contents = OWSTableContents()

        let photosSection = OWSTableSection()
        photosSection.customHeaderHeight = 14

        let choosePhotoItem = OWSTableItem.disclosureItem(
            icon: .buttonPhotoLibrary,
            withText: OWSLocalizedString(
                "SET_WALLPAPER_CHOOSE_PHOTO",
                comment: "Title for the wallpaper choose from photos option",
            ),
        ) { [weak self] in
            guard let self else { return }
            let vc = UIImagePickerController()
            vc.delegate = self
            vc.sourceType = .photoLibrary
            vc.mediaTypes = [UTType.image.identifier]
            self.presentFormSheet(vc, animated: true)
        }
        photosSection.add(choosePhotoItem)

        contents.add(photosSection)

        let presetsSection = OWSTableSection()
        presetsSection.headerTitle = OWSLocalizedString(
            "SET_WALLPAPER_PRESETS",
            comment: "Title for the wallpaper presets section",
        )

        let presetsItem = OWSTableItem { [weak self] in
            let cell = OWSTableItem.newCell()
            guard let self else { return cell }
            cell.contentView.addSubview(self.collectionView)
            self.collectionView.autoPinEdgesToSuperviewMargins()
            return cell
        } actionBlock: {}
        presetsSection.add(presetsItem)

        contents.add(presetsSection)

        self.contents = contents
    }

    // MARK: - UIImagePickerControllerDelegate

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any],
    ) {
        guard let rawImage = info[.originalImage] as? UIImage else {
            return owsFailDebug("Missing image")
        }

        let vc = PreviewWallpaperViewController(
            mode: .photo(selectedPhoto: rawImage),
            thread: thread,
            delegate: self,
        )

        picker.dismiss(animated: true) {
            self.presentFullScreen(UINavigationController(rootViewController: vc), animated: true)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }

    // MARK: - PreviewWallpaperDelegate

    func previewWallpaperDidCancel(_ vc: PreviewWallpaperViewController) {
        vc.dismiss(animated: true)
    }

    func previewWallpaperDidComplete(_ vc: PreviewWallpaperViewController) {
        navigationController?.popViewController(animated: false)
        vc.dismiss(animated: true)
    }
}

private class WallpaperCollectionView: UICollectionView, UICollectionViewDataSource, UICollectionViewDelegate {
    private let shouldDimInDarkMode: Bool
    private let flowLayout = UICollectionViewFlowLayout()
    private let selectionHandler: (Wallpaper) -> Void
    private lazy var heightConstraint = autoSetDimension(.height, toSize: 0)

    init(
        shouldDimInDarkMode: Bool,
        selectionHandler: @escaping (Wallpaper) -> Void,
    ) {
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

    func updateLayout(referenceWidth: CGFloat) {
        let numberOfColumns: CGFloat = 3
        let numberOfRows = CGFloat(Wallpaper.defaultWallpapers.count) / numberOfColumns

        let availableWidth = referenceWidth -
            (OWSTableViewController2.cellHInnerMargin * 2 + flowLayout.minimumInteritemSpacing * (numberOfColumns - 1))
        let itemWidth = availableWidth / numberOfColumns
        let itemHeight = itemWidth / CurrentAppContext().frame.size.aspectRatio

        flowLayout.itemSize = CGSize(width: itemWidth, height: itemHeight)
        flowLayout.invalidateLayout()

        heightConstraint.constant = numberOfRows * itemHeight + ((numberOfRows - 1) * flowLayout.minimumLineSpacing) + contentInset.totalHeight
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        Wallpaper.defaultWallpapers.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: WallpaperCell.reuseIdentifier,
            for: indexPath,
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

private class WallpaperCell: UICollectionViewCell {
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
            shouldDimInDarkTheme: shouldDimInDarkMode,
        )?.build().asPreviewView()

        guard let wallpaperView else {
            return owsFailDebug("Missing wallpaper view")
        }

        contentView.addSubview(wallpaperView)
        contentView.clipsToBounds = true
        wallpaperView.autoPinEdgesToSuperviewEdges()
    }
}
