//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Photos

protocol PhotoCollectionPickerDelegate: AnyObject {
    func photoCollectionPicker(_ photoCollectionPicker: PhotoCollectionPickerController, didPickCollection collection: PhotoAlbum)
}

class PhotoCollectionPickerController: OWSTableViewController, PhotoLibraryDelegate {

    override var prefersStatusBarHidden: Bool {
        !UIDevice.current.hasIPhoneXNotch && !UIDevice.current.isIPad && !CurrentAppContext().hasActiveCall
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    private weak var collectionDelegate: PhotoCollectionPickerDelegate?

    private let library: PhotoLibrary
    private var photoCollections: [PhotoCollection]
    private let folder: PhotoCollectionFolder?

    required init(library: PhotoLibrary,
                  collectionDelegate: PhotoCollectionPickerDelegate,
                  folder: PhotoCollectionFolder? = nil) {
        self.library = library
        self.photoCollections = library.allPhotoCollections()
        self.collectionDelegate = collectionDelegate
        self.folder = folder
        super.init()
    }

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        library.add(delegate: self)

        updateContents()

        preferredNavigationBarStyle = OWSNavigationBarStyle.alwaysDark.rawValue
    }

    override func applyTheme() {
        // don't call super -- we want to set our own theme
        view.backgroundColor = Theme.darkThemeBackgroundColor
        tableView.backgroundColor = Theme.darkThemeBackgroundColor
        tableView.separatorColor = .clear
    }

    // MARK: -

    private func updateContents() {
        if let folder {
            photoCollections = folder.contents()
        } else {
            photoCollections = library.allPhotoCollections()
        }

        let sectionItems = photoCollections.map { collection in
            return OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    return UITableViewCell()
                }
                return self.buildTableCell(collection: collection)
                },
                                actionBlock: { [weak self] in
                                    guard let strongSelf = self else { return }
                                    strongSelf.didSelectCollection(collection: collection)
                })
        }

        let section = OWSTableSection(title: nil, items: sectionItems)
        let contents = OWSTableContents()
        contents.addSection(section)
        self.contents = contents
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
        let photoMediaSize = PhotoMediaSize(thumbnailSize: CGSize(square: kImageSize))

        let contentCount: Int
        let assetItem: PhotoPickerAssetItem?

        switch collection {
        case .album(let album):
            let contents = album.contents()
            contentCount = contents.assetCount
            assetItem = contents.lastAssetItem(photoMediaSize: photoMediaSize)
        case .folder(let folder):
            contentCount = folder.contents().count
            assetItem = nil // TODO: Folder item(s)
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

        cell.contentView.addSubview(hStackView)
        hStackView.autoPinEdgesToSuperviewMargins()

        return cell
    }

    // MARK: Actions

    func didSelectCollection(collection: PhotoCollection) {
        guard let collectionDelegate else { return }
        switch collection {
        case .album(let album):
            collectionDelegate.photoCollectionPicker(self, didPickCollection: album)
        case .folder(let folder):
            let collectionPickerController = PhotoCollectionPickerController(
                library: library,
                collectionDelegate: collectionDelegate,
                folder: folder
            )
            // TODO: Set title view
            navigationController?.pushViewController(collectionPickerController, animated: true)
        }
    }

    // MARK: PhotoLibraryDelegate

    func photoLibraryDidChange(_ photoLibrary: PhotoLibrary) {
        updateContents()
    }
}
