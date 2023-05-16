//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Photos
import SignalUI

protocol PhotoCollectionPickerDelegate: AnyObject {
    func photoCollectionPicker(_ photoCollectionPicker: PhotoCollectionPickerController, didPickCollection collection: PhotoCollection)
}

class PhotoCollectionPickerController: OWSTableViewController {

    private weak var collectionDelegate: PhotoCollectionPickerDelegate?

    private let library: PhotoLibrary

    required init(library: PhotoLibrary, collectionDelegate: PhotoCollectionPickerDelegate) {
        self.library = library
        self.collectionDelegate = collectionDelegate
        super.init()
    }

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        library.add(delegate: self)

        updateContents()
    }

    override func applyTheme() {
        // don't call super -- we want to set our own theme
        view.backgroundColor = Theme.darkThemeBackgroundColor
        tableView.backgroundColor = Theme.darkThemeBackgroundColor
        tableView.separatorColor = .clear
    }

    // MARK: -

    private func updateContents() {
        let photoCollections = library.allPhotoCollections()
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

        let contents = collection.contents()

        let titleLabel = UILabel()
        titleLabel.text = collection.localizedTitle()
        titleLabel.font = UIFont.dynamicTypeBody
        titleLabel.textColor = Theme.darkThemePrimaryColor

        let countLabel = UILabel()
        countLabel.text = numberFormatter.string(for: contents.assetCount)
        countLabel.font = UIFont.dynamicTypeCaption1
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

    private func didSelectCollection(collection: PhotoCollection) {
        collectionDelegate?.photoCollectionPicker(self, didPickCollection: collection)
    }
}

extension PhotoCollectionPickerController: PhotoLibraryDelegate {

    func photoLibraryDidChange(_ photoLibrary: PhotoLibrary) {
        updateContents()
    }
}
