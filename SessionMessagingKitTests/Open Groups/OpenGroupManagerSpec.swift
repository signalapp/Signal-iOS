// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import PromiseKit
import Sodium
import SessionSnodeKit

import Quick
import Nimble

@testable import SessionMessagingKit

class OpenGroupManagerSpec: QuickSpec {
    class TestCapabilitiesAndRoomApi: TestOnionRequestAPI {
        static let capabilitiesData: OpenGroupAPI.Capabilities = OpenGroupAPI.Capabilities(capabilities: [.sogs], missing: nil)
        static let roomData: OpenGroupAPI.Room = OpenGroupAPI.Room(
            token: "test",
            name: "test",
            description: nil,
            infoUpdates: 0,
            messageSequence: 0,
            created: 0,
            activeUsers: 0,
            activeUsersCutoff: 0,
            imageId: nil,
            pinnedMessages: nil,
            admin: false,
            globalAdmin: false,
            admins: [],
            hiddenAdmins: nil,
            moderator: false,
            globalModerator: false,
            moderators: [],
            hiddenModerators: nil,
            read: false,
            defaultRead: nil,
            defaultAccessible: nil,
            write: false,
            defaultWrite: nil,
            upload: false,
            defaultUpload: nil
        )
        
        override class var mockResponse: Data? {
            let responses: [Data] = [
                try! JSONEncoder().encode(
                    OpenGroupAPI.BatchSubResponse(
                        code: 200,
                        headers: [:],
                        body: capabilitiesData,
                        failedToParseBody: false
                    )
                ),
                try! JSONEncoder().encode(
                    OpenGroupAPI.BatchSubResponse(
                        code: 200,
                        headers: [:],
                        body: roomData,
                        failedToParseBody: false
                    )
                )
            ]
            
            return "[\(responses.map { String(data: $0, encoding: .utf8)! }.joined(separator: ","))]".data(using: .utf8)
        }
    }
    
    // MARK: - Spec

    override func spec() {
        var mockStorage: MockStorage!
        var mockSodium: MockSodium!
        var mockAeadXChaCha20Poly1305Ietf: MockAeadXChaCha20Poly1305Ietf!
        var mockGenericHash: MockGenericHash!
        var mockSign: MockSign!
        var mockUserDefaults: MockUserDefaults!
        var dependencies: Dependencies!
        
        var testInteraction: TestInteraction!
        var testGroupThread: TestGroupThread!
        var testTransaction: TestTransaction!

        describe("an OpenGroupAPI") {
            // MARK: - Configuration
            
            beforeEach {
                mockStorage = MockStorage()
                mockSodium = MockSodium()
                mockAeadXChaCha20Poly1305Ietf = MockAeadXChaCha20Poly1305Ietf()
                mockGenericHash = MockGenericHash()
                mockSign = MockSign()
                mockUserDefaults = MockUserDefaults()
                dependencies = Dependencies(
                    onionApi: TestCapabilitiesAndRoomApi.self,
                    storage: mockStorage,
                    sodium: mockSodium,
                    aeadXChaCha20Poly1305Ietf: mockAeadXChaCha20Poly1305Ietf,
                    sign: mockSign,
                    genericHash: mockGenericHash,
                    ed25519: MockEd25519(),
                    nonceGenerator16: OpenGroupAPISpec.TestNonce16Generator(),
                    nonceGenerator24: OpenGroupAPISpec.TestNonce24Generator(),
                    standardUserDefaults: mockUserDefaults,
                    date: Date(timeIntervalSince1970: 1234567890)
                )
                testInteraction = TestInteraction()
                testInteraction.mockData[.uniqueId] = "TestInteractionId"
                testInteraction.mockData[.timestamp] = UInt64(123)
                
                testGroupThread = TestGroupThread()
                testGroupThread.mockData[.groupModel] = TSGroupModel(
                    title: "TestTitle",
                    memberIds: [],
                    image: nil,
                    groupId: LKGroupUtilities.getEncodedOpenGroupIDAsData("testServer.testRoom"),
                    groupType: .openGroup,
                    adminIds: [],
                    moderatorIds: []
                )
                testGroupThread.mockData[.interactions] = [testInteraction]
                
                testTransaction = TestTransaction()
                testTransaction.mockData[.objectForKey] = testGroupThread
                
                mockStorage
                    .when { $0.write(with: { _ in }) }
                    .then { args in (args.first as? ((Any) -> Void))?(testTransaction as Any) }
                    .thenReturn(Promise.value(()))
                mockStorage
                    .when { $0.write(with: { _ in }, completion: { }) }
                    .then { args in
                        (args.first as? ((Any) -> Void))?(testTransaction as Any)
                        (args.last as? (() -> Void))?()
                    }
                    .thenReturn(Promise.value(()))
                mockStorage
                    .when { $0.getUserKeyPair() }
                    .thenReturn(
                        try! ECKeyPair(
                            publicKeyData: Data.data(fromHex: TestConstants.publicKey)!,
                            privateKeyData: Data.data(fromHex: TestConstants.privateKey)!
                        )
                    )
                mockStorage
                    .when { $0.getUserED25519KeyPair() }
                    .thenReturn(
                        Box.KeyPair(
                            publicKey: Data.data(fromHex: TestConstants.publicKey)!.bytes,
                            secretKey: Data.data(fromHex: TestConstants.edSecretKey)!.bytes
                        )
                    )
                mockStorage
                    .when { $0.getAllOpenGroups() }
                    .thenReturn([
                        "0": OpenGroup(
                            server: "testServer",
                            room: "testRoom",
                            publicKey: TestConstants.publicKey,
                            name: "Test",
                            groupDescription: nil,
                            imageID: nil,
                            infoUpdates: 0
                        )
                    ])
                mockStorage
                    .when { $0.getOpenGroup(for: any()) }
                    .thenReturn(
                        OpenGroup(
                            server: "testServer",
                            room: "testRoom",
                            publicKey: TestConstants.publicKey,
                            name: "Test",
                            groupDescription: nil,
                            imageID: nil,
                            infoUpdates: 0
                        )
                    )
                mockStorage
                    .when { $0.getOpenGroupServer(name: any()) }
                    .thenReturn(
                        OpenGroupAPI.Server(
                            name: "testServer",
                            capabilities: OpenGroupAPI.Capabilities(capabilities: [.sogs], missing: [])
                        )
                    )
                mockStorage
                    .when { $0.getOpenGroupPublicKey(for: any()) }
                    .thenReturn(TestConstants.publicKey)
                
                mockGenericHash.when { $0.hash(message: any(), outputLength: any()) }.thenReturn([])
                mockSodium
                    .when { $0.blindedKeyPair(serverPublicKey: any(), edKeyPair: any(), genericHash: mockGenericHash) }
                    .thenReturn(
                        Box.KeyPair(
                            publicKey: Data.data(fromHex: TestConstants.publicKey)!.bytes,
                            secretKey: Data.data(fromHex: TestConstants.edSecretKey)!.bytes
                        )
                    )
                mockSodium
                    .when {
                        $0.sogsSignature(
                            message: any(),
                            secretKey: any(),
                            blindedSecretKey: any(),
                            blindedPublicKey: any()
                        )
                    }
                    .thenReturn("TestSogsSignature".bytes)
                mockSign.when { $0.signature(message: any(), secretKey: any()) }.thenReturn("TestSignature".bytes)
            }

            afterEach {
                OpenGroupManager.shared.stopPolling()   // Need to stop any pollers which get created during tests
                
                mockStorage = nil
                mockSodium = nil
                mockAeadXChaCha20Poly1305Ietf = nil
                mockGenericHash = nil
                mockSign = nil
                mockUserDefaults = nil
                dependencies = nil
                
                testInteraction = nil
                testGroupThread = nil
                testTransaction = nil
            }
            
            // MARK: - Polling
            
            context("when starting polling") {
                beforeEach {
                    mockStorage
                        .when { $0.getAllOpenGroups() }
                        .thenReturn([
                            "0": OpenGroup(
                                server: "testServer",
                                room: "testRoom",
                                publicKey: TestConstants.publicKey,
                                name: "Test",
                                groupDescription: nil,
                                imageID: nil,
                                infoUpdates: 0
                            ),
                            "1": OpenGroup(
                                server: "testServer1",
                                room: "testRoom1",
                                publicKey: TestConstants.publicKey,
                                name: "Test1",
                                groupDescription: nil,
                                imageID: nil,
                                infoUpdates: 0
                            )
                        ])
                    mockStorage.when { $0.removeOpenGroupSequenceNumber(for: any(), on: any(), using: any()) }.thenReturn(())
                    mockStorage.when { $0.setOpenGroupPublicKey(for: any(), to: any(), using: any()) }.thenReturn(())
                    mockStorage.when { $0.setOpenGroupServer(any(), using: any()) }.thenReturn(())
                    mockStorage.when { $0.setOpenGroup(any(), for: any(), using: any()) }.thenReturn(())
                    mockStorage.when { $0.setUserCount(to: any(), forOpenGroupWithID: any(), using: any()) }.thenReturn(())
                    mockStorage.when { $0.getOpenGroupInboxLatestMessageId(for: any()) }.thenReturn(nil)
                    mockStorage.when { $0.getOpenGroupOutboxLatestMessageId(for: any()) }.thenReturn(nil)
                    mockStorage.when { $0.getOpenGroupSequenceNumber(for: any(), on: any()) }.thenReturn(nil)
                    
                    mockUserDefaults
                        .when { $0.object(forKey: SNUserDefaults.Date.lastOpen.rawValue) }
                        .thenReturn(Date(timeIntervalSince1970: 1234567890))
                }
                
                it("creates pollers for all of the open groups") {
                    OpenGroupManager.shared.startPolling(using: dependencies)
                    
                    expect(OpenGroupManager.shared.cache.pollers.keys.map { String($0) }.sorted)
                        .to(equal(["testserver", "testserver1"]))
                }
                
                it("updates the isPolling flag") {
                    OpenGroupManager.shared.startPolling(using: dependencies)
                    
                    expect(OpenGroupManager.shared.cache.isPolling).to(beTrue())
                }
                
                it("does nothing if already polling") {
                    OpenGroupManager.shared.mutableCache.mutate { $0.isPolling = true }
                    OpenGroupManager.shared.startPolling(using: dependencies)
                    
                    expect(OpenGroupManager.shared.cache.pollers.keys.map { String($0) })
                        .to(equal([]))
                }
            }
            
            context("when stopping polling") {
                beforeEach {
                    mockStorage
                        .when { $0.getAllOpenGroups() }
                        .thenReturn([
                            "0": OpenGroup(
                                server: "testServer",
                                room: "testRoom",
                                publicKey: TestConstants.publicKey,
                                name: "Test",
                                groupDescription: nil,
                                imageID: nil,
                                infoUpdates: 0
                            ),
                            "1": OpenGroup(
                                server: "testServer1",
                                room: "testRoom1",
                                publicKey: TestConstants.publicKey,
                                name: "Test1",
                                groupDescription: nil,
                                imageID: nil,
                                infoUpdates: 0
                            )
                        ])
                    mockStorage.when { $0.removeOpenGroupSequenceNumber(for: any(), on: any(), using: any()) }.thenReturn(())
                    mockStorage.when { $0.setOpenGroupPublicKey(for: any(), to: any(), using: any()) }.thenReturn(())
                    mockStorage.when { $0.setOpenGroupServer(any(), using: any()) }.thenReturn(())
                    mockStorage.when { $0.setOpenGroup(any(), for: any(), using: any()) }.thenReturn(())
                    mockStorage.when { $0.setUserCount(to: any(), forOpenGroupWithID: any(), using: any()) }.thenReturn(())
                    mockStorage.when { $0.getOpenGroupInboxLatestMessageId(for: any()) }.thenReturn(nil)
                    mockStorage.when { $0.getOpenGroupOutboxLatestMessageId(for: any()) }.thenReturn(nil)
                    mockStorage.when { $0.getOpenGroupSequenceNumber(for: any(), on: any()) }.thenReturn(nil)
                    
                    mockUserDefaults
                        .when { $0.object(forKey: SNUserDefaults.Date.lastOpen.rawValue) }
                        .thenReturn(Date(timeIntervalSince1970: 1234567890))
                    
                    OpenGroupManager.shared.startPolling(using: dependencies)
                }
                
                it("removes all pollers") {
                    OpenGroupManager.shared.stopPolling()
                    
                    expect(OpenGroupManager.shared.cache.pollers.keys.map { String($0) })
                        .to(equal([]))
                }
                
                it("updates the isPolling flag") {
                    OpenGroupManager.shared.stopPolling()
                    
                    expect(OpenGroupManager.shared.cache.isPolling).to(beFalse())
                }
            }
            
            // MARK: - Adding & Removing
            
            context("when adding") {
                beforeEach {
                    mockStorage.when { $0.removeOpenGroupSequenceNumber(for: any(), on: any(), using: any()) }.thenReturn(())
                    mockStorage.when { $0.setOpenGroupPublicKey(for: any(), to: any(), using: any()) }.thenReturn(())
                    mockStorage.when { $0.setOpenGroupServer(any(), using: any()) }.thenReturn(())
                    mockStorage.when { $0.setOpenGroup(any(), for: any(), using: any()) }.thenReturn(())
                    mockStorage.when { $0.setUserCount(to: any(), forOpenGroupWithID: any(), using: any()) }.thenReturn(())
                    mockStorage.when { $0.getOpenGroupInboxLatestMessageId(for: any()) }.thenReturn(nil)
                    mockStorage.when { $0.getOpenGroupOutboxLatestMessageId(for: any()) }.thenReturn(nil)
                    mockStorage.when { $0.getOpenGroupSequenceNumber(for: any(), on: any()) }.thenReturn(nil)
                    
                    mockUserDefaults
                        .when { $0.object(forKey: SNUserDefaults.Date.lastOpen.rawValue) }
                        .thenReturn(Date(timeIntervalSince1970: 1234567890))
                }
                
                it("resets the sequence number of the open group") {
                    OpenGroupManager.shared
                        .add(
                            roomToken: "testRoom",
                            server: "testServer",
                            publicKey: "testKey",
                            isConfigMessage: false,
                            using: testTransaction,
                            dependencies: dependencies
                        )
                        .retainUntilComplete()
                    
                    expect(mockStorage)
                        .to(
                            call(.exactly(times: 1)) {
                                $0.removeOpenGroupSequenceNumber(
                                    for: "testRoom",
                                    on: "testServer",
                                    using: testTransaction as Any
                                )
                            }
                        )
                }
                
                it("sets the public key of the open group server") {
                    OpenGroupManager.shared
                        .add(
                            roomToken: "testRoom",
                            server: "testServer",
                            publicKey: "testKey",
                            isConfigMessage: false,
                            using: testTransaction,
                            dependencies: dependencies
                        )
                        .retainUntilComplete()
                    
                    expect(mockStorage)
                        .to(
                            call(.exactly(times: 1)) {
                                $0.setOpenGroupPublicKey(
                                    for: "testRoom",
                                    to: "testKey",
                                    using: testTransaction as Any
                                )
                            }
                        )
                }
                
                it("adds a poller") {
                    OpenGroupManager.shared
                        .add(
                            roomToken: "testRoom",
                            server: "testServer",
                            publicKey: "testKey",
                            isConfigMessage: false,
                            using: testTransaction,
                            dependencies: dependencies
                        )
                        .retainUntilComplete()
                    
                    expect(OpenGroupManager.shared.cache.pollers["testServer"])
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                }
                
                context("an existing room") {
                    beforeEach {
                        OpenGroupManager.shared
                            .add(
                                roomToken: "testRoom",
                                server: "testServer",
                                publicKey: "testKey",
                                isConfigMessage: false,
                                using: testTransaction,
                                dependencies: dependencies
                            )
                            .retainUntilComplete()
                        
                        // There is a bunch of async code in this function so we need to wait until if finishes
                        // processing before doing the actual tests
                        expect(mockStorage)
                            .toEventually(
                                call { $0.setOpenGroup(any(), for: "testServer", using: testTransaction as Any) },
                                timeout: .milliseconds(100)
                            )
                        
                        mockStorage.resetCallCounts()
                    }
                    
                    it("does not reset the sequence number or update the public key") {
                        OpenGroupManager.shared
                            .add(
                                roomToken: "testRoom",
                                server: "testServer",
                                publicKey: "testKey",
                                isConfigMessage: false,
                                using: testTransaction,
                                dependencies: dependencies
                            )
                            .retainUntilComplete()
                        
                        expect(mockStorage)
                            .toEventuallyNot(
                                call {
                                    $0.removeOpenGroupSequenceNumber(
                                        for: "testRoom",
                                        on: "testServer",
                                        using: testTransaction as Any
                                    )
                                },
                                timeout: .milliseconds(100)
                            )
                        expect(mockStorage)
                            .toEventuallyNot(
                                call {
                                    $0.setOpenGroupPublicKey(
                                        for: "testRoom",
                                        to: "testKey",
                                        using: testTransaction as Any
                                    )
                                },
                                timeout: .milliseconds(100)
                            )
                    }
                }
                
                context("with an invalid response") {
                    beforeEach {
                        class TestApi: TestOnionRequestAPI {
                            override class var mockResponse: Data? { return Data() }
                        }
                        dependencies = dependencies.with(onionApi: TestApi.self)
                        
                        mockUserDefaults
                            .when { $0.object(forKey: SNUserDefaults.Date.lastOpen.rawValue) }
                            .thenReturn(Date(timeIntervalSince1970: 1234567890))
                    }
                
                    it("fails with the error") {
                        var error: Error?
                        
                        let promise = OpenGroupManager.shared
                            .add(
                                roomToken: "testRoom",
                                server: "testServer",
                                publicKey: "testKey",
                                isConfigMessage: false,
                                using: testTransaction,
                                dependencies: dependencies
                            )
                        promise.catch { error = $0 }
                        promise.retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(HTTP.Error.parsingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                    }
                }
            }
            
            context("when removing") {
            
//            public func delete(_ openGroup: OpenGroup, associatedWith thread: TSThread, using transaction: YapDatabaseReadWriteTransaction, dependencies: Dependencies = Dependencies()) {
//                // Stop the poller if needed
//                let openGroups = dependencies.storage.getAllOpenGroups().values.filter { $0.server == openGroup.server }
//                if openGroups.count == 1 && openGroups.last == openGroup {
//                    let poller = pollers[openGroup.server]
//                    poller?.stop()
//                    pollers[openGroup.server] = nil
//                }
//
//                // Remove all data
//                var messageIDs: Set<String> = []
//                var messageTimestamps: Set<UInt64> = []
//                thread.enumerateInteractions(with: transaction) { interaction, _ in
//                    messageIDs.insert(interaction.uniqueId!)
//                    messageTimestamps.insert(interaction.timestamp)
//                }
//                dependencies.storage.updateMessageIDCollectionByPruningMessagesWithIDs(messageIDs, using: transaction)
//                dependencies.storage.removeReceivedMessageTimestamps(messageTimestamps, using: transaction)
//                dependencies.storage.removeOpenGroupSequenceNumber(for: openGroup.room, on: openGroup.server, using: transaction)
//
//                thread.removeAllThreadInteractions(with: transaction)
//                thread.remove(with: transaction)
//                dependencies.storage.removeOpenGroup(for: thread.uniqueId!, using: transaction)
//
//                // Only remove the open group public key and server info if the user isn't in any other rooms
//                if openGroups.count <= 1 {
//                    dependencies.storage.removeOpenGroupServer(name: openGroup.server, using: transaction)
//                    dependencies.storage.removeOpenGroupPublicKey(for: openGroup.server, using: transaction)
//                }
            }
        }
    }
}
