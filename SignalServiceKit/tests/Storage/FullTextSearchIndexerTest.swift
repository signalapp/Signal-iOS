//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import LibSignalClient
@testable import SignalServiceKit

class FullTextSearchIndexerTest: SSKBaseTest {

    private var localIdentifiers: LocalIdentifiers!
    private var aliceThread: TSContactThread!
    private var bobThread: TSContactThread!
    private var groupThread: TSGroupThread!
    
    override func setUp() {
        super.setUp()
        
        localIdentifiers = LocalIdentifiers.forUnitTests
        
        write { transaction in
            // Set up registration state
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: localIdentifiers,
                tx: transaction
            )
            
            // Create Alice contact thread
            let aliceAci = Aci.randomForTesting()
            let alicePhoneNumber = "+12345550100"
            let aliceRecipient = DependenciesBridge.shared.recipientMerger.applyMergeFromContactDiscovery(
                localIdentifiers: localIdentifiers,
                phoneNumber: E164(alicePhoneNumber)!,
                pni: Pni.randomForTesting(),
                aci: aliceAci,
                tx: transaction
            )
            DependenciesBridge.shared.recipientManager.markAsRegisteredAndSave(
                aliceRecipient!,
                shouldUpdateStorageService: false,
                tx: transaction
            )
            aliceThread = TSContactThread.getOrCreateThread(
                withContactAddress: aliceRecipient!.address,
                transaction: transaction
            )
            
            // Create Bob contact thread
            let bobAci = Aci.randomForTesting()
            let bobPhoneNumber = "+12345550200"
            let bobRecipient = DependenciesBridge.shared.recipientMerger.applyMergeFromContactDiscovery(
                localIdentifiers: localIdentifiers,
                phoneNumber: E164(bobPhoneNumber)!,
                pni: Pni.randomForTesting(),
                aci: bobAci,
                tx: transaction
            )
            DependenciesBridge.shared.recipientManager.markAsRegisteredAndSave(
                bobRecipient!,
                shouldUpdateStorageService: false,
                tx: transaction
            )
            bobThread = TSContactThread.getOrCreateThread(
                withContactAddress: bobRecipient!.address,
                transaction: transaction
            )
            
            // Create group thread
            groupThread = try! GroupManager.createGroupForTests(
                members: [
                    aliceRecipient!.address,
                    bobRecipient!.address,
                    localIdentifiers.aciAddress
                ],
                shouldInsertInfoMessage: false,
                name: "Test Group",
                transaction: transaction
            )
        }
    }
    
    // MARK: - Test Global Search vs Thread-Specific Search
    
    func testSearchExhaustivenessInConversation() {
        
        write { transaction in
            // Create many messages in different threads containing "http"
            for i in 1...100 {
                let message = TSOutgoingMessage(
                    in: aliceThread,
                    messageBody: "This is message \(i) with http link"
                )
                message.anyInsert(transaction: transaction)
            }
            
            // Create messages in the same thread containing "https"
            for i in 1...50 {
                let message = TSOutgoingMessage(
                    in: aliceThread,
                    messageBody: "This is message \(i) with https secure link"
                )
                message.anyInsert(transaction: transaction)
            }
            
            // Create many messages in different threads to create noise
            for i in 1...600 {
                let thread = (i % 2 == 0) ? bobThread : groupThread
                let message = TSOutgoingMessage(
                    in: thread!,
                    messageBody: "This is noise message \(i) with http link"
                )
                message.anyInsert(transaction: transaction)
            }
        }
        
        read { transaction in
            // Test global search
            var httpResults: [TSMessage] = []
            var httpsResults: [TSMessage] = []
            
            FullTextSearchIndexer.search(
                for: "http",
                maxResults: 500,
                tx: transaction
            ) { message, _, _ in
                httpResults.append(message)
            }
            
            FullTextSearchIndexer.search(
                for: "https",
                maxResults: 500,
                tx: transaction
            ) { message, _, _ in
                httpsResults.append(message)
            }
            
            // Global search: "https" should return fewer results than "http" (as expected)
            XCTAssertGreaterThan(httpResults.count, httpsResults.count, "Global search: http should return more results than https")
            
            // Test thread-specific search
            var threadHttpResults: [TSMessage] = []
            var threadHttpsResults: [TSMessage] = []
            
            FullTextSearchIndexer.search(
                for: "http",
                maxResults: 500,
                threadUniqueId: aliceThread.uniqueId,
                tx: transaction
            ) { message, _, _ in
                threadHttpResults.append(message)
            }
            
            FullTextSearchIndexer.search(
                for: "https",
                maxResults: 500,
                threadUniqueId: aliceThread.uniqueId,
                tx: transaction
            ) { message, _, _ in
                threadHttpsResults.append(message)
            }
            
            // Thread-specific search: "http" should return more results than "https" 
            // because "http" appears in both "http" and "https" messages
            XCTAssertEqual(threadHttpResults.count, 150, "Thread search: should find all messages containing 'http' in Alice's thread")
            XCTAssertEqual(threadHttpsResults.count, 50, "Thread search: should find only 'https' messages in Alice's thread")
            XCTAssertGreaterThan(threadHttpResults.count, threadHttpsResults.count, "Thread search: http should return more results than https")
            
            // Verify all results are from the correct thread
            for message in threadHttpResults {
                XCTAssertEqual(message.uniqueThreadId, aliceThread.uniqueId, "All thread search results should be from Alice's thread")
            }
            
            for message in threadHttpsResults {
                XCTAssertEqual(message.uniqueThreadId, aliceThread.uniqueId, "All thread search results should be from Alice's thread")
            }
        }
    }
    
    func testSearchWithinSpecificConversation() {
        write { transaction in
            // Add messages to Alice's thread
            let aliceMessage1 = TSOutgoingMessage(in: aliceThread, messageBody: "Hello Alice, how are you?")
            let aliceMessage2 = TSOutgoingMessage(in: aliceThread, messageBody: "Alice, let's meet for coffee")
            let aliceMessage3 = TSOutgoingMessage(in: aliceThread, messageBody: "See you later!")
            
            // Add messages to Bob's thread
            let bobMessage1 = TSOutgoingMessage(in: bobThread, messageBody: "Hello Bob, nice to see you")
            let bobMessage2 = TSOutgoingMessage(in: bobThread, messageBody: "Bob, can you help me?")
            
            // Add messages to group thread
            let groupMessage1 = TSOutgoingMessage(in: groupThread, messageBody: "Hello everyone!")
            let groupMessage2 = TSOutgoingMessage(in: groupThread, messageBody: "Group meeting tomorrow")
            
            [aliceMessage1, aliceMessage2, aliceMessage3, bobMessage1, bobMessage2, groupMessage1, groupMessage2].forEach {
                $0.anyInsert(transaction: transaction)
            }
        }
        
        read { transaction in
            // Search for "Hello" in Alice's thread only
            var aliceResults: [TSMessage] = []
            FullTextSearchIndexer.search(
                for: "Hello",
                maxResults: 10,
                threadUniqueId: aliceThread.uniqueId,
                tx: transaction
            ) { message, _, _ in
                aliceResults.append(message)
            }
            
            XCTAssertEqual(aliceResults.count, 1, "Should find exactly 1 'Hello' message in Alice's thread")
            XCTAssertEqual(aliceResults.first?.uniqueThreadId, aliceThread.uniqueId)
            XCTAssertTrue(aliceResults.first?.body?.contains("Hello Alice") == true)
            
            // Search for "Hello" in Bob's thread only
            var bobResults: [TSMessage] = []
            FullTextSearchIndexer.search(
                for: "Hello",
                maxResults: 10,
                threadUniqueId: bobThread.uniqueId,
                tx: transaction
            ) { message, _, _ in
                bobResults.append(message)
            }
            
            XCTAssertEqual(bobResults.count, 1, "Should find exactly 1 'Hello' message in Bob's thread")
            XCTAssertEqual(bobResults.first?.uniqueThreadId, bobThread.uniqueId)
            XCTAssertTrue(bobResults.first?.body?.contains("Hello Bob") == true)
            
            // Global search for "Hello" should find both
            var globalResults: [TSMessage] = []
            FullTextSearchIndexer.search(
                for: "Hello",
                maxResults: 10,
                tx: transaction
            ) { message, _, _ in
                globalResults.append(message)
            }
            
            XCTAssertEqual(globalResults.count, 3, "Global search should find all 3 'Hello' messages")
        }
    }
    
    func testSearchWithNonExistentThread() {
        write { transaction in
            let message = TSOutgoingMessage(in: aliceThread, messageBody: "Test message for search")
            message.anyInsert(transaction: transaction)
        }
        
        read { transaction in
            var results: [TSMessage] = []
            FullTextSearchIndexer.search(
                for: "Test",
                maxResults: 10,
                threadUniqueId: "non-existent-thread-id",
                tx: transaction
            ) { message, _, _ in
                results.append(message)
            }
            
            XCTAssertEqual(results.count, 0, "Should find no results for non-existent thread")
        }
    }
    
    func testSearchPerformanceWithLargeDataset() {
        // Create a large dataset to test performance
        write { transaction in
            for i in 1...1000 {
                let thread = (i % 3 == 0) ? aliceThread : (i % 3 == 1) ? bobThread : groupThread
                let message = TSOutgoingMessage(
                    in: thread!,
                    messageBody: "Performance test message \(i) with searchable content"
                )
                message.anyInsert(transaction: transaction)
            }
        }
        
        read { transaction in
            let startTime = CFAbsoluteTimeGetCurrent()
            
            var results: [TSMessage] = []
            FullTextSearchIndexer.search(
                for: "searchable",
                maxResults: 500,  // Allow more results than search can find to test expected numbers
                threadUniqueId: aliceThread.uniqueId,
                tx: transaction
            ) { message, _, _ in
                results.append(message)
            }

            // Should return results in a reasonable time
            let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
            XCTAssertLessThan(timeElapsed, 1.0, "Search should complete within 1 second")
            
            // Should find the expected number of results (approximately 1/3 of messages)
            XCTAssertGreaterThan(results.count, 300, "Should find results from Alice's thread")
            XCTAssertLessThan(results.count, 400, "Should not find more results than expected")
            
            // Verify all results are from the correct thread
            for message in results {
                XCTAssertEqual(message.uniqueThreadId, aliceThread.uniqueId)
            }
        }
    }
    
    func testSearchSnippetGeneration() {
        write { transaction in
            let longMessage = TSOutgoingMessage(
                in: aliceThread,
                messageBody: "This is a very long message that contains many words and should generate a proper snippet when searching for specific terms like 'important' which appears in the middle of this lengthy text. The purpose of this extended message is to thoroughly test the full-text search functionality and ensure that snippets are generated correctly regardless of where the search term appears within the message content. We need to verify that both common terms like 'http' and more specific terms like 'https' are handled properly by the search indexer. This message also includes various types of content such as URLs like https://example.com and http://test.com, email addresses like user@example.com, and technical terms that might be searched for in a messaging application. The search functionality should be able to handle case-insensitive searches, partial word matches, and provide meaningful context around the matched terms. Additionally, we want to ensure that the search results are ranked appropriately and that the most relevant messages appear first in the search results. This comprehensive test message helps validate that our search improvements for conversation-specific queries work correctly and return exhaustive results as intended. The message continues with more content to make it sufficiently long for testing snippet generation with various search terms positioned at different locations throughout the text."
            )
            longMessage.anyInsert(transaction: transaction)
        }
        
        read { transaction in
            var foundSnippet: String?
            FullTextSearchIndexer.search(
                for: "important",
                maxResults: 1,
                threadUniqueId: aliceThread.uniqueId,
                tx: transaction
            ) { _, snippet, _ in
                foundSnippet = snippet
            }
            
            XCTAssertNotNil(foundSnippet, "Should generate a snippet")
            XCTAssertTrue(foundSnippet?.contains("important") == true, "Snippet should contain the search term")
            XCTAssertTrue(foundSnippet?.contains("…") == true, "Snippet should contain ellipsis for truncation")
        }
    }
    
    func testEmptySearchQuery() {
        write { transaction in
            let message = TSOutgoingMessage(in: aliceThread, messageBody: "Test message")
            message.anyInsert(transaction: transaction)
        }
        
        read { transaction in
            var results: [TSMessage] = []
            FullTextSearchIndexer.search(
                for: "",
                maxResults: 10,
                threadUniqueId: aliceThread.uniqueId,
                tx: transaction
            ) { message, _, _ in
                results.append(message)
            }
            
            XCTAssertEqual(results.count, 0, "Empty search query should return no results")
        }
    }
    
    func testMaxResultsLimit() {
        write { transaction in
            // Create more messages than maxResults limit
            for i in 1...20 {
                let message = TSOutgoingMessage(
                    in: aliceThread,
                    messageBody: "Message \(i) with keyword target"
                )
                message.anyInsert(transaction: transaction)
            }
        }
        
        read { transaction in
            var results: [TSMessage] = []
            FullTextSearchIndexer.search(
                for: "target",
                maxResults: 5,
                threadUniqueId: aliceThread.uniqueId,
                tx: transaction
            ) { message, _, _ in
                results.append(message)
            }
            
            XCTAssertEqual(results.count, 5, "Should respect maxResults limit")
        }
    }
}

// MARK: - Helper Extensions

private extension TSOutgoingMessage {
    convenience init(in thread: TSThread, messageBody: String) {
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(thread: thread, messageBody: messageBody)
        self.init(outgoingMessageWith: builder, recipientAddressStates: [:])
    }
}

