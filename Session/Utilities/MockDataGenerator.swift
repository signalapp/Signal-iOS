// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Sodium
import SessionMessagingKit

enum MockDataGenerator {
    // Note: This was taken from TensorFlow's Random (https://github.com/apple/swift/blob/bc8f9e61d333b8f7a625f74d48ef0b554726e349/stdlib/public/TensorFlow/Random.swift)
    // the complex approach is needed due to an issue with Swift's randomElement(using:)
    // generation (see https://stackoverflow.com/a/64897775 for more info)
    struct ARC4RandomNumberGenerator: RandomNumberGenerator {
        var state: [UInt8] = Array(0...255)
        var iPos: UInt8 = 0
        var jPos: UInt8 = 0
        
        init<T: BinaryInteger>(seed: T) {
            self.init(
                seed: (0..<(UInt64.bitWidth / UInt64.bitWidth)).map { index in
                    UInt8(truncatingIfNeeded: seed >> (UInt8.bitWidth * index))
                }
            )
        }
        
        init(seed: [UInt8]) {
            precondition(seed.count > 0, "Length of seed must be positive")
            precondition(seed.count <= 256, "Length of seed must be at most 256")
            
            // Note: Have to use a for loop instead of a 'forEach' otherwise
            // it doesn't work properly (not sure why...)
            var j: UInt8 = 0
            for i: UInt8 in 0...255 {
              j &+= S(i) &+ seed[Int(i) % seed.count]
              swapAt(i, j)
            }
        }
        
        /// Produce the next random UInt64 from the stream, and advance the internal state
        mutating func next() -> UInt64 {
            // Note: Have to use a for loop instead of a 'forEach' otherwise
            // it doesn't work properly (not sure why...)
            var result: UInt64 = 0
            for _ in 0..<UInt64.bitWidth / UInt8.bitWidth {
              result <<= UInt8.bitWidth
              result += UInt64(nextByte())
            }
            
            return result
        }
        
        /// Helper to access the state
        private func S(_ index: UInt8) -> UInt8 {
            return state[Int(index)]
        }
        
        /// Helper to swap elements of the state
        private mutating func swapAt(_ i: UInt8, _ j: UInt8) {
            state.swapAt(Int(i), Int(j))
        }

        /// Generates the next byte in the keystream.
        private mutating func nextByte() -> UInt8 {
            iPos &+= 1
            jPos &+= S(iPos)
            swapAt(iPos, jPos)
            return S(S(iPos) &+ S(jPos))
        }
    }
    
    static func generateMockData() {
        // Don't re-generate the mock data if it already exists
        var existingMockDataThread: TSContactThread?
        
        Storage.read { transaction in
            existingMockDataThread = TSContactThread.getWithContactSessionID("MockDatabaseThread", transaction: transaction)
        }

        guard existingMockDataThread == nil else { return }
        
        /// The mock data generation is quite slow, there are 3 parts which take a decent amount of time (deleting the account afterwards will also take a long time):
        ///     Generating the threads & content - ~3s per 100
        ///     Writing to the database - ~10s per 1000
        ///     Updating the UI - ~10s per 1000
        let dmThreadCount: Int = 100
        let closedGroupThreadCount: Int = 0
        let openGroupThreadCount: Int = 0
        let maxMessagesPerThread: Int = 50
        let dmRandomSeed: Int = 1111
        let cgRandomSeed: Int = 2222
        let ogRandomSeed: Int = 3333
        
        // FIXME: Make sure this data doesn't go off device somehow?
        Storage.shared.write { anyTransaction in
            guard let transaction: YapDatabaseReadWriteTransaction = anyTransaction as? YapDatabaseReadWriteTransaction else { return }
            
            // First create the thread used to indicate that the mock data has been generated
            _ = TSContactThread.getOrCreateThread(withContactSessionID: "MockDatabaseThread", transaction: transaction)
            
            // Multiple spaces to make it look more like words
            let stringContent: [String] = "abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789 ".map { String($0) }
            let timestampNow: TimeInterval = Date().timeIntervalSince1970
            let userSessionId: String = getUserHexEncodedPublicKey()
            
            // MARK: - -- DM Thread
            var dmThreadRandomGenerator: ARC4RandomNumberGenerator = ARC4RandomNumberGenerator(seed: dmRandomSeed)
            
            (0..<dmThreadCount).forEach { threadIndex in
                let data = Data((0..<16).map { _ in UInt8.random(in: (UInt8.min...UInt8.max), using: &dmThreadRandomGenerator) })
                
                let randomSessionId: String = KeyPairUtilities.generate(from: data).x25519KeyPair.hexEncodedPublicKey
                let isMessageRequest: Bool = Bool.random(using: &dmThreadRandomGenerator)
                let contactNameLength: Int = ((5..<20).randomElement(using: &dmThreadRandomGenerator) ?? 0)
                let numMessages: Int = ((0..<maxMessagesPerThread).randomElement(using: &dmThreadRandomGenerator) ?? 0)
                
                // Generate the thread
                let thread: TSContactThread = TSContactThread.getOrCreateThread(withContactSessionID: randomSessionId, transaction: transaction)
                thread.shouldBeVisible = true
                
                // Generate the contact
                let contact = Contact(sessionID: randomSessionId)
                contact.name = (0..<contactNameLength)
                    .compactMap { _ in stringContent.randomElement(using: &dmThreadRandomGenerator) }
                    .joined()
                contact.isApproved = (!isMessageRequest || Bool.random(using: &dmThreadRandomGenerator))
                contact.didApproveMe = (!isMessageRequest && Bool.random(using: &dmThreadRandomGenerator))
                Storage.shared.setContact(contact, using: transaction)
                
                // Generate the message history (Note: Unapproved message requests will only include incoming messages)
                (0..<numMessages).forEach { index in
                    let isIncoming: Bool = (
                        Bool.random(using: &dmThreadRandomGenerator) &&
                        (!isMessageRequest || contact.isApproved)
                    )
                    let messageLength: Int = ((3..<40).randomElement(using: &dmThreadRandomGenerator) ?? 0)
                    
                    let message: VisibleMessage = VisibleMessage()
                    message.sender = (isIncoming ? randomSessionId : userSessionId)
                    message.sentTimestamp = UInt64(floor(timestampNow - Double(index * 5)))
                    message.text = (0..<messageLength)
                        .compactMap { _ in stringContent.randomElement(using: &dmThreadRandomGenerator) }
                        .joined()
                    
                    if isIncoming {
                        let tsMessage: TSOutgoingMessage = TSOutgoingMessage.from(message, associatedWith: thread, using: transaction)
                        tsMessage.save(with: transaction)
                    }
                    else {
                        let tsMessage: TSIncomingMessage = TSIncomingMessage.from(message, quotedMessage: nil, linkPreview: nil, associatedWith: thread)
                        tsMessage.save(with: transaction)
                    }
                }
                
                // Save the thread
                thread.save(with: transaction)
            }
            
            // MARK: - -- Closed Group
            var cgThreadRandomGenerator: ARC4RandomNumberGenerator = ARC4RandomNumberGenerator(seed: cgRandomSeed)
            
            (0..<closedGroupThreadCount).forEach { threadIndex in
                let data = Data((0..<16).map { _ in UInt8.random(in: (UInt8.min...UInt8.max), using: &cgThreadRandomGenerator) })
                let randomGroupPublicKey: String = KeyPairUtilities.generate(from: data).x25519KeyPair.hexEncodedPublicKey
                let groupNameLength: Int = ((5..<20).randomElement(using: &cgThreadRandomGenerator) ?? 0)
                let groupName: String = (0..<groupNameLength)
                    .compactMap { _ in stringContent.randomElement(using: &cgThreadRandomGenerator) }
                    .joined()
                let numGroupMembers: Int = ((0..<5).randomElement(using: &cgThreadRandomGenerator) ?? 0)
                let numMessages: Int = ((0..<maxMessagesPerThread).randomElement(using: &cgThreadRandomGenerator) ?? 0)
                
                // Generate the Contacts in the group
                var members: [String] = [userSessionId]
                
                (0..<numGroupMembers).forEach { _ in
                    let contactData = Data((0..<16).map { _ in UInt8.random(in: (UInt8.min...UInt8.max), using: &cgThreadRandomGenerator) })
                    let randomSessionId: String = KeyPairUtilities.generate(from: contactData).x25519KeyPair.hexEncodedPublicKey
                    let contactNameLength: Int = ((5..<20).randomElement(using: &cgThreadRandomGenerator) ?? 0)
                    let contact = Contact(sessionID: randomSessionId)
                    contact.name = (0..<contactNameLength)
                        .compactMap { _ in stringContent.randomElement(using: &cgThreadRandomGenerator) }
                        .joined()
                    Storage.shared.setContact(contact, using: transaction)
                    
                    members.append(randomSessionId)
                }
                
                let groupId: Data = LKGroupUtilities.getEncodedClosedGroupIDAsData(randomGroupPublicKey)
                let group: TSGroupModel = TSGroupModel(
                    title: groupName,
                    memberIds: members,
                    image: nil,
                    groupId: groupId,
                    groupType: .closedGroup,
                    adminIds: [members.randomElement(using: &cgThreadRandomGenerator) ?? userSessionId]
                )
                let thread = TSGroupThread.getOrCreateThread(with: group, transaction: transaction)
                thread.shouldBeVisible = true
                thread.save(with: transaction)
                
                // Add the group to the user's set of public keys to poll for and store the key pair
                let encryptionKeyPair = Curve25519.generateKeyPair()
                Storage.shared.addClosedGroupPublicKey(randomGroupPublicKey, using: transaction)
                Storage.shared.addClosedGroupEncryptionKeyPair(encryptionKeyPair, for: randomGroupPublicKey, using: transaction)
                
                // Generate the message history (Note: Unapproved message requests will only include incoming messages)
                (0..<numMessages).forEach { index in
                    let messageLength: Int = ((3..<40).randomElement(using: &dmThreadRandomGenerator) ?? 0)
                    let message: VisibleMessage = VisibleMessage()
                    message.sender = (members.randomElement(using: &cgThreadRandomGenerator) ?? userSessionId)
                    message.sentTimestamp = UInt64(floor(timestampNow - Double(index * 5)))
                    message.text = (0..<messageLength)
                        .compactMap { _ in stringContent.randomElement(using: &dmThreadRandomGenerator) }
                        .joined()
                    
                    if message.sender != userSessionId {
                        let tsMessage: TSOutgoingMessage = TSOutgoingMessage.from(message, associatedWith: thread, using: transaction)
                        tsMessage.save(with: transaction)
                    }
                    else {
                        let tsMessage: TSIncomingMessage = TSIncomingMessage.from(message, quotedMessage: nil, linkPreview: nil, associatedWith: thread)
                        tsMessage.save(with: transaction)
                    }
                }
                
                // Save the thread
                thread.save(with: transaction)
            }
        
            // MARK: - --Open Group
            var ogThreadRandomGenerator: ARC4RandomNumberGenerator = ARC4RandomNumberGenerator(seed: ogRandomSeed)
            
            (0..<openGroupThreadCount).forEach { threadIndex in
                let data = Data((0..<16).map { _ in UInt8.random(in: (UInt8.min...UInt8.max), using: &ogThreadRandomGenerator) })
                let randomGroupPublicKey: String = KeyPairUtilities.generate(from: data).x25519KeyPair.hexEncodedPublicKey
                let serverNameLength: Int = ((5..<20).randomElement(using: &ogThreadRandomGenerator) ?? 0)
                let roomNameLength: Int = ((5..<20).randomElement(using: &ogThreadRandomGenerator) ?? 0)
                let serverName: String = (0..<serverNameLength)
                    .compactMap { _ in stringContent.randomElement(using: &ogThreadRandomGenerator) }
                    .joined()
                let roomName: String = (0..<roomNameLength)
                    .compactMap { _ in stringContent.randomElement(using: &ogThreadRandomGenerator) }
                    .joined()
    
                // Create the open group model and the thread
                let openGroup: OpenGroupV2 = OpenGroupV2(server: serverName, room: roomName, name: roomName, publicKey: randomGroupPublicKey, imageID: nil)
                let groupId: Data = LKGroupUtilities.getEncodedOpenGroupIDAsData(openGroup.id)
                let model = TSGroupModel(title: openGroup.name, memberIds: [ userSessionId ], image: nil, groupId: groupId, groupType: .openGroup, adminIds: [])
                
                let thread = TSGroupThread.getOrCreateThread(with: model, transaction: transaction)
                thread.shouldBeVisible = true
                thread.save(with: transaction)
                
                Storage.shared.setV2OpenGroup(openGroup, for: thread.uniqueId!, using: transaction)
            }
        }
    }
}
