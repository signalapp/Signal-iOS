#import <XCTest/XCTest.h>
#import "TestUtil.h"
#import "RecentCall.h"

@interface RecentCallTest : XCTestCase
@end

@implementation RecentCallTest

-(void) testConstruction_Incoming {
    RecentCall* r = [RecentCall recentCallWithContactID:123
                                              andNumber:testPhoneNumber1
                                            andCallType:RPRecentCallTypeIncoming];
    test(r.contactRecordID == 123);
    test([r.phoneNumber.toE164 isEqual:testPhoneNumber1.toE164]);
    test(abs([r.date timeIntervalSinceDate:NSDate.date] < 10));
    test(r.userNotified == true);
    test(r.callType == RPRecentCallTypeIncoming);
}

-(void) testConstruction_Missed {
    RecentCall* r = [RecentCall recentCallWithContactID:235
                                              andNumber:testPhoneNumber2
                                            andCallType:RPRecentCallTypeMissed];
    test(r.contactRecordID == 235);
    test([r.phoneNumber.toE164 isEqual:testPhoneNumber2.toE164]);
    test(abs([r.date timeIntervalSinceDate:NSDate.date] < 10));
    test(r.userNotified == false);
    test(r.callType == RPRecentCallTypeMissed);
}

@end
