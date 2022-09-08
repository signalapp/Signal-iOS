// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Combine
import GRDB
import DifferenceKit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit

class PhotoCollectionPickerViewModel: SettingsTableViewModel<NoNav, PhotoCollectionPickerViewModel.Section, PhotoCollectionPickerViewModel.Item> {
    // MARK: - Config
    
    public enum Section: SettingSection {
        case content
    }
    
    public struct Item: Equatable, Hashable, Differentiable {
        let id: String
    }

    private let library: PhotoLibrary
    private let onCollectionSelected: (PhotoCollection) -> Void
    private var photoCollections: CurrentValueSubject<[PhotoCollection], Error>

    // MARK: - Initialization

    init(library: PhotoLibrary, onCollectionSelected: @escaping (PhotoCollection) -> Void) {
        self.library = library
        self.onCollectionSelected = onCollectionSelected
        self.photoCollections = CurrentValueSubject(library.allPhotoCollections())
    }

    // MARK: - Content

    override var title: String { "NOTIFICATIONS_STYLE_SOUND_TITLE".localized() }

    private var _settingsData: [SectionModel] = []
    public override var settingsData: [SectionModel] { _settingsData }
    public override var observableSettingsData: ObservableData { _observableSettingsData }

    private lazy var _observableSettingsData: ObservableData = {
        self.photoCollections
            .map { collections in
                [
                    SectionModel(
                        model: .content,
                        elements: collections.map { collection in
                            let contents: PhotoCollectionContents = collection.contents()
                            let photoMediaSize: PhotoMediaSize = PhotoMediaSize(
                                thumbnailSize: CGSize(width: IconSize.large.size, height: IconSize.large.size)
                            )
                            let lastAssetItem: PhotoPickerAssetItem? = contents.lastAssetItem(photoMediaSize: photoMediaSize)
                            
                            return SettingInfo(
                                id: Item(id: collection.id),
                                iconSize: .large,
                                iconSetter: { imageView in
                                    // Note: We need to capture 'lastAssetItem' otherwise it'll be released and we won't
                                    // be able to load the thumbnail
                                    lastAssetItem?.asyncThumbnail { [weak imageView] image in
                                        imageView?.image = image
                                    }
                                },
                                title: collection.localizedTitle(),
                                subtitle: "\(contents.assetCount)",
                                action: .trigger(showChevron: false) { [weak self] in
                                    self?.onCollectionSelected(collection)
                                }
                            )
                        }
                    )
                ]
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }()

    // MARK: - Functions

    public override func updateSettings(_ updatedSettings: [SectionModel]) {
        self._settingsData = updatedSettings
    }

    // MARK: PhotoLibraryDelegate

    func photoLibraryDidChange(_ photoLibrary: PhotoLibrary) {
        self.photoCollections.send(library.allPhotoCollections())
    }
}
