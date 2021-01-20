//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

class SetWallpaperViewController: OWSTableViewController {
    let thread: TSThread?
    public init(thread: TSThread? = nil) {
        self.thread = thread
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: Wallpaper.wallpaperDidChangeNotification,
            object: nil
        )
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SET_WALLPAPER_TITLE", comment: "Title for the set wallpaper settings view.")
        useThemeBackgroundColors = true
        updateTableContents()
    }

    @objc
    func updateTableContents() {
        let contents = OWSTableContents()

        let photosSection = OWSTableSection()
        photosSection.customHeaderHeight = 14

        let choosePhotoItem = OWSTableItem.disclosureItem(
            icon: .settingsAllMedia,
            name: "Choose from Photos",
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

        contents.addSection(photosSection)

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

        databaseStorage.asyncWrite { transaction in
            do {
                try Wallpaper.setPhoto(rawImage, for: self.thread, transaction: transaction)
            } catch {
                owsFailDebug("Failed to set photo \(error)")
            }
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
}
