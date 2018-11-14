//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
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
    private let lastPhotoCollection: PhotoCollection
    private var photoCollections: PhotoCollections

    required init(library: PhotoLibrary,
                  lastPhotoCollection: PhotoCollection,
                  collectionDelegate: PhotoCollectionPickerDelegate) {
        self.library = library
        self.lastPhotoCollection = lastPhotoCollection
        self.photoCollections = library.allPhotoCollections()
        self.collectionDelegate = collectionDelegate
        super.init()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        let titleLabel = UILabel()
        titleLabel.text = lastPhotoCollection.localizedTitle()
        titleLabel.textColor = Theme.primaryColor
        titleLabel.font = UIFont.ows_dynamicTypeBody.ows_mediumWeight()

        let titleIconView = UIImageView()
        titleIconView.tintColor = Theme.primaryColor
        titleIconView.image = UIImage(named: "navbar_disclosure_up")?.withRenderingMode(.alwaysTemplate)

        let titleView = UIStackView(arrangedSubviews: [titleLabel, titleIconView])
        titleView.axis = .horizontal
        titleView.alignment = .center
        titleView.spacing = 5
        titleView.isUserInteractionEnabled = true
        titleView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(titleTapped)))
        navigationItem.titleView = titleView

        library.add(delegate: self)

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                           target: self,
                                                           action: #selector(didPressCancel))

        updateContents()
    }

    private func updateContents() {
        photoCollections = library.allPhotoCollections()

        let section = OWSTableSection()
        let count = photoCollections.count
        for index in 0..<count {
            let collection = photoCollections.collection(at: index)
            section.add(OWSTableItem.init(customCellBlock: { () -> UITableViewCell in
                let cell = OWSTableItem.newCell()

                let imageView = UIImageView()
                let kImageSize = 50
                imageView.autoSetDimensions(to: CGSize(width: kImageSize, height: kImageSize))

                let contents = collection.contents()
                if contents.count > 0 {
                    let photoMediaSize = PhotoMediaSize(thumbnailSize: CGSize(width: kImageSize, height: kImageSize))
                    let assetItem = contents.assetItem(at: 0, photoMediaSize: photoMediaSize)
                    imageView.image = assetItem.asyncThumbnail { [weak imageView] image in
                        guard let strongImageView = imageView else {
                            return
                        }
                        guard let image = image else {
                            return
                        }
                        strongImageView.image = image
                    }
                }

                let titleLabel = UILabel()
                titleLabel.text = collection.localizedTitle()
                titleLabel.font = UIFont.ows_regularFont(withSize: 18)
                titleLabel.textColor = Theme.primaryColor

                let stackView = UIStackView(arrangedSubviews: [imageView, titleLabel])
                stackView.axis = .horizontal
                stackView.alignment = .center
                stackView.spacing = 10

                cell.contentView.addSubview(stackView)
                stackView.ows_autoPinToSuperviewMargins()

                return cell
            },
                                          customRowHeight: UITableViewAutomaticDimension,
                                          actionBlock: { [weak self] in
                                            guard let strongSelf = self else { return }
                                            strongSelf.didSelectCollection(collection: collection)
            }))
        }
        let contents = OWSTableContents()
        contents.addSection(section)
        self.contents = contents
    }

    // MARK: Actions

    @objc
    func didPressCancel(sender: UIBarButtonItem) {
        self.dismiss(animated: true)
    }

    func didSelectCollection(collection: PhotoCollection) {
        collectionDelegate?.photoCollectionPicker(self, didPickCollection: collection)

        self.dismiss(animated: true)
    }

    @objc func titleTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        self.dismiss(animated: true)
    }

    // MARK: PhotoLibraryDelegate

    func photoLibraryDidChange(_ photoLibrary: PhotoLibrary) {
        updateContents()
    }
}
