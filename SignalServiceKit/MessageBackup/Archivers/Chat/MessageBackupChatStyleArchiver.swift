//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class MessageBackupChatStyleArchiver: MessageBackupProtoArchiver {

    private let attachmentManager: AttachmentManager
    private let attachmentStore: AttachmentStore
    private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
    private let chatColorSettingStore: ChatColorSettingStore
    private let dateProvider: DateProvider
    private let wallpaperStore: WallpaperStore

    public init(
        attachmentManager: AttachmentManager,
        attachmentStore: AttachmentStore,
        backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
        chatColorSettingStore: ChatColorSettingStore,
        dateProvider: @escaping DateProvider,
        wallpaperStore: WallpaperStore
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
        self.chatColorSettingStore = chatColorSettingStore
        self.dateProvider = dateProvider
        self.wallpaperStore = wallpaperStore
    }

    // MARK: - Custom Chat Colors

    func archiveCustomChatColors(
        context: MessageBackup.CustomChatColorArchivingContext
    ) -> MessageBackup.ArchiveSingleFrameResult<[BackupProto_ChatStyle.CustomChatColor], MessageBackup.AccountDataId> {
        var partialErrors = [MessageBackup.ArchiveFrameError<CustomChatColor.Key>]()
        var protos = [BackupProto_ChatStyle.CustomChatColor]()

        for (key, customChatColor) in chatColorSettingStore.fetchCustomValues(tx: context.tx) {

            let protoColor: BackupProto_ChatStyle.CustomChatColor.OneOf_Color
            switch customChatColor.colorSetting {
            case .themedColor(let color, _):
                // Themes should be impossible with custom chat colors; add an error
                // but just take the light theme color and keep going.
                partialErrors.append(.archiveFrameError(
                    .themedCustomChatColor,
                    key
                ))
                fallthrough
            case .solidColor(let color):
                protoColor = .solid(color.asRGBHex())

            case .themedGradient(let gradientColor1, let gradientColor2, _, _, let angleRadians):
                // Themes should be impossible with custom chat colors; add an error
                // but just take the light theme colors and keep going.
                partialErrors.append(.archiveFrameError(
                    .themedCustomChatColor,
                    key
                ))
                fallthrough
            case .gradient(let gradientColor1, let gradientColor2, let angleRadians):
                var gradient = BackupProto_ChatStyle.Gradient()
                // Convert radians to degrees.
                gradient.angle = UInt32(angleRadians * 180 / .pi)
                gradient.colors = [gradientColor1.asRGBHex(), gradientColor2.asRGBHex()]
                // iOS only supports 2 "positions"; hardcode them.
                gradient.positions = [0, 1]
                protoColor = .gradient(gradient)
            }

            var proto = BackupProto_ChatStyle.CustomChatColor()
            proto.id = context.assignCustomChatColorId(to: key).value
            proto.color = protoColor

            protos.append(proto)
        }

        if !partialErrors.isEmpty {
            // Just log these errors, but count as success and proceed.
            MessageBackup.log(partialErrors)
        }

        return .success(protos)
    }

    func restoreCustomChatColors(
        _ chatColorProtos: [BackupProto_ChatStyle.CustomChatColor],
        context: MessageBackup.CustomChatColorRestoringContext
    ) -> MessageBackup.RestoreFrameResult<MessageBackup.AccountDataId> {
        var partialErrors = [MessageBackup.RestoreFrameError<MessageBackup.AccountDataId>]()

        for chatColorProto in chatColorProtos {
            let customChatColorId = MessageBackup.CustomChatColorId(value: chatColorProto.id)

            let colorOrGradientSetting: ColorOrGradientSetting
            switch chatColorProto.color {
            case .none:
                partialErrors.append(.restoreFrameError(
                    .invalidProtoData(.unrecognizedCustomChatStyleColor),
                    .forCustomChatColorError(chatColorId: customChatColorId)
                ))
                continue
            case .solid(let colorRGBHex):
                colorOrGradientSetting = .solidColor(
                    color: OWSColor.fromRGBHex(colorRGBHex)
                )
            case .gradient(let gradient):
                // iOS only supports 2 "positions". We take the first
                // and the last colors and call it a day.
                guard
                    gradient.colors.count > 0,
                    let firstColorRGBHex = gradient.colors.first,
                    let lastColorRGBHex = gradient.colors.last
                else {
                    partialErrors.append(.restoreFrameError(
                        .invalidProtoData(.chatStyleGradientSingleOrNoColors),
                        .forCustomChatColorError(chatColorId: customChatColorId)
                    ))
                    continue
                }
                // Angle is in degrees; convert to radians.
                let angleRadians = CGFloat(gradient.angle) * .pi / 180
                colorOrGradientSetting = .gradient(
                    gradientColor1: OWSColor.fromRGBHex(firstColorRGBHex),
                    gradientColor2: OWSColor.fromRGBHex(lastColorRGBHex),
                    angleRadians: angleRadians
                )
            }

            let customChatColorKey = CustomChatColor.Key.generateRandom()

            chatColorSettingStore.upsertCustomValue(
                CustomChatColor(
                    colorSetting: colorOrGradientSetting,
                    // These dates don't really matter for anything other than sorting;
                    // they're not in the proto so just use the current date which is
                    // just as well.
                    creationTimestamp: dateProvider().ows_millisecondsSince1970
                ),
                for: customChatColorKey,
                tx: context.tx
            )

            context.mapCustomChatColorId(
                customChatColorId,
                to: customChatColorKey
            )
        }

        if partialErrors.isEmpty {
            return .success
        } else {
            return .partialRestore(partialErrors)
        }
    }

    // MARK: - Chat Style

    /// Returns a nil result if no field has been explicitly set and therefore the default chat style
    /// should be _unset_ on the settings proto.
    func archiveDefaultChatStyle(
        context: MessageBackup.CustomChatColorArchivingContext
    ) -> MessageBackup.ArchiveSingleFrameResult<BackupProto_ChatStyle?, MessageBackup.AccountDataId> {
        return _archiveChatStyle(
            thread: nil,
            context: context,
            errorId: .localUser
        )
    }

    func archiveChatStyle(
        thread: MessageBackup.ChatThread,
        chatId: MessageBackup.ChatId,
        context: MessageBackup.CustomChatColorArchivingContext
    ) -> MessageBackup.ArchiveSingleFrameResult<BackupProto_ChatStyle?, MessageBackup.ThreadUniqueId> {
        return _archiveChatStyle(
            thread: thread,
            context: context,
            errorId: thread.tsThread.uniqueThreadIdentifier
        )
    }

    /// thread = nil for the default global setting
    private func _archiveChatStyle<IDType>(
        thread: MessageBackup.ChatThread?,
        context: MessageBackup.CustomChatColorArchivingContext,
        errorId: IDType
    ) -> MessageBackup.ArchiveSingleFrameResult<BackupProto_ChatStyle?, IDType> {
        var proto = BackupProto_ChatStyle()

        // If none of the things that feed the fields of the chat style are
        // _explicitly_ set, don't generate a chat style.
        var hasAnExplicitlySetField = false

        let hasBubbleStyle = chatColorSettingStore.hasChatColorSetting(
            for: thread?.tsThread,
            tx: context.tx
        )
        if hasBubbleStyle {
            hasAnExplicitlySetField = true
            let bubbleStyle = chatColorSettingStore.chatColorSetting(
                for: thread?.tsThread,
                tx: context.tx
            )
            switch bubbleStyle {
            case .auto:
                proto.bubbleColor = .autoBubbleColor(BackupProto_ChatStyle.AutomaticBubbleColor())
            case .builtIn(let paletteChatColor):
                proto.bubbleColor = .bubbleColorPreset(paletteChatColor.asBackupProto())
            case .custom(let key, _):
                guard let customColorId = context[key] else {
                    return .failure(.archiveFrameError(
                        .referencedCustomChatColorMissing(key),
                        errorId
                    ))
                }
                proto.bubbleColor = .customColorID(customColorId.value)
            }
        }

        let dimWallpaperInDarkMode = wallpaperStore.fetchOptionalDimInDarkMode(
            for: thread?.tsThread.uniqueId,
            tx: context.tx
        )
        if let dimWallpaperInDarkMode {
            hasAnExplicitlySetField = true
            proto.dimWallpaperInDarkMode = dimWallpaperInDarkMode
        }

        if let wallpaper = wallpaperStore.fetchWallpaper(for: thread?.tsThread.uniqueId, tx: context.tx) {
            hasAnExplicitlySetField = true
            if let preset = wallpaper.asBackupProto() {
                proto.wallpaper = .wallpaperPreset(preset)
            } else if wallpaper == .photo {
                let result = self.archiveWallpaperAttachment(
                    thread: thread,
                    errorId: errorId,
                    context: context
                )
                switch result {
                case .success(let wallpaperAttachmentProto):
                    if let wallpaperAttachmentProto {
                        hasAnExplicitlySetField = true
                        proto.wallpaper = .wallpaperPhoto(wallpaperAttachmentProto)
                    } else {
                        // No wallpaper found; don't set.
                        break
                    }
                case .failure(let error):
                    return .failure(error)
                }
            } else {
                return .failure(.archiveFrameError(
                    .unknownWallpaper,
                    errorId
                ))
            }
        }

        if hasAnExplicitlySetField {
            return .success(proto)
        } else {
            return .success(nil)
        }
    }

    /// - parameter chatStyleProto: Nil if unset in the parent proto (hasFoo is false)
    func restoreDefaultChatStyle(
        _ chatStyleProto: BackupProto_ChatStyle?,
        context: MessageBackup.CustomChatColorRestoringContext
    ) -> MessageBackup.RestoreFrameResult<MessageBackup.AccountDataId> {
        return _restoreChatStyle(
            chatStyleProto,
            thread: nil,
            context: context,
            errorId: .localUser
        )
    }

    /// - parameter chatStyleProto: Nil if unset in the parent proto (hasFoo is false)
    func restoreChatStyle(
        _ chatStyleProto: BackupProto_ChatStyle?,
        thread: MessageBackup.ChatThread,
        chatId: MessageBackup.ChatId,
        context: MessageBackup.CustomChatColorRestoringContext
    ) -> MessageBackup.RestoreFrameResult<MessageBackup.ChatId> {
        return _restoreChatStyle(
            chatStyleProto,
            thread: thread,
            context: context,
            errorId: chatId
        )
    }

    /// - parameter chatStyleProto: Nil if unset in the parent proto (hasFoo is false)
    /// - parameter thread: Nil for the default global setting
    private func _restoreChatStyle<IDType>(
        _ chatStyleProto: BackupProto_ChatStyle?,
        thread: MessageBackup.ChatThread?,
        context: MessageBackup.CustomChatColorRestoringContext,
        errorId: IDType
    ) -> MessageBackup.RestoreFrameResult<IDType> {
        var partialErrors = [MessageBackup.RestoreFrameError<IDType>]()

        if let chatStyleProto {
            switch chatStyleProto.bubbleColor {
            case .none:
                // We can't differentiate between unset bubble color
                // and an unknown type of bubble color oneof case. In
                // either case, treat it as auto.
                fallthrough
            case .autoBubbleColor:
                // Nothing to do! Auto is the default.
                break
            case .bubbleColorPreset(let bubbleColorPreset):
                guard let palette = bubbleColorPreset.asPaletteChatColor() else {
                    return .failure([.restoreFrameError(
                        .invalidProtoData(.unrecognizedChatStyleBubbleColorPreset),
                        errorId
                    )])
                }
                chatColorSettingStore.setChatColorSetting(
                    ChatColorSetting.builtIn(palette),
                    for: thread?.tsThread,
                    tx: context.tx
                )
            case .customColorID(let customColorIdRaw):
                let customColorId = MessageBackup.CustomChatColorId(value: customColorIdRaw)
                guard let customColorKey = context[customColorId] else {
                    return .failure([.restoreFrameError(
                        .invalidProtoData(.customChatColorNotFound(customColorId)),
                        errorId
                    )])
                }
                guard
                    let customColor = chatColorSettingStore.fetchCustomValue(
                        for: customColorKey,
                        tx: context.tx
                    )
                else {
                    return .failure([.restoreFrameError(
                        .referencedCustomChatColorNotFound(customColorKey),
                        errorId
                    )])
                }
                chatColorSettingStore.setChatColorSetting(
                    ChatColorSetting.custom(
                        customColorKey,
                        customColor
                    ),
                    for: thread?.tsThread,
                    tx: context.tx
                )
            }
        }

        if let chatStyleProto {
            wallpaperStore.setDimInDarkMode(
                chatStyleProto.dimWallpaperInDarkMode,
                for: thread?.tsThread.uniqueId,
                tx: context.tx
            )
        }

        if let chatStyleProto {
            switch chatStyleProto.wallpaper {
            case .none:
                // We can't differentiate between unset wallpaper
                // and an unknown type of wallpaper oneof case. In
                // either case, leave the wallpaper unset.
                break
            case .wallpaperPreset(let wallpaperPreset):
                guard let wallpaper = wallpaperPreset.asWallpaper() else {
                    return .failure([.restoreFrameError(
                        .invalidProtoData(.unrecognizedChatStyleWallpaperPreset),
                        errorId
                    )])
                }
                wallpaperStore.setWallpaperType(
                    wallpaper,
                    for: thread?.tsThread.uniqueId,
                    tx: context.tx
                )
            case .wallpaperPhoto(let filePointer):
                wallpaperStore.setWallpaperType(
                    .photo,
                    for: thread?.tsThread.uniqueId,
                    tx: context.tx
                )
                let attachmentResult = restoreWallpaperAttachment(
                    filePointer,
                    thread: thread,
                    errorId: errorId,
                    context: context
                )
                switch attachmentResult {
                case .success:
                    break
                case .partialRestore(let errors):
                    partialErrors.append(contentsOf: errors)
                case .failure(let errors):
                    partialErrors.append(contentsOf: errors)
                    return .failure(partialErrors)
                }
            }
        }

        if partialErrors.isEmpty {
            return .success
        } else {
            return .partialRestore(partialErrors)
        }
    }

    // MARK: - Wallpaper Images

    private func archiveWallpaperAttachment<IDType>(
        thread: MessageBackup.ChatThread?,
        errorId: IDType,
        context: MessageBackup.ArchivingContext
    ) -> MessageBackup.ArchiveSingleFrameResult<BackupProto_FilePointer?, IDType> {
        let owner: AttachmentReference.OwnerId
        if let thread {
            owner = .threadWallpaperImage(threadRowId: thread.threadRowId)
        } else {
            owner = .globalThreadWallpaperImage
        }
        guard
            let referencedAttachment = attachmentStore.fetchFirstReferencedAttachment(
                for: owner,
                tx: context.tx
            )
        else {
            return .success(nil)
        }

        // TODO: [Backups] enqueue the attachment to be uploaded

        let isFreeTierBackup = MessageBackupMessageAttachmentArchiver.isFreeTierBackup()
        return .success(referencedAttachment.asBackupFilePointer(isFreeTierBackup: isFreeTierBackup))
    }

    private func restoreWallpaperAttachment<IDType>(
        _ attachment: BackupProto_FilePointer,
        thread: MessageBackup.ChatThread?,
        errorId: IDType,
        context: MessageBackup.RestoringContext
    ) -> MessageBackup.RestoreFrameResult<IDType> {
        let uploadEra: String
        do {
            uploadEra = try MessageBackupMessageAttachmentArchiver.uploadEra()
        } catch {
            return .failure([.restoreFrameError(
                .uploadEraDerivationFailed(error),
                errorId
            )])
        }

        let ownedAttachment = OwnedAttachmentBackupPointerProto(
            proto: attachment,
            // Wallpapers never have any flag or client id
            renderingFlag: .default,
            clientUUID: nil,
            owner: {
                if let thread {
                    return .threadWallpaperImage(threadRowId: thread.threadRowId)
                } else {
                    return .globalThreadWallpaperImage
                }
            }())

        let errors = attachmentManager.createAttachmentPointers(
            from: [ownedAttachment],
            uploadEra: uploadEra,
            tx: context.tx
        )

        guard errors.isEmpty else {
            // Treat attachment failures as non-catastrophic; a thread without
            // a wallpaper still works.
            return .partialRestore(errors.map { error in
                return .restoreFrameError(
                    .fromAttachmentCreationError(error),
                    errorId
                )
            })
        }

        let results = attachmentStore.fetchReferences(owners: [ownedAttachment.owner.id], tx: context.tx)
        if results.isEmpty {
            return .partialRestore([.restoreFrameError(
                .failedToCreateAttachment,
                errorId
            )])
        }

        do {
            try results.forEach {
                try backupAttachmentDownloadStore.enqueue($0, tx: context.tx)
            }
        } catch {
            return .partialRestore([.restoreFrameError(
                .failedToEnqueueAttachmentDownload(error),
                errorId
            )])
        }

        return .success
    }
}

// MARK: - Converters

// MARK: Wallpaper presets

fileprivate extension Wallpaper {

    func asBackupProto() -> BackupProto_ChatStyle.WallpaperPreset? {
        // These don't match names exactly because...well nobody knows why
        // the iOS enum names were defined this way. They're persisted to the
        // db now, so we just gotta keep the mapping.
        return switch self {
        case .blush: .solidBlush
        case .copper: .solidCopper
        case .zorba: .solidDust
        case .envy: .solidCeladon
        case .sky: .solidPacific
        case .wildBlueYonder: .solidFrost
        case .lavender: .solidLilac
        case .shocking: .solidPink
        case .gray: .solidSilver
        case .eden: .solidRainforest
        case .violet: .solidNavy
        case .eggplant: .solidEggplant
        case .starshipGradient: .gradientSunset
        case .woodsmokeGradient: .gradientNoir
        case .coralGradient: .gradientHeatmap
        case .ceruleanGradient: .gradientAqua
        case .roseGradient: .gradientIridescent
        case .aquamarineGradient: .gradientMonstera
        case .tropicalGradient: .gradientBliss
        case .blueGradient: .gradientSky
        case .bisqueGradient: .gradientPeach
        case .photo: nil
        }
    }
}

fileprivate extension BackupProto_ChatStyle.WallpaperPreset {

    func asWallpaper() -> Wallpaper? {
        // These don't match names exactly because...well nobody knows why
        // the iOS enum names were defined this way. They're persisted to the
        // db now, so we just gotta keep the mapping.
        return switch self {
        // NOTE: This should only return nil for unrecognized/unknown cases.
        case .unknownWallpaperPreset: nil
        case .UNRECOGNIZED: nil
        case .solidBlush: .blush
        case .solidCopper: .copper
        case .solidDust: .zorba
        case .solidCeladon: .envy
        case .solidRainforest: .eden
        case .solidPacific: .sky
        case .solidFrost: .wildBlueYonder
        case .solidNavy: .violet
        case .solidLilac: .lavender
        case .solidPink: .shocking
        case .solidEggplant: .eggplant
        case .solidSilver: .gray
        case .gradientSunset: .starshipGradient
        case .gradientNoir: .woodsmokeGradient
        case .gradientHeatmap: .coralGradient
        case .gradientAqua: .ceruleanGradient
        case .gradientIridescent: .roseGradient
        case .gradientMonstera: .aquamarineGradient
        case .gradientBliss: .tropicalGradient
        case .gradientSky: .blueGradient
        case .gradientPeach: .bisqueGradient
        }
    }
}

// MARK: Bubble Color Presets

fileprivate extension PaletteChatColor {

    func asBackupProto() -> BackupProto_ChatStyle.BubbleColorPreset {
        return switch self {
        case .ultramarine: .solidUltramarine
        case .crimson: .solidCrimson
        case .vermilion: .solidVermilion
        case .burlap: .solidBurlap
        case .forest: .solidForest
        case .wintergreen: .solidWintergreen
        case .teal: .solidTeal
        case .blue: .solidBlue
        case .indigo: .solidIndigo
        case .violet: .solidViolet
        case .plum: .solidPlum
        case .taupe: .solidTaupe
        case .steel: .solidSteel
        case .ember: .gradientEmber
        case .midnight: .gradientMidnight
        case .infrared: .gradientInfrared
        case .lagoon: .gradientLagoon
        case .fluorescent: .gradientFluorescent
        case .basil: .gradientBasil
        case .sublime: .gradientSublime
        case .sea: .gradientSea
        case .tangerine: .gradientTangerine
        }
    }
}

fileprivate extension BackupProto_ChatStyle.BubbleColorPreset {

    func asPaletteChatColor() -> PaletteChatColor? {
        return switch self {
        // NOTE: This should only return nil for unrecognized/unknown cases.
        case .unknownBubbleColorPreset: nil
        case .UNRECOGNIZED: nil
        case .solidUltramarine: .ultramarine
        case .solidCrimson: .crimson
        case .solidVermilion: .vermilion
        case .solidBurlap: .burlap
        case .solidForest: .forest
        case .solidWintergreen: .wintergreen
        case .solidTeal: .teal
        case .solidBlue: .blue
        case .solidIndigo: .indigo
        case .solidViolet: .violet
        case .solidPlum: .plum
        case .solidTaupe: .taupe
        case .solidSteel: .steel
        case .gradientEmber: .ember
        case .gradientMidnight: .midnight
        case .gradientInfrared: .infrared
        case .gradientLagoon: .lagoon
        case .gradientFluorescent: .fluorescent
        case .gradientBasil: .basil
        case .gradientSublime: .sublime
        case .gradientSea: .sea
        case .gradientTangerine: .tangerine
        }
    }
}

// MARK: OWSColor

extension OWSColor {

    func asRGBHex() -> UInt32 {
        return UInt32(red * 255) << 16 | UInt32(green * 255) << 8 | UInt32(blue * 255) << 0
    }

    static func fromRGBHex(_ value: UInt32) -> OWSColor {
        let red = CGFloat(((value >> 16) & 0xff)) / 255.0
        let green = CGFloat(((value >> 8) & 0xff)) / 255.0
        let blue = CGFloat(((value >> 0) & 0xff)) / 255.0
        return OWSColor(red: red, green: green, blue: blue)
    }
}
