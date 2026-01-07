//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class BackupArchiveChatStyleArchiver: BackupArchiveProtoStreamWriter {

    private let attachmentManager: AttachmentManager
    private let attachmentStore: AttachmentStore
    private let backupAttachmentDownloadScheduler: BackupAttachmentDownloadScheduler
    private let chatColorSettingStore: ChatColorSettingStore
    private let wallpaperStore: WallpaperStore

    public init(
        attachmentManager: AttachmentManager,
        attachmentStore: AttachmentStore,
        backupAttachmentDownloadScheduler: BackupAttachmentDownloadScheduler,
        chatColorSettingStore: ChatColorSettingStore,
        wallpaperStore: WallpaperStore,
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.backupAttachmentDownloadScheduler = backupAttachmentDownloadScheduler
        self.chatColorSettingStore = chatColorSettingStore
        self.wallpaperStore = wallpaperStore
    }

    // MARK: - Custom Chat Colors

    func archiveCustomChatColors(
        context: BackupArchive.CustomChatColorArchivingContext,
    ) -> BackupArchive.ArchiveSingleFrameResult<[BackupProto_ChatStyle.CustomChatColor], BackupArchive.AccountDataId> {
        var partialErrors = [BackupArchive.ArchiveFrameError<CustomChatColor.Key>]()
        var protos = [BackupProto_ChatStyle.CustomChatColor]()

        for (key, customChatColor) in chatColorSettingStore.fetchCustomValues(tx: context.tx) {

            let protoColor: BackupProto_ChatStyle.CustomChatColor.OneOf_Color
            switch customChatColor.colorSetting {
            case .themedColor(let color, _):
                // Themes should be impossible with custom chat colors; add an error
                // but just take the light theme color and keep going.
                partialErrors.append(.archiveFrameError(
                    .themedCustomChatColor,
                    key,
                ))
                fallthrough
            case .solidColor(let color):
                protoColor = .solid(color.asARGBHex())
            case .themedGradient(let gradientColor1, let gradientColor2, _, _, let angleRadians):
                // Themes should be impossible with custom chat colors; add an error
                // but just take the light theme colors and keep going.
                partialErrors.append(.archiveFrameError(
                    .themedCustomChatColor,
                    key,
                ))
                fallthrough
            case .gradient(let gradientColor1, let gradientColor2, var angleRadians):
                var gradient = BackupProto_ChatStyle.Gradient()

                /// Convert radians to degrees. We manually round since the
                /// float math is slightly lossy and sometimes gives back
                /// `N.99999999999`; we want to return `N+1`, but the `UInt32`
                /// conversion always rounds down.
                while angleRadians < 0 {
                    angleRadians += .pi * 2
                }
                gradient.angle = UInt32(round(angleRadians * 180 / .pi))

                /// iOS only supports 2 "positions"; hardcode them.
                gradient.positions = [0, 1]
                gradient.colors = [gradientColor1.asARGBHex(), gradientColor2.asARGBHex()]

                protoColor = .gradient(gradient)
            }

            var proto = BackupProto_ChatStyle.CustomChatColor()
            proto.id = context.assignCustomChatColorId(to: key).value
            proto.color = protoColor

            protos.append(proto)
        }

        if !partialErrors.isEmpty {
            // Just log these errors, but count as success and proceed.
            BackupArchive
                .collapse(
                    partialErrors
                        .map { BackupArchive.LoggableErrorAndProto(error: $0, wasFrameDropped: false) },
                )
                .forEach { $0.log() }
        }

        return .success(protos)
    }

    func restoreCustomChatColors(
        _ chatColorProtos: [BackupProto_ChatStyle.CustomChatColor],
        context: BackupArchive.CustomChatColorRestoringContext,
    ) -> BackupArchive.RestoreFrameResult<BackupArchive.AccountDataId> {
        var partialErrors = [BackupArchive.RestoreFrameError<BackupArchive.AccountDataId>]()

        /// We track a `creationTimestamp` for custom chat colors. In practice
        /// that value isn't used for anything beyond sorting; however, because
        /// we want the persisted sort order to be consistent with the ordering
        /// in the Backup, we can't use the same timestamp for all colors. To
        /// that end, we'll start with "now" and increment as we create more
        /// colors.
        var chatColorCreationTimestamp = context.startTimestampMs

        for chatColorProto in chatColorProtos {
            let customChatColorId = BackupArchive.CustomChatColorId(value: chatColorProto.id)

            let colorOrGradientSetting: ColorOrGradientSetting
            switch chatColorProto.color {
            case .none:
                // Fallback to default (skip this chat color)
                continue
            case .solid(let colorARGBHex):
                colorOrGradientSetting = .solidColor(
                    color: OWSColor.fromARGBHex(colorARGBHex),
                )
            case .gradient(let gradient):
                // iOS only supports 2 "positions". We take the first
                // and the last colors and call it a day.
                guard
                    gradient.colors.count > 0,
                    let firstColorARGBHex = gradient.colors.first,
                    let lastColorARGBHex = gradient.colors.last
                else {
                    partialErrors.append(.restoreFrameError(
                        .invalidProtoData(.chatStyleGradientSingleOrNoColors),
                        .forCustomChatColorError(chatColorId: customChatColorId),
                    ))
                    continue
                }
                // Angle is in degrees; convert to radians.
                let angleRadians = CGFloat(gradient.angle) * .pi / 180
                colorOrGradientSetting = .gradient(
                    gradientColor1: OWSColor.fromARGBHex(firstColorARGBHex),
                    gradientColor2: OWSColor.fromARGBHex(lastColorARGBHex),
                    angleRadians: angleRadians,
                )
            }

            let customChatColorKey = CustomChatColor.Key.generateRandom()

            chatColorSettingStore.upsertCustomValue(
                CustomChatColor(
                    colorSetting: colorOrGradientSetting,
                    // These dates don't really matter for anything other than sorting;
                    // they're not in the proto so just use the current date which is
                    // just as well.
                    creationTimestamp: {
                        let retVal = chatColorCreationTimestamp
                        chatColorCreationTimestamp += 1
                        return retVal
                    }(),
                ),
                for: customChatColorKey,
                tx: context.tx,
            )

            context.mapCustomChatColorId(
                customChatColorId,
                to: customChatColorKey,
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
        context: BackupArchive.CustomChatColorArchivingContext,
    ) -> BackupArchive.ArchiveSingleFrameResult<BackupProto_ChatStyle?, BackupArchive.AccountDataId> {
        return _archiveChatStyle(
            thread: nil,
            context: context,
            errorId: .localUser,
        )
    }

    func archiveChatStyle(
        thread: BackupArchive.ChatThread,
        context: BackupArchive.CustomChatColorArchivingContext,
    ) -> BackupArchive.ArchiveSingleFrameResult<BackupProto_ChatStyle?, BackupArchive.ThreadUniqueId> {
        return _archiveChatStyle(
            thread: thread,
            context: context,
            errorId: thread.tsThread.uniqueThreadIdentifier,
        )
    }

    /// thread = nil for the default global setting
    private func _archiveChatStyle<IDType>(
        thread: BackupArchive.ChatThread?,
        context: BackupArchive.CustomChatColorArchivingContext,
        errorId: IDType,
    ) -> BackupArchive.ArchiveSingleFrameResult<BackupProto_ChatStyle?, IDType> {
        var proto = BackupProto_ChatStyle()
        // This can never be unset, so we'll default it to "auto". If we have an
        // explicit bubble color, we'll overwrite this below.
        proto.bubbleColor = .autoBubbleColor(BackupProto_ChatStyle.AutomaticBubbleColor())

        // If none of the things that feed the fields of the chat style are
        // _explicitly_ set, don't generate a chat style.
        var hasAnExplicitlySetField = false

        if let wallpaper = wallpaperStore.fetchWallpaper(for: thread?.tsThread.uniqueId, tx: context.tx) {
            let protoWallpaper: BackupProto_ChatStyle.OneOf_Wallpaper?

            switch wallpaper.asBackupProto() {
            case .wallpaperPreset(let preset):
                protoWallpaper = .wallpaperPreset(preset)
            case .photo:
                switch self.archiveWallpaperAttachment(
                    thread: thread,
                    errorId: errorId,
                    context: context,
                ) {
                case .success(.some(let wallpaperAttachmentProto)):
                    protoWallpaper = .wallpaperPhoto(wallpaperAttachmentProto)
                case .success(nil):
                    protoWallpaper = nil
                case .failure(let error):
                    return .failure(error)
                }
            }

            if let protoWallpaper {
                hasAnExplicitlySetField = true
                proto.wallpaper = protoWallpaper
            }
        }

        let hasBubbleStyle = chatColorSettingStore.hasChatColorSetting(
            for: thread?.tsThread,
            tx: context.tx,
        )
        if hasBubbleStyle {
            hasAnExplicitlySetField = true
            let bubbleStyle = chatColorSettingStore.chatColorSetting(
                for: thread?.tsThread,
                tx: context.tx,
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
                        errorId,
                    ))
                }
                proto.bubbleColor = .customColorID(customColorId.value)
            }
        }

        let dimWallpaperInDarkMode = wallpaperStore.fetchDimInDarkMode(
            for: thread?.tsThread.uniqueId,
            tx: context.tx,
        )
        if let dimWallpaperInDarkMode {
            hasAnExplicitlySetField = true
            proto.dimWallpaperInDarkMode = dimWallpaperInDarkMode
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
        context: BackupArchive.CustomChatColorRestoringContext,
    ) -> BackupArchive.RestoreFrameResult<BackupArchive.AccountDataId> {
        return _restoreChatStyle(
            chatStyleProto,
            thread: nil,
            context: context,
            errorId: .localUser,
        )
    }

    /// - parameter chatStyleProto: Nil if unset in the parent proto (hasFoo is false)
    func restoreChatStyle(
        _ chatStyleProto: BackupProto_ChatStyle?,
        thread: BackupArchive.ChatThread,
        chatId: BackupArchive.ChatId,
        context: BackupArchive.CustomChatColorRestoringContext,
    ) -> BackupArchive.RestoreFrameResult<BackupArchive.ChatId> {
        return _restoreChatStyle(
            chatStyleProto,
            thread: thread,
            context: context,
            errorId: chatId,
        )
    }

    /// - parameter chatStyleProto: Nil if unset in the parent proto (hasFoo is false)
    /// - parameter thread: Nil for the default global setting
    private func _restoreChatStyle<IDType>(
        _ chatStyleProto: BackupProto_ChatStyle?,
        thread: BackupArchive.ChatThread?,
        context: BackupArchive.CustomChatColorRestoringContext,
        errorId: IDType,
    ) -> BackupArchive.RestoreFrameResult<IDType> {
        var partialErrors = [BackupArchive.RestoreFrameError<IDType>]()

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
                    // If we can't recognize the preset, use auto (skip)
                    break
                }
                chatColorSettingStore.setChatColorSetting(
                    ChatColorSetting.builtIn(palette),
                    for: thread?.tsThread,
                    tx: context.tx,
                )
            case .customColorID(let customColorIdRaw):
                let customColorId = BackupArchive.CustomChatColorId(value: customColorIdRaw)
                guard let customColorKey = context[customColorId] else {
                    return .failure([.restoreFrameError(
                        .invalidProtoData(.customChatColorNotFound(customColorId)),
                        errorId,
                    )])
                }
                guard
                    let customColor = chatColorSettingStore.fetchCustomValue(
                        for: customColorKey,
                        tx: context.tx,
                    )
                else {
                    return .failure([.restoreFrameError(
                        .referencedCustomChatColorNotFound(customColorKey),
                        errorId,
                    )])
                }
                chatColorSettingStore.setChatColorSetting(
                    ChatColorSetting.custom(
                        customColorKey,
                        customColor,
                    ),
                    for: thread?.tsThread,
                    tx: context.tx,
                )
            }
        }

        if let chatStyleProto {
            wallpaperStore.setDimInDarkMode(
                chatStyleProto.dimWallpaperInDarkMode,
                for: thread?.tsThread.uniqueId,
                tx: context.tx,
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
                    // If we can't recognize the preset enum,
                    // leave the wallpaper unset.
                    break
                }
                wallpaperStore.setWallpaperType(
                    wallpaper,
                    for: thread?.tsThread.uniqueId,
                    tx: context.tx,
                )
            case .wallpaperPhoto(let filePointer):
                wallpaperStore.setWallpaperType(
                    .photo,
                    for: thread?.tsThread.uniqueId,
                    tx: context.tx,
                )
                let attachmentResult = restoreWallpaperAttachment(
                    filePointer,
                    thread: thread,
                    errorId: errorId,
                    context: context,
                )
                switch attachmentResult {
                case .success:
                    break
                case .unrecognizedEnum:
                    return attachmentResult
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
        thread: BackupArchive.ChatThread?,
        errorId: IDType,
        context: BackupArchive.ArchivingContext,
    ) -> BackupArchive.ArchiveSingleFrameResult<BackupProto_FilePointer?, IDType> {
        let owner: AttachmentReference.OwnerId
        if let thread {
            owner = .threadWallpaperImage(threadRowId: thread.threadRowId)
        } else {
            owner = .globalThreadWallpaperImage
        }
        guard
            let referencedAttachment = attachmentStore.fetchAnyReferencedAttachment(
                for: owner,
                tx: context.tx,
            )
        else {
            return .success(nil)
        }

        return .success(referencedAttachment.asBackupFilePointer(
            currentBackupAttachmentUploadEra: context.currentBackupAttachmentUploadEra,
            attachmentByteCounter: context.attachmentByteCounter,
        ))
    }

    private func restoreWallpaperAttachment<IDType>(
        _ attachment: BackupProto_FilePointer,
        thread: BackupArchive.ChatThread?,
        errorId: IDType,
        context: BackupArchive.CustomChatColorRestoringContext,
    ) -> BackupArchive.RestoreFrameResult<IDType> {
        guard let uploadEra = context.accountDataContext.uploadEra else {
            return .failure([.restoreFrameError(
                .invalidProtoData(.accountDataNotFound),
                errorId,
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
            }(),
        )

        let error = attachmentManager.createAttachmentPointer(
            from: ownedAttachment,
            uploadEra: uploadEra,
            attachmentByteCounter: context.attachmentByteCounter,
            tx: context.tx,
        )

        if let error {
            // Treat attachment failures as non-catastrophic; a thread without
            // a wallpaper still works.
            return .partialRestore([.restoreFrameError(
                .fromAttachmentCreationError(error),
                errorId,
            )])
        }

        let results = attachmentStore.fetchReferencedAttachments(owners: [ownedAttachment.owner.id], tx: context.tx)
        if results.isEmpty {
            return .partialRestore([.restoreFrameError(
                .failedToCreateAttachment,
                errorId,
            )])
        }

        guard let backupPlan = context.accountDataContext.backupPlan else {
            return .failure([.restoreFrameError(
                .invalidProtoData(
                    .accountDataNotFound,
                ),
                errorId,
            )])
        }

        for referencedAttachment in results {
            backupAttachmentDownloadScheduler.enqueueFromBackupIfNeeded(
                referencedAttachment,
                restoreStartTimestampMs: context.startTimestampMs,
                backupPlan: backupPlan,
                remoteConfig: context.accountDataContext.currentRemoteConfig,
                isPrimaryDevice: context.isPrimaryDevice,
                tx: context.tx,
            )
        }

        return .success
    }
}

// MARK: - Converters

// MARK: Wallpaper presets

private extension Wallpaper {

    enum BackupRepresentation {
        case wallpaperPreset(BackupProto_ChatStyle.WallpaperPreset)
        case photo
    }

    func asBackupProto() -> BackupRepresentation {
        // These don't match names exactly because...well nobody knows why
        // the iOS enum names were defined this way. They're persisted to the
        // db now, so we just gotta keep the mapping.
        return switch self {
        case .blush: .wallpaperPreset(.solidBlush)
        case .copper: .wallpaperPreset(.solidCopper)
        case .zorba: .wallpaperPreset(.solidDust)
        case .envy: .wallpaperPreset(.solidCeladon)
        case .sky: .wallpaperPreset(.solidPacific)
        case .wildBlueYonder: .wallpaperPreset(.solidFrost)
        case .lavender: .wallpaperPreset(.solidLilac)
        case .shocking: .wallpaperPreset(.solidPink)
        case .gray: .wallpaperPreset(.solidSilver)
        case .eden: .wallpaperPreset(.solidRainforest)
        case .violet: .wallpaperPreset(.solidNavy)
        case .eggplant: .wallpaperPreset(.solidEggplant)
        case .starshipGradient: .wallpaperPreset(.gradientSunset)
        case .woodsmokeGradient: .wallpaperPreset(.gradientNoir)
        case .coralGradient: .wallpaperPreset(.gradientHeatmap)
        case .ceruleanGradient: .wallpaperPreset(.gradientAqua)
        case .roseGradient: .wallpaperPreset(.gradientIridescent)
        case .aquamarineGradient: .wallpaperPreset(.gradientMonstera)
        case .tropicalGradient: .wallpaperPreset(.gradientBliss)
        case .blueGradient: .wallpaperPreset(.gradientSky)
        case .bisqueGradient: .wallpaperPreset(.gradientPeach)
        case .photo: .photo
        }
    }
}

private extension BackupProto_ChatStyle.WallpaperPreset {

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

private extension PaletteChatColor {

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

private extension BackupProto_ChatStyle.BubbleColorPreset {

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

private extension OWSColor {

    /// Returns this color as an `0xAARRGGBB` hex value.
    func asARGBHex() -> UInt32 {
        let alphaComponent = UInt32(255) << 24
        let redComponent = UInt32(round(red * 255)) << 16
        let greenComponent = UInt32(round(green * 255)) << 8
        let blueComponent = UInt32(round(blue * 255)) << 0

        return alphaComponent | redComponent | greenComponent | blueComponent
    }

    /// Builds a color from an `0xAARRGGBB` hex value.
    static func fromARGBHex(_ value: UInt32) -> OWSColor {
        // let alpha = CGFloat(((value >> 24) & 0xff)) / 255.0
        let red = CGFloat((value >> 16) & 0xff) / 255.0
        let green = CGFloat((value >> 8) & 0xff) / 255.0
        let blue = CGFloat((value >> 0) & 0xff) / 255.0
        return OWSColor(red: red, green: green, blue: blue)
    }
}
