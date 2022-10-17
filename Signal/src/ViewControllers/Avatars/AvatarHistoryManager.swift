//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

enum AvatarContext {
    case groupId(Data)
    case profile

    var key: String {
        switch self {
        case .groupId(let data): return "group.\(data.hexadecimalString)"
        case .profile: return "profile"
        }
    }
}

@objc
public class AvatarHistoryManager: NSObject {
    static let keyValueStore = SDSKeyValueStore(collection: "AvatarHistory")
    static let appSharedDataDirectory = URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath())
    static let imageHistoryDirectory = URL(fileURLWithPath: "AvatarHistory", isDirectory: true, relativeTo: appSharedDataDirectory)

    @objc
    override init() {
        super.init()
        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            DispatchQueue.global().async {
                self.cleanupOrphanedImages()
            }
        }
    }

    func cleanupOrphanedImages() {
        owsAssertDebug(!Thread.isMainThread)

        guard OWSFileSystem.fileOrFolderExists(url: Self.imageHistoryDirectory) else { return }

        let allRecords: [[AvatarRecord]] = databaseStorage.read { transaction in
            do {
                return try Self.keyValueStore.allCodableValues(transaction: transaction)
            } catch {
                owsFailDebug("Failed to decode avatar history for orphan cleanup \(error)")
                return []
            }
        }

        let filesToKeep = allRecords.flatMap { $0.compactMap { $0.imageUrl?.path } }

        let filesInDirectory: [String]
        do {
            filesInDirectory = try OWSFileSystem.recursiveFilesInDirectory(Self.imageHistoryDirectory.path)
        } catch {
            owsFailDebug("Failed to lookup files in image history directory \(error)")
            return
        }

        var orphanCount = 0
        for file in filesInDirectory where !filesToKeep.contains(file) {
            guard OWSFileSystem.deleteFile(file) else {
                owsFailDebug("Failed to delete orphaned avatar image file \(file)")
                continue
            }
            orphanCount += 1
        }

        if orphanCount > 0 {
            Logger.info("Deleted \(orphanCount) orphaned avatar images.")
        }
    }

    func models(for context: AvatarContext, transaction: SDSAnyReadTransaction) -> [AvatarModel] {
        var (models, icons) = persisted(for: context, transaction: transaction)

        let defaultIcons: [AvatarIcon]
        switch context {
        case .groupId: defaultIcons = AvatarIcon.defaultGroupIcons
        case .profile: defaultIcons = AvatarIcon.defaultProfileIcons
        }

        // Insert models for default icons that aren't persisted
        for icon in defaultIcons.filter({ !icons.contains($0) }) {
            models.append(.init(
                type: .icon(icon),
                theme: .forIcon(icon)
            ))
        }

        return models
    }

    func touchedModel(_ model: AvatarModel, in context: AvatarContext, transaction: SDSAnyWriteTransaction) {
        var (models, _) = persisted(for: context, transaction: transaction)

        models.removeAll { $0.identifier == model.identifier }
        models.insert(model, at: 0)

        let records: [AvatarRecord] = models.map { model in
            switch model.type {
            case .icon(let icon):
                owsAssertDebug(model.identifier == icon.rawValue)
                return AvatarRecord(kind: .icon, identifier: model.identifier, imageUrl: nil, text: nil, theme: model.theme.rawValue)
            case .image(let url):
                return AvatarRecord(kind: .image, identifier: model.identifier, imageUrl: url, text: nil, theme: model.theme.rawValue)
            case .text(let text):
                return AvatarRecord(kind: .text, identifier: model.identifier, imageUrl: nil, text: text, theme: model.theme.rawValue)
            }
        }

        do {
            try Self.keyValueStore.setCodable(records, key: context.key, transaction: transaction)
        } catch {
            owsFailDebug("Failed to touch avatar history \(error)")
        }
    }

    func deletedModel(_ model: AvatarModel, in context: AvatarContext, transaction: SDSAnyWriteTransaction) {
        var (models, _) = persisted(for: context, transaction: transaction)

        models.removeAll { $0.identifier == model.identifier }

        if case .image(let url) = model.type {
            OWSFileSystem.deleteFileIfExists(url.path)
        }

        let records: [AvatarRecord] = models.map { model in
            switch model.type {
            case .icon(let icon):
                owsAssertDebug(model.identifier == icon.rawValue)
                return AvatarRecord(kind: .icon, identifier: model.identifier, imageUrl: nil, text: nil, theme: model.theme.rawValue)
            case .image(let url):
                return AvatarRecord(kind: .image, identifier: model.identifier, imageUrl: url, text: nil, theme: model.theme.rawValue)
            case .text(let text):
                return AvatarRecord(kind: .text, identifier: model.identifier, imageUrl: nil, text: text, theme: model.theme.rawValue)
            }
        }

        do {
            try Self.keyValueStore.setCodable(records, key: context.key, transaction: transaction)
        } catch {
            owsFailDebug("Failed to touch avatar history \(error)")
        }
    }

    func recordModelForImage(_ image: UIImage, in context: AvatarContext, transaction: SDSAnyWriteTransaction) -> AvatarModel? {
        OWSFileSystem.ensureDirectoryExists(Self.imageHistoryDirectory.path)

        let identifier = UUID().uuidString
        let url = URL(fileURLWithPath: identifier + ".jpg", relativeTo: Self.imageHistoryDirectory)

        let avatarData = OWSProfileManager.avatarData(forAvatarImage: image)
        do {
            try avatarData.write(to: url)
        } catch {
            owsFailDebug("Failed to record model for image \(error)")
            return nil
        }

        let model = AvatarModel(identifier: identifier, type: .image(url), theme: .default)
        touchedModel(model, in: context, transaction: transaction)
        return model
    }

    private func persisted(
        for context: AvatarContext,
        transaction: SDSAnyReadTransaction
    ) -> (models: [AvatarModel], persistedIcons: Set<AvatarIcon>) {
        let records: [AvatarRecord]?

        do {
            records = try Self.keyValueStore.getCodableValue(forKey: context.key, transaction: transaction)
        } catch {
            owsFailDebug("Failed to load persisted avatar records \(error)")
            records = nil
        }

        var icons = Set<AvatarIcon>()
        var models = [AvatarModel]()

        for record in records ?? [] {
            switch record.kind {
            case .icon:
                guard let icon = AvatarIcon(rawValue: record.identifier) else {
                    owsFailDebug("Invalid avatar icon \(record.identifier)")
                    continue
                }
                icons.insert(icon)
                models.append(.init(
                    identifier: record.identifier,
                    type: .icon(icon),
                    theme: AvatarTheme(rawValue: record.theme) ?? .default
                ))
            case .image:
                guard let imageUrl = record.imageUrl, OWSFileSystem.fileOrFolderExists(url: imageUrl) else {
                    owsFailDebug("Invalid avatar image \(record.identifier)")
                    continue
                }
                models.append(.init(
                    identifier: record.identifier,
                    type: .image(imageUrl),
                    theme: AvatarTheme(rawValue: record.theme) ?? .default
                ))
            case .text:
                guard let text = record.text else {
                    owsFailDebug("Missing avatar text")
                    continue
                }
                models.append(.init(
                    identifier: record.identifier,
                    type: .text(text),
                    theme: AvatarTheme(rawValue: record.theme) ?? .default
                ))
            }
        }

        return (models, icons)
    }
}

// We don't encode an AvatarModel directly to future proof
// us against changes to AvatarIcon, AvatarType, etc. enums
// since Codable is brittle when it encounters things it
// doesn't know about.
private struct AvatarRecord: Codable {
    enum Kind: String, Codable {
        case icon, text, image
    }
    let kind: Kind
    let identifier: String
    let imageUrl: URL?
    let text: String?
    let theme: String
}
