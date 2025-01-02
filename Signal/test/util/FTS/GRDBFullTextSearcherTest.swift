//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import LibSignalClient
import XCTest

@testable import Signal
@testable import SignalServiceKit
@testable import SignalUI

// MARK: -

class GRDBFullTextSearcherTest: SignalBaseTest {

    // MARK: - Dependencies

    var searcher: FullTextSearcher {
        FullTextSearcher.shared
    }

    // MARK: - Test Life Cycle

    private var bobRecipient: SignalRecipient!
    private var aliceRecipient: SignalRecipient!

    override func setUp() {
        super.setUp()

        let localIdentifiers: LocalIdentifiers = .forUnitTests

        SSKEnvironment.shared.setContactManagerForUnitTests(OWSContactsManager(
            appReadiness: AppReadinessMock(),
            nicknameManager: DependenciesBridge.shared.nicknameManager,
            recipientDatabaseTable: DependenciesBridge.shared.recipientDatabaseTable,
            usernameLookupManager: DependenciesBridge.shared.usernameLookupManager
        ))

        // ensure local client has necessary "registered" state
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: localIdentifiers,
                tx: tx.asV2Write
            )
        }

        let profileManager = SSKEnvironment.shared.profileManagerRef as! OWSFakeProfileManager

        self.write { transaction in
            let recipientManager = DependenciesBridge.shared.recipientManager

            let aliceAci = Aci.randomForTesting()
            let aliceProfile = makeUserProfile(for: aliceAci, givenName: "Alice", familyName: "Aliceson")
            aliceProfile.anyInsert(transaction: transaction)
            let alicePni = Pni.randomForTesting()
            let alicePhoneNumber = "+12345550100"
            self.aliceRecipient = DependenciesBridge.shared.recipientMerger.applyMergeFromContactDiscovery(
                localIdentifiers: localIdentifiers,
                phoneNumber: E164(alicePhoneNumber)!,
                pni: alicePni,
                aci: aliceAci,
                tx: transaction.asV2Write
            )
            recipientManager.markAsRegisteredAndSave(
                self.aliceRecipient!,
                shouldUpdateStorageService: false,
                tx: transaction.asV2Write
            )

            let bobAci = Aci.randomForTesting()
            let bobProfile = makeUserProfile(for: bobAci, givenName: "Bob", familyName: "Barker")
            bobProfile.anyInsert(transaction: transaction)
            let bobPni = Pni.randomForTesting()
            let bobPhoneNumber = "+4915123456789"
            self.bobRecipient = DependenciesBridge.shared.recipientMerger.applyMergeFromContactDiscovery(
                localIdentifiers: localIdentifiers,
                phoneNumber: E164(bobPhoneNumber)!,
                pni: bobPni,
                aci: bobAci,
                tx: transaction.asV2Write
            )
            recipientManager.markAsRegisteredAndSave(
                self.bobRecipient!,
                shouldUpdateStorageService: false,
                tx: transaction.asV2Write
            )

            profileManager.fakeUserProfiles = [
                self.aliceRecipient!.address: aliceProfile,
                self.bobRecipient!.address: bobProfile,
            ]

            let bookClubGroupThread = try! GroupManager.createGroupForTests(
                members: [self.aliceRecipient.address, self.bobRecipient.address, localIdentifiers.aciAddress],
                shouldInsertInfoMessage: true,
                name: "Book Club",
                transaction: transaction
            )
            self.bookClubThreadViewModel = ThreadViewModel(
                thread: bookClubGroupThread,
                forChatList: true,
                transaction: transaction
            )

            let snackClubGroupThread = try! GroupManager.createGroupForTests(
                members: [self.aliceRecipient.address, localIdentifiers.aciAddress],
                shouldInsertInfoMessage: true,
                name: "Snack Club",
                transaction: transaction
            )
            self.snackClubThreadViewModel = ThreadViewModel(
                thread: snackClubGroupThread,
                forChatList: true,
                transaction: transaction
            )

            let aliceContactThread = TSContactThread.getOrCreateThread(withContactAddress: self.aliceRecipient.address, transaction: transaction)
            self.aliceThreadViewModel = ThreadViewModel(
                thread: aliceContactThread,
                forChatList: true,
                transaction: transaction
            )

            let bobContactThread = TSContactThread.getOrCreateThread(withContactAddress: self.bobRecipient.address, transaction: transaction)
            self.bobEmptyThreadViewModel = ThreadViewModel(
                thread: bobContactThread,
                forChatList: true,
                transaction: transaction
            )

            let helloAlice = TSOutgoingMessage(in: aliceContactThread, messageBody: "Hello Alice")
            helloAlice.anyInsert(transaction: transaction)

            let goodbyeAlice = TSOutgoingMessage(in: aliceContactThread, messageBody: "Goodbye Alice")
            goodbyeAlice.anyInsert(transaction: transaction)

            let helloBookClub = TSOutgoingMessage(in: bookClubGroupThread, messageBody: "Hello Book Club")
            helloBookClub.anyInsert(transaction: transaction)

            let goodbyeBookClub = TSOutgoingMessage(in: bookClubGroupThread, messageBody: "Goodbye Book Club")
            goodbyeBookClub.anyInsert(transaction: transaction)

            let bobsPhoneNumber = TSOutgoingMessage(in: bookClubGroupThread, messageBody: "My phone number is: 234-555-0100")
            bobsPhoneNumber.anyInsert(transaction: transaction)

            let bobsFaxNumber = TSOutgoingMessage(in: bookClubGroupThread, messageBody: "My fax is: 234-555-0101")
            bobsFaxNumber.anyInsert(transaction: transaction)
        }
    }

    private func makeUserProfile(for aci: Aci, givenName: String, familyName: String) -> OWSUserProfile {
        return OWSUserProfile(
            id: nil,
            uniqueId: UUID().uuidString,
            serviceIdString: aci.serviceIdUppercaseString,
            phoneNumber: nil,
            avatarFileName: nil,
            avatarUrlPath: nil,
            profileKey: nil,
            givenName: givenName,
            familyName: familyName,
            bio: nil,
            bioEmoji: nil,
            badges: [],
            lastFetchDate: nil,
            lastMessagingDate: nil,
            isPhoneNumberShared: true
        )
    }

    // MARK: - Fixtures

    var bookClubThreadViewModel: ThreadViewModel!
    var snackClubThreadViewModel: ThreadViewModel!

    var aliceThreadViewModel: ThreadViewModel!
    var bobEmptyThreadViewModel: ThreadViewModel!

    // MARK: Tests

    private func AssertEqualThreadLists(_ left: [ThreadViewModel], _ right: [ThreadViewModel], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(left.count, right.count, file: file, line: line)
        guard left.count != right.count else {
            return
        }
        // Only bother comparing uniqueIds.
        let leftIds = left.map { $0.threadRecord.uniqueId }
        let rightIds = right.map { $0.threadRecord.uniqueId }
        XCTAssertEqual(leftIds, rightIds, file: file, line: line)
    }

    func testSearchByGroupName() {
        var threadViewModels: [ThreadViewModel] = []

        // No Match
        threadViewModels = searchConversations(searchText: "asdasdasd")
        XCTAssert(threadViewModels.isEmpty)

        // Partial Match
        threadViewModels = searchConversations(searchText: "Book")
        XCTAssertEqual(1, threadViewModels.count)
        AssertEqualThreadLists([bookClubThreadViewModel], threadViewModels)

        threadViewModels = searchConversations(searchText: "Snack")
        XCTAssertEqual(1, threadViewModels.count)
        AssertEqualThreadLists([snackClubThreadViewModel], threadViewModels)

        // Multiple Partial Matches
        threadViewModels = searchConversations(searchText: "Club")
        XCTAssertEqual(2, threadViewModels.count)
        AssertEqualThreadLists([bookClubThreadViewModel, snackClubThreadViewModel], threadViewModels)

        // Match Name Exactly
        threadViewModels = searchConversations(searchText: "Book Club")
        XCTAssertEqual(1, threadViewModels.count)
        AssertEqualThreadLists([bookClubThreadViewModel], threadViewModels)
    }

    func testSearchContactByNumber() {
        var threadViewModels: [ThreadViewModel] = []

        // No match
        threadViewModels = searchConversations(searchText: "+16505550150")
        XCTAssertEqual(0, threadViewModels.count)

        // Exact match
        threadViewModels = searchConversations(searchText: aliceRecipient.address.phoneNumber!)
        XCTAssertEqual(3, threadViewModels.count)
        AssertEqualThreadLists([bookClubThreadViewModel, aliceThreadViewModel, snackClubThreadViewModel], threadViewModels)

        // Partial match
        threadViewModels = searchConversations(searchText: "+123455")
        XCTAssertEqual(3, threadViewModels.count)
        AssertEqualThreadLists([bookClubThreadViewModel, aliceThreadViewModel, snackClubThreadViewModel], threadViewModels)

        // Prefixes
        threadViewModels = searchConversations(searchText: "12345550100")
        XCTAssertEqual(3, threadViewModels.count)
        AssertEqualThreadLists([bookClubThreadViewModel, aliceThreadViewModel, snackClubThreadViewModel], threadViewModels)

        threadViewModels = searchConversations(searchText: "49")
        XCTAssertEqual(1, threadViewModels.count)
        AssertEqualThreadLists([bookClubThreadViewModel], threadViewModels)

        threadViewModels = searchConversations(searchText: "1-234-55")
        XCTAssertEqual(3, threadViewModels.count)
        AssertEqualThreadLists([bookClubThreadViewModel, aliceThreadViewModel, snackClubThreadViewModel], threadViewModels)

        threadViewModels = searchConversations(searchText: "123455")
        XCTAssertEqual(3, threadViewModels.count)
        AssertEqualThreadLists([bookClubThreadViewModel, aliceThreadViewModel, snackClubThreadViewModel], threadViewModels)

        threadViewModels = searchConversations(searchText: "1.234.55")
        XCTAssertEqual(3, threadViewModels.count)
        AssertEqualThreadLists([bookClubThreadViewModel, aliceThreadViewModel, snackClubThreadViewModel], threadViewModels)

        threadViewModels = searchConversations(searchText: "1 234 55")
        XCTAssertEqual(3, threadViewModels.count)
        AssertEqualThreadLists([bookClubThreadViewModel, aliceThreadViewModel, snackClubThreadViewModel], threadViewModels)

        // Phone Number formatting should be forgiving
        threadViewModels = searchConversations(searchText: "234.55")
        XCTAssertEqual(3, threadViewModels.count)
        AssertEqualThreadLists([bookClubThreadViewModel, aliceThreadViewModel, snackClubThreadViewModel], threadViewModels)

        threadViewModels = searchConversations(searchText: "234 55")
        XCTAssertEqual(3, threadViewModels.count)
        AssertEqualThreadLists([bookClubThreadViewModel, aliceThreadViewModel, snackClubThreadViewModel], threadViewModels)
    }

    func testSearchConversationByContactByName() {
        var threadViewModels: [ThreadViewModel] = []

        threadViewModels = searchConversations(searchText: "Alice")
        XCTAssertEqual(3, threadViewModels.count)
        AssertEqualThreadLists([bookClubThreadViewModel, aliceThreadViewModel, snackClubThreadViewModel], threadViewModels)

        threadViewModels = searchConversations(searchText: "Bob")
        XCTAssertEqual(1, threadViewModels.count)
        AssertEqualThreadLists([bookClubThreadViewModel], threadViewModels)

        threadViewModels = searchConversations(searchText: "Barker")
        XCTAssertEqual(1, threadViewModels.count)
        AssertEqualThreadLists([bookClubThreadViewModel], threadViewModels)

        threadViewModels = searchConversations(searchText: "Bob B")
        XCTAssertEqual(1, threadViewModels.count)
        AssertEqualThreadLists([bookClubThreadViewModel], threadViewModels)
    }

    func testSearchMessageByBodyContent() {
        var resultSet: HomeScreenSearchResultSet = .empty

        resultSet = getResultSet(searchText: "Hello Alice")
        XCTAssertEqual(1, resultSet.messageResults.count)
        AssertEqualThreadLists([aliceThreadViewModel], resultSet.messageResults.map { $0.threadViewModel })

        resultSet = getResultSet(searchText: "Hello")
        XCTAssertEqual(2, resultSet.messageResults.count)
        AssertEqualThreadLists([aliceThreadViewModel, bookClubThreadViewModel], resultSet.messageResults.map { $0.threadViewModel })
    }

    func testSearchEdgeCases() {
        var resultSet: HomeScreenSearchResultSet = .empty

        resultSet = getResultSet(searchText: "Hello Alice")
        XCTAssertEqual(1, resultSet.messageResults.count)
        XCTAssertEqual(["Hello Alice"], bodies(forMessageResults: resultSet.messageResults))

        resultSet = getResultSet(searchText: "hello alice")
        XCTAssertEqual(1, resultSet.messageResults.count)
        XCTAssertEqual(["Hello Alice"], bodies(forMessageResults: resultSet.messageResults))

        resultSet = getResultSet(searchText: "Hel")
        XCTAssertEqual(2, resultSet.messageResults.count)
        XCTAssertEqual(["Hello Alice", "Hello Book Club"], bodies(forMessageResults: resultSet.messageResults))

        resultSet = getResultSet(searchText: "Hel Ali")
        XCTAssertEqual(1, resultSet.messageResults.count)
        XCTAssertEqual(["Hello Alice"], bodies(forMessageResults: resultSet.messageResults))

        resultSet = getResultSet(searchText: "Hel Ali Alic")
        XCTAssertEqual(1, resultSet.messageResults.count)
        XCTAssertEqual(["Hello Alice"], bodies(forMessageResults: resultSet.messageResults))

        resultSet = getResultSet(searchText: "Ali Hel")
        XCTAssertEqual(1, resultSet.messageResults.count)
        XCTAssertEqual(["Hello Alice"], bodies(forMessageResults: resultSet.messageResults))

        resultSet = getResultSet(searchText: "CLU")
        XCTAssertEqual(2, resultSet.messageResults.count)
        XCTAssertEqual(["Goodbye Book Club", "Hello Book Club"], bodies(forMessageResults: resultSet.messageResults))

        resultSet = getResultSet(searchText: "hello !@##!@#!$^@!@#! alice")
        XCTAssertEqual(1, resultSet.messageResults.count)
        XCTAssertEqual(["Hello Alice"], bodies(forMessageResults: resultSet.messageResults))

        resultSet = getResultSet(searchText: "2345 phone")
        XCTAssertEqual(1, resultSet.messageResults.count)
        XCTAssertEqual(["My phone number is: 234-555-0100"], bodies(forMessageResults: resultSet.messageResults))

        resultSet = getResultSet(searchText: "PHO 2345")
        XCTAssertEqual(1, resultSet.messageResults.count)
        XCTAssertEqual(["My phone number is: 234-555-0100"], bodies(forMessageResults: resultSet.messageResults))

        resultSet = getResultSet(searchText: "fax")
        XCTAssertEqual(1, resultSet.messageResults.count)
        XCTAssertEqual(["My fax is: 234-555-0101"], bodies(forMessageResults: resultSet.messageResults))

        resultSet = getResultSet(searchText: "fax 2345")
        XCTAssertEqual(1, resultSet.messageResults.count)
        XCTAssertEqual(["My fax is: 234-555-0101"], bodies(forMessageResults: resultSet.messageResults))
    }

    // MARK: - More Tests

    func testModelLifecycle1() {

        var thread: TSGroupThread! = nil
        self.write { transaction in
            thread = try! GroupManager.createGroupForTests(
                members: [self.aliceRecipient.address, self.bobRecipient.address, DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)!.aciAddress],
                shouldInsertInfoMessage: true,
                name: "Lifecycle",
                transaction: transaction
            )
        }

        let message1 = TSOutgoingMessage(in: thread, messageBody: "This world contains glory and despair.")
        let message2 = TSOutgoingMessage(in: thread, messageBody: "This world contains hope and despair.")

        XCTAssertEqual(0, getResultSet(searchText: "GLORY").messageResults.count)
        XCTAssertEqual(0, getResultSet(searchText: "HOPE").messageResults.count)
        XCTAssertEqual(0, getResultSet(searchText: "DESPAIR").messageResults.count)
        XCTAssertEqual(0, getResultSet(searchText: "DEFEAT").messageResults.count)

        self.write { transaction in
            message1.anyInsert(transaction: transaction)
            message2.anyInsert(transaction: transaction)
        }

        XCTAssertEqual(1, getResultSet(searchText: "GLORY").messageResults.count)
        XCTAssertEqual(1, getResultSet(searchText: "HOPE").messageResults.count)
        XCTAssertEqual(2, getResultSet(searchText: "DESPAIR").messageResults.count)
        XCTAssertEqual(0, getResultSet(searchText: "DEFEAT").messageResults.count)

        self.write { transaction in
            message1.update(withMessageBody: "This world contains glory and defeat.", transaction: transaction)
        }

        XCTAssertEqual(1, getResultSet(searchText: "GLORY").messageResults.count)
        XCTAssertEqual(1, getResultSet(searchText: "HOPE").messageResults.count)
        XCTAssertEqual(1, getResultSet(searchText: "DESPAIR").messageResults.count)
        XCTAssertEqual(1, getResultSet(searchText: "DEFEAT").messageResults.count)

        self.write { transaction in
            DependenciesBridge.shared.interactionDeleteManager.delete(message1, sideEffects: .default(), tx: transaction.asV2Write)
        }

        XCTAssertEqual(0, getResultSet(searchText: "GLORY").messageResults.count)
        XCTAssertEqual(1, getResultSet(searchText: "HOPE").messageResults.count)
        XCTAssertEqual(1, getResultSet(searchText: "DESPAIR").messageResults.count)
        XCTAssertEqual(0, getResultSet(searchText: "DEFEAT").messageResults.count)

        self.write { transaction in
            DependenciesBridge.shared.interactionDeleteManager.delete(message2, sideEffects: .default(), tx: transaction.asV2Write)
        }

        XCTAssertEqual(0, getResultSet(searchText: "GLORY").messageResults.count)
        XCTAssertEqual(0, getResultSet(searchText: "HOPE").messageResults.count)
        XCTAssertEqual(0, getResultSet(searchText: "DESPAIR").messageResults.count)
        XCTAssertEqual(0, getResultSet(searchText: "DEFEAT").messageResults.count)
    }

    func testModelLifecycle2() {

        var message1: TSOutgoingMessage!
        var message2: TSOutgoingMessage!
        self.write { transaction in
            let thread = try! GroupManager.createGroupForTests(
                members: [self.aliceRecipient.address, self.bobRecipient.address, DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)!.aciAddress],
                shouldInsertInfoMessage: true,
                name: "Lifecycle",
                transaction: transaction
            )

            message1 = TSOutgoingMessage(in: thread, messageBody: "This world contains glory and despair.")
            message2 = TSOutgoingMessage(in: thread, messageBody: "This world contains hope and despair.")

            message1.anyInsert(transaction: transaction)
            message2.anyInsert(transaction: transaction)
        }

        XCTAssertEqual(1, getResultSet(searchText: "GLORY").messageResults.count)
        XCTAssertEqual(1, getResultSet(searchText: "HOPE").messageResults.count)
        XCTAssertEqual(2, getResultSet(searchText: "DESPAIR").messageResults.count)
        XCTAssertEqual(0, getResultSet(searchText: "DEFEAT").messageResults.count)

        self.write { transaction in
            DependenciesBridge.shared.interactionDeleteManager
                .delete(interactions: [message1, message2], sideEffects: .default(), tx: transaction.asV2Write)
        }

        XCTAssertEqual(0, getResultSet(searchText: "GLORY").messageResults.count)
        XCTAssertEqual(0, getResultSet(searchText: "HOPE").messageResults.count)
        XCTAssertEqual(0, getResultSet(searchText: "DESPAIR").messageResults.count)
        XCTAssertEqual(0, getResultSet(searchText: "DEFEAT").messageResults.count)
    }

    func testDiacritics() {

        self.write { transaction in
            let thread = try! GroupManager.createGroupForTests(
                members: [self.aliceRecipient.address, self.bobRecipient.address, DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)!.aciAddress],
                shouldInsertInfoMessage: true,
                name: "Lifecycle",
                transaction: transaction
            )

            TSOutgoingMessage(in: thread, messageBody: "NOËL and SØRINA and ADRIÁN and FRANÇOIS and NUÑEZ and Björk.").anyInsert(transaction: transaction)
        }

        XCTAssertEqual(1, getResultSet(searchText: "NOËL").messageResults.count)
        XCTAssertEqual(1, getResultSet(searchText: "noel").messageResults.count)
        XCTAssertEqual(1, getResultSet(searchText: "SØRINA").messageResults.count)
        // I guess Ø isn't a diacritical mark but a separate letter.
        XCTAssertEqual(0, getResultSet(searchText: "sorina").messageResults.count)
        XCTAssertEqual(1, getResultSet(searchText: "ADRIÁN").messageResults.count)
        XCTAssertEqual(1, getResultSet(searchText: "adrian").messageResults.count)
        XCTAssertEqual(1, getResultSet(searchText: "FRANÇOIS").messageResults.count)
        XCTAssertEqual(1, getResultSet(searchText: "francois").messageResults.count)
        XCTAssertEqual(1, getResultSet(searchText: "NUÑEZ").messageResults.count)
        XCTAssertEqual(1, getResultSet(searchText: "nunez").messageResults.count)
        XCTAssertEqual(1, getResultSet(searchText: "Björk").messageResults.count)
        XCTAssertEqual(1, getResultSet(searchText: "Bjork").messageResults.count)
    }

    private func AssertValidResultSet(query: String, expectedResultCount: Int, file: StaticString = #filePath, line: UInt = #line) {
        // For these simple test cases, the snippet should contain the entire query.
        let expectedSnippetContent: String = query

        let resultSet = getResultSet(searchText: query)
        XCTAssertEqual(expectedResultCount, resultSet.messageResults.count, file: file, line: line)
        for result in resultSet.messageResults {
            guard let snippet = result.snippet else {
                XCTFail("Missing snippet.", file: file, line: line)
                continue
            }
            let snippetString: String
            switch snippet {
            case .text(let string):
                snippetString = string
            case .attributedText(let nSAttributedString):
                snippetString = nSAttributedString.string
            case .messageBody(let hydratedMessageBody):
                snippetString = hydratedMessageBody.asPlaintext()
            }
            XCTAssertTrue(snippetString.lowercased().contains(expectedSnippetContent.lowercased()), file: file, line: line)
        }
    }

    func testSnippets() {

        var thread: TSGroupThread! = nil
        self.write { transaction in
            thread = try! GroupManager.createGroupForTests(
                members: [self.aliceRecipient.address, self.bobRecipient.address, DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)!.aciAddress],
                shouldInsertInfoMessage: true,
                name: "Lifecycle",
                transaction: transaction
            )
        }

        let message1 = TSOutgoingMessage(in: thread, messageBody: "This world contains glory and despair.")
        let message2 = TSOutgoingMessage(in: thread, messageBody: "This world contains hope and despair.")

        AssertValidResultSet(query: "GLORY", expectedResultCount: 0)
        AssertValidResultSet(query: "HOPE", expectedResultCount: 0)
        AssertValidResultSet(query: "DESPAIR", expectedResultCount: 0)
        AssertValidResultSet(query: "DEFEAT", expectedResultCount: 0)

        self.write { transaction in
            message1.anyInsert(transaction: transaction)
            message2.anyInsert(transaction: transaction)
        }

        AssertValidResultSet(query: "GLORY", expectedResultCount: 1)
        AssertValidResultSet(query: "HOPE", expectedResultCount: 1)
        AssertValidResultSet(query: "DESPAIR", expectedResultCount: 2)
        AssertValidResultSet(query: "DEFEAT", expectedResultCount: 0)
    }

    // MARK: - Perf

    func testPerf() {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx.asV2Write
            )
        }

        let string1 = "krazy"
        let string2 = "kat"
        let messageCount: UInt = 100

        Bench(title: "Populate Index", memorySamplerRatio: 1) { _ in
            self.write { transaction in
                let thread = try! GroupManager.createGroupForTests(
                    members: [self.aliceRecipient.address, self.bobRecipient.address, DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)!.aciAddress],
                    shouldInsertInfoMessage: true,
                    name: "Perf",
                    transaction: transaction
                )

                TSOutgoingMessage(in: thread, messageBody: string1).anyInsert(transaction: transaction)

                for _ in 0...messageCount {
                    let message = TSOutgoingMessage(in: thread, messageBody: UUID().uuidString)
                    message.anyInsert(transaction: transaction)
                    message.update(withMessageBody: UUID().uuidString, transaction: transaction)
                }

                TSOutgoingMessage(in: thread, messageBody: string2).anyInsert(transaction: transaction)
            }
        }

        Bench(title: "Search", memorySamplerRatio: 1) { _ in
            self.read { transaction in
                let getMatchCount = { (searchText: String) -> UInt in
                    var count: UInt = 0
                    FullTextSearchIndexer.search(
                        for: searchText,
                        maxResults: 500,
                        tx: transaction
                    ) { (match, snippet, _) in
                        count += 1
                    }
                    return count
                }
                XCTAssertEqual(1, getMatchCount(string1))
                XCTAssertEqual(1, getMatchCount(string2))
                XCTAssertEqual(0, getMatchCount(UUID().uuidString))
            }
        }
    }

    // MARK: - Helpers

    func bodies<T>(forMessageResults messageResults: [ConversationSearchResult<T>]) -> [String] {
        var result = [String]()

        self.read { transaction in
            for messageResult in messageResults {
                guard let messageId = messageResult.messageId else {
                    owsFailDebug("message result missing message id")
                    continue
                }
                guard let interaction = TSInteraction.anyFetch(uniqueId: messageId, transaction: transaction) else {
                    owsFailDebug("couldn't load interaction for message result")
                    continue
                }
                guard let message = interaction as? TSMessage else {
                    owsFailDebug("invalid message for message result")
                    continue
                }
                guard let messageBody = message.body else {
                    owsFailDebug("message result missing message body")
                    continue
                }
                result.append(messageBody)
            }
        }

        return result.sorted()
    }

    private func searchConversations(searchText: String) -> [ThreadViewModel] {
        let results = getResultSet(searchText: searchText)
        let contactThreadViewModels = results.contactThreadResults.map { $0.threadViewModel }
        let groupThreadViewModels = results.groupThreadResults.map { $0.threadViewModel }
        return contactThreadViewModels + groupThreadViewModels
    }

    private func getResultSet(searchText: String) -> HomeScreenSearchResultSet {
        self.read { transaction in
            self.searcher.searchForHomeScreen(
                searchText: searchText,
                isCanceled: { false },
                transaction: transaction
            )!
        }
    }
}

// MARK: -

private extension TSOutgoingMessage {
    convenience init(in thread: TSThread, messageBody: String) {
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(thread: thread, messageBody: messageBody)
        self.init(outgoingMessageWith: builder, recipientAddressStates: [:])
    }
}
