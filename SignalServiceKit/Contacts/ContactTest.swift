//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

final class ContactTest: XCTestCase {
    func testStableDecoding0() throws {
        let encodedValue = try XCTUnwrap(Data(base64Encoded: "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGvECALDCUmKjA5Ojs8PUFCQ0hJSktQVmhpamtscHR4goOEhVUkbnVsbNwNDg8QERITFBUWFxgZGhscGR4fICEiIyRbY25Db250YWN0SWRfEA9NVExNb2RlbFZlcnNpb25ZZmlyc3ROYW1lWGxhc3ROYW1lWHVuaXF1ZUlkXxAScGhvbmVOdW1iZXJOYW1lTWFwViRjbGFzc18QEnBhcnNlZFBob25lTnVtYmVyc18QFHVzZXJUZXh0UGhvbmVOdW1iZXJzWGZ1bGxOYW1lVmVtYWlsc1huaWNrbmFtZYAQgAKAC4AegBCABYAfgBGADYAdgAOADBAA0icTKClaTlMub2JqZWN0c6CABNIrLC0uWiRjbGFzc25hbWVYJGNsYXNzZXNXTlNBcnJheaItL1hOU09iamVjdNMxJxMyNThXTlMua2V5c6IzNIAGgAeiNjeACIAJgApcKzE3NjM1NTUwMTAxXCsxNzYzNTU1MDEwMFRXb3JrVk1vYmlsZdIrLD4/XE5TRGljdGlvbmFyeaJAL1xOU0RpY3Rpb25hcnlUSm9oblZKb2hubnnSJxNEKaJFRoAOgA+ABF4oNzYzKSA1NTUtMDEwMF4oNzYzKSA1NTUtMDEwMV8QLUNCQTZEMzJDLTVGQkUtNDU4My04QTRDLTQ4QjA1RDVFRTc0NzpBQlBlcnNvbtInE0wpok1OgBKAGoAE01ETUjRUVV8QIVJQRGVmYXVsdHNLZXlQaG9uZU51bWJlckNhbm9uaWNhbF8QHlJQRGVmYXVsdHNLZXlQaG9uZU51bWJlclN0cmluZ4AHgBmAE9kTV1hZWltcXV5fYGFiYGRgZmBfEBFjb3VudHJ5Q29kZVNvdXJjZV8QEml0YWxpYW5MZWFkaW5nWmVyb15uYXRpb25hbE51bWJlcl8QHHByZWZlcnJlZERvbWVzdGljQ2FycmllckNvZGVbY291bnRyeUNvZGVZZXh0ZW5zaW9uXxAUbnVtYmVyT2ZMZWFkaW5nWmVyb3NYcmF3SW5wdXSAGIAAgBaAFYAAgBSAAIAXgAAQARMAAAABxx0/lAgQAdIrLG1uXU5CUGhvbmVOdW1iZXKiby9dTkJQaG9uZU51bWJlctIrLHFyW1Bob25lTnVtYmVyonMvW1Bob25lTnVtYmVy01ETUjNUd4AGgBmAG9kTV1hZWltcXV5fYGF8YGRgZmCAGIAAgBaAHIAAgBSAAIAXgAATAAAAAccdP5VYSm9obiBEb2VTRG9l0isshodXQ29udGFjdKOGiC9YTVRMTW9kZWwACAARABoAJAApADIANwBJAEwAUQBTAHYAfACVAKEAswC9AMYAzwDkAOsBAAEXASABJwEwATIBNAE2ATgBOgE8AT4BQAFCAUQBRgFIAUoBTwFaAVsBXQFiAW0BdgF+AYEBigGRAZkBnAGeAaABowGlAacBqQG2AcMByAHPAdQB4QHkAfEB9gH9AgICBQIHAgkCCwIaAikCWQJeAmECYwJlAmcCbgKSArMCtQK3ArkCzALgAvUDBAMjAy8DOQNQA1kDWwNdA18DYQNjA2UDZwNpA2sDbQN2A3cDeQN+A4wDjwOdA6IDrgOxA70DxAPGA8gDygPdA98D4QPjA+UD5wPpA+sD7QPvA/gEAQQFBAoEEgQWAAAAAAAAAgEAAAAAAAAAiQAAAAAAAAAAAAAAAAAABB8="))

        let decodedContact = try NSKeyedUnarchiver.unarchivedObject(ofClass: Contact.self, from: encodedValue, requiringSecureCoding: false)
        XCTAssertEqual(decodedContact?.cnContactId, "CBA6D32C-5FBE-4583-8A4C-48B05D5EE747:ABPerson")
        XCTAssertEqual(decodedContact?.firstName, "John")
        XCTAssertEqual(decodedContact?.lastName, "Doe")
        XCTAssertEqual(decodedContact?.nickname, "Johnny")
        XCTAssertEqual(decodedContact?.fullName, "John Doe")
    }

    func testStableDecoding1() throws {
        let encodedValue = try XCTUnwrap(Data(base64Encoded: "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGoCwwZGhscHR5VJG51bGzWDQ4PEBESExQVFhcYWWZpcnN0TmFtZVhsYXN0TmFtZVhuaWNrbmFtZVhmdWxsTmFtZVtjbkNvbnRhY3RJZFYkY2xhc3OAA4AEgAaABYACgAdfEC1DQkE2RDMyQy01RkJFLTQ1ODMtOEE0Qy00OEIwNUQ1RUU3NDc6QUJQZXJzb25USm9oblNEb2VYSm9obiBEb2VWSm9obm550h8gISJaJGNsYXNzbmFtZVgkY2xhc3Nlc1dDb250YWN0oiEjWE5TT2JqZWN0AAgAEQAaACQAKQAyADcASQBMAFEAUwBcAGIAbwB5AIIAiwCUAKAApwCpAKsArQCvALEAswDjAOgA7AD1APwBAQEMARUBHQEgAAAAAAAAAgEAAAAAAAAAJAAAAAAAAAAAAAAAAAAAASk="))

        let decodedContact = try NSKeyedUnarchiver.unarchivedObject(ofClass: Contact.self, from: encodedValue, requiringSecureCoding: false)
        XCTAssertEqual(decodedContact?.cnContactId, "CBA6D32C-5FBE-4583-8A4C-48B05D5EE747:ABPerson")
        XCTAssertEqual(decodedContact?.firstName, "John")
        XCTAssertEqual(decodedContact?.lastName, "Doe")
        XCTAssertEqual(decodedContact?.nickname, "Johnny")
        XCTAssertEqual(decodedContact?.fullName, "John Doe")
    }
}
