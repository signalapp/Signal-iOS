//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "MockSSKEnvironment.h"
#import "SSKBaseTestObjC.h"
#import "SignalRecipient.h"
#import "TSAccountManager.h"
#import "TestAppContext.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@interface SignalRecipientTest : SSKBaseTestObjC

@property (nonatomic) SignalServiceAddress *localAddress;

@end

#pragma mark -

@implementation SignalRecipientTest

- (void)setUp
{
    [super setUp];

    [[TSAccountManager sharedInstance] registerForTestsWithLocalNumber:@"+13231231234" uuid:[NSUUID new]];
    self.localAddress = TSAccountManager.localAddress;
}

- (void)tearDown
{
    [super tearDown];
}

- (void)testSelfRecipientWithExistingRecord
{
    // Sanity Check
    XCTAssertNotNil(self.localAddress);

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [SignalRecipient markRecipientAsRegisteredAndGet:self.localAddress transaction:transaction];

        XCTAssertTrue([SignalRecipient isRegisteredRecipient:self.localAddress transaction:transaction]);
    }];
}

- (void)testRecipientWithExistingRecord
{
    // Sanity Check
    XCTAssertNotNil(self.localAddress);
    SignalServiceAddress *recipient = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+15551231234"];
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [SignalRecipient markRecipientAsRegisteredAndGet:recipient transaction:transaction];

        XCTAssertTrue([SignalRecipient isRegisteredRecipient:recipient transaction:transaction]);
    }];
}

@end
