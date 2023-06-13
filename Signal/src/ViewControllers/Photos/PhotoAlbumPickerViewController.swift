//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Photos
import SignalCoreKit
import SignalUI

protocol PhotoAlbumPickerDelegate: AnyObject {
    func photoAlbumPicker(_ picker: PhotoAlbumPickerViewController, didSelectAlbum album: PhotoAlbum)
}

class PhotoAlbumPickerViewController: OWSTableViewController, OWSNavigationChildController {

    private weak var collectionDelegate: PhotoAlbumPickerDelegate?

    private let library: PhotoLibrary
    private let folder: PhotoCollectionFolder?

    required init(library: PhotoLibrary,
                  collectionDelegate: PhotoAlbumPickerDelegate,
                  folder: PhotoCollectionFolder? = nil) {
        self.library = library
        self.collectionDelegate = collectionDelegate
        self.folder = folder
        super.init()
    }

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        library.add(delegate: self)

        updateContents()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let selectedIndexPath = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: selectedIndexPath, animated: false)
        }
    }

    override func applyTheme() {
        // don't call super -- we want to set our own theme
        view.backgroundColor = Theme.darkThemeBackgroundColor
        tableView.backgroundColor = Theme.darkThemeBackgroundColor
        tableView.separatorColor = .clear

    }

    // MARK: -

    private func updateContents() {
        let photoCollections: [PhotoCollection]
        if let folder {
            photoCollections = folder.contents().collections()
        } else {
            photoCollections = library.allPhotoCollections()
        }

        let sectionItems = photoCollections.map { collection in
            return OWSTableItem(
                customCellBlock: { [weak self] in
                    guard let self else { return UITableViewCell() }
                    return self.buildTableCell(collection: collection)
                },
                actionBlock: { [weak self] in
                    self?.didSelectCollection(collection: collection)
                }
            )
        }

        contents = OWSTableContents(sections: [ OWSTableSection(title: nil, items: sectionItems) ])
    }

    private lazy var numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private func buildTableCell(collection: PhotoCollection) -> UITableViewCell {
        let cell = OWSTableItem.newCell()

        cell.backgroundColor = Theme.darkThemeBackgroundColor
        cell.selectedBackgroundView?.backgroundColor = UIColor(white: 0.2, alpha: 1)

        let kImageSize: CGFloat = 80
        let folderImageSpacing: CGFloat = 1
        let folderImageSize = (kImageSize - folderImageSpacing) / 2
        let photoMediaSize = PhotoMediaSize(thumbnailSize: CGSize(square: kImageSize))
        let folderMediaSize = PhotoMediaSize(thumbnailSize: CGSize(square: folderImageSize))

        let contentCount: Int
        var assetItem: PhotoPickerAssetItem?
        var assetItems: [PhotoPickerAssetItem]?

        switch collection {
        case .album(let album):
            let contents = album.contents()
            contentCount = contents.assetCount
            assetItem = contents.lastAssetItem(photoMediaSize: photoMediaSize)
        case .folder(let folder):
            let contents = folder.contents()
            contentCount = contents.collectionCount
            let previewAssetItems = contents.previewAssetItems(photoMediaSize: folderMediaSize)
            assetItems = previewAssetItems
        }

        let titleLabel = UILabel()
        titleLabel.text = collection.localizedTitle()
        titleLabel.font = UIFont.dynamicTypeBody
        titleLabel.textColor = Theme.darkThemePrimaryColor

        let countLabel = UILabel()
        countLabel.text = numberFormatter.string(for: contentCount)
        countLabel.font = UIFont.dynamicTypeCaption1
        countLabel.textColor = Theme.darkThemePrimaryColor

        let textStack = UIStackView(arrangedSubviews: [titleLabel, countLabel])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.autoSetDimensions(to: CGSize(square: kImageSize))

        let hStackView = UIStackView(arrangedSubviews: [imageView, textStack])
        hStackView.axis = .horizontal
        hStackView.alignment = .center
        hStackView.spacing = 11

        if let assetItem {
            // Album
            loadThumbnail(for: imageView, using: assetItem)
        } else if let assetItems {
            // Folder
            assetItems.enumerated().forEach { i, asset in
                let folderImageView = UIImageView()
                folderImageView.contentMode = .scaleAspectFill
                folderImageView.clipsToBounds = true

                imageView.addSubview(folderImageView)

                folderImageView.autoSetDimensions(to: CGSize(square: folderImageSize))

                // 2x2 grid
                // 0 1
                // 2 3
                if [0, 2].contains(i) {
                    folderImageView.autoPinEdge(toSuperviewEdge: .leading)
                } else {
                    folderImageView.autoPinEdge(toSuperviewEdge: .trailing)
                }
                if [0, 1].contains(i) {
                    folderImageView.autoPinEdge(toSuperviewEdge: .top)
                } else {
                    folderImageView.autoPinEdge(toSuperviewEdge: .bottom)
                }

                loadThumbnail(for: folderImageView, using: asset)
            }
        }

        cell.contentView.addSubview(hStackView)
        hStackView.autoPinEdgesToSuperviewMargins()

        return cell
    }

    private func loadThumbnail(for imageView: UIImageView, using assetItem: PhotoPickerAssetItem) {
        imageView.image = assetItem.asyncThumbnail { [weak imageView] image in
            AssertIsOnMainThread()

            guard let imageView = imageView else {
                return
            }

            guard let image = image else {
                owsFailDebug("image was unexpectedly nil")
                return
            }

            imageView.image = image
        }
    }

    // MARK: Actions

    func didSelectCollection(collection: PhotoCollection) {
        guard let collectionDelegate else { return }
        switch collection {
        case .album(let album):
            collectionDelegate.photoAlbumPicker(self, didSelectAlbum: album)
        case .folder(let folder):
            let collectionPickerController = PhotoAlbumPickerViewController(
                library: library,
                collectionDelegate: collectionDelegate,
                folder: folder
            )
            navigationController?.pushViewController(collectionPickerController, animated: true)
        }
    }
}

extension PhotoAlbumPickerViewController: PhotoLibraryDelegate {

    func photoLibraryDidChange(_ photoLibrary: PhotoLibrary) {
        updateContents()
    }
}
