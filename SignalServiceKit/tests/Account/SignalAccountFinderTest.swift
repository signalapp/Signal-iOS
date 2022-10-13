//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

class SignalAccountFinderTest: SSKBaseTestSwift {
    private lazy var localAddress = CommonGenerator.address()

    override func setUp() {
        super.setUp()
        // Create local account.
        tsAccountManager.registerForTests(withLocalNumber: localAddress.phoneNumber!,
                                          uuid: localAddress.uuid!)
    }

    private func createRecipientsAndAccounts(_ addresses: [SignalServiceAddress]) -> [SignalAccount] {
        let accounts = addresses.map { SignalAccount(address: $0) }
        // Create recipients and accounts.
        write { transaction in
            for address in addresses {
                SignalRecipient.mark(asRegisteredAndGet: address, trustLevel: .high, transaction: transaction)
            }
            for account in accounts {
                account.anyInsert(transaction: transaction)
            }
        }
        return accounts
    }

    func testReadManyValues() {
        let addresses = [SignalServiceAddress(phoneNumber: "+17035559901"),
                         SignalServiceAddress(phoneNumber: "+17035559902"),
                         SignalServiceAddress(uuid: UUID()),
                         SignalServiceAddress(uuid: UUID())]
        let accounts = createRecipientsAndAccounts(addresses)

        read { transaction in
            let accountFinder = AnySignalAccountFinder()
            let actual = accountFinder.signalAccounts(for: addresses, transaction: transaction)
            XCTAssertEqual(actual.map { $0?.recipientAddress },
                           accounts.map { $0.recipientAddress })
        }
    }

    func testReadPhoneNumbersAndBogus() {
        let addresses = [SignalServiceAddress(phoneNumber: "+17035559901"),
                         SignalServiceAddress(phoneNumber: "+17035550000")]
        let accounts = createRecipientsAndAccounts(addresses)

        read { transaction in
            let accountFinder = AnySignalAccountFinder()
            let bogus = [SignalServiceAddress(uuid: UUID())]
            let actual = accountFinder.signalAccounts(for: addresses + bogus, transaction: transaction)
            XCTAssertEqual(actual.map { $0?.recipientAddress },
                           accounts.map { $0.recipientAddress } + [ nil ])
        }
    }

    func testMixOfRealAndBogusAddresses() {
        let addresses = [SignalServiceAddress(phoneNumber: "+17035559901"),
                         SignalServiceAddress(phoneNumber: "+17035550000")]  // no account for this one
        let accounts = createRecipientsAndAccounts([addresses[0]])

        read { transaction in
            let accountFinder = AnySignalAccountFinder()
            let actual = accountFinder.signalAccounts(for: addresses, transaction: transaction)
            XCTAssertEqual(actual.map { $0?.recipientAddress },
                           accounts.map { $0.recipientAddress } + [ nil ])
        }
    }

    func testTwoAccountsWithSamePhoneNumber() {
        let addresses = [SignalServiceAddress(phoneNumber: "+17035559901"),
                         SignalServiceAddress(phoneNumber: "+17035559901")]
        let accounts = createRecipientsAndAccounts(addresses)

        read { transaction in
            let accountFinder = AnySignalAccountFinder()
            let actual = accountFinder.signalAccounts(for: addresses, transaction: transaction)
            XCTAssertEqual(actual.map { $0?.recipientAddress },
                           accounts.map { $0.recipientAddress })
        }
    }

    func testTwoAccountsWithSameUUID() {
        let uuid = UUID()
        let addresses = [SignalServiceAddress(uuid: uuid),
                         SignalServiceAddress(uuid: uuid)]
        let accounts = createRecipientsAndAccounts(addresses)

        read { transaction in
            let accountFinder = AnySignalAccountFinder()
            let actual = accountFinder.signalAccounts(for: addresses, transaction: transaction)
            XCTAssertEqual(actual.map { $0?.recipientAddress },
                           accounts.map { $0.recipientAddress })
        }
    }
}
