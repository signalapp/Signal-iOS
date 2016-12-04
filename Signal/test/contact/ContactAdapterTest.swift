//  Created by Michael Kirk on 12/4/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

import XCTest

class ContactAdapterTest: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testFullNameWithABContact() {
        let image = UIImage()
        let phoneNumbers = ["555 444 1234", "323-123-1234"]
        let abContactId = ABRecordID(1234)
        let contactFromAB = Contact(firstName: "Emma", lastName: "Goldman", userTextPhoneNumbers: phoneNumbers, image: image, contactId: abContactId)

        let contactAdapter = ContactAdapter(contact: contactFromAB)
        XCTAssertEqual("Emma Goldman", contactAdapter.fullName)
    }

    @available(iOS 9.0, *)
    func testFullNameWithCNContact() {
        let cnContact = CNMutableContact()
        cnContact.givenName = "Emma"
        cnContact.familyName = "Goldman"

        let contactFromCn = Contact(contact: cnContact)

        let contactAdapter = ContactAdapter(contact: contactFromCn)
        XCTAssertEqual("Emma Goldman", contactAdapter.fullName)
    }

}
