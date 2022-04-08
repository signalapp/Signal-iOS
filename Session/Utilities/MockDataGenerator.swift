// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Sodium
import Curve25519Kit
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
    
    // MARK: - Generation
        
    static var printProgress: Bool = true
    static var hasStartedGenerationThisRun: Bool = false
    
    static func generateMockData() {
        // Don't re-generate the mock data if it already exists
        var existingMockDataThread: TSContactThread?
        
        Storage.read { transaction in
            existingMockDataThread = TSContactThread.getWithContactSessionID("MockDatabaseThread", transaction: transaction)
        }

        guard !hasStartedGenerationThisRun && existingMockDataThread == nil else {
            hasStartedGenerationThisRun = true
            return
        }
        
        /// The mock data generation is quite slow, there are 3 parts which take a decent amount of time (deleting the account afterwards will also take a long time):
        ///     Generating the threads & content - ~3s per 100
        ///     Writing to the database - ~10s per 1000
        ///     Updating the UI - ~10s per 1000
        let dmThreadCount: Int = 1000
        let closedGroupThreadCount: Int = 50
        let openGroupThreadCount: Int = 20
        let messageRangePerThread: [ClosedRange<Int>] = [(0...500)]
        let dmRandomSeed: Int = 1111
        let cgRandomSeed: Int = 2222
        let ogRandomSeed: Int = 3333
        let chunkSize: Int = 1000    // Chunk up the thread writing to prevent memory issues
        let stringContent: [String] = "abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789 ".map { String($0) }
        let wordContent: [String] = ["alias", "consequatur", "aut", "perferendis", "sit", "voluptatem", "accusantium", "doloremque", "aperiam", "eaque", "ipsa", "quae", "ab", "illo", "inventore", "veritatis", "et", "quasi", "architecto", "beatae", "vitae", "dicta", "sunt", "explicabo", "aspernatur", "aut", "odit", "aut", "fugit", "sed", "quia", "consequuntur", "magni", "dolores", "eos", "qui", "ratione", "voluptatem", "sequi", "nesciunt", "neque", "dolorem", "ipsum", "quia", "dolor", "sit", "amet", "consectetur", "adipisci", "velit", "sed", "quia", "non", "numquam", "eius", "modi", "tempora", "incidunt", "ut", "labore", "et", "dolore", "magnam", "aliquam", "quaerat", "voluptatem", "ut", "enim", "ad", "minima", "veniam", "quis", "nostrum", "exercitationem", "ullam", "corporis", "nemo", "enim", "ipsam", "voluptatem", "quia", "voluptas", "sit", "suscipit", "laboriosam", "nisi", "ut", "aliquid", "ex", "ea", "commodi", "consequatur", "quis", "autem", "vel", "eum", "iure", "reprehenderit", "qui", "in", "ea", "voluptate", "velit", "esse", "quam", "nihil", "molestiae", "et", "iusto", "odio", "dignissimos", "ducimus", "qui", "blanditiis", "praesentium", "laudantium", "totam", "rem", "voluptatum", "deleniti", "atque", "corrupti", "quos", "dolores", "et", "quas", "molestias", "excepturi", "sint", "occaecati", "cupiditate", "non", "provident", "sed", "ut", "perspiciatis", "unde", "omnis", "iste", "natus", "error", "similique", "sunt", "in", "culpa", "qui", "officia", "deserunt", "mollitia", "animi", "id", "est", "laborum", "et", "dolorum", "fuga", "et", "harum", "quidem", "rerum", "facilis", "est", "et", "expedita", "distinctio", "nam", "libero", "tempore", "cum", "soluta", "nobis", "est", "eligendi", "optio", "cumque", "nihil", "impedit", "quo", "porro", "quisquam", "est", "qui", "minus", "id", "quod", "maxime", "placeat", "facere", "possimus", "omnis", "voluptas", "assumenda", "est", "omnis", "dolor", "repellendus", "temporibus", "autem", "quibusdam", "et", "aut", "consequatur", "vel", "illum", "qui", "dolorem", "eum", "fugiat", "quo", "voluptas", "nulla", "pariatur", "at", "vero", "eos", "et", "accusamus", "officiis", "debitis", "aut", "rerum", "necessitatibus", "saepe", "eveniet", "ut", "et", "voluptates", "repudiandae", "sint", "et", "molestiae", "non", "recusandae", "itaque", "earum", "rerum", "hic", "tenetur", "a", "sapiente", "delectus", "ut", "aut", "reiciendis", "voluptatibus", "maiores", "doloribus", "asperiores", "repellat"]
        let timestampNow: TimeInterval = Date().timeIntervalSince1970
        let userSessionId: String = getUserHexEncodedPublicKey()
        let logProgress: (String, String) -> () = { title, event in
            guard printProgress else { return }

            print("[MockDataGenerator] (\(Date().timeIntervalSince1970)) \(title) - \(event)")
        }
        
        hasStartedGenerationThisRun = true
        
        // FIXME: Make sure this data doesn't go off device somehow?
        logProgress("", "Start")
        
        // First create the thread used to indicate that the mock data has been generated
        Storage.write { transaction in
            _ = TSContactThread.getOrCreateThread(withContactSessionID: "MockDatabaseThread", transaction: transaction)
        }
        
        // MARK: - -- DM Thread
        
        var dmThreadRandomGenerator: ARC4RandomNumberGenerator = ARC4RandomNumberGenerator(seed: dmRandomSeed)
        var dmThreadIndex: Int = 0
        logProgress("DM Threads", "Start Generating \(dmThreadCount) threads")
        
        while dmThreadIndex < dmThreadCount {
            let remainingThreads: Int = (dmThreadCount - dmThreadIndex)
            
            (0..<min(chunkSize, remainingThreads)).forEach { index in
                let threadIndex: Int = (dmThreadIndex + index)
                
                Storage.write { transaction in
                    logProgress("DM Thread \(threadIndex)", "Start")
                
                    let data = Data((0..<16).map { _ in UInt8.random(in: (UInt8.min...UInt8.max), using: &dmThreadRandomGenerator) })
                    let randomSessionId: String = try! Identity.generate(from: data).x25519KeyPair.hexEncodedPublicKey
                    let isMessageRequest: Bool = Bool.random(using: &dmThreadRandomGenerator)
                    let contactNameLength: Int = ((5..<20).randomElement(using: &dmThreadRandomGenerator) ?? 0)
                    let numMessages: Int = (messageRangePerThread[threadIndex % messageRangePerThread.count]
                        .randomElement(using: &dmThreadRandomGenerator) ?? 0)
                    
                    // Generate the thread
                    let thread: TSContactThread = TSContactThread.getOrCreateThread(withContactSessionID: randomSessionId, transaction: transaction)
                    thread.shouldBeVisible = true
                    
                    // Generate the contact
                    let contact = Legacy.Contact(sessionID: randomSessionId)
                    contact.name = (0..<contactNameLength)
                        .compactMap { _ in stringContent.randomElement(using: &dmThreadRandomGenerator) }
                        .joined()
                    contact.isApproved = (!isMessageRequest || Bool.random(using: &dmThreadRandomGenerator))
                    contact.didApproveMe = (
                        !isMessageRequest &&
                        (((0..<10).randomElement(using: &dmThreadRandomGenerator) ?? 0) < 8) // 80% approved the current user
                    )
                    transaction.setObject(contact, forKey: contact.sessionID, inCollection: Legacy.contactCollection)
                    
                    // Generate the message history (Note: Unapproved message requests will only include incoming messages)
                    logProgress("DM Thread \(threadIndex)", "Generate \(numMessages) Messages")
                    (0..<numMessages).forEach { index in
                        let isIncoming: Bool = (
                            Bool.random(using: &dmThreadRandomGenerator) &&
                            (!isMessageRequest || contact.isApproved)
                        )
                        let messageWords: Int = ((1..<20).randomElement(using: &dmThreadRandomGenerator) ?? 0)
                        
                        let message: VisibleMessage = VisibleMessage()
                        message.sender = (isIncoming ? randomSessionId : userSessionId)
                        message.sentTimestamp = UInt64(floor(timestampNow - Double(index * 5)) * 1000)
                        message.text = (0..<messageWords)
                            .compactMap { _ in wordContent.randomElement(using: &dmThreadRandomGenerator) }
                            .joined(separator: " ")
                        
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
                    logProgress("DM Thread \(threadIndex)", "Done")
                }
            }
            
            dmThreadIndex += chunkSize
        }
        logProgress("DM Threads", "Done")
            
        // MARK: - -- Closed Group
        
        var cgThreadRandomGenerator: ARC4RandomNumberGenerator = ARC4RandomNumberGenerator(seed: cgRandomSeed)
        var cgThreadIndex: Int = 0
        logProgress("Closed Group Threads", "Start Generating \(closedGroupThreadCount) threads")
            
        while cgThreadIndex < closedGroupThreadCount {
            let remainingThreads: Int = (closedGroupThreadCount - cgThreadIndex)
            
            (0..<min(chunkSize, remainingThreads)).forEach { index in
                let threadIndex: Int = (cgThreadIndex + index)
                    
                Storage.write { transaction in
                    logProgress("Closed Group Thread \(threadIndex)", "Start")
                    
                    let data = Data((0..<16).map { _ in UInt8.random(in: (UInt8.min...UInt8.max), using: &cgThreadRandomGenerator) })
                    let randomGroupPublicKey: String = try! Identity.generate(from: data).x25519KeyPair.hexEncodedPublicKey
                    let groupNameLength: Int = ((5..<20).randomElement(using: &cgThreadRandomGenerator) ?? 0)
                    let groupName: String = (0..<groupNameLength)
                        .compactMap { _ in stringContent.randomElement(using: &cgThreadRandomGenerator) }
                        .joined()
                    let numGroupMembers: Int = ((0..<10).randomElement(using: &cgThreadRandomGenerator) ?? 0)
                    let numMessages: Int = (messageRangePerThread[threadIndex % messageRangePerThread.count]
                        .randomElement(using: &cgThreadRandomGenerator) ?? 0)
                    
                    // Generate the Contacts in the group
                    var members: [String] = [userSessionId]
                    logProgress("Closed Group Thread \(threadIndex)", "Generate \(numGroupMembers) Contacts")
                    
                    (0..<numGroupMembers).forEach { _ in
                        let contactData = Data((0..<16).map { _ in UInt8.random(in: (UInt8.min...UInt8.max), using: &cgThreadRandomGenerator) })
                        let randomSessionId: String = try! Identity.generate(from: contactData).x25519KeyPair.hexEncodedPublicKey
                        let contactNameLength: Int = ((5..<20).randomElement(using: &cgThreadRandomGenerator) ?? 0)
                        let contact = Legacy.Contact(sessionID: randomSessionId)
                        contact.name = (0..<contactNameLength)
                            .compactMap { _ in stringContent.randomElement(using: &cgThreadRandomGenerator) }
                            .joined()
                        transaction.setObject(contact, forKey: contact.sessionID, inCollection: Legacy.contactCollection)
                        
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
                    let keyPair: Box.KeyPair = Box.KeyPair(
                        publicKey: encryptionKeyPair.publicKey.bytes,
                        secretKey: encryptionKeyPair.privateKey.bytes
                    )
                    Storage.shared.addClosedGroupPublicKey(randomGroupPublicKey, using: transaction)
                    Storage.shared.addClosedGroupEncryptionKeyPair(keyPair, for: randomGroupPublicKey, using: transaction)
                    Storage.shared.setClosedGroupFormationTimestamp(to: UInt64(floor(timestampNow) * 1000), for: randomGroupPublicKey, using: transaction)
                    
                    // Generate the message history (Note: Unapproved message requests will only include incoming messages)
                    logProgress("Closed Group Thread \(threadIndex)", "Generate \(numMessages) Messages")
                    
                    (0..<numMessages).forEach { index in
                        let messageWords: Int = ((1..<20).randomElement(using: &cgThreadRandomGenerator) ?? 0)
                        let message: VisibleMessage = VisibleMessage()
                        message.sender = (members.randomElement(using: &cgThreadRandomGenerator) ?? userSessionId)
                        message.sentTimestamp = UInt64(floor(timestampNow - Double(index * 5)) * 1000)
                        message.text = (0..<messageWords)
                            .compactMap { _ in wordContent.randomElement(using: &cgThreadRandomGenerator) }
                            .joined(separator: " ")
                        
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
                    logProgress("Closed Group Thread \(threadIndex)", "Done")
                }
            }
            
            cgThreadIndex += chunkSize
        }
        logProgress("Closed Group Threads", "Done")
        
        // MARK: - --Open Group
        
        var ogThreadRandomGenerator: ARC4RandomNumberGenerator = ARC4RandomNumberGenerator(seed: ogRandomSeed)
        var ogThreadIndex: Int = 0
        logProgress("Open Group Threads", "Start Generating \(openGroupThreadCount) threads")
            
        while ogThreadIndex < openGroupThreadCount {
            let remainingThreads: Int = (openGroupThreadCount - ogThreadIndex)
            
            (0..<min(chunkSize, remainingThreads)).forEach { index in
                let threadIndex: Int = (ogThreadIndex + index)
                    
                Storage.write { transaction in
                    logProgress("Open Group Thread \(threadIndex)", "Start")
                
                    let randomGroupPublicKey: String = ((0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &dmThreadRandomGenerator) }).toHexString()
                    let serverNameLength: Int = ((5..<20).randomElement(using: &ogThreadRandomGenerator) ?? 0)
                    let roomNameLength: Int = ((5..<20).randomElement(using: &ogThreadRandomGenerator) ?? 0)
                    let serverName: String = (0..<serverNameLength)
                        .compactMap { _ in stringContent.randomElement(using: &ogThreadRandomGenerator) }
                        .joined()
                    let roomName: String = (0..<roomNameLength)
                        .compactMap { _ in stringContent.randomElement(using: &ogThreadRandomGenerator) }
                        .joined()
                    let numGroupMembers: Int = ((0..<250).randomElement(using: &ogThreadRandomGenerator) ?? 0)
                    let numMessages: Int = (messageRangePerThread[threadIndex % messageRangePerThread.count]
                        .randomElement(using: &ogThreadRandomGenerator) ?? 0)
        
                    // Generate the Contacts in the group
                    var members: [String] = [userSessionId]
                    logProgress("Open Group Thread \(threadIndex)", "Generate \(numGroupMembers) Contacts")

                    (0..<numGroupMembers).forEach { _ in
                        let contactData = Data((0..<16).map { _ in UInt8.random(in: (UInt8.min...UInt8.max), using: &ogThreadRandomGenerator) })
                        let randomSessionId: String = try! Identity.generate(from: contactData).x25519KeyPair.hexEncodedPublicKey
                        let contactNameLength: Int = ((5..<20).randomElement(using: &ogThreadRandomGenerator) ?? 0)
                        let contact = Legacy.Contact(sessionID: randomSessionId)
                        contact.name = (0..<contactNameLength)
                            .compactMap { _ in stringContent.randomElement(using: &ogThreadRandomGenerator) }
                            .joined()
                        transaction.setObject(contact, forKey: contact.sessionID, inCollection: Legacy.contactCollection)

                        members.append(randomSessionId)
                    }
                    
                    // Create the open group model and the thread
                    let openGroup: OpenGroupV2 = OpenGroupV2(server: serverName, room: roomName, name: roomName, publicKey: randomGroupPublicKey, imageID: nil)
                    let groupId: Data = LKGroupUtilities.getEncodedOpenGroupIDAsData(openGroup.id)
                    let model = TSGroupModel(title: openGroup.name, memberIds: members, image: nil, groupId: groupId, groupType: .openGroup, adminIds: [])
                    
                    let thread = TSGroupThread.getOrCreateThread(with: model, transaction: transaction)
                    thread.shouldBeVisible = true
                    thread.save(with: transaction)
                    
                    Storage.shared.setV2OpenGroup(openGroup, for: thread.uniqueId!, using: transaction)
                    
                    // Generate the message history (Note: Unapproved message requests will only include incoming messages)
                    logProgress("Open Group Thread \(threadIndex)", "Generate \(numMessages) Messages")

                    (0..<numMessages).forEach { index in
                        let messageWords: Int = ((1..<20).randomElement(using: &ogThreadRandomGenerator) ?? 0)
                        let message: VisibleMessage = VisibleMessage()
                        message.sender = (members.randomElement(using: &ogThreadRandomGenerator) ?? userSessionId)
                        message.sentTimestamp = UInt64(floor(timestampNow - Double(index * 5)) * 1000)
                        message.text = (0..<messageWords)
                            .compactMap { _ in wordContent.randomElement(using: &ogThreadRandomGenerator) }
                            .joined(separator: " ")

                        if message.sender != userSessionId {
                            let tsMessage: TSOutgoingMessage = TSOutgoingMessage.from(message, associatedWith: thread, using: transaction)
                            tsMessage.save(with: transaction)
                        }
                        else {
                            let tsMessage: TSIncomingMessage = TSIncomingMessage.from(message, quotedMessage: nil, linkPreview: nil, associatedWith: thread)
                            tsMessage.save(with: transaction)
                        }
                    }

                    logProgress("Open Group Thread \(threadIndex)", "Done")
                }
            }
            
            ogThreadIndex += chunkSize
        }
        
        logProgress("Open Group Threads", "Done")
        logProgress("", "Complete")
    }
}
