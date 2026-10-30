//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing
import XCTest
@testable import SignalServiceKit

struct SoundsTest {
    @Test(arguments: [
        ("Hello.m4a", 7562547131314274304),
        ("Goodbye.mp4", 10601446312307589120),
    ])
    func testCustomSoundId(testCase: (filename: String, id: UInt64)) {
        #expect(CustomSound.idFromFilename(testCase.filename) == testCase.id)
    }
}

final class DeleteCustomSoundTest: SSKBaseTest {

    private func writeTestSoundFile(_ filename: String) throws -> URL {
        let soundUrl = URL(fileURLWithPath: Sounds.soundsDirectory, isDirectory: true)
            .appendingPathComponent(filename)
        try Data([0x00]).write(to: soundUrl)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: soundUrl)
        }
        return soundUrl
    }

    func testDeleteCustomSound() throws {
        let filename = "TestDeleteCustomSound.aifc"
        let soundUrl = try writeTestSoundFile(filename)

        let sound = Sound.custom(CustomSound(filename: filename))
        XCTAssertTrue(Sounds.allNotificationSounds.contains(sound))

        Sounds.deleteCustomSound(sound)

        XCTAssertFalse(FileManager.default.fileExists(atPath: soundUrl.path))
        XCTAssertFalse(Sounds.allNotificationSounds.contains(sound))
    }

    func testDeleteCustomSoundClearsReferences() throws {
        let filename = "TestDeleteReferencedSound.aifc"
        _ = try writeTestSoundFile(filename)

        let sound = Sound.custom(CustomSound(filename: filename))
        let notificationPreferencesManager = DependenciesBridge.shared.notificationPreferencesManager

        let originalSound = SSKEnvironment.shared.databaseStorageRef.read { tx in
            notificationPreferencesManager.globalNotificationSound(tx: tx)
        }
        addTeardownBlock {
            SSKEnvironment.shared.databaseStorageRef.write { tx in
                notificationPreferencesManager.setGlobalNotificationSound(originalSound, tx: tx)
            }
        }

        write { tx in
            notificationPreferencesManager.setGlobalNotificationSound(sound, tx: tx)
        }

        Sounds.deleteCustomSound(sound)

        let globalSound = SSKEnvironment.shared.databaseStorageRef.read { tx in
            notificationPreferencesManager.globalNotificationSound(tx: tx)
        }
        XCTAssertEqual(globalSound, NotificationPreferencesManager.Defaults.globalNotificationSound)
    }
}
