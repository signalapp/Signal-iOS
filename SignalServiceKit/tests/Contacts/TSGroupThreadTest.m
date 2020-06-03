//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "SSKBaseTestObjC.h"
#import "TSGroupThread.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSGroupThreadTest : SSKBaseTestObjC

@end

@implementation TSGroupThreadTest

- (void)testHasSafetyNumbers
{
    TSGroupThread *groupThread = [[TSGroupThread alloc] initWithDictionary:@{} error:nil];
    XCTAssertFalse(groupThread.hasSafetyNumbers);
}

@end

NS_ASSUME_NONNULL_END
