//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "MockSSKEnvironment.h"
#import "OWSIdentityManager.h"
#import "SSKBaseTestObjC.h"
#import "TSContactThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSContactThreadTest : SSKBaseTestObjC

@property (nonatomic) TSContactThread *contactThread;

@end

@implementation TSContactThreadTest

- (void)setUp
{
    [super setUp];

    self.contactThread = [TSContactThread
        getOrCreateThreadWithContactAddress:[[SignalServiceAddress alloc] initWithPhoneNumber:@"fake-contact-id"]];
}

- (void)testHasSafetyNumbersWithoutRemoteIdentity
{
    XCTAssertFalse(self.contactThread.hasSafetyNumbers);
}

- (void)testHasSafetyNumbersWithRemoteIdentity
{
    [[OWSIdentityManager sharedManager]
        saveRemoteIdentity:[[NSMutableData alloc] initWithLength:kStoredIdentityKeyLength]
                   address:self.contactThread.contactAddress];
    XCTAssert(self.contactThread.hasSafetyNumbers);
}

@end

NS_ASSUME_NONNULL_END
