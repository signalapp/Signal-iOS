//
//  SignalUITests.swift
//  SignalUITests
//
//  Created by Matthew Kotila on 1/13/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.
//

import XCTest

class SignalUITests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIApplication().launch()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    // requires unverified app
    func testCountryCodeSelectionScreenNavigation() {
        
        let app = XCUIApplication()
        app.buttons["Country Code"].tap()
        
        XCTAssert(app.staticTexts["Select Country Code"].exists)
        
    }
    
    // requires unverified app
    func testCountryCodeSelectionScreenBackNavigation() {
        
        let app = XCUIApplication()
        app.buttons["Country Code"].tap()
        app.navigationBars["Select Country Code"].buttons["btnCancel  white"].tap()
        
        XCTAssert(app.staticTexts["Your Phone Number"].exists)
        
    }
    
    // requires unverified app
    func testCountryCodeSelectionScreenSearch() {
        
        let app = XCUIApplication()
        app.buttons["Country Code"].tap()
        let searchField = app.tables.childrenMatchingType(.SearchField).element
        searchField.tap()
        searchField.typeText("Fran")
        
        XCTAssert(app.staticTexts["France"].exists)
        
    }
    
    // requires unverified app
    func testCountryCodeSelectionScreenStandardSelect() {
        
        let app = XCUIApplication()
        app.buttons["Country Code"].tap()
        app.tables.staticTexts["France"].tap()
        
        XCTAssert(app.buttons["France"].exists)
        XCTAssert(app.buttons["+33"].exists)
        
    }
    
    // requires unverified app
    func testCountryCodeSelectionScreenSearchSelect() {
        
        let app = XCUIApplication()
        app.buttons["Country Code"].tap()
        let searchField = app.tables.childrenMatchingType(.SearchField).element
        searchField.tap()
        searchField.typeText("Fran")
        app.tables.staticTexts["France"].tap()
        
        XCTAssert(app.buttons["France"].exists)
        XCTAssert(app.buttons["+33"].exists)
        
    }
    
    // requires unverified app
    func testVerifyUnsupportedPhoneNumberAlert() {
        
        let app = XCUIApplication()
        app.buttons["Verify This Device"].tap()
        
        XCTAssert(app.alerts["Registration Error"].exists)
        
    }
    
    // requires unverified app
    func testVerifySupportedPhoneNumberChangeNumberNavigation() {
        
        let app = XCUIApplication()
        app.textFields["Enter Number"].typeText("5555555555")
        app.buttons["Verify This Device"].tap()
        app.buttons["     Change Number"].tap()
        
        XCTAssert(app.staticTexts["Your Phone Number"].exists)
        
    }
    
    // requires verified app
    func testSettingsNavigation() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["settings"].tap()
        
        XCTAssert(app.staticTexts["Settings"].exists)
        
        app.navigationBars["Settings"].buttons["Done"].tap()
        
        XCTAssert(app.buttons["Inbox"].exists)
        
    }
    
    // requires verified app
    func testSettingsPrivacyNavigation() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["settings"].tap()
        app.tables.staticTexts["Privacy"].tap()
        
        XCTAssert(app.navigationBars["Privacy"].exists)
        
    }
    
    // requires verified app
    func testSettingsPrivacyClearHistoryLogAlert() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["settings"].tap()
        let tablesQuery = app.tables
        tablesQuery.staticTexts["Privacy"].tap()
        tablesQuery.staticTexts["Clear History Logs"].tap()
        
        
        XCTAssert(app.staticTexts["Are you sure you want to delete all your history (messages, attachments, call history ...) ? This action cannot be reverted."].exists)
        
    }
    
    // requires verified app
    func testSettingsNotificationsNavigation() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["settings"].tap()
        app.tables.staticTexts["Notifications"].tap()
        
        XCTAssert(app.navigationBars["Notifications"].exists)
        
    }
    
    // requires verified app
    func testSettingsNotificationsOptionsNavigation() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["settings"].tap()
        app.tables.staticTexts["Notifications"].tap()
        app.tables.staticTexts["Show"].tap()
        
        XCTAssert(app.navigationBars["NotificationSettingsOptionsView"].exists)
        
    }
    
    // requires verified app
    func testSettingsAdvancedNavigation() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["settings"].tap()
        app.tables.staticTexts["Advanced"].tap()
        
        XCTAssert(app.navigationBars["Advanced"].exists)
        
    }
    
    // requires verified app
    func testSettingsAboutNavigation() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["settings"].tap()
        app.tables.staticTexts["About"].tap()
        
        XCTAssert(app.navigationBars["About"].exists)
        
    }
    
    // requires verified app
    func testSettingsDeleteAccountAlert() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["settings"].tap()
        app.tables.buttons["Delete Account"].tap()
        
        XCTAssert(app.alerts["Are you sure you want to delete your account?"].exists)
        
    }
    
    // requires verified app
    func testComposeNewMessageNavigation() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        
        XCTAssert(app.navigationBars["New Message"].exists)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testComposeMessageSelectNavigation() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.tables.staticTexts["Test"].tap()
        
        XCTAssert(app.navigationBars["Test"].exists)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testComposeMessageSend() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.tables.staticTexts["Test"].tap()
        
        app.textViews.elementBoundByIndex(app.textViews.count - 1).tap()
        app.textViews.elementBoundByIndex(app.textViews.count - 1).typeText("1")
        app.toolbars.buttons["Send"].tap()
        
        XCTAssert(app.textViews["1"].exists)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testComposeMessageSendImage() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.tables.staticTexts["Test"].tap()
        let oldImagesCount = app.images.count
        app.toolbars.buttons["btnAttachments  blue"].tap()
        app.buttons["Choose from Library..."].tap()
        app.buttons["Camera Roll"].tap()
        app.cells.elementBoundByIndex(0).tap()
        
        XCTAssert(app.images.count > oldImagesCount)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testComposeMessageSendImageOptions() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.tables.staticTexts["Test"].tap()
        app.toolbars.buttons["btnAttachments  blue"].tap()
        app.buttons["Choose from Library..."].tap()
        app.buttons["Camera Roll"].tap()
        app.cells.elementBoundByIndex(0).tap()
        app.collectionViews.cells.otherElements.childrenMatchingType(.Other).elementBoundByIndex(0).childrenMatchingType(.Image).element.tap()
        app.buttons["savephoto"].tap()
        sleep(1)
        
        XCTAssert(app.buttons["Save to Camera Roll"].exists)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testComposeMessageSendVideo() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.tables.staticTexts["Test"].tap()
        let oldImagesCount = app.images.count
        app.toolbars.buttons["btnAttachments  blue"].tap()
        app.buttons["Choose from Library..."].tap()
        app.buttons["Videos"].tap()
        app.cells.elementBoundByIndex(0).tap()
        app.buttons["Choose"].tap()
        sleep(2)
        
        XCTAssert(app.images.count > oldImagesCount)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testComposeMessageSelectSendConversationsTimestamp() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.tables.staticTexts["Test"].tap()
        
        app.textViews.elementBoundByIndex(app.textViews.count - 1).tap()
        app.textViews.elementBoundByIndex(app.textViews.count - 1).typeText("1")
        app.toolbars.buttons["Send"].tap()
        
        let dateFormatter = NSDateFormatter.init()
        dateFormatter.dateStyle = .NoStyle
        dateFormatter.timeStyle = .ShortStyle
        let timestamp = dateFormatter.stringFromDate(NSDate.init())
        
        app.buttons.elementBoundByIndex(0).tap()
        
        XCTAssert(app.tables.staticTexts[timestamp].exists)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testComposeMessageSelectDisplayContactPhoneNumber() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.tables.staticTexts["Test"].tap()
        
        app.navigationBars.staticTexts["Test"].tap()
        
        XCTAssert(app.navigationBars.staticTexts["+x xxx-xxx-xxxx"].exists)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testComposeMessageAttachmentAlert() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.tables.staticTexts["Test"].tap()
        sleep(2)
        app.toolbars.buttons["btnAttachments  blue"].tap()
        
        print(XCUIApplication().debugDescription)
        
        XCTAssert(app.buttons["Take Photo or Video"].exists)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testComposeMessageFingerprintNavigation() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.tables.staticTexts["Test"].tap()
        app.navigationBars["Test"].staticTexts["Test"].pressForDuration(1.0)
        
        XCTAssert(app.staticTexts["Your Fingerprint"].exists)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testComposeMessageFingerprintExitNavigation() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.tables.staticTexts["Test"].tap()
        app.navigationBars["Test"].staticTexts["Test"].pressForDuration(1.0)
        app.buttons["×"].tap()
        
        XCTAssert(!app.staticTexts["Your Fingerprint"].exists)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testComposeMessageFingerprintSessionAlert() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.tables.staticTexts["Test"].tap()
        app.navigationBars["Test"].staticTexts["Test"].pressForDuration(1.0)
        app.staticTexts["Your Fingerprint"].pressForDuration(1.5)
        
        XCTAssert(app.buttons["Reset this session."].exists)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testComposeMessageFingerprintDisplayNavigation() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.tables.staticTexts["Test"].tap()
        app.navigationBars["Test"].staticTexts["Test"].pressForDuration(1.0)
        app.staticTexts["Your Fingerprint"].tap()
        
        XCTAssert(app.buttons["quit"].exists)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testComposeMessageFingerprintDisplayExitNavigation() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.tables.staticTexts["Test"].tap()
        app.navigationBars["Test"].staticTexts["Test"].pressForDuration(1.0)
        app.staticTexts["Your Fingerprint"].tap()
        app.buttons["quit"].tap()
        
        XCTAssert(!app.buttons["quit"].exists)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testConversationExitNavigation() {
        
        let app = XCUIApplication()
        app.staticTexts["Test"].tap()
        app.buttons.elementBoundByIndex(0).tap()
        
        XCTAssert(app.buttons["Inbox"].exists)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testConversationsSwipe() {
        
        let app = XCUIApplication()
        app.staticTexts["Test"].swipeLeft()
        
        XCTAssert(app.buttons["Delete"].exists)
        XCTAssert(app.buttons["Archive"].exists)
        
    }
    
    // requires verified app
    func testComposeMessageNewGroupNavigation() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.navigationBars["New Message"].buttons["btnGroup  white"].tap()
        
        XCTAssert(app.navigationBars["New Group"].exists)
        
    }
    
    // requires verified app
    func testComposeMessagNewGroupPictureAlert() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.navigationBars["New Message"].buttons["btnGroup  white"].tap()
        app.buttons["empty group avatar"].tap()
        
        XCTAssert(app.buttons["Take a Picture"].exists)
        
    }
    
    // requires verified app
    // THIS TEST SOMETIMES CRASHES MIDWAY DUE TO INHERENT ISSUE WITH SIGNAL'S
    // GROUP CREATION
    func testComposeMessageNewGroupCreate() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.navigationBars["New Message"].buttons["btnGroup  white"].tap()
        app.buttons["add conversation"].tap()
        
        XCTAssert(app.alerts["Creating group"].exists)
        
        XCTAssert(app.tables.staticTexts["New Group"].exists)
        
    }
    
    // requires verified app
    // THIS TEST SOMETIMES CRASHES MIDWAY DUE TO INHERENT ISSUE WITH SIGNAL'S
    // GROUP CREATION
    func testComposeMessageNewGroupCreateDelete() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.navigationBars["New Message"].buttons["btnGroup  white"].tap()
        app.buttons["add conversation"].tap()
        app.buttons.elementBoundByIndex(0).tap()
        app.staticTexts["New Group"].swipeLeft()
        app.tables.buttons["Delete"].tap()
        
        XCTAssert(app.staticTexts["Leaving group"].exists)
        
    }
    
    // requires verified app
    func testGroupContactOptionsAction() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.navigationBars["New Message"].buttons["btnGroup  white"].tap()
        app.buttons["add conversation"].tap()
        app.tables.staticTexts["New Group"].tap()
        app.navigationBars["New Group"].buttons["contact options action"].tap()
        
        XCTAssert(app.buttons["Update"].exists)
        XCTAssert(app.buttons["Leave"].exists)
        XCTAssert(app.buttons["Members"].exists)
        
    }
    
    // requires verified app
    func testGroupContactOptionsUpdateAction() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.navigationBars["New Message"].buttons["btnGroup  white"].tap()
        app.buttons["add conversation"].tap()
        app.tables.staticTexts["New Group"].tap()
        app.navigationBars["New Group"].buttons["contact options action"].tap()
        app.toolbars.buttons["Update"].tap()
        
        XCTAssert(app.tables["Add people"].exists)
        
    }
    
    // requires verified app
    func testGroupContactOptionsMembersAction() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.navigationBars["New Message"].buttons["btnGroup  white"].tap()
        app.buttons["add conversation"].tap()
        app.tables.staticTexts["New Group"].tap()
        app.navigationBars["New Group"].buttons["contact options action"].tap()
        app.toolbars.buttons["Members"].tap()
        
        XCTAssert(app.tables.staticTexts["Group Members:"].exists)
        
    }
    
    // requires verified app
    func testGroupContactOptionsLeaveAction() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.navigationBars["New Message"].buttons["btnGroup  white"].tap()
        app.buttons["add conversation"].tap()
        app.tables.staticTexts["New Group"].tap()
        app.navigationBars["New Group"].buttons["contact options action"].tap()
        app.toolbars.buttons["Leave"].tap()
        
        XCTAssert(app.staticTexts["You have left the group."].exists)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testComposeMessageContactSearch() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        let searchField = app.tables.searchFields["Search by name or number"]
        searchField.tap()
        app.typeText("Tes")
        
        XCTAssert(app.tables.staticTexts["Test"].exists)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testComposeMessageContactSearchSelect() {
        
        let app = XCUIApplication()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.tables.searchFields["Search by name or number"].tap()
        app.typeText("Tes")
        
        app.tables.staticTexts["Test"].coordinateWithNormalizedOffset(CGVectorMake(0.0, 0.0)).tap()
        
        XCTAssert(app.navigationBars["Test"].exists)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testInboxConversationArchive() {
        
        let app = XCUIApplication()
        app.buttons["Inbox"].tap()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.staticTexts["Test"].tap()
        app.textViews.elementBoundByIndex(app.textViews.count - 1).tap()
        app.textViews.elementBoundByIndex(app.textViews.count - 1).typeText("1")
        app.toolbars.buttons["Send"].tap()
        app.buttons.elementBoundByIndex(0).tap()
        app.staticTexts["Test"].swipeLeft()
        app.tables.buttons["Archive"].tap()
        
        XCTAssert(!app.tables.cells["Test"].exists)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testInboxConversationDelete() {
        
        let app = XCUIApplication()
        app.buttons["Inbox"].tap()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.staticTexts["Test"].tap()
        app.textViews.elementBoundByIndex(app.textViews.count - 1).tap()
        app.textViews.elementBoundByIndex(app.textViews.count - 1).typeText("1")
        app.toolbars.buttons["Send"].tap()
        app.buttons.elementBoundByIndex(0).tap()
        app.staticTexts["Test"].swipeLeft()
        app.tables.buttons["Delete"].tap()
        
        XCTAssert(!app.tables.cells["Test"].exists)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testArchiveConversationUnarchive() {
        
        let app = XCUIApplication()
        app.buttons["Inbox"].tap()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.staticTexts["Test"].tap()
        app.textViews.elementBoundByIndex(app.textViews.count - 1).tap()
        app.textViews.elementBoundByIndex(app.textViews.count - 1).typeText("1")
        app.toolbars.buttons["Send"].tap()
        app.buttons.elementBoundByIndex(0).tap()
        app.staticTexts["Test"].swipeLeft()
        app.tables.buttons["Archive"].tap()
        app.buttons["Archive"].tap()
        app.staticTexts["Test"].swipeLeft()
        app.tables.buttons["Unarchive"].tap()
        
        XCTAssert(!app.tables.cells["Test"].exists)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testArchiveConversationDelete() {
        
        let app = XCUIApplication()
        app.buttons["Inbox"].tap()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.staticTexts["Test"].tap()
        app.textViews.elementBoundByIndex(app.textViews.count - 1).tap()
        app.textViews.elementBoundByIndex(app.textViews.count - 1).typeText("1")
        app.toolbars.buttons["Send"].tap()
        app.buttons.elementBoundByIndex(0).tap()
        app.staticTexts["Test"].swipeLeft()
        app.tables.buttons["Archive"].tap()
        app.buttons["Archive"].tap()
        app.staticTexts["Test"].swipeLeft()
        app.tables.buttons["Delete"].tap()
        
        XCTAssert(!app.tables.cells["Test"].exists)
        
    }
    
    // requires verified app AND valid contact with name "Test"
    func testSettingsPrivacyClearHistory() {
        
        let app = XCUIApplication()
        app.buttons["Inbox"].tap()
        app.navigationBars["Conversations"].buttons["Compose"].tap()
        app.staticTexts["Test"].tap()
        app.textViews.elementBoundByIndex(app.textViews.count - 1).tap()
        app.textViews.elementBoundByIndex(app.textViews.count - 1).typeText("1")
        app.toolbars.buttons["Send"].tap()
        app.buttons.elementBoundByIndex(0).tap()
        app.buttons["settings"].tap()
        app.tables.staticTexts["Privacy"].tap()
        app.tables.staticTexts["Clear History Logs"].tap()
        app.buttons["I'm sure."].tap()
        app.buttons["Settings"].tap()
        app.buttons["Done"].tap()
        
        XCTAssert(!app.staticTexts["Test"].exists)
        
    }
    
    // requires verified app
    func testSettingsAdvancedEnableDebugLog() {
        
        let app = XCUIApplication()
        app.buttons["settings"].tap()
        app.tables.staticTexts["Advanced"].tap()
        app.switches.elementBoundByIndex(0).coordinateWithNormalizedOffset(CGVectorMake(0, 0)).pressForDuration(0, thenDragToCoordinate: app.switches.elementBoundByIndex(0).coordinateWithNormalizedOffset(CGVectorMake(1, 0)))
        
        XCTAssert(app.tables.staticTexts["Submit Debug Log"].exists)
        
    }
    
    // requires verified app
    func testSettingsAdvancedDisableDebugLog() {
        
        let app = XCUIApplication()
        app.buttons["settings"].tap()
        app.tables.staticTexts["Advanced"].tap()
        app.switches.elementBoundByIndex(0).coordinateWithNormalizedOffset(CGVectorMake(0, 0)).pressForDuration(0, thenDragToCoordinate: app.switches.elementBoundByIndex(0).coordinateWithNormalizedOffset(CGVectorMake(-1, 0)))
        
        XCTAssert(!app.tables.staticTexts["Submit Debug Log"].exists)
        
    }
    
    // requires verified app
    func testSettingsAdvancedSubmitDebugLog() {
        
        let app = XCUIApplication()
        app.buttons["settings"].tap()
        app.tables.staticTexts["Advanced"].tap()
        app.switches["Enable Debug Log"].swipeLeft()
        app.tables.staticTexts["Submit Debug Log"].tap()
        
        XCTAssert(app.staticTexts["Sending debug log ..."].exists)
        
        expectationForPredicate(NSPredicate(format: "exists == true"), evaluatedWithObject: app.alerts["Submit Debug Log"], handler: nil)
        waitForExpectationsWithTimeout(5, handler: nil)
        
        XCTAssert(app.alerts["Submit Debug Log"].exists)
        
    }
    
    // requires verified app
    func testSettingsAdvancedReRegisterForPushNotifications() {
        
        let app = XCUIApplication()
        app.buttons["settings"].tap()
        app.tables.staticTexts["Advanced"].tap()
        app.tables.staticTexts["Re-register for push notifications"].tap()
        
        XCTAssert(app.alerts["Push Notifications"].exists)
        
    }
    
    // requires verified app
    func testSettingsNotificationsOptionsPreview() {
        
        let app = XCUIApplication()
        app.buttons["settings"].tap()
        app.tables.staticTexts["Notifications"].tap()
        app.tables.staticTexts["Show"].tap()
        app.tables.staticTexts["Sender name & message"].tap()
        
        XCTAssert(app.staticTexts["Sender name & message"].exists)
        
    }
    
}
