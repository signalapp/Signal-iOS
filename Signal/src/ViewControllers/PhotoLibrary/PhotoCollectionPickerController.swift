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
    private let previousPhotoCollection: PhotoCollection
    private var photoCollections: [PhotoCollection]

    required init(library: PhotoLibrary,
                  previousPhotoCollection: PhotoCollection,
                  collectionDelegate: PhotoCollectionPickerDelegate) {
        self.library = library
        self.previousPhotoCollection = previousPhotoCollection
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

        view.backgroundColor = Theme.darkThemeBackgroundColor
        tableView.backgroundColor = Theme.darkThemeBackgroundColor
        tableView.separatorColor = .clear

        if #available(iOS 11, *) {
            let titleLabel = UILabel()
            titleLabel.text = previousPhotoCollection.localizedTitle()
            titleLabel.textColor = Theme.darkThemePrimaryColor
            titleLabel.font = UIFont.ows_dynamicTypeBody.ows_mediumWeight()

            let titleIconView = UIImageView()
            titleIconView.tintColor = Theme.darkThemePrimaryColor
            titleIconView.image = UIImage(named: "navbar_disclosure_up")?.withRenderingMode(.alwaysTemplate)

            let titleView = UIStackView(arrangedSubviews: [titleLabel, titleIconView])
            titleView.axis = .horizontal
            titleView.alignment = .center
            titleView.spacing = 5
            titleView.isUserInteractionEnabled = true
            titleView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(titleTapped)))
            navigationItem.titleView = titleView
        } else {
            navigationItem.title = previousPhotoCollection.localizedTitle()
        }

        library.add(delegate: self)

        let cancelButton = UIBarButtonItem(barButtonSystemItem: .stop,
                                           target: self,
                                           action: #selector(didPressCancel))
        cancelButton.tintColor = Theme.darkThemePrimaryColor
        navigationItem.leftBarButtonItem = cancelButton

        updateContents()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if let navBar = self.navigationController?.navigationBar as? OWSNavigationBar {
            navBar.overrideTheme(type: .alwaysDark)
        } else {
            owsFailDebug("Invalid nav bar.")
        }
    }

    // MARK: -

    private func updateContents() {
        photoCollections = library.allPhotoCollections()

        let sectionItems = photoCollections.map { collection in
            return OWSTableItem(customCellBlock: { self.buildTableCell(collection: collection) },
                                customRowHeight: UITableViewAutomaticDimension,
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
        cell.contentView.backgroundColor = Theme.darkThemeBackgroundColor
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
        let kImageSize = 80
        imageView.autoSetDimensions(to: CGSize(width: kImageSize, height: kImageSize))

        let hStackView = UIStackView(arrangedSubviews: [imageView, textStack])
        hStackView.axis = .horizontal
        hStackView.alignment = .center
        hStackView.spacing = 11

        let photoMediaSize = PhotoMediaSize(thumbnailSize: CGSize(width: kImageSize, height: kImageSize))
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
        hStackView.ows_autoPinToSuperviewMargins()

        return cell
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
