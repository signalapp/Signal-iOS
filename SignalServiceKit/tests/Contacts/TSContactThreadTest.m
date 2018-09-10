//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSContactThread.h"
#import "MockSSKEnvironment.h"
#import "OWSIdentityManager.h"
#import "SSKBaseTest.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSContactThreadTest : SSKBaseTest

@property (nonatomic) TSContactThread *contactThread;

@end

@implementation TSContactThreadTest

- (void)setUp
{
    [super setUp];

    self.contactThread = [TSContactThread getOrCreateThreadWithContactId:@"fake-contact-id"];
    [OWSRecipientIdentity removeAllObjectsInCollection];
}

- (void)testHasSafetyNumbersWithoutRemoteIdentity
{
    XCTAssertFalse(self.contactThread.hasSafetyNumbers);
}

- (void)testHasSafetyNumbersWithRemoteIdentity
{
    [[OWSIdentityManager sharedManager] saveRemoteIdentity:[NSData new]
                                               recipientId:self.contactThread.contactIdentifier];
    XCTAssert(self.contactThread.hasSafetyNumbers);
}

@end

NS_ASSUME_NONNULL_END
