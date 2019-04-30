//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

// Supplies sticker pack data
public protocol StickerPackDataSourceDelegate: class {
    func stickerPackDataDidChange()
}

// MARK: -

// Supplies sticker pack data
protocol StickerPackDataSource: class {
    func add(delegate: StickerPackDataSourceDelegate)

    func info() -> StickerPackInfo
    func title() -> String?
    func author() -> String?

    func getStickerPack() -> StickerPack?

    func installedCoverInfo() -> StickerInfo?
    func installedStickerInfos() -> [StickerInfo]

    func filePath(forSticker stickerInfo: StickerInfo) -> String?
}

// MARK: -

// A base class for StickerPackDataSource.
public class BaseStickerPackDataSource: NSObject {

    fileprivate var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: Delegates

    private var delegates = [Weak<StickerPackDataSourceDelegate>]()

    func add(delegate: StickerPackDataSourceDelegate) {
        AssertIsOnMainThread()

        delegates.append(Weak(value: delegate))
    }

    func fireDidChange() {
        AssertIsOnMainThread()

        for delegate in delegates {
            guard let delegate = delegate.value else {
                continue
            }
            delegate.stickerPackDataDidChange()
        }
    }

    // MARK: Properties

    // This should only be set if the cover is available.
    fileprivate var coverInfo: StickerInfo? {
        didSet {
            AssertIsOnMainThread()

            if oldValue == nil {
                fireDidChange()
            }
        }
    }

    // This should only be set for stickers which are available.
    fileprivate var stickerInfos = [StickerInfo]() {
        didSet {
            AssertIsOnMainThread()

            let before = Set(oldValue.map { $0.asKey() })
            let after = Set(stickerInfos.map { $0.asKey() })
            Logger.verbose("---- stickerInfos: \(before.count) -> \(after.count) ? \(before != after)")
            if before != after {
                fireDidChange()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: -

// Supplies sticker pack data for installed sticker packs.
public class InstalledStickerPackDataSource: BaseStickerPackDataSource {

    // MARK: Properties

    private let stickerPackInfo: StickerPackInfo

    fileprivate var stickerPack: StickerPack? {
        didSet {
            AssertIsOnMainThread()

            ensureDownloads()

            fireDidChange()
        }
    }

    @objc
    public required init(stickerPackInfo: StickerPackInfo) {
        self.stickerPackInfo = stickerPackInfo

        super.init()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stickersOrPacksDidChange),
                                               name: StickerManager.StickersOrPacksDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: NSNotification.Name.OWSApplicationDidBecomeActive,
                                               object: nil)

        ensureState()
    }

    private func ensureState() {
        databaseStorage.readSwallowingErrors { (transaction) in
            // Update Sticker Pack.
            guard let stickerPack = StickerManager.fetchStickerPack(stickerPackInfo: self.stickerPackInfo,
                                                                    transaction: transaction) else {
                                                                        self.stickerPack = nil
                                                                        self.coverInfo = nil
                                                                        self.stickerInfos = []
                                                                        return
            }
            guard stickerPack.isInstalled else {
                // Ignore sticker packs which are "saved" but not "installed".
                self.stickerPack = nil
                self.coverInfo = nil
                self.stickerInfos = []
                return
            }
            self.stickerPack = stickerPack

            // Update Stickers.
            if self.coverInfo == nil {
                let coverInfo = stickerPack.coverInfo
                if StickerManager.isStickerInstalled(stickerInfo: coverInfo) {
                    self.coverInfo = coverInfo
                }
            }

            self.stickerInfos = StickerManager.installedStickers(forStickerPack: stickerPack, transaction: transaction)
        }
    }

    private func ensureDownloads() {
        guard let stickerPack = stickerPack else {
            return
        }
        // Download any missing stickers.
        StickerManager.ensureDownloadsAsync(forStickerPack: stickerPack)
    }

    // MARK: Events

    @objc func stickersOrPacksDidChange() {
        AssertIsOnMainThread()

        Logger.verbose("")

        ensureState()
    }

    @objc func didBecomeActive() {
        AssertIsOnMainThread()

        ensureState()

        ensureDownloads()
    }
}

// MARK: -

extension InstalledStickerPackDataSource: StickerPackDataSource {
    func info() -> StickerPackInfo {
        return stickerPackInfo
    }

    func title() -> String? {
        return stickerPack?.title
    }

    func author() -> String? {
        return stickerPack?.author
    }

    func getStickerPack() -> StickerPack? {
        return stickerPack
    }

    func installedCoverInfo() -> StickerInfo? {
        AssertIsOnMainThread()

        return coverInfo
    }

    func installedStickerInfos() -> [StickerInfo] {
        AssertIsOnMainThread()

        return stickerInfos
    }

    func filePath(forSticker stickerInfo: StickerInfo) -> String? {
        AssertIsOnMainThread()

        return StickerManager.filepathForInstalledSticker(stickerInfo: stickerInfo)
    }
}

// MARK: -

// Supplies sticker pack data for NON-installed sticker packs.
//
// It uses a InstalledStickerPackDataSource internally so that
// we use any installed data, if possible.
public class TransientStickerPackDataSource: BaseStickerPackDataSource {

    // MARK: Properties

    private let stickerPackInfo: StickerPackInfo

    fileprivate var stickerPack: StickerPack? {
        didSet {
            AssertIsOnMainThread()

            guard stickerPack != nil else {
                owsFailDebug("Missing stickerPack.")
                return
            }

            fireDidChange()
        }
    }

    // If the pack is installed, we should use that data wherever possible.
    private let installedDataSource: InstalledStickerPackDataSource

    // This should only be accessed on the main thread.
    private var stickerFilePathMap = [String: String]()

    @objc
    public required init(stickerPackInfo: StickerPackInfo) {
        self.stickerPackInfo = stickerPackInfo

        self.installedDataSource = InstalledStickerPackDataSource(stickerPackInfo: stickerPackInfo)

        super.init()

        self.installedDataSource.add(delegate: self)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: NSNotification.Name.OWSApplicationDidBecomeActive,
                                               object: nil)

        ensureState()
    }

    deinit {
        // Eagerly clean up temp files.
        let stickerFilePathMap = self.stickerFilePathMap
        DispatchQueue.global(qos: .background).async {
            for filePath in stickerFilePathMap.values {
                OWSFileSystem.deleteFileIfExists(filePath)
            }
        }
    }

    private func ensureState() {
        AssertIsOnMainThread()

        if installedDataSource.getStickerPack() != nil {
            // If the "installed" data source has data,
            // don't bother loading the manifest & sticker data.
            return
        }

        // If necessary, download and parse the pack's manifest.
        guard let stickerPack = stickerPack else {
            StickerManager.tryToDownloadAndParseStickerPack(stickerPackInfo: stickerPackInfo, skipIfSaved: false)
                .done { [weak self] (stickerPack) in
                    guard let self = self else {
                        return
                    }
                    guard self.stickerPack == nil else {
                        return
                    }
                    self.stickerPack = stickerPack
                    self.ensureState()
                    self.fireDidChange()
            }.retainUntilComplete()
            return
        }

        // Try to download sticker data, if necessary.
        if ensureStickerDownload(stickerPack: stickerPack, stickerInfo: stickerPack.coverInfo) {
            self.coverInfo = stickerPack.coverInfo
        } else {
            self.coverInfo = nil
        }

        var downloadedStickerInfos = [StickerInfo]()
        for stickerInfo in stickerPack.stickerInfos {
            if ensureStickerDownload(stickerPack: stickerPack, stickerInfo: stickerInfo) {
                downloadedStickerInfos.append(stickerInfo)
            }
        }
        self.stickerInfos = downloadedStickerInfos
    }

    // Returns true if sticker is already downloaded.
    // If not, kicks off the download.
    private func ensureStickerDownload(stickerPack: StickerPack,
                                       stickerInfo: StickerInfo) -> Bool {
        guard nil == self.filePath(forSticker: stickerInfo) else {
            // This sticker is already downloaded.
            return true
        }
        // This sticker is not downloaded; try to download now.
        StickerManager.tryToDownloadSticker(stickerPack: stickerPack, stickerInfo: stickerInfo, skipIfSaved: false)
            .map(on: DispatchQueue.global()) { (stickerData: Data) -> String in
                let filePath = OWSFileSystem.temporaryFilePath(withFileExtension: "webp")
                try stickerData.write(to: URL(fileURLWithPath: filePath))
                return filePath
            }.done { [weak self] (filePath) in
                guard let self = self else {
                    return
                }
                self.set(filePath: filePath, forSticker: stickerInfo)
            }.catch(on: DispatchQueue.global()) { (error) in
                owsFailDebug("error: \(error)")
            }.retainUntilComplete()
        return false
    }

    private func set(filePath: String, forSticker stickerInfo: StickerInfo) {
        AssertIsOnMainThread()

        let key = stickerInfo.asKey()
        guard nil == stickerFilePathMap[key] else {
            return
        }
        stickerFilePathMap[key] = filePath
        ensureState()
    }

    // MARK: Events

    @objc func didBecomeActive() {
        AssertIsOnMainThread()

        ensureState()
    }
}

// MARK: -

extension TransientStickerPackDataSource: StickerPackDataSource {
    func info() -> StickerPackInfo {
        AssertIsOnMainThread()

        return stickerPackInfo
    }

    func title() -> String? {
        AssertIsOnMainThread()

        if let stickerPack = installedDataSource.getStickerPack() {
            return stickerPack.title
        }

        return stickerPack?.title
    }

    func author() -> String? {
        AssertIsOnMainThread()

        if let stickerPack = installedDataSource.getStickerPack() {
            return stickerPack.author
        }

        return stickerPack?.author
    }

    func getStickerPack() -> StickerPack? {
        AssertIsOnMainThread()

        if let stickerPack = installedDataSource.getStickerPack() {
            return stickerPack
        }

        return stickerPack
    }

    func installedCoverInfo() -> StickerInfo? {
        AssertIsOnMainThread()

        if let coverInfo = installedDataSource.installedCoverInfo() {
            return coverInfo
        }

        return coverInfo
    }

    func installedStickerInfos() -> [StickerInfo] {
        AssertIsOnMainThread()

        let installedStickerInfos = installedDataSource.installedStickerInfos()
        if installedStickerInfos.count > 0 {
            return installedStickerInfos
        }

        return stickerInfos
    }

    func filePath(forSticker stickerInfo: StickerInfo) -> String? {
        AssertIsOnMainThread()

        if let filePath = installedDataSource.filePath(forSticker: stickerInfo) {
            return filePath
        }

        return stickerFilePathMap[stickerInfo.asKey()]
    }
}

// MARK: -

extension TransientStickerPackDataSource: StickerPackDataSourceDelegate {
    public func stickerPackDataDidChange() {
        ensureState()
    }
}

// MARK: -

// Supplies sticker pack data for recently used stickers.
public class RecentStickerPackDataSource: BaseStickerPackDataSource {

    @objc
    public required override init() {
        super.init()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(recentStickersDidChange),
                                               name: StickerManager.RecentStickersDidChange,
                                               object: nil)

        ensureState()
    }

    private func ensureState() {
        stickerInfos = StickerManager.recentStickers()
    }

    // MARK: Events

    @objc
    func recentStickersDidChange() {
        AssertIsOnMainThread()

        ensureState()
    }
}

// MARK: -

extension RecentStickerPackDataSource: StickerPackDataSource {
    func info() -> StickerPackInfo {
        owsFailDebug("This method should never be called.")
        return StickerPackInfo.defaultValue
    }

    func title() -> String? {
        owsFailDebug("This method should never be called.")
        return nil
    }

    func author() -> String? {
        owsFailDebug("This method should never be called.")
        return nil
    }

    func getStickerPack() -> StickerPack? {
        owsFailDebug("This method should never be called.")
        return nil
    }

    func installedCoverInfo() -> StickerInfo? {
        owsFailDebug("This method should never be called.")
        return nil
    }

    func installedStickerInfos() -> [StickerInfo] {
        AssertIsOnMainThread()

        return stickerInfos
    }

    func filePath(forSticker stickerInfo: StickerInfo) -> String? {
        AssertIsOnMainThread()

        return StickerManager.filepathForInstalledSticker(stickerInfo: stickerInfo)
    }
}
