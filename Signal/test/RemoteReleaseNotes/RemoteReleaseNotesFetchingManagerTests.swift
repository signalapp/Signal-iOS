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
    private let experienceUpgradeStore = ExperienceUpgradeStore()
    private let mockThreadStore = MockThreadStore()
    private let mockInteractionStore = MockInteractionStore()
    private var remoteReleaseNotesFetchingManager: RemoteReleaseNotesFetchingManager
    private let mockRemoteReleaseNotesService: MockRemoteReleaseNotesService = MockRemoteReleaseNotesService()
    private let mockAppVersion: MockAppVersion
    private var mockTSAccountManager = MockTSAccountManager()
    private let blockedReleaseNotesStore = BlockedReleaseNotesStore()
    private let releaseNotesStore = ReleaseNoteStore()

    init() {
        // To avoid hitting the ThreadAssociatedData dependency that testing can't support, pre-seed the thread in the thread store.
        mockThreadStore.insertThread(TSReleaseNotesThread(uniqueId: TSReleaseNotesThread.releaseNotesUniqueId))

        mockAppVersion = MockAppVersion()
        mockAppVersion.currentAppVersion = "5.0.0.0"

        remoteReleaseNotesFetchingManager = RemoteReleaseNotesFetchingManager(
            db: db,
            attachmentContentValidator: AttachmentContentValidatorMock(),
            attachmentManager: AttachmentManagerMock(),
            blockingManager: BlockingManager(blockedGroupStore: BlockedGroupStore(), blockedRecipientStore: BlockedRecipientStore(), blockedReleaseNotesStore: blockedReleaseNotesStore),
            tsAccountManager: mockTSAccountManager,
            notificationPresenter: NoopNotificationPresenterImpl(),
            threadStore: mockThreadStore,
            interactionStore: mockInteractionStore,
            appVersion: mockAppVersion,
            dateProvider: { Date() },
            remoteReleaseNotesService: mockRemoteReleaseNotesService,
            releaseNoteStore: releaseNotesStore,
        )
    }

    mutating func manager(
        dateProvider: @escaping DateProvider = { Date() },
    ) -> RemoteReleaseNotesFetchingManager {
        RemoteReleaseNotesFetchingManager(
            db: db,
            attachmentContentValidator: AttachmentContentValidatorMock(),
            attachmentManager: AttachmentManagerMock(),
            blockingManager: BlockingManager(blockedGroupStore: BlockedGroupStore(), blockedRecipientStore: BlockedRecipientStore(), blockedReleaseNotesStore: blockedReleaseNotesStore),
            tsAccountManager: mockTSAccountManager,
            notificationPresenter: NoopNotificationPresenterImpl(),
            threadStore: mockThreadStore,
            interactionStore: mockInteractionStore,
            appVersion: mockAppVersion,
            dateProvider: dateProvider,
            remoteReleaseNotesService: mockRemoteReleaseNotesService,
            releaseNoteStore: releaseNotesStore,
        )
    }

    @Test
    func testRemoteMegaphoneFetch() async throws {
        let uuid = UUID().uuidString
        mockRemoteReleaseNotesService.manifests = ([RemoteMegaphoneModel.Manifest(
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

        mockRemoteReleaseNotesService.megaphoneTranslations = [uuid: RemoteMegaphoneModel.Translation(
            id: uuid,
            title: "Donate Today",
            body: "Support privacy by donating to Signal. We're counting on your support.",
            imageRemoteUrlPath: "/static/release-notes/donate-heart.png",
            hasImage: true,
            primaryActionText: "Donate",
            secondaryActionText: "Not now",
        )]

        try await remoteReleaseNotesFetchingManager.syncRemoteReleaseNotes()

        db.read { tx in
            experienceUpgradeStore.enumerateExperienceUpgrades(tx: tx) { upgrade in
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

    @Test
    mutating func testRemoteAnnouncementFetch() async throws {
        // Set current date and registration date to 8 days ago so repeat UUID gets fetched.
        mockTSAccountManager.registrationDateMock = { Date().addingTimeInterval(-8 * .day) }
        remoteReleaseNotesFetchingManager = manager(dateProvider: { Date() - 8 * .day })

        let uuid = UUID().uuidString
        mockRemoteReleaseNotesService.manifests = ([], [RemoteAnnouncementModel.Manifest(
            id: uuid,
            minAppVersion: try! AppVersionNumber4(AppVersionNumber("4.0.0.1")),
            countries: nil,
            link: nil,
            action: nil,
        )])

        mockRemoteReleaseNotesService.announcementTranslations = [uuid: RemoteAnnouncementModel.Translation(
            id: uuid,
            title: "Put a pin in it",
            body: "Your most frequently asked questions, dinner reservations, and vacation itineraries are already top of mind. Now they can be top of chat as well.\n\nNow you can pin up to three messages to the top of any 1-1 or group chat to share important information. Simple permissions make it easy to limit pinned messages to group admins, and messages can be pinned forever or for a limited time. Simply tap-and-hold any message and select \"Pin\" to get started.",
            mediaRemoteUrlPath: nil,
            mediaSize: nil,
            mediaMimeType: nil,
            linkText: nil,
            callToActionText: nil,
            bodyRanges: nil,
        )]

        let titleBodyCombined = "Put a pin in it\n\nYour most frequently asked questions, dinner reservations, and vacation itineraries are already top of mind. Now they can be top of chat as well.\n\nNow you can pin up to three messages to the top of any 1-1 or group chat to share important information. Simple permissions make it easy to limit pinned messages to group admins, and messages can be pinned forever or for a limited time. Simply tap-and-hold any message and select \"Pin\" to get started."

        try await remoteReleaseNotesFetchingManager.syncRemoteReleaseNotes()

        var messages = mockInteractionStore.insertedInteractions

        #expect(messages.count == 1)

        var releaseNotesMessage = messages.first! as! TSReleaseNotesMessage
        #expect(releaseNotesMessage.body == titleBodyCombined)

        // try to insert same UUID again with different body, make sure it fails.
        mockRemoteReleaseNotesService.announcementTranslations = [uuid: RemoteAnnouncementModel.Translation(
            id: uuid,
            title: "New title",
            body: "New body",
            mediaRemoteUrlPath: nil,
            mediaSize: nil,
            mediaMimeType: nil,
            linkText: nil,
            callToActionText: nil,
            bodyRanges: nil,
        )]

        try await remoteReleaseNotesFetchingManager.syncRemoteReleaseNotes()
        messages = mockInteractionStore.insertedInteractions
        #expect(messages.count == 1)
        releaseNotesMessage = messages.first! as! TSReleaseNotesMessage
        #expect(releaseNotesMessage.body == titleBodyCombined)
    }

    @Test
    mutating func testRemoteAnnouncementFetch_waitForNextFetch() async throws {
        let uuid1 = UUID().uuidString
        let uuid2 = UUID().uuidString
        mockRemoteReleaseNotesService.manifests = ([], [
            RemoteAnnouncementModel.Manifest(
                id: uuid1,
                minAppVersion: try! AppVersionNumber4(AppVersionNumber("4.0.0.1")),
                countries: nil,
                link: nil,
                action: nil,
            ),
            RemoteAnnouncementModel.Manifest(
                id: uuid2,
                minAppVersion: try! AppVersionNumber4(AppVersionNumber("4.0.0.2")), // Increase version
                countries: nil,
                link: nil,
                action: nil,
            ),
        ])

        mockRemoteReleaseNotesService.announcementTranslations = [
            uuid1: RemoteAnnouncementModel.Translation(
                id: uuid1,
                title: "Put a pin in it",
                body: "Your most frequently asked questions, dinner reservations, and vacation itineraries are already top of mind. Now they can be top of chat as well.\n\nNow you can pin up to three messages to the top of any 1-1 or group chat to share important information. Simple permissions make it easy to limit pinned messages to group admins, and messages can be pinned forever or for a limited time. Simply tap-and-hold any message and select \"Pin\" to get started.",
                mediaRemoteUrlPath: nil,
                mediaSize: nil,
                mediaMimeType: nil,
                linkText: nil,
                callToActionText: nil,
                bodyRanges: nil,
            ),
            uuid2: RemoteAnnouncementModel.Translation(
                id: uuid2,
                title: "Signal Polls Are Here",
                body: "Are you and your friends on the same page, or are you poll-ar opposites?\n\nPolls are an easy way to see what your group chat really thinks. Create a poll with competing dinner options, vacation destinations, musical preferences for an upcoming road trip, or any other important choices.\n\nEveryone in the group can vote and see each other's responses, and you can decide whether or not to allow multiple votes.",
                mediaRemoteUrlPath: nil,
                mediaSize: nil,
                mediaMimeType: nil,
                linkText: nil,
                callToActionText: nil,
                bodyRanges: nil,
            ),
        ]

        let titleBodyCombined1 = "Put a pin in it\n\nYour most frequently asked questions, dinner reservations, and vacation itineraries are already top of mind. Now they can be top of chat as well.\n\nNow you can pin up to three messages to the top of any 1-1 or group chat to share important information. Simple permissions make it easy to limit pinned messages to group admins, and messages can be pinned forever or for a limited time. Simply tap-and-hold any message and select \"Pin\" to get started."

        // sync once, should see the min version release note.
        try await remoteReleaseNotesFetchingManager.syncRemoteReleaseNotes()

        var messages = mockInteractionStore.insertedInteractions
        #expect(mockInteractionStore.insertedInteractions.count == 1)

        let releaseNotesMessage1 = messages.first! as! TSReleaseNotesMessage
        #expect(releaseNotesMessage1.body == titleBodyCombined1)

        // sync again, should not see the second release note because enough time hasn't passed
        try await remoteReleaseNotesFetchingManager.syncRemoteReleaseNotes()

        messages = mockInteractionStore.insertedInteractions
        #expect(mockInteractionStore.insertedInteractions.count == 1)
    }

    @Test
    func testRemoteAnnouncementFetch_unsupportedVersion() async throws {
        // Store a manifest with a min version that is higher than our current version.
        let uuid1 = UUID().uuidString
        mockRemoteReleaseNotesService.manifests = ([], [RemoteAnnouncementModel.Manifest(
            id: uuid1,
            minAppVersion: try! AppVersionNumber4(AppVersionNumber("5.5.5.5")),
            countries: nil,
            link: nil,
            action: nil,
        )])

        mockRemoteReleaseNotesService.announcementTranslations = [uuid1: RemoteAnnouncementModel.Translation(
            id: uuid1,
            title: "Put a pin in it",
            body: "Your most frequently asked questions, dinner reservations, and vacation itineraries are already top of mind. Now they can be top of chat as well.\n\nNow you can pin up to three messages to the top of any 1-1 or group chat to share important information. Simple permissions make it easy to limit pinned messages to group admins, and messages can be pinned forever or for a limited time. Simply tap-and-hold any message and select \"Pin\" to get started.",
            mediaRemoteUrlPath: nil,
            mediaSize: nil,
            mediaMimeType: nil,
            linkText: nil,
            callToActionText: nil,
            bodyRanges: nil,
        )]

        try await remoteReleaseNotesFetchingManager.syncRemoteReleaseNotes()

        let messages = mockInteractionStore.insertedInteractions
        #expect(messages.count == 0)
    }

    @Test
    mutating func testRemoteAnnouncementFetch_multipleAnnouncements() async throws {
        // Set date to 8 days ago so repeat UUID gets fetched.
        remoteReleaseNotesFetchingManager = manager(dateProvider: { Date() - 8 * .day })

        let uuid1 = UUID().uuidString
        let uuid2 = UUID().uuidString
        mockRemoteReleaseNotesService.manifests = ([], [
            RemoteAnnouncementModel.Manifest(
                id: uuid1,
                minAppVersion: try! AppVersionNumber4(AppVersionNumber("4.0.0.1")),
                countries: nil,
                link: nil,
                action: nil,
            ),
            RemoteAnnouncementModel.Manifest(
                id: uuid2,
                minAppVersion: try! AppVersionNumber4(AppVersionNumber("4.0.0.2")), // Increase version
                countries: nil,
                link: nil,
                action: nil,
            ),
        ])

        mockRemoteReleaseNotesService.announcementTranslations = [
            uuid1: RemoteAnnouncementModel.Translation(
                id: uuid1,
                title: "Put a pin in it",
                body: "Your most frequently asked questions, dinner reservations, and vacation itineraries are already top of mind. Now they can be top of chat as well.\n\nNow you can pin up to three messages to the top of any 1-1 or group chat to share important information. Simple permissions make it easy to limit pinned messages to group admins, and messages can be pinned forever or for a limited time. Simply tap-and-hold any message and select \"Pin\" to get started.",
                mediaRemoteUrlPath: nil,
                mediaSize: nil,
                mediaMimeType: nil,
                linkText: nil,
                callToActionText: nil,
                bodyRanges: nil,
            ),
            uuid2: RemoteAnnouncementModel.Translation(
                id: uuid2,
                title: "Signal Polls Are Here",
                body: "Are you and your friends on the same page, or are you poll-ar opposites?\n\nPolls are an easy way to see what your group chat really thinks. Create a poll with competing dinner options, vacation destinations, musical preferences for an upcoming road trip, or any other important choices.\n\nEveryone in the group can vote and see each other's responses, and you can decide whether or not to allow multiple votes.",
                mediaRemoteUrlPath: nil,
                mediaSize: nil,
                mediaMimeType: nil,
                linkText: nil,
                callToActionText: nil,
                bodyRanges: nil,
            ),
        ]

        let titleBodyCombined1 = "Put a pin in it\n\nYour most frequently asked questions, dinner reservations, and vacation itineraries are already top of mind. Now they can be top of chat as well.\n\nNow you can pin up to three messages to the top of any 1-1 or group chat to share important information. Simple permissions make it easy to limit pinned messages to group admins, and messages can be pinned forever or for a limited time. Simply tap-and-hold any message and select \"Pin\" to get started."
        let titleBodyCombined2 = "Signal Polls Are Here\n\nAre you and your friends on the same page, or are you poll-ar opposites?\n\nPolls are an easy way to see what your group chat really thinks. Create a poll with competing dinner options, vacation destinations, musical preferences for an upcoming road trip, or any other important choices.\n\nEveryone in the group can vote and see each other's responses, and you can decide whether or not to allow multiple votes."

        // sync once, should see the min version release note.
        try await remoteReleaseNotesFetchingManager.syncRemoteReleaseNotes()

        var messages = mockInteractionStore.insertedInteractions
        #expect(mockInteractionStore.insertedInteractions.count == 1)

        let releaseNotesMessage1 = messages.first! as! TSReleaseNotesMessage
        #expect(releaseNotesMessage1.body == titleBodyCombined1)

        // sync again, should see the second release note

        try await remoteReleaseNotesFetchingManager.syncRemoteReleaseNotes()

        messages = mockInteractionStore.insertedInteractions
        #expect(mockInteractionStore.insertedInteractions.count == 2)

        let releaseNotesMessage2 = messages.last! as! TSReleaseNotesMessage
        #expect(releaseNotesMessage2.body == titleBodyCombined2)
    }

    @Test
    mutating func testRemoteAnnouncementFetch_tooSoonAfterRegistration() async throws {
        mockTSAccountManager.registrationDateMock = { Date().addingTimeInterval(-1 * .day) }

        let uuid = UUID().uuidString
        mockRemoteReleaseNotesService.manifests = ([], [RemoteAnnouncementModel.Manifest(
            id: uuid,
            minAppVersion: try! AppVersionNumber4(AppVersionNumber("4.0.0.1")),
            countries: nil,
            link: nil,
            action: nil,
        )])

        mockRemoteReleaseNotesService.announcementTranslations = [uuid: RemoteAnnouncementModel.Translation(
            id: uuid,
            title: "Put a pin in it",
            body: "Your most frequently asked questions, dinner reservations, and vacation itineraries are already top of mind. Now they can be top of chat as well.\n\nNow you can pin up to three messages to the top of any 1-1 or group chat to share important information. Simple permissions make it easy to limit pinned messages to group admins, and messages can be pinned forever or for a limited time. Simply tap-and-hold any message and select \"Pin\" to get started.",
            mediaRemoteUrlPath: nil,
            mediaSize: nil,
            mediaMimeType: nil,
            linkText: nil,
            callToActionText: nil,
            bodyRanges: nil,
        )]

        try await remoteReleaseNotesFetchingManager.syncRemoteReleaseNotes()

        let messages = mockInteractionStore.insertedInteractions
        #expect(messages.count == 0)
    }

    @Test
    mutating func testRemoteAnnouncementFetch_blocked() async throws {
        remoteReleaseNotesFetchingManager = manager(dateProvider: { Date() - 8 * .day })

        db.write { tx in
            blockedReleaseNotesStore.setBlocked(true, tx: tx)
        }

        let uuid = UUID().uuidString
        mockRemoteReleaseNotesService.manifests = ([], [RemoteAnnouncementModel.Manifest(
            id: uuid,
            minAppVersion: try! AppVersionNumber4(AppVersionNumber("4.0.0.1")),
            countries: nil,
            link: nil,
            action: nil,
        )])

        mockRemoteReleaseNotesService.announcementTranslations = [uuid: RemoteAnnouncementModel.Translation(
            id: uuid,
            title: "Put a pin in it",
            body: "Your most frequently asked questions, dinner reservations, and vacation itineraries are already top of mind. Now they can be top of chat as well.\n\nNow you can pin up to three messages to the top of any 1-1 or group chat to share important information. Simple permissions make it easy to limit pinned messages to group admins, and messages can be pinned forever or for a limited time. Simply tap-and-hold any message and select \"Pin\" to get started.",
            mediaRemoteUrlPath: nil,
            mediaSize: nil,
            mediaMimeType: nil,
            linkText: nil,
            callToActionText: nil,
            bodyRanges: nil,
        )]

        try await remoteReleaseNotesFetchingManager.syncRemoteReleaseNotes()

        #expect(mockInteractionStore.insertedInteractions.count == 0, "Blocked thread means we don't store release notes")
        var messages = mockInteractionStore.insertedInteractions
        #expect(messages.count == 0)

        db.write { tx in
            blockedReleaseNotesStore.setBlocked(false, tx: tx)
        }
        try await remoteReleaseNotesFetchingManager.syncRemoteReleaseNotes()

        messages = mockInteractionStore.insertedInteractions
        #expect(messages.count == 0, "We marked this UUID as seen already, so no new messages should have been inserted")

        let releaseNote = db.read { tx in
            releaseNotesStore.existingReleaseNoteForManifestId(uuid, tx: tx)
        }
        #expect(releaseNote != nil, "The release note received while blocking should be marked as seen")
    }
}

class MockRemoteReleaseNotesService: RemoteReleaseNotesServiceProtocol {
    let megaphoneUUID: String = UUID().uuidString
    let announcementUUID: String = UUID().uuidString

    var manifests: ([RemoteMegaphoneModel.Manifest], [RemoteAnnouncementModel.Manifest]) = ([], [])
    var announcementTranslations: [String: RemoteAnnouncementModel.Translation] = [:]
    var megaphoneTranslations: [String: RemoteMegaphoneModel.Translation] = [:]

    private func fetchUUIDStringFromPath(_ path: String) -> String? {
        return path.components(separatedBy: "/").first(where: { UUID(uuidString: $0) != nil })
    }

    func fetchManifests() async throws -> ([RemoteMegaphoneModel.Manifest], [RemoteAnnouncementModel.Manifest]) {
        return manifests
    }

    func fetchAnnouncementTranslation(translationUrlPath: String) async throws -> RemoteAnnouncementModel.Translation {
        guard let uuidString = fetchUUIDStringFromPath(translationUrlPath) else {
            throw OWSAssertionError("Invalid translation path")
        }
        return announcementTranslations[uuidString]!
    }

    func fetchMegaphoneTranslation(translationUrlPath: String) async throws -> RemoteMegaphoneModel.Translation {
        guard let uuidString = fetchUUIDStringFromPath(translationUrlPath) else {
            throw OWSAssertionError("Invalid translation path")
        }
        return megaphoneTranslations[uuidString]!
    }

    func downloadMedia(mediaRemoteUrlPath: String, mediaFileUrl: URL, translationId: String) async throws -> Bool {
        return false
    }
}
