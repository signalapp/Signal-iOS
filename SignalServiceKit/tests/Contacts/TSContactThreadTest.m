//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
        getOrCreateThreadWithContactAddress:[[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"]];
}

- (void)testHasSafetyNumbersWithoutRemoteIdentity
{
    XCTAssertFalse(self.contactThread.hasSafetyNumbers);
}

- (void)testHasSafetyNumbersWithRemoteIdentity
{
    [[OWSIdentityManager shared] saveRemoteIdentity:[[NSMutableData alloc] initWithLength:kStoredIdentityKeyLength]
                                            address:self.contactThread.contactAddress];
    XCTAssert(self.contactThread.hasSafetyNumbers);
}

@end

NS_ASSUME_NONNULL_END
