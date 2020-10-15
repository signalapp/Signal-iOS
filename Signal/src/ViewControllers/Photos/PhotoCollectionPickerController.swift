//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import Photos
import PromiseKit

protocol PhotoCollectionPickerDelegate: class {
    func photoCollectionPicker(_ photoCollectionPicker: PhotoCollectionPickerController, didPickCollection collection: PhotoCollection)
}

class PhotoCollectionPickerController: OWSTableViewController, PhotoLibraryDelegate {

    private weak var collectionDelegate: PhotoCollectionPickerDelegate?

    private let library: PhotoLibrary
    private var photoCollections: [PhotoCollection]

    required init(library: PhotoLibrary,
                  collectionDelegate: PhotoCollectionPickerDelegate) {
        self.library = library
        self.photoCollections = library.allPhotoCollections()
        self.collectionDelegate = collectionDelegate
        super.init()
    }

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.darkThemeBackgroundColor
        tableView.backgroundColor = Theme.darkThemeBackgroundColor
        tableView.separatorColor = .clear

        library.add(delegate: self)

        updateContents()
    }

    // MARK: -

    private func updateContents() {
        photoCollections = library.allPhotoCollections()

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

    private let numberFormatter: NumberFormatter = NumberFormatter()

    private func buildTableCell(collection: PhotoCollection) -> UITableViewCell {
        let cell = OWSTableItem.newCell()

        cell.backgroundColor = Theme.darkThemeBackgroundColor
        cell.selectedBackgroundView?.backgroundColor = UIColor(white: 0.2, alpha: 1)

        let contents = collection.contents()

        let titleLabel = UILabel()
        titleLabel.text = collection.localizedTitle()
        titleLabel.font = UIFont.ows_dynamicTypeBody
        titleLabel.textColor = Theme.darkThemePrimaryColor

        let countLabel = UILabel()
        countLabel.text = numberFormatter.string(for: contents.assetCount)
        countLabel.font = UIFont.ows_dynamicTypeCaption1
        countLabel.textColor = Theme.darkThemePrimaryColor

        let textStack = UIStackView(arrangedSubviews: [titleLabel, countLabel])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        let kImageSize: CGFloat = 80
        imageView.autoSetDimensions(to: CGSize(square: kImageSize))

        let hStackView = UIStackView(arrangedSubviews: [imageView, textStack])
        hStackView.axis = .horizontal
        hStackView.alignment = .center
        hStackView.spacing = 11

        let photoMediaSize = PhotoMediaSize(thumbnailSize: CGSize(square: kImageSize))
        if let assetItem = contents.lastAssetItem(photoMediaSize: photoMediaSize) {
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
        collectionDelegate?.photoCollectionPicker(self, didPickCollection: collection)
    }

    // MARK: PhotoLibraryDelegate

    func photoLibraryDidChange(_ photoLibrary: PhotoLibrary) {
        updateContents()
    }
}
