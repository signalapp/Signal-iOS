//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AudioToolbox
import SignalCoreKit
import SignalServiceKit

public enum Sound: Equatable {
    case standard(StandardSound)
    case custom(CustomSound)

    public static func == (lhs: Sound, rhs: Sound) -> Bool {
        return lhs.id == rhs.id
    }
}

public extension Sound {

    var id: UInt {
        switch self {
        case .standard(let standardSound):
            return standardSound.rawValue
        case .custom(let customSound):
            return customSound.id
        }
    }

    var displayName: String {
        switch self {
        case .standard(let standardSound):
            return standardSound.displayName

        case .custom(let customSound):
            return customSound.displayName
        }
    }

    var filename: String? {
        filename(quiet: false)
    }

    func filename(quiet: Bool) -> String? {
        switch self {
        case .standard(let standardSound):
            return standardSound.filename(quiet: quiet)
        case .custom(let customSound):
            return customSound.filename
        }
    }

    func soundUrl(quiet: Bool) -> URL? {
        if case .custom(let customSound) = self {
            return customSound.url
        }
        guard
            case .standard(let standardSound) = self,
            let filename = standardSound.filename(quiet: quiet)
        else {
            return nil
        }
        let url = Bundle.main.url(
            forResource: (filename as NSString).deletingPathExtension,
            withExtension: (filename as NSString).pathExtension
        )
        owsAssertDebug(url != nil)
        return url
    }
}

public enum StandardSound: UInt {
    case `default` = 0

    // Notification Sounds
    case aurora = 1
    case bamboo = 2
    case chord = 3
    case circles = 4
    case complete = 5
    case hello = 6
    case input = 7
    case keys = 8
    case note = 9
    case popcorn = 10
    case pulse = 11
    case synth = 12
    case signalClassic = 13

    // Ringtone Sounds
    case reflection = 14

    // Calls
    case callConnecting = 15
    case callOutboundRinging = 16
    case callBusy = 17
    case callEnded = 18

    // Group Calls
    case groupCallJoin = 19
    case groupCallLeave = 20

    // Other
    case messageSent = 21
    case none = 22
    case silence = 23

    // Audio Playback
    case beginNextTrack = 24
    case endLastTrack = 25

    public static let defaultiOSIncomingRingtone: StandardSound = .reflection
}

public extension StandardSound {

    var displayName: String {
        // TODO: Should we localize these sound names?
        switch self {
        case .`default`:
            owsFailDebug("invalid argument.")
            return ""

            // Notification Sounds
        case .aurora: return "Aurora"
        case .bamboo: return "Bamboo"
        case .chord: return "Chord"
        case .circles: return "Circles"
        case .complete: return "Complete"
        case .hello: return "Hello"
        case .input: return "Input"
        case .keys: return "Keys"
        case .note: return "Note"
        case .popcorn: return "Popcorn"
        case .pulse: return "Pulse"
        case .synth: return "Synth"
        case .signalClassic: return "Signal Classic"

            // Ringtone Sounds
        case .reflection: return "Opening"

            // Calls
        case .callConnecting: return "Call Connecting"
        case .callOutboundRinging: return "Call Outboung Ringing"
        case .callBusy: return "Call Busy"
        case .callEnded: return "Call Ended"

            // Group Calls
        case .groupCallJoin: return "Group Call Join"
        case .groupCallLeave: return "Group Call Leave"

            // Other
        case .messageSent: return "Message Sent"
        case .none: return OWSLocalizedString(
            "SOUNDS_NONE",
            comment: "Label for the 'no sound' option that allows users to disable sounds for notifications, etc."
        )
        case .silence: return "Silence"

            // Audio Playback
        case .beginNextTrack:
            return "Begin Next Track"
        case .endLastTrack:
            return "End Last Track"
        }
    }

    fileprivate func filename(quiet: Bool) -> String? {
        switch self {
        case .`default`:
            owsFailDebug("invalid argument.")
            return nil

            // Notification Sounds
        case .aurora:
            return quiet ? "aurora-quiet.aifc" : "aurora.aifc"
        case .bamboo:
            return quiet ? "bamboo-quiet.aifc" : "bamboo.aifc"
        case .chord:
            return quiet ? "chord-quiet.aifc" : "chord.aifc"
        case .circles:
            return quiet ? "circles-quiet.aifc" : "circles.aifc"
        case .complete:
            return quiet ? "complete-quiet.aifc" : "complete.aifc"
        case .hello:
            return quiet ? "hello-quiet.aifc" : "hello.aifc"
        case .input:
            return quiet ? "input-quiet.aifc" : "input.aifc"
        case .keys:
            return quiet ? "keys-quiet.aifc" : "keys.aifc"
        case .note:
            return quiet ? "note-quiet.aifc" : "note.aifc"
        case .popcorn:
            return quiet ? "popcorn-quiet.aifc" : "popcorn.aifc"
        case .pulse:
            return quiet ? "pulse-quiet.aifc" : "pulse.aifc"
        case .synth:
            return quiet ? "synth-quiet.aifc" : "synth.aifc"
        case .signalClassic:
            return quiet ? "classic-quiet.aifc" : "classic.aifc"

            // Ringtone Sounds
        case .reflection: return "Reflection.m4r"

            // Calls
        case .callConnecting: return "ringback_tone_ansi.caf"
        case .callOutboundRinging: return "ringback_tone_ansi.caf"
        case .callBusy: return "busy_tone_ansi.caf"
        case .callEnded: return "end_call_tone_cept.caf"

            // Group Calls
        case .groupCallJoin: return "group_call_join.aiff"
        case .groupCallLeave: return "group_call_leave.aiff"

            // Other
        case .messageSent: return "message_sent.aiff"
        case .silence: return "silence.aiff"
        case .none: return nil

            // Audio Playback
        case .beginNextTrack: return "state-change_confirm-down.caf"
        case .endLastTrack: return "state-change_confirm-up.caf"
        }
    }
}

public struct CustomSound {

    let id: UInt
    let filename: String

    private init(id: UInt, filename: String) {
        self.id = id
        self.filename = filename
    }

    init?(filename: String) {
        guard let id = CustomSound.idFromFilename(filename) else {
            return nil
        }
        self.id = id
        self.filename = filename
    }

    fileprivate var displayName: String {
        let filenameWithoutExtension = (filename as NSString).deletingPathExtension
        guard !filenameWithoutExtension.isEmpty else {
            owsFailDebug("Empty filename")
            return "Custom Sound"
        }
        return filenameWithoutExtension.capitalized
    }

    fileprivate var url: URL {
        return URL(fileURLWithPath: Sounds.soundsDirectory, isDirectory: true).appendingPathComponent(filename)
    }

    fileprivate static var all: [CustomSound] {
        let filenames: [String]
        do {
            filenames = try FileManager.default.contentsOfDirectory(atPath: Sounds.soundsDirectory)
        } catch {
            owsFailDebug("Failed retrieving custom sound files: \(error)")
            return []
        }

        let sounds: [CustomSound] = filenames.compactMap { filename in
            guard filename != Sounds.defaultNotificationSoundFilename else { return nil }
            return CustomSound(filename: filename)
        }
        return sounds
    }

    // MARK: -

    private static let customSoundShift: UInt = 16

    private static func idFromFilename(_ filename: String) -> UInt? {
        guard let filenameData = filename.data(using: .utf8) else {
            owsFailDebug("could not get data from filename.")
            return nil
        }
        guard let hashData = Cryptography.computeSHA256Digest(filenameData, truncatedToBytes: UInt(MemoryLayout<UInt>.size)) else {
            owsFailDebug("could not get hash from filename.")
            return nil
        }

        var hashValue: UInt = 0
        hashData.withUnsafeBytes { ptr in
            hashValue = ptr.load(as: UInt.self)
        }
        return hashValue << customSoundShift
    }
}

private class SystemSound: NSObject {

    let id: SystemSoundID
    let soundUrl: URL

    init?(url: URL) {
        var newSoundId: SystemSoundID = 0
        guard
            kAudioServicesNoError == AudioServicesCreateSystemSoundID(url as CFURL, &newSoundId),
            newSoundId != 0
        else {
            owsFailDebug("AudioServicesCreateSystemSoundID failed")
            return nil
        }
        id = newSoundId
        soundUrl = url
        super.init()
    }

    deinit {
        Logger.debug("in dealloc disposing sound: \(soundUrl.lastPathComponent))")
        let status = AudioServicesDisposeSystemSoundID(id)
        owsAssertDebug(status == kAudioServicesNoError)
    }
}

public class Sounds: Dependencies {

    // This name is specified in the payload by the Signal Service when requesting fallback push notifications.
    fileprivate static let defaultNotificationSoundFilename = "NewMessage.aifc"
    fileprivate static let soundsStorageGlobalNotificationKey = "kOWSSoundsStorageGlobalNotificationKey"

    private static let cachedSystemSounds = AnyLRUCache(maxSize: 4, nseMaxSize: 0, shouldEvacuateInBackground: false)

    private static let keyValueStore = SDSKeyValueStore(collection: "kOWSSoundsStorageNotificationCollection")

    private init() { }

    public static func performStartupTasks() {
        AppReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            Sounds.migrateLegacySounds()
            Sounds.cleanupOrphanedSounds()
        }
    }

    // MARK: - Public

    public static var allNotificationSounds: [Sound] {
        let standardSounds: [StandardSound] = [
            // None and Note (default) should be first.
            .none,
            .note,
            .aurora,
            .bamboo,
            .chord,
            .circles,
            .complete,
            .hello,
            .input,
            .keys,
            .popcorn,
            .pulse,
            .signalClassic,
            .synth
        ]
        let customSounds = CustomSound.all
        return standardSounds.map({ Sound.standard($0) }) + customSounds.map({ Sound.custom($0) })
    }

    public static var soundsDirectory: String {
        let directory = OWSFileSystem.appSharedDataDirectoryPath().appendingPathComponent("Library/Sounds")
        OWSFileSystem.ensureDirectoryExists(directory)
        return directory
    }

    public static func systemSoundIDForSound(_ sound: Sound, quiet: Bool) -> SystemSoundID? {
        let cacheKey = String(format: "%lu:%d", sound.id, quiet)
        if let cachedSound = cachedSystemSounds.get(key: cacheKey as NSString) as? SystemSound {
            return cachedSound.id
        }

        guard
            let soundUrl = sound.soundUrl(quiet: quiet),
            let systemSound = SystemSound(url: soundUrl)
        else {
            owsFailDebug("Failed to create system sound")
            return nil
        }
        cachedSystemSounds.set(key: cacheKey as NSString, value: systemSound)
        return systemSound.id
    }

    public static func importSoundsAtUrls(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        let fileManager = FileManager.default
        for url in urls {
            let filename = url.lastPathComponent
            guard
                !filename.isEmpty,
                let destinationUrl = NSURL(fileURLWithPath: soundsDirectory, isDirectory: true).appendingPathComponent(filename),
                !fileManager.fileExists(atPath: destinationUrl.path)
            else {
                continue
            }

            do {
                try fileManager.copyItem(at: url, to: destinationUrl)
            } catch {
                owsFailDebug("Failed to import custom sound with error: \(error)")
            }
        }
    }

    // MARK: - Notifications

    public static var defaultNotificationSound: Sound { .standard(.note) }

    private static func soundForId(_ soundId: UInt) -> Sound {
        if let standardSound = StandardSound(rawValue: soundId) {
            return .standard(standardSound)
        }
        if let customSound = CustomSound.all.first(where: { $0.id == soundId }) {
            return .custom(customSound)
        }
        return defaultNotificationSound
    }

    public static var globalNotificationSound: Sound {
        let soundId = databaseStorage.read { transaction in
            return keyValueStore.getUInt(soundsStorageGlobalNotificationKey, transaction: transaction)
        }
        guard let soundId else { return defaultNotificationSound }
        return soundForId(soundId)
    }

    public static func setGlobalNotificationSound(_ sound: Sound) {
        databaseStorage.write { transaction in
            setGlobalNotificationSound(sound, transaction: transaction)
        }
    }

    private static func setGlobalNotificationSound(_ sound: Sound, transaction: SDSAnyWriteTransaction) {
        Logger.info("Setting global notification sound to: \(sound.displayName)")

        // Fallback push notifications play a sound specified by the server, but we don't want to store this configuration
        // on the server. Instead, we create a file with the same name as the default to be played when receiving
        // a fallback notification.

        let defaultSoundUrl = URL(fileURLWithPath: soundsDirectory, isDirectory: true).appendingPathComponent(defaultNotificationSoundFilename)

        Logger.debug("writing new default sound to \(defaultSoundUrl)")

        let soundUrl = sound.soundUrl(quiet: false)
        let soundData: Data = {
            if let soundUrl, let data = try? Data(contentsOf: soundUrl) {
                return data
            }
            guard sound == .standard(.none) else {
                owsFailDebug("Failed to load sound data.")
                return Data()
            }
            return Data()
        }()

        // Quick way to achieve an atomic "copy" operation that allows overwriting if the user has previously specified
        // a default notification sound.
        do {
            try soundData.write(to: defaultSoundUrl, options: .atomic)
        } catch {
            owsFailDebug("Unable to write new default sound data from: \(String(describing: soundUrl)) to \(defaultSoundUrl): \(error)")
            return
        }

        // The globally configured sound the user has configured is unprotected, so that we can still play the sound if the
        // user hasn't authenticated after power-cycling their device.
        OWSFileSystem.protectFileOrFolder(atPath: defaultSoundUrl.path, fileProtectionType: .none)

        keyValueStore.setUInt(sound.id, key: soundsStorageGlobalNotificationKey, transaction: transaction)
    }

    public static func notificationSoundForThread(_ thread: TSThread) -> Sound {
        let soundId = databaseStorage.read { transaction in
            return keyValueStore.getUInt(thread.uniqueId, transaction: transaction)
        }
        guard let soundId else { return globalNotificationSound }
        return soundForId(soundId)
    }

    public static func setNotificationSound(_ sound: Sound, forThread thread: TSThread) {
        databaseStorage.write { transaction in
            keyValueStore.setUInt(sound.id, key: thread.uniqueId, transaction: transaction)
        }
    }

    // MARK: - Util

    private static func deleteCustomSound(_ sound: CustomSound) -> Bool {
        do {
            try OWSFileSystem.deleteFileIfExists(url: sound.url)
            return true
        } catch {
            owsFailDebug("Failed to delete custom sound: \(error)")
            return false
        }
    }

    private static func migrateLegacySounds() {
        owsAssertDebug(CurrentAppContext().isMainApp)

        let legacySoundsDirectory = OWSFileSystem.appLibraryDirectoryPath().appendingPathComponent("Sounds")
        guard OWSFileSystem.fileOrFolderExists(atPath: legacySoundsDirectory) else { return }

        guard let legacySoundFiles = try? FileManager.default.contentsOfDirectory(atPath: legacySoundsDirectory) else {
            owsFailDebug("Failed looking up legacy sound files")
            return
        }

        for soundFile in legacySoundFiles {
            do {
                try FileManager.default.moveItem(
                    atPath: legacySoundsDirectory.appendingPathComponent(soundFile),
                    toPath: soundsDirectory.appendingPathComponent(soundFile)
                )
            } catch {
                owsFailDebug("Failed to migrate legacy sound file: \(error)")
            }
        }

        if !OWSFileSystem.deleteFile(legacySoundsDirectory) {
            owsFailDebug("Failed to delete legacy sounds directory")
        }
    }

    private static func cleanupOrphanedSounds() {
        owsAssertDebug(CurrentAppContext().isMainApp)

        let allCustomSounds = CustomSound.all
        guard !allCustomSounds.isEmpty else { return }

        let allInUseSoundIds = databaseStorage.read { transaction in
            return Set(keyValueStore.allValues(transaction: transaction) as! [UInt])
        }

        let orphanedSounds = allCustomSounds.filter { !allInUseSoundIds.contains($0.id) }
        guard !orphanedSounds.isEmpty else { return }

        var deletedCount: UInt = 0
        for sound in orphanedSounds {
            if deleteCustomSound(sound) {
                deletedCount += 1
            }
        }

        Logger.info("Cleaned up \(deletedCount) orphaned custom sounds.")
    }
}
