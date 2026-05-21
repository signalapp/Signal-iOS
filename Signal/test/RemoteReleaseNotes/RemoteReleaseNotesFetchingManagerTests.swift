//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import LibSignalClient
@testable import SignalServiceKit

@MainActor
struct RemoteReleaseNotesFetchingManagerTests {
    private let db = InMemoryDB()
    private let remoteReleaseNotesFetchingManager: RemoteReleaseNotesFetchingManager

    init() {
        remoteReleaseNotesFetchingManager = RemoteReleaseNotesFetchingManager(
            db: db,
            remoteReleaseNotesService: MockRemoteReleaseNotesService(),
        )
    }

    @Test
    func testRemoteMegaphoneFetch() async throws {
        try await remoteReleaseNotesFetchingManager.syncRemoteReleaseNotes()

        db.read { tx in
            ExperienceUpgrade.anyEnumerate(transaction: tx) { upgrade, _ in
                switch upgrade.manifest {
                case .remoteMegaphone(let megaphone):
                    #expect(megaphone.translation.title == "Donate Today")
                    #expect(megaphone.translation.body == "Support privacy by donating to Signal. We're counting on your support.")
                    #expect(megaphone.translation.secondaryActionText == "Not now")
                    #expect(megaphone.translation.primaryActionText == "Donate")
                    #expect(megaphone.translation.hasImage == false)
                default:
                    #expect(Bool(false), "unexpected upgrade: \(upgrade)")
                }
            }
        }
    }
}

class MockRemoteReleaseNotesService: RemoteReleaseNotesServiceProtocol {
    let uuid: String = UUID().uuidString

    func fetchManifests() async throws -> ([RemoteMegaphoneModel.Manifest], [RemoteAnnouncementModel.Manifest]) {

        return ([RemoteMegaphoneModel.Manifest(
            id: uuid,
            priority: 100,
            minAppVersion: "6.1.0.17",
            countries: "1:1000000",
            dontShowBefore: 0,
            dontShowAfter: UInt64(Date.distantFuture.timeIntervalSince1970),
            showForNumberOfDays: 30,
            conditionalCheck: RemoteMegaphoneModel.Manifest.ConditionalCheck(fromConditionalId: "standard_donate"),
            primaryAction: RemoteMegaphoneModel.Manifest.Action(fromActionId: "primaryCtaId"),
            primaryActionData: nil,
            secondaryAction: RemoteMegaphoneModel.Manifest.Action(fromActionId: "snooze"),
            secondaryActionData: try RemoteMegaphoneModel.Manifest.ActionData.parse(
                fromJson: ["snoozeDurationDays": [UInt(5), UInt(7), UInt(100)]],
            ),
        )], [])
    }

    func fetchTranslationParser(translationUrlPath: String) async throws -> ParamParser {
        return ParamParser(
            [
                "image": "/static/release-notes/donate-heart.png",
                "uuid": uuid,
                "secondaryCtaText": "Not now",
                "body": "Support privacy by donating to Signal. We're counting on your support.",
                "primaryCtaText": "Donate",
                "title": "Donate Today",
            ],
        )
    }

    func downloadMedia(mediaRemoteUrlPath: String, mediaFileUrl: URL, translationId: String) async throws -> Bool {
        return false
    }
}
