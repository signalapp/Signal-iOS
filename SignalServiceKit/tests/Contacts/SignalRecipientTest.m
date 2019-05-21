//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "MockSSKEnvironment.h"
#import "OWSPrimaryStorage.h"
#import "SSKBaseTestObjC.h"
#import "SignalRecipient.h"
#import "TSAccountManager.h"
#import "TestAppContext.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@interface TSAccountManager (Testing)

- (void)storeLocalNumber:(NSString *)localNumber;

@end

@interface SignalRecipientTest : SSKBaseTestObjC

@property (nonatomic) NSString *localNumber;

@end

@implementation SignalRecipientTest

- (void)setUp
{
    [super setUp];

    self.localNumber = @"+13231231234";
    [[TSAccountManager sharedInstance] storeLocalNumber:self.localNumber];
}

- (void)tearDown
{
    [super tearDown];
}

- (void)testSelfRecipientWithExistingRecord
{
    // Sanity Check
    XCTAssertNotNil(self.localNumber);

    [self yapWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [SignalRecipient markRecipientAsRegisteredAndGet:self.localNumber transaction:transaction];

        XCTAssertTrue([SignalRecipient isRegisteredRecipient:self.localNumber transaction:transaction]);
    }];
}

- (void)testRecipientWithExistingRecord
{
    // Sanity Check
    XCTAssertNotNil(self.localNumber);
    NSString *recipientId = @"+15551231234";
    [self yapWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [SignalRecipient markRecipientAsRegisteredAndGet:recipientId transaction:transaction];
        
        XCTAssertTrue([SignalRecipient isRegisteredRecipient:recipientId transaction:transaction]);
    }];
}

@end
