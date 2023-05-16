//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

// Supplies sticker pack data
public protocol StickerPackDataSourceDelegate: AnyObject {
    func stickerPackDataDidChange()
}

// MARK: -

// Supplies sticker pack data
public protocol StickerPackDataSource: AnyObject {
    func add(delegate: StickerPackDataSourceDelegate)

    // This will be nil for the "recents" source.
    var info: StickerPackInfo? { get }
    var title: String? { get }
    var author: String? { get }

    func getStickerPack() -> StickerPack?

    var installedCoverInfo: StickerInfo? { get }
    var installedStickerInfos: [StickerInfo] { get }

    func metadata(forSticker stickerInfo: StickerInfo) -> StickerMetadata?
}

// MARK: -

// A base class for StickerPackDataSource.
public class BaseStickerPackDataSource: NSObject {

    // MARK: Delegates

    private var delegates = [Weak<StickerPackDataSourceDelegate>]()

    public func add(delegate: StickerPackDataSourceDelegate) {
        AssertIsOnMainThread()

        delegates.append(Weak(value: delegate))
    }

    private lazy var didChangeEvent: DebouncedEvent = {
        DebouncedEvents.build(mode: .firstLast,
                              maxFrequencySeconds: 0.5,
                              onQueue: .asyncOnQueue(queue: .main)) { [weak self] in
            AssertIsOnMainThread()
            guard let self = self else {
                return
            }
            // Inform any observing views or data sources that they of the change.
            // We do this async since we are likely inside of a transaction
            // to avoid opening another transaction within it.
            let delegates = self.delegates
            DispatchQueue.main.async {
                for delegate in delegates {
                    delegate.value?.stickerPackDataDidChange()
                }
            }
        }
    }()

    func fireDidChange() {
        AssertIsOnMainThread()

        didChangeEvent.requestNotify()
    }

    // MARK: Properties

    // This should only be set if the cover is available.
    // It might not be available if:
    //
    // * We're still downloading the manifest.
    // * We're still downloading the cover sticker data.
    // * There is no cover associated with this data source (e.g. "recent stickers").
    fileprivate var coverInfo: StickerInfo? {
        didSet {
            AssertIsOnMainThread()

            if oldValue == nil, coverInfo != nil {
                fireDidChange()
            }
        }
    }

    // This should only be set for stickers which are available.
    // See comment on coverInfo.
    fileprivate var stickerInfos = [StickerInfo]() {
        didSet {
            AssertIsOnMainThread()

            if oldValue.count != stickerInfos.count {
                fireDidChange()
            } else {
                let oldKeySet = oldValue.map { $0.packId }
                if !stickerInfos.allSatisfy({ oldKeySet.contains($0.packId) }) {
                    fireDidChange()
                }
            }
        }
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

            if oldValue == nil, stickerPack != nil {
                ensureDownloads()
                fireDidChange()
            }
        }
    }

    public required init(stickerPackInfo: StickerPackInfo) {
        self.stickerPackInfo = stickerPackInfo

        super.init()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stickersOrPacksDidChange),
                                               name: StickerManager.stickersOrPacksDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: .OWSApplicationDidBecomeActive,
                                               object: nil)

        ensureState()
    }

    func ensureState() {
        databaseStorage.read { readTx in
            let stateTuple = Self.fetchInstalledState(for: self.stickerPackInfo, readTx: readTx)

            guard let stickerPack = stateTuple.stickerPack, stickerPack.isInstalled else {
                self.stickerPack = nil
                self.coverInfo = nil
                self.stickerInfos = []
                return
            }

            self.stickerPack = stickerPack
            self.stickerInfos = stateTuple.installedStickers
            if self.coverInfo == nil, let coverInfo = stateTuple.installedCoverInfo {
                self.coverInfo = coverInfo
            }
        }
    }

    func ensureStateAsync(completion: (() -> Void)? = nil) {
        DispatchQueue.sharedUserInitiated.async {
            let stateTuple = self.databaseStorage.read { readTx in
                return Self.fetchInstalledState(for: self.stickerPackInfo, readTx: readTx)
            }

            DispatchQueue.main.async {
                guard let stickerPack = stateTuple.stickerPack, stickerPack.isInstalled else {
                    self.stickerPack = nil
                    self.coverInfo = nil
                    self.stickerInfos = []
                    return
                }

                self.stickerPack = stickerPack
                self.stickerInfos = stateTuple.installedStickers
                if self.coverInfo == nil, let coverInfo = stateTuple.installedCoverInfo {
                    self.coverInfo = coverInfo
                }

                completion?()
            }
        }
    }

    private static func fetchInstalledState(for stickerPackInfo: StickerPackInfo, readTx: SDSAnyReadTransaction) -> (
        stickerPack: StickerPack?,
        installedCoverInfo: StickerInfo?,
        installedStickers: [StickerInfo]) {

        // Update Sticker Pack.
        guard let stickerPack = StickerManager.fetchStickerPack(stickerPackInfo: stickerPackInfo,
                                                                transaction: readTx) else {
            return (nil, nil, [])
        }
        guard stickerPack.isInstalled else {
            // Ignore sticker packs which are "saved" but not "installed".
            return (nil, nil, [])
        }

        // Update Stickers.

        let coverInfo: StickerInfo?
        if StickerManager.isStickerInstalled(stickerInfo: stickerPack.coverInfo, transaction: readTx) {
            coverInfo = stickerPack.coverInfo
        } else {
            coverInfo = nil
        }
        let stickerInfos = StickerManager.installedStickers(forStickerPack: stickerPack,
                                                            verifyExists: false,
                                                            transaction: readTx)

        return (stickerPack, coverInfo, stickerInfos)
    }

    private func ensureDownloads() {
        guard let stickerPack = stickerPack else {
            return
        }
        // Download any missing stickers.
        _ = StickerManager.ensureDownloadsAsync(forStickerPack: stickerPack)
    }

    // MARK: Events

    @objc
    private func stickersOrPacksDidChange() {
        AssertIsOnMainThread()

        Logger.verbose("")

        ensureStateAsync()
    }

    @objc
    private func didBecomeActive() {
        AssertIsOnMainThread()

        ensureStateAsync {
            self.ensureDownloads()
        }
    }
}

// MARK: -

extension InstalledStickerPackDataSource: StickerPackDataSource {
    public var info: StickerPackInfo? {
        return stickerPackInfo
    }

    public var title: String? {
        return stickerPack?.title
    }

    public var author: String? {
        return stickerPack?.author
    }

    public func getStickerPack() -> StickerPack? {
        return stickerPack
    }

    public var installedCoverInfo: StickerInfo? {
        AssertIsOnMainThread()

        return coverInfo
    }

    public var installedStickerInfos: [StickerInfo] {
        AssertIsOnMainThread()

        return stickerInfos
    }

    public func metadata(forSticker stickerInfo: StickerInfo) -> StickerMetadata? {
        AssertIsOnMainThread()

        // This logic is perf-sensitive and on the main thread;
        // don't bother checking that the sticker data resides on disk.
        return StickerManager.installedStickerMetadataWithSneakyTransaction(stickerInfo: stickerInfo)
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

    // If false, only download manifest and cover.
    private let shouldDownloadAllStickers: Bool

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
    private var stickerMetadataMap = [String: StickerMetadata]()
    private var temporaryFileUrls = [URL]()

    public required init(stickerPackInfo: StickerPackInfo,
                         shouldDownloadAllStickers: Bool) {
        self.stickerPackInfo = stickerPackInfo
        self.shouldDownloadAllStickers = shouldDownloadAllStickers

        self.installedDataSource = InstalledStickerPackDataSource(stickerPackInfo: stickerPackInfo)

        super.init()

        self.installedDataSource.add(delegate: self)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: .OWSApplicationDidBecomeActive,
                                               object: nil)

        ensureState()
    }

    deinit {
        // Eagerly clean up temp files.
        let temporaryFileUrls = self.temporaryFileUrls
        DispatchQueue.global(qos: .background).async {
            for fileUrl in temporaryFileUrls {
                do {
                    try OWSFileSystem.deleteFileIfExists(url: fileUrl)
                } catch {
                    owsFailDebug("Error: \(error)")
                }
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
            downloadStickerPack()
            return
        }

        // Try to download sticker data, if necessary.
        if ensureStickerDownload(stickerPack: stickerPack, stickerInfo: stickerPack.coverInfo) {
            self.coverInfo = stickerPack.coverInfo
        } else {
            self.coverInfo = nil
        }

        if shouldDownloadAllStickers {
            var downloadedStickerInfos = [StickerInfo]()
            for stickerInfo in stickerPack.stickerInfos {
                if ensureStickerDownload(stickerPack: stickerPack, stickerInfo: stickerInfo) {
                    downloadedStickerInfos.append(stickerInfo)
                }
            }
            self.stickerInfos = downloadedStickerInfos
        } else {
            self.stickerInfos = []
        }
    }

    // This should only be accessed on the main thread.
    private var downloadKeySet = Set<String>()

    private func downloadStickerPack() {
        AssertIsOnMainThread()

        let key = stickerPackInfo.asKey
        guard !downloadKeySet.contains(key) else {
            // Download already in flight.
            return
        }
        downloadKeySet.insert(key)

        StickerManager.tryToDownloadStickerPack(stickerPackInfo: stickerPackInfo)
            .done(on: DispatchQueue.main) { [weak self] (stickerPack) in
                guard let self = self else {
                    return
                }
                guard self.stickerPack == nil else {
                    return
                }
                self.stickerPack = stickerPack
                assert(self.downloadKeySet.contains(key))
                self.downloadKeySet.remove(key)
                self.ensureState()
                self.fireDidChange()
            }.catch { [weak self] (error) in
                owsFailDebug("error: \(error)")
                guard let self = self else {
                    return
                }
                assert(self.downloadKeySet.contains(key))
                self.downloadKeySet.remove(key)
                // Sticker pack downloads may fail permanently,
                // which affects StickerManager state
                // so nudge the view to update even though the
                // the data source change may not have changed.
                self.fireDidChange()
            }
    }

    // Returns true if sticker is already downloaded.
    // If not, kicks off the download.
    private func ensureStickerDownload(stickerPack: StickerPack,
                                       stickerInfo: StickerInfo) -> Bool {
        AssertIsOnMainThread()

        guard let stickerPackItem = stickerPack.stickerPackItem(forStickerInfo: stickerInfo) else {
            owsFailDebug("Couldn't find item for sticker info.")
            return false
        }

        guard nil == self.metadata(forSticker: stickerInfo) else {
            // This sticker is already downloaded.
            return true
        }

        let key = stickerInfo.asKey()
        guard !downloadKeySet.contains(key) else {
            // Download already in flight.
            return false
        }
        downloadKeySet.insert(key)

        // This sticker is not downloaded; try to download now.
        firstly(on: DispatchQueue.global()) {
            StickerManager.tryToDownloadSticker(stickerPack: stickerPack, stickerInfo: stickerInfo)
        }.done(on: DispatchQueue.main) { [weak self] (temporaryFileUrl) in
            guard let self = self else {
                return
            }
            self.temporaryFileUrls.append(temporaryFileUrl)
            assert(self.downloadKeySet.contains(key))
            self.downloadKeySet.remove(key)
            self.set(temporaryFileUrl: temporaryFileUrl, stickerInfo: stickerInfo, stickerPackItem: stickerPackItem)
        }.catch { [weak self] (error) in
            owsFailDebug("error: \(error)")
            guard let self = self else {
                return
            }
            assert(self.downloadKeySet.contains(key))
            self.downloadKeySet.remove(key)
        }
        return false
    }

    private func set(temporaryFileUrl: URL,
                     stickerInfo: StickerInfo,
                     stickerPackItem: StickerPackItem) {
        AssertIsOnMainThread()

        let key = stickerInfo.asKey()
        guard nil == stickerMetadataMap[key] else {
            return
        }
        let stickerType = StickerManager.stickerType(forContentType: stickerPackItem.contentType)
        let stickerMetadata = StickerMetadata(stickerInfo: stickerInfo,
                                              stickerType: stickerType,
                                              stickerDataUrl: temporaryFileUrl,
                                              emojiString: stickerPackItem.emojiString)
        stickerMetadataMap[key] = stickerMetadata
        ensureState()
        fireDidChange()
    }

    // MARK: Events

    @objc
    private func didBecomeActive() {
        AssertIsOnMainThread()

        ensureState()
    }
}

// MARK: -

extension TransientStickerPackDataSource: StickerPackDataSource {
    public var info: StickerPackInfo? {
        AssertIsOnMainThread()

        return stickerPackInfo
    }

    public var title: String? {
        AssertIsOnMainThread()

        if let stickerPack = installedDataSource.getStickerPack() {
            return stickerPack.title
        }

        return stickerPack?.title
    }

    public var author: String? {
        AssertIsOnMainThread()

        if let stickerPack = installedDataSource.getStickerPack() {
            return stickerPack.author
        }

        return stickerPack?.author
    }

    public func getStickerPack() -> StickerPack? {
        AssertIsOnMainThread()

        if let stickerPack = installedDataSource.getStickerPack() {
            return stickerPack
        }

        return stickerPack
    }

    public var installedCoverInfo: StickerInfo? {
        AssertIsOnMainThread()

        if let coverInfo = installedDataSource.installedCoverInfo {
            return coverInfo
        }

        return coverInfo
    }

    public var installedStickerInfos: [StickerInfo] {
        AssertIsOnMainThread()

        let installedStickerInfos = installedDataSource.installedStickerInfos
        if installedStickerInfos.count > 0 {
            return installedStickerInfos
        }

        return stickerInfos
    }

    public func metadata(forSticker stickerInfo: StickerInfo) -> StickerMetadata? {
        AssertIsOnMainThread()

        let key = stickerInfo.asKey()
        if let stickerMetadata = stickerMetadataMap[key] {
            return stickerMetadata
        }

        guard let stickerMetadata = StickerManager.installedStickerMetadataWithSneakyTransaction(stickerInfo: stickerInfo) else {
                                                                                                    return nil
        }
        stickerMetadataMap[key] = stickerMetadata
        return stickerMetadata
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

    public required override init() {
        super.init()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(recentStickersDidChange),
                                               name: StickerManager.recentStickersDidChange,
                                               object: nil)

        ensureState()
    }

    private func ensureState() {
        stickerInfos = StickerManager.recentStickers()
    }

    // MARK: Events

    @objc
    private func recentStickersDidChange() {
        AssertIsOnMainThread()

        ensureState()
    }
}

// MARK: -

extension RecentStickerPackDataSource: StickerPackDataSource {
    public var info: StickerPackInfo? {
        owsFailDebug("This method should never be called.")
        return nil
    }

    public var title: String? {
        owsFailDebug("This method should never be called.")
        return nil
    }

    public var author: String? {
        owsFailDebug("This method should never be called.")
        return nil
    }

    public func getStickerPack() -> StickerPack? {
        owsFailDebug("This method should never be called.")
        return nil
    }

    public var installedCoverInfo: StickerInfo? {
        owsFailDebug("This method should never be called.")
        return nil
    }

    public var installedStickerInfos: [StickerInfo] {
        AssertIsOnMainThread()

        return stickerInfos
    }

    public func metadata(forSticker stickerInfo: StickerInfo) -> StickerMetadata? {
        AssertIsOnMainThread()

        // This logic is perf-sensitive and on the main thread;
        // don't bother checking that the sticker data resides on disk.
        return StickerManager.installedStickerMetadataWithSneakyTransaction(stickerInfo: stickerInfo)
    }
}

// MARK: -

extension StickerPack {
    func stickerPackItem(forStickerInfo stickerInfo: StickerInfo) -> StickerPackItem? {
        if cover.stickerId == stickerInfo.stickerId {
            return cover
        }
        for item in items {
            if item.stickerId == stickerInfo.stickerId {
                return item
            }
        }
        return nil
    }
}

// MARK: -

extension StickerPackItem {
    var stickerType: StickerType {
        StickerManager.stickerType(forContentType: contentType)
    }
}
