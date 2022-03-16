// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import PromiseKit
import Sodium
import SessionSnodeKit

import Quick
import Nimble

@testable import SessionMessagingKit

// MARK: - OpenGroupManagerSpec

class OpenGroupManagerSpec: QuickSpec {
    class TestCapabilitiesAndRoomApi: TestOnionRequestAPI {
        static let capabilitiesData: OpenGroupAPI.Capabilities = OpenGroupAPI.Capabilities(capabilities: [.sogs], missing: nil)
        static let roomData: OpenGroupAPI.Room = OpenGroupAPI.Room(
            token: "test",
            name: "test",
            roomDescription: nil,
            infoUpdates: 10,
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
        var mockOGMCache: MockOGMCache!
        var mockStorage: MockStorage!
        var mockSodium: MockSodium!
        var mockAeadXChaCha20Poly1305Ietf: MockAeadXChaCha20Poly1305Ietf!
        var mockGenericHash: MockGenericHash!
        var mockSign: MockSign!
        var mockUserDefaults: MockUserDefaults!
        var dependencies: OpenGroupManager.OGMDependencies!
        
        var testInteraction: TestInteraction!
        var testGroupThread: TestGroupThread!
        var testTransaction: TestTransaction!
        var testOpenGroup: OpenGroup!
        var testPollInfo: OpenGroupAPI.RoomPollInfo!
        
        var cache: OpenGroupManager.Cache!
        var openGroupManager: OpenGroupManager!

        describe("an OpenGroupManager") {
            // MARK: - Configuration
            
            beforeEach {
                mockOGMCache = MockOGMCache()
                mockStorage = MockStorage()
                mockSodium = MockSodium()
                mockAeadXChaCha20Poly1305Ietf = MockAeadXChaCha20Poly1305Ietf()
                mockGenericHash = MockGenericHash()
                mockSign = MockSign()
                mockUserDefaults = MockUserDefaults()
                dependencies = OpenGroupManager.OGMDependencies(
                    cache: Atomic(mockOGMCache),
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
                testGroupThread.mockData[.uniqueId] = "TestGroupId"
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
                
                testOpenGroup = OpenGroup(
                    server: "testServer",
                    room: "testRoom",
                    publicKey: TestConstants.publicKey,
                    name: "Test",
                    groupDescription: nil,
                    imageID: nil,
                    infoUpdates: 10
                )
                testPollInfo = OpenGroupAPI.RoomPollInfo(
                    token: "testRoom",
                    activeUsers: 10,
                    admin: false,
                    globalAdmin: false,
                    moderator: false,
                    globalModerator: false,
                    read: false,
                    defaultRead: nil,
                    defaultAccessible: nil,
                    write: false,
                    defaultWrite: nil,
                    upload: false,
                    defaultUpload: nil,
                    details: TestCapabilitiesAndRoomApi.roomData
                )
                
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
                        "0": testOpenGroup
                    ])
                mockStorage
                    .when { $0.getOpenGroup(for: any()) }
                    .thenReturn(testOpenGroup)
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
                
                mockGenericHash.when { $0.hash(message: anyArray(), outputLength: any()) }.thenReturn([])
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
                            message: anyArray(),
                            secretKey: anyArray(),
                            blindedSecretKey: anyArray(),
                            blindedPublicKey: anyArray()
                        )
                    }
                    .thenReturn("TestSogsSignature".bytes)
                mockSign.when { $0.signature(message: anyArray(), secretKey: anyArray()) }.thenReturn("TestSignature".bytes)
                
                cache = OpenGroupManager.Cache()
                openGroupManager = OpenGroupManager()
            }

            afterEach {
                OpenGroupManager.shared.stopPolling()   // Need to stop any pollers which get created during tests
                openGroupManager.stopPolling()          // Assuming it's different from the above
                
                mockOGMCache = nil
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
                testOpenGroup = nil
                
                openGroupManager = nil
            }
            
            // MARK: - Cache
            
            context("cache data") {
                it("defaults the time since last open to greatestFiniteMagnitude") {
                    mockUserDefaults
                        .when { $0.object(forKey: SNUserDefaults.Date.lastOpen.rawValue) }
                        .thenReturn(nil)
                    
                    expect(cache.getTimeSinceLastOpen(using: dependencies))
                        .to(beCloseTo(.greatestFiniteMagnitude))
                }
                
                it("returns the time since the last open") {
                    mockUserDefaults
                        .when { $0.object(forKey: SNUserDefaults.Date.lastOpen.rawValue) }
                        .thenReturn(Date(timeIntervalSince1970: 1234567880))
                    dependencies = dependencies.with(date: Date(timeIntervalSince1970: 1234567890))
                    
                    expect(cache.getTimeSinceLastOpen(using: dependencies))
                        .to(beCloseTo(10))
                }
                
                it("caches the time since the last open") {
                    mockUserDefaults
                        .when { $0.object(forKey: SNUserDefaults.Date.lastOpen.rawValue) }
                        .thenReturn(Date(timeIntervalSince1970: 1234567770))
                    dependencies = dependencies.with(date: Date(timeIntervalSince1970: 1234567780))
                    
                    expect(cache.getTimeSinceLastOpen(using: dependencies))
                        .to(beCloseTo(10))
                    
                    mockUserDefaults
                        .when { $0.object(forKey: SNUserDefaults.Date.lastOpen.rawValue) }
                        .thenReturn(Date(timeIntervalSince1970: 1234567890))
                 
                    // Cached value shouldn't have been updated
                    expect(cache.getTimeSinceLastOpen(using: dependencies))
                        .to(beCloseTo(10))
                }
            }
            
            // MARK: - Polling
            
            context("when starting polling") {
                beforeEach {
                    mockStorage
                        .when { $0.getAllOpenGroups() }
                        .thenReturn([
                            "0": testOpenGroup,
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
                    mockStorage.when { $0.removeOpenGroupSequenceNumber(for: any(), on: any(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.setOpenGroupPublicKey(for: any(), to: any(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.setOpenGroupServer(any(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.setOpenGroup(any(), for: any(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.setUserCount(to: any(), forOpenGroupWithID: any(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.getOpenGroupInboxLatestMessageId(for: any()) }.thenReturn(nil)
                    mockStorage.when { $0.getOpenGroupOutboxLatestMessageId(for: any()) }.thenReturn(nil)
                    mockStorage.when { $0.getOpenGroupSequenceNumber(for: any(), on: any()) }.thenReturn(nil)
                    
                    mockOGMCache.when { $0.hasPerformedInitialPoll }.thenReturn([:])
                    mockOGMCache.when { $0.timeSinceLastPoll }.thenReturn([:])
                    mockOGMCache.when { $0.getTimeSinceLastOpen(using: dependencies) }.thenReturn(0)
                    mockOGMCache.when { $0.isPolling }.thenReturn(false)
                    mockOGMCache.when { $0.pollers }.thenReturn([:])
                    
                    mockUserDefaults
                        .when { $0.object(forKey: SNUserDefaults.Date.lastOpen.rawValue) }
                        .thenReturn(Date(timeIntervalSince1970: 1234567890))
                }
                
                it("creates pollers for all of the open groups") {
                    openGroupManager.startPolling(using: dependencies)
                    
                    expect(mockOGMCache)
                        .to(call(matchingParameters: true) {
                            $0.pollers = [
                                "testserver": OpenGroupAPI.Poller(for: "testserver"),
                                "testserver1": OpenGroupAPI.Poller(for: "testserver1")
                            ]
                        })
                }
                
                it("updates the isPolling flag") {
                    openGroupManager.startPolling(using: dependencies)
                    
                    expect(mockOGMCache).to(call(matchingParameters: true) { $0.isPolling = true })
                }
                
                it("does nothing if already polling") {
                    mockOGMCache.when { $0.isPolling }.thenReturn(true)
                    
                    openGroupManager.startPolling(using: dependencies)
                    
                    expect(mockOGMCache).toNot(call { $0.pollers })
                }
            }
            
            context("when stopping polling") {
                beforeEach {
                    mockStorage
                        .when { $0.getAllOpenGroups() }
                        .thenReturn([
                            "0": testOpenGroup,
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
                    mockStorage.when { $0.removeOpenGroupSequenceNumber(for: any(), on: any(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.setOpenGroupPublicKey(for: any(), to: any(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.setOpenGroupServer(any(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.setOpenGroup(any(), for: any(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.setUserCount(to: any(), forOpenGroupWithID: any(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.getOpenGroupInboxLatestMessageId(for: any()) }.thenReturn(nil)
                    mockStorage.when { $0.getOpenGroupOutboxLatestMessageId(for: any()) }.thenReturn(nil)
                    mockStorage.when { $0.getOpenGroupSequenceNumber(for: any(), on: any()) }.thenReturn(nil)
                    
                    mockOGMCache.when { $0.isPolling }.thenReturn(true)
                    mockOGMCache.when { $0.pollers }.thenReturn(["testserver": OpenGroupAPI.Poller(for: "testserver")])
                    
                    mockUserDefaults
                        .when { $0.object(forKey: SNUserDefaults.Date.lastOpen.rawValue) }
                        .thenReturn(Date(timeIntervalSince1970: 1234567890))
                    
                    openGroupManager.startPolling(using: dependencies)
                }
                
                it("removes all pollers") {
                    openGroupManager.stopPolling(using: dependencies)
                    
                    expect(mockOGMCache).to(call(matchingParameters: true) { $0.pollers = [:] })
                }
                
                it("updates the isPolling flag") {
                    openGroupManager.stopPolling(using: dependencies)
                    
                    expect(mockOGMCache).to(call(matchingParameters: true) { $0.isPolling = false })
                }
            }
            
            // MARK: - Adding & Removing
            
            context("when adding") {
                beforeEach {
                    mockStorage.when { $0.removeOpenGroupSequenceNumber(for: any(), on: any(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.setOpenGroupPublicKey(for: any(), to: any(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.setOpenGroupServer(any(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.setOpenGroup(any(), for: any(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.setUserCount(to: any(), forOpenGroupWithID: any(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.getOpenGroupInboxLatestMessageId(for: any()) }.thenReturn(nil)
                    mockStorage.when { $0.getOpenGroupOutboxLatestMessageId(for: any()) }.thenReturn(nil)
                    mockStorage.when { $0.getOpenGroupSequenceNumber(for: any(), on: any()) }.thenReturn(nil)
                    
                    mockOGMCache.when { $0.pollers }.thenReturn([:])
                    mockOGMCache.when { $0.moderators }.thenReturn([:])
                    mockOGMCache.when { $0.admins }.thenReturn([:])
                    
                    mockUserDefaults
                        .when { $0.object(forKey: SNUserDefaults.Date.lastOpen.rawValue) }
                        .thenReturn(Date(timeIntervalSince1970: 1234567890))
                }
                
                it("resets the sequence number of the open group") {
                    openGroupManager
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
                    openGroupManager
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
                    openGroupManager
                        .add(
                            roomToken: "testRoom",
                            server: "testServer",
                            publicKey: "testKey",
                            isConfigMessage: false,
                            using: testTransaction,
                            dependencies: dependencies
                        )
                        .retainUntilComplete()
                    
                    expect(mockOGMCache)
                        .toEventually(
                            call(matchingParameters: true) {
                                $0.pollers = ["testServer": OpenGroupAPI.Poller(for: "testServer")]
                            },
                            timeout: .milliseconds(100)
                        )
                }
                
                context("an existing room") {
                    beforeEach {
                        mockOGMCache.when { $0.pollers }.thenReturn(["testServer": OpenGroupAPI.Poller(for: "testServer")])
                    }
                    
                    it("does not reset the sequence number or update the public key") {
                        openGroupManager
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
                        
                        let promise = openGroupManager
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
                beforeEach {
                    mockStorage
                        .when { $0.updateMessageIDCollectionByPruningMessagesWithIDs(anySet(), using: anyAny()) }
                        .thenReturn(())
                    mockStorage.when { $0.removeReceivedMessageTimestamps(anySet(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.removeOpenGroupSequenceNumber(for: any(), on: any(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.removeOpenGroup(for: any(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.removeOpenGroupServer(name: any(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.removeOpenGroupPublicKey(for: any(), using: anyAny()) }.thenReturn(())
                    
                    mockOGMCache.when { $0.pollers }.thenReturn([:])
                }
                
                it("removes messages for the given thread") {
                    openGroupManager
                        .delete(
                            testOpenGroup,
                            associatedWith: testGroupThread,
                            using: testTransaction,
                            dependencies: dependencies
                        )
                    
                    expect(mockStorage)
                        .to(call(matchingParameters: true) {
                            $0.updateMessageIDCollectionByPruningMessagesWithIDs(
                                Set(arrayLiteral: testInteraction.uniqueId!),
                                using: testTransaction! as Any
                            )
                        })
                }
                
                it("removes received timestamps for the given thread") {
                    openGroupManager
                        .delete(
                            testOpenGroup,
                            associatedWith: testGroupThread,
                            using: testTransaction,
                            dependencies: dependencies
                        )
                    
                    expect(mockStorage)
                        .to(call(matchingParameters: true) {
                            $0.removeReceivedMessageTimestamps(
                                Set(arrayLiteral: testInteraction.timestamp),
                                using: testTransaction! as Any
                            )
                        })
                }
                
                it("removes the sequence number for the given thread") {
                    openGroupManager
                        .delete(
                            testOpenGroup,
                            associatedWith: testGroupThread,
                            using: testTransaction,
                            dependencies: dependencies
                        )
                    
                    expect(mockStorage)
                        .to(call(matchingParameters: true) {
                            $0.removeOpenGroupSequenceNumber(
                                for: "testRoom",
                                on: "testserver",
                                using: testTransaction! as Any
                            )
                        })
                }
                
                it("removes all interactions for the given thread") {
                    openGroupManager
                        .delete(
                            testOpenGroup,
                            associatedWith: testGroupThread,
                            using: YapDatabaseReadWriteTransaction(),
                            dependencies: dependencies
                        )
                    
                    expect(testGroupThread.didCallRemoveAllThreadInteractions).to(beTrue())
                }
                
                it("removes the given thread") {
                    openGroupManager
                        .delete(
                            testOpenGroup,
                            associatedWith: testGroupThread,
                            using: YapDatabaseReadWriteTransaction(),
                            dependencies: dependencies
                        )
                    
                    expect(testGroupThread.didCallRemove).to(beTrue())
                }
                
                it("removes the open group") {
                    openGroupManager
                        .delete(
                            testOpenGroup,
                            associatedWith: testGroupThread,
                            using: testTransaction,
                            dependencies: dependencies
                        )
                    
                    expect(mockStorage)
                        .to(call(matchingParameters: true) {
                            $0.removeOpenGroup(
                                for: testGroupThread.uniqueId!,
                                using: testTransaction! as Any
                            )
                        })
                }
                
                context("and there is only one open group for this server") {
                    it("stops the poller") {
                        mockOGMCache.when { $0.pollers }.thenReturn(["testserver": OpenGroupAPI.Poller(for: "testserver")])
                        
                        openGroupManager
                            .delete(
                                testOpenGroup,
                                associatedWith: testGroupThread,
                                using: testTransaction,
                                dependencies: dependencies
                            )
                        
                        expect(mockOGMCache).to(call(matchingParameters: true) { $0.pollers = [:] })
                    }
                    
                    it("removes the open group server") {
                        openGroupManager
                            .delete(
                                testOpenGroup,
                                associatedWith: testGroupThread,
                                using: testTransaction,
                                dependencies: dependencies
                            )
                        
                        expect(mockStorage)
                            .to(call(matchingParameters: true) {
                                $0.removeOpenGroupServer(
                                    name: "testserver",
                                    using: testTransaction! as Any
                                )
                            })
                    }
                    
                    it("removes the open group public key") {
                        openGroupManager
                            .delete(
                                testOpenGroup,
                                associatedWith: testGroupThread,
                                using: testTransaction,
                                dependencies: dependencies
                            )
                        
                        expect(mockStorage)
                            .to(call(matchingParameters: true) {
                                $0.removeOpenGroupPublicKey(
                                    for: "testserver",
                                    using: testTransaction! as Any
                                )
                            })
                    }
                }
                
                context("and the are multiple open groups for this server") {
                    beforeEach {
                        mockStorage
                            .when { $0.getAllOpenGroups() }
                            .thenReturn([
                                "0": testOpenGroup,
                                "1": OpenGroup(
                                    server: "testServer",
                                    room: "testRoom1",
                                    publicKey: TestConstants.publicKey,
                                    name: "Test1",
                                    groupDescription: nil,
                                    imageID: nil,
                                    infoUpdates: 0
                                )
                            ])
                    }
                    
                    it("does not stop the poller") {
                        mockOGMCache.when { $0.pollers }.thenReturn(["testserver": OpenGroupAPI.Poller(for: "testserver")])
                        
                        openGroupManager
                            .delete(
                                testOpenGroup,
                                associatedWith: testGroupThread,
                                using: testTransaction,
                                dependencies: dependencies
                            )
                        
                        expect(mockOGMCache).toNot(call { $0.pollers })
                    }
                    
                    it("does not remove the open group server") {
                        openGroupManager
                            .delete(
                                testOpenGroup,
                                associatedWith: testGroupThread,
                                using: testTransaction,
                                dependencies: dependencies
                            )
                        
                        expect(mockStorage).toNot(call { $0.removeOpenGroupServer(name: any(), using: anyAny()) })
                    }
                    
                    it("does not remove the open group public key") {
                        openGroupManager
                            .delete(
                                testOpenGroup,
                                associatedWith: testGroupThread,
                                using: testTransaction,
                                dependencies: dependencies
                            )
                        
                        expect(mockStorage).toNot(call { $0.removeOpenGroupPublicKey(for: any(), using: anyAny()) })
                    }
                }
            }
            
            // MARK: - Response Processing
            
            // MARK: - --handleCapabilities
            
            context("when handling capabilities") {
                beforeEach {
                    mockStorage.when { $0.setOpenGroupServer(any(), using: anyAny()) }.thenReturn(())
                    
                    OpenGroupManager
                        .handleCapabilities(
                            OpenGroupAPI.Capabilities(capabilities: [], missing: []),
                            on: "testserver",
                            using: testTransaction,
                            dependencies: dependencies
                        )
                }
                
                it("stores the capabilities") {
                    expect(mockStorage).to(call { $0.setOpenGroupServer(any(), using: anyAny()) })
                }
            }
            
            // MARK: - --handlePollInfo
            
            context("when handling room poll info") {
                beforeEach {
                    mockStorage.when { $0.setOpenGroup(any(), for: any(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.setOpenGroupServer(any(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.setUserCount(to: any(), forOpenGroupWithID: any(), using: anyAny()) }.thenReturn(())
                    mockStorage.when { $0.getOpenGroupSequenceNumber(for: any(), on: any()) }.thenReturn(nil)
                    mockStorage.when { $0.getOpenGroupInboxLatestMessageId(for: any()) }.thenReturn(nil)
                    mockStorage.when { $0.getOpenGroupOutboxLatestMessageId(for: any()) }.thenReturn(nil)
                    
                    mockOGMCache.when { $0.pollers }.thenReturn([:])
                    mockOGMCache.when { $0.moderators }.thenReturn([:])
                    mockOGMCache.when { $0.admins }.thenReturn([:])
                    
                    mockUserDefaults
                        .when { $0.object(forKey: SNUserDefaults.Date.lastOpen.rawValue) }
                        .thenReturn(nil)
                }
                
                it("attempts to retrieve the existing thread") {
                    OpenGroupManager.handlePollInfo(
                        testPollInfo,
                        publicKey: TestConstants.publicKey,
                        for: "testRoom",
                        on: "testServer",
                        using: testTransaction,
                        dependencies: dependencies
                    )
                    
                    // The 'testGroupThread' should be the one retrieved
                    expect(testGroupThread.numSaveCalls).to(equal(1))
                }
                
                it("attempts to retrieve the existing open group") {
                    OpenGroupManager.handlePollInfo(
                        testPollInfo,
                        publicKey: TestConstants.publicKey,
                        for: "testRoom",
                        on: "testServer",
                        using: testTransaction,
                        dependencies: dependencies
                    )
                    
                    expect(mockStorage).to(call { $0.getOpenGroup(for: any()) })
                }
                
                it("saves the thread") {
                    OpenGroupManager.handlePollInfo(
                        testPollInfo,
                        publicKey: TestConstants.publicKey,
                        for: "testRoom",
                        on: "testServer",
                        using: testTransaction,
                        dependencies: dependencies
                    )
                    
                    expect(testGroupThread.numSaveCalls).to(equal(1))
                }
                
                it("saves the open group") {
                    OpenGroupManager.handlePollInfo(
                        testPollInfo,
                        publicKey: TestConstants.publicKey,
                        for: "testRoom",
                        on: "testServer",
                        using: testTransaction,
                        dependencies: dependencies
                    )
                    
                    expect(mockStorage).to(call { $0.setOpenGroup(any(), for: any(), using: anyAny()) })
                }
                
                it("saves the updated user count") {
                    OpenGroupManager.handlePollInfo(
                        testPollInfo,
                        publicKey: TestConstants.publicKey,
                        for: "testRoom",
                        on: "testServer",
                        using: testTransaction,
                        dependencies: dependencies
                    )
                    
                    expect(mockStorage)
                        .to(call(matchingParameters: true) {
                            $0.setUserCount(to: 10, forOpenGroupWithID: "testServer.testRoom", using: testTransaction! as Any)
                        })
                }
                
                it("calls the completion block") {
                    var didCallComplete: Bool = false
                    
                    OpenGroupManager.handlePollInfo(
                        testPollInfo,
                        publicKey: TestConstants.publicKey,
                        for: "testRoom",
                        on: "testServer",
                        using: testTransaction,
                        dependencies: dependencies
                    ) {
                        didCallComplete = true
                    }
                    
                    expect(didCallComplete)
                        .toEventually(
                            beTrue(),
                            timeout: .milliseconds(100)
                        )
                }
                
                context("and updating the moderator list") {
                    it("successfully updates") {
                        mockOGMCache.when { $0.moderators }.thenReturn([:])
                        testPollInfo = OpenGroupAPI.RoomPollInfo(
                            token: "testRoom",
                            activeUsers: 10,
                            admin: false,
                            globalAdmin: false,
                            moderator: false,
                            globalModerator: false,
                            read: false,
                            defaultRead: nil,
                            defaultAccessible: nil,
                            write: false,
                            defaultWrite: nil,
                            upload: false,
                            defaultUpload: nil,
                            details: TestCapabilitiesAndRoomApi.roomData.with(moderators: ["TestMod"], admins: [])
                        )
                        
                        OpenGroupManager.handlePollInfo(
                            testPollInfo,
                            publicKey: TestConstants.publicKey,
                            for: "testRoom",
                            on: "testServer",
                            using: testTransaction,
                            dependencies: dependencies
                        )
                        
                        expect(mockOGMCache)
                            .toEventually(
                                call(matchingParameters: true) {
                                    $0.moderators = ["testServer": ["testRoom": Set(arrayLiteral: "TestMod")]]
                                },
                                timeout: .milliseconds(100)
                            )
                    }
                    
                    it("defaults to an empty array if no moderators are provided") {
                        mockOGMCache.when { $0.moderators }.thenReturn([:])
                        testPollInfo = OpenGroupAPI.RoomPollInfo(
                            token: "testRoom",
                            activeUsers: 10,
                            admin: false,
                            globalAdmin: false,
                            moderator: false,
                            globalModerator: false,
                            read: false,
                            defaultRead: nil,
                            defaultAccessible: nil,
                            write: false,
                            defaultWrite: nil,
                            upload: false,
                            defaultUpload: nil,
                            details: nil
                        )
                        
                        OpenGroupManager.handlePollInfo(
                            testPollInfo,
                            publicKey: TestConstants.publicKey,
                            for: "testRoom",
                            on: "testServer",
                            using: testTransaction,
                            dependencies: dependencies
                        )
                        
                        expect(mockOGMCache)
                            .toEventually(
                                call(matchingParameters: true) {
                                    $0.moderators = ["testServer": ["testRoom": Set()]]
                                },
                                timeout: .milliseconds(100)
                            )
                    }
                }
                
                context("and updating the admin list") {
                    it("successfully updates") {
                        mockOGMCache.when { $0.admins }.thenReturn([:])
                        testPollInfo = OpenGroupAPI.RoomPollInfo(
                            token: "testRoom",
                            activeUsers: 10,
                            admin: false,
                            globalAdmin: false,
                            moderator: false,
                            globalModerator: false,
                            read: false,
                            defaultRead: nil,
                            defaultAccessible: nil,
                            write: false,
                            defaultWrite: nil,
                            upload: false,
                            defaultUpload: nil,
                            details: TestCapabilitiesAndRoomApi.roomData.with(moderators: [], admins: ["TestAdmin"])
                        )
                        
                        OpenGroupManager.handlePollInfo(
                            testPollInfo,
                            publicKey: TestConstants.publicKey,
                            for: "testRoom",
                            on: "testServer",
                            using: testTransaction,
                            dependencies: dependencies
                        )
                        
                        expect(mockOGMCache)
                            .toEventually(
                                call(matchingParameters: true) {
                                    $0.admins = ["testServer": ["testRoom": Set(arrayLiteral: "TestAdmin")]]
                                },
                                timeout: .milliseconds(100)
                            )
                    }
                    
                    it("defaults to an empty array if no moderators are provided") {
                        mockOGMCache.when { $0.admins }.thenReturn([:])
                        testPollInfo = OpenGroupAPI.RoomPollInfo(
                            token: "testRoom",
                            activeUsers: 10,
                            admin: false,
                            globalAdmin: false,
                            moderator: false,
                            globalModerator: false,
                            read: false,
                            defaultRead: nil,
                            defaultAccessible: nil,
                            write: false,
                            defaultWrite: nil,
                            upload: false,
                            defaultUpload: nil,
                            details: nil
                        )
                        
                        OpenGroupManager.handlePollInfo(
                            testPollInfo,
                            publicKey: TestConstants.publicKey,
                            for: "testRoom",
                            on: "testServer",
                            using: testTransaction,
                            dependencies: dependencies
                        )
                        
                        expect(mockOGMCache)
                            .toEventually(
                                call(matchingParameters: true) {
                                    $0.admins = ["testServer": ["testRoom": Set()]]
                                },
                                timeout: .milliseconds(100)
                            )
                    }
                }
                
                context("when it cannot get the thread id") {
                    it("does not save the thread") {
                        testGroupThread.mockData[.uniqueId] = nil
                        
                        OpenGroupManager.handlePollInfo(
                            testPollInfo,
                            publicKey: TestConstants.publicKey,
                            for: "testRoom",
                            on: "testServer",
                            using: testTransaction,
                            dependencies: dependencies
                        )
                        
                        expect(testGroupThread.numSaveCalls).to(equal(0))
                    }
                }
                
                context("when not given a public key") {
                    it("saves the open group with the existing public key") {
                        OpenGroupManager.handlePollInfo(
                            testPollInfo,
                            publicKey: nil,
                            for: "testRoom",
                            on: "testServer",
                            using: testTransaction,
                            dependencies: dependencies
                        )
                        
                        expect(mockStorage)
                            .to(call(matchingParameters: true) {
                                $0.setOpenGroup(
                                    OpenGroup(
                                        server: "testServer",
                                        room: "testRoom",
                                        publicKey: TestConstants.publicKey,
                                        name: "test",
                                        groupDescription: nil,
                                        imageID: nil,
                                        infoUpdates: 10
                                    ),
                                    for: "TestGroupId",
                                    using: testTransaction! as Any
                                )
                            })
                    }
                }
                
                context("when it cannot get the public key") {
                    it("does not save the thread") {
                        mockStorage.when { $0.getOpenGroup(for: any()) }.thenReturn(nil)
                        
                        OpenGroupManager.handlePollInfo(
                            testPollInfo,
                            publicKey: nil,
                            for: "testRoom",
                            on: "testServer",
                            using: testTransaction,
                            dependencies: dependencies
                        )
                        
                        expect(testGroupThread.numSaveCalls).to(equal(0))
                    }
                }
                
                context("when storing the open group") {
                    it("defaults the infoUpdates to zero") {
                        mockStorage.when { $0.getOpenGroup(for: any()) }.thenReturn(nil)
                        testPollInfo = OpenGroupAPI.RoomPollInfo(
                            token: "testRoom",
                            activeUsers: 10,
                            admin: false,
                            globalAdmin: false,
                            moderator: false,
                            globalModerator: false,
                            read: false,
                            defaultRead: nil,
                            defaultAccessible: nil,
                            write: false,
                            defaultWrite: nil,
                            upload: false,
                            defaultUpload: nil,
                            details: nil
                        )
                        
                        OpenGroupManager.handlePollInfo(
                            testPollInfo,
                            publicKey: TestConstants.publicKey,
                            for: "testRoom",
                            on: "testServer",
                            using: testTransaction,
                            dependencies: dependencies
                        )
                        
                        expect(mockStorage)
                            .to(call(matchingParameters: true) {
                                $0.setOpenGroup(
                                    OpenGroup(
                                        server: "testServer",
                                        room: "testRoom",
                                        publicKey: TestConstants.publicKey,
                                        name: "TestTitle",
                                        groupDescription: nil,
                                        imageID: nil,
                                        infoUpdates: 0
                                    ),
                                    for: "TestGroupId",
                                    using: testTransaction! as Any
                                )
                            })
                    }
                }
                
                context("when checking to start polling") {
                    it("starts a new poller when not already polling") {
                        mockOGMCache.when { $0.pollers }.thenReturn([:])
                        
                        OpenGroupManager.handlePollInfo(
                            testPollInfo,
                            publicKey: TestConstants.publicKey,
                            for: "testRoom",
                            on: "testServer",
                            using: testTransaction,
                            dependencies: dependencies
                        )
                        
                        expect(mockOGMCache)
                            .to(call(matchingParameters: true) {
                                $0.pollers = ["testServer": OpenGroupAPI.Poller(for: "testServer")]
                            })
                    }
                    
                    it("does not start a new poller when already polling") {
                        mockOGMCache.when { $0.pollers }.thenReturn(["testServer": OpenGroupAPI.Poller(for: "testServer")])
                        
                        OpenGroupManager.handlePollInfo(
                            testPollInfo,
                            publicKey: TestConstants.publicKey,
                            for: "testRoom",
                            on: "testServer",
                            using: testTransaction,
                            dependencies: dependencies
                        )
                        
                        expect(mockOGMCache).to(call(.exactly(times: 1)) { $0.pollers })
                    }
                }
                
                context("when trying to get the room image") {
                    beforeEach {
                        let image: UIImage = UIImage(color: .red, size: CGSize(width: 1, height: 1))
                        let imageData: Data = image.pngData()!
                        mockStorage.when { $0.getOpenGroupImage(for: any(), on: any()) }.thenReturn(nil)
                        
                        mockOGMCache.when { $0.groupImagePromises }
                            .thenReturn(["testServer.testRoom": Promise.value(imageData)])
                    }
                    
                    it("uses the provided room image id if available") {
                        testPollInfo = OpenGroupAPI.RoomPollInfo(
                            token: "testRoom",
                            activeUsers: 10,
                            admin: false,
                            globalAdmin: false,
                            moderator: false,
                            globalModerator: false,
                            read: false,
                            defaultRead: nil,
                            defaultAccessible: nil,
                            write: false,
                            defaultWrite: nil,
                            upload: false,
                            defaultUpload: nil,
                            details: OpenGroupAPI.Room(
                                token: "test",
                                name: "test",
                                roomDescription: nil,
                                infoUpdates: 0,
                                messageSequence: 0,
                                created: 0,
                                activeUsers: 0,
                                activeUsersCutoff: 0,
                                imageId: 10,
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
                        )
                        
                        OpenGroupManager.handlePollInfo(
                            testPollInfo,
                            publicKey: TestConstants.publicKey,
                            for: "testRoom",
                            on: "testServer",
                            using: testTransaction,
                            dependencies: dependencies
                        )
                        
                        expect(mockStorage)
                            .to(call(matchingParameters: true) {
                                $0.setOpenGroup(
                                    OpenGroup(
                                        server: "testServer",
                                        room: "testRoom",
                                        publicKey: TestConstants.publicKey,
                                        name: "test",
                                        groupDescription: nil,
                                        imageID: "10",
                                        infoUpdates: 0
                                    ),
                                    for: "TestGroupId",
                                    using: testTransaction! as Any
                                )
                            })
                        expect(testGroupThread.groupModel.groupImage)
                            .toEventuallyNot(
                                beNil(),
                                timeout: .milliseconds(100)
                            )
                        expect(testGroupThread.numSaveCalls)
                            .toEventually(
                                equal(2),   // Call to save the open group and then to save the image
                                timeout: .milliseconds(100)
                            )
                    }
                    
                    it("uses the existing room image id if none is provided") {
                        mockStorage
                            .when { $0.getOpenGroup(for: any()) }
                            .thenReturn(
                                OpenGroup(
                                    server: "testServer",
                                    room: "testRoom",
                                    publicKey: TestConstants.publicKey,
                                    name: "Test",
                                    groupDescription: nil,
                                    imageID: "12",
                                    infoUpdates: 10
                                )
                            )
                        testPollInfo = OpenGroupAPI.RoomPollInfo(
                            token: "testRoom",
                            activeUsers: 10,
                            admin: false,
                            globalAdmin: false,
                            moderator: false,
                            globalModerator: false,
                            read: false,
                            defaultRead: nil,
                            defaultAccessible: nil,
                            write: false,
                            defaultWrite: nil,
                            upload: false,
                            defaultUpload: nil,
                            details: nil
                        )
                        
                        OpenGroupManager.handlePollInfo(
                            testPollInfo,
                            publicKey: TestConstants.publicKey,
                            for: "testRoom",
                            on: "testServer",
                            using: testTransaction,
                            dependencies: dependencies
                        )
                        
                        expect(mockStorage)
                            .to(call(matchingParameters: true) {
                                $0.setOpenGroup(
                                    OpenGroup(
                                        server: "testServer",
                                        room: "testRoom",
                                        publicKey: TestConstants.publicKey,
                                        name: "TestTitle",
                                        groupDescription: nil,
                                        imageID: "12",
                                        infoUpdates: 10
                                    ),
                                    for: "TestGroupId",
                                    using: testTransaction! as Any
                                )
                            })
                        expect(testGroupThread.groupModel.groupImage)
                            .toEventuallyNot(
                                beNil(),
                                timeout: .milliseconds(100)
                            )
                        expect(testGroupThread.numSaveCalls)
                            .toEventually(
                                equal(2),   // Call to save the open group and then to save the image
                                timeout: .milliseconds(100)
                            )
                    }
                    
                    it("uses the new room image id if there is an existing one") {
                        testGroupThread.mockData[.groupModel] = TSGroupModel(
                            title: "TestTitle",
                            memberIds: [],
                            image: UIImage(color: .blue, size: CGSize(width: 1, height: 1)),
                            groupId: LKGroupUtilities.getEncodedOpenGroupIDAsData("testServer.testRoom"),
                            groupType: .openGroup,
                            adminIds: [],
                            moderatorIds: []
                        )
                        mockStorage
                            .when { $0.getOpenGroup(for: any()) }
                            .thenReturn(
                                OpenGroup(
                                    server: "testServer",
                                    room: "testRoom",
                                    publicKey: TestConstants.publicKey,
                                    name: "Test",
                                    groupDescription: nil,
                                    imageID: "12",
                                    infoUpdates: 10
                                )
                            )
                        testPollInfo = OpenGroupAPI.RoomPollInfo(
                            token: "testRoom",
                            activeUsers: 10,
                            admin: false,
                            globalAdmin: false,
                            moderator: false,
                            globalModerator: false,
                            read: false,
                            defaultRead: nil,
                            defaultAccessible: nil,
                            write: false,
                            defaultWrite: nil,
                            upload: false,
                            defaultUpload: nil,
                            details: OpenGroupAPI.Room(
                                token: "test",
                                name: "test",
                                roomDescription: nil,
                                infoUpdates: 10,
                                messageSequence: 0,
                                created: 0,
                                activeUsers: 0,
                                activeUsersCutoff: 0,
                                imageId: 10,
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
                        )
                        
                        OpenGroupManager.handlePollInfo(
                            testPollInfo,
                            publicKey: TestConstants.publicKey,
                            for: "testRoom",
                            on: "testServer",
                            using: testTransaction,
                            dependencies: dependencies
                        )
                        
                        expect(mockStorage)
                            .to(call(matchingParameters: true) {
                                $0.setOpenGroup(
                                    OpenGroup(
                                        server: "testServer",
                                        room: "testRoom",
                                        publicKey: TestConstants.publicKey,
                                        name: "test",
                                        groupDescription: nil,
                                        imageID: "10",
                                        infoUpdates: 10
                                    ),
                                    for: "TestGroupId",
                                    using: testTransaction! as Any
                                )
                            })
                        expect(testGroupThread.groupModel.groupImage)
                            .toEventuallyNot(
                                beNil(),
                                timeout: .milliseconds(100)
                            )
                        expect(testGroupThread.numSaveCalls)
                            .toEventually(
                                equal(2),   // Call to save the open group and then to save the image
                                timeout: .milliseconds(100)
                            )
                    }
                    
                    it("does nothing if there is no room image") {
                        OpenGroupManager.handlePollInfo(
                            testPollInfo,
                            publicKey: TestConstants.publicKey,
                            for: "testRoom",
                            on: "testServer",
                            using: testTransaction,
                            dependencies: dependencies
                        )
                        
                        expect(testGroupThread.groupModel.groupImage)
                            .toEventually(
                                beNil(),
                                timeout: .milliseconds(100)
                            )
                        expect(testGroupThread.numSaveCalls)
                            .toEventually(
                                equal(1),
                                timeout: .milliseconds(100)
                            )
                    }
                    
                    it("does nothing if it fails to retrieve the room image") {
                        mockOGMCache.when { $0.groupImagePromises }
                            .thenReturn(["testServer.testRoom": Promise(error: HTTP.Error.generic)])
                        
                        testPollInfo = OpenGroupAPI.RoomPollInfo(
                            token: "testRoom",
                            activeUsers: 10,
                            admin: false,
                            globalAdmin: false,
                            moderator: false,
                            globalModerator: false,
                            read: false,
                            defaultRead: nil,
                            defaultAccessible: nil,
                            write: false,
                            defaultWrite: nil,
                            upload: false,
                            defaultUpload: nil,
                            details: OpenGroupAPI.Room(
                                token: "test",
                                name: "test",
                                roomDescription: nil,
                                infoUpdates: 0,
                                messageSequence: 0,
                                created: 0,
                                activeUsers: 0,
                                activeUsersCutoff: 0,
                                imageId: 10,
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
                        )
                        
                        OpenGroupManager.handlePollInfo(
                            testPollInfo,
                            publicKey: TestConstants.publicKey,
                            for: "testRoom",
                            on: "testServer",
                            using: testTransaction,
                            dependencies: dependencies
                        )
                        
                        expect(testGroupThread.groupModel.groupImage)
                            .toEventually(
                                beNil(),
                                timeout: .milliseconds(100)
                            )
                        expect(testGroupThread.numSaveCalls)
                            .toEventually(
                                equal(1),
                                timeout: .milliseconds(100)
                            )
                    }
                    
                    it("saves the retrieved room image") {
                        testPollInfo = OpenGroupAPI.RoomPollInfo(
                            token: "testRoom",
                            activeUsers: 10,
                            admin: false,
                            globalAdmin: false,
                            moderator: false,
                            globalModerator: false,
                            read: false,
                            defaultRead: nil,
                            defaultAccessible: nil,
                            write: false,
                            defaultWrite: nil,
                            upload: false,
                            defaultUpload: nil,
                            details: OpenGroupAPI.Room(
                                token: "test",
                                name: "test",
                                roomDescription: nil,
                                infoUpdates: 10,
                                messageSequence: 0,
                                created: 0,
                                activeUsers: 0,
                                activeUsersCutoff: 0,
                                imageId: 10,
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
                        )
                        
                        OpenGroupManager.handlePollInfo(
                            testPollInfo,
                            publicKey: TestConstants.publicKey,
                            for: "testRoom",
                            on: "testServer",
                            using: testTransaction,
                            dependencies: dependencies
                        )
                        
                        expect(testGroupThread.groupModel.groupImage)
                            .toEventuallyNot(
                                beNil(),
                                timeout: .milliseconds(100)
                            )
                        expect(testGroupThread.numSaveCalls)
                            .toEventually(
                                equal(2),   // Call to save the open group and then to save the image
                                timeout: .milliseconds(100)
                            )
                    }
                }
            }
            
            // MARK: - --handleMessages
            
            context("when handling messages") {
                beforeEach {
                    mockStorage
                        .when {
                            $0.setOpenGroupSequenceNumber(
                                for: any(),
                                on: any(),
                                to: any(),
                                using: testTransaction as Any
                            )
                        }
                        .thenReturn(())
                }
                
                it("updates the sequence number when there are messages") {
                    OpenGroupManager.handleMessages(
                        [
                            OpenGroupAPI.Message(
                                id: 1,
                                sender: nil,
                                posted: 123,
                                edited: nil,
                                seqNo: 124,
                                whisper: false,
                                whisperMods: false,
                                whisperTo: nil,
                                base64EncodedData: nil,
                                base64EncodedSignature: nil
                            )
                        ],
                        for: "testRoom",
                        on: "testServer",
                        isBackgroundPoll: false,
                        using: testTransaction,
                        dependencies: dependencies
                    )
                    
                    expect(mockStorage)
                        .to(call(matchingParameters: true) {
                            $0.setOpenGroupSequenceNumber(
                                for: "testRoom",
                                on: "testServer",
                                to: 124,
                                using: testTransaction as Any
                            )
                        })
                }
                
                it("does not update the sequence number if there are no messages") {
                    OpenGroupManager.handleMessages(
                        [],
                        for: "testRoom",
                        on: "testServer",
                        isBackgroundPoll: false,
                        using: testTransaction,
                        dependencies: dependencies
                    )
                    
                    expect(mockStorage)
                        .toNot(call {
                            $0.setOpenGroupSequenceNumber(for: any(), on: any(), to: any(), using: testTransaction as Any)
                        })
                }
            }
        }
    }
}

// MARK: - Room Convenience Extensions

extension OpenGroupAPI.Room {
    func with(moderators: [String], admins: [String]) -> OpenGroupAPI.Room {
        return OpenGroupAPI.Room(
            token: self.token,
            name: self.name,
            roomDescription: self.roomDescription,
            infoUpdates: self.infoUpdates,
            messageSequence: self.messageSequence,
            created: self.created,
            activeUsers: self.activeUsers,
            activeUsersCutoff: self.activeUsersCutoff,
            imageId: self.imageId,
            pinnedMessages: self.pinnedMessages,
            admin: self.admin,
            globalAdmin: self.globalAdmin,
            admins: admins,
            hiddenAdmins: self.hiddenAdmins,
            moderator: self.moderator,
            globalModerator: self.globalModerator,
            moderators: moderators,
            hiddenModerators: self.hiddenModerators,
            read: self.read,
            defaultRead: self.defaultRead,
            defaultAccessible: self.defaultAccessible,
            write: self.write,
            defaultWrite: self.defaultWrite,
            upload: self.upload,
            defaultUpload: self.defaultUpload
        )
    }
}
