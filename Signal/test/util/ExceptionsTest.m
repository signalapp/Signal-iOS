#import "Constraints.h"
#import "ExceptionsTest.h"
#import "TestUtil.h"

@implementation ExceptionsTest
- (void)testContracts {
    ows_require(1 + 1 == 2);
    @try {
        ows_require(1 + 1 == 3);
        XCTFail(@"");
    } @catch (BadArgument *ex) {
        test([[ex reason] hasPrefix:@"require 1 + 1 == 3"]);
    }

    requireState(1 + 1 == 2);
    @try {
        requireState(1 + 1 == 3);
        XCTFail(@"");
    } @catch (BadState *ex) {
        test([[ex reason] hasPrefix:@"required state: 1 + 1 == 3"]);
    }

    checkOperationDescribe(1 + 1 == 2, @"addition.");
    @try {
        checkOperationDescribe(1 + 1 == 3, @"addition.");
        XCTFail(@"");
    } @catch (OperationFailed *ex) {
        test([[ex reason] hasPrefix:@"Operation failed: addition. Expected: 1 + 1 == 3"]);
    }

    checkOperation(1 + 1 == 2);
    @try {
        checkOperation(1 + 1 == 3);
        XCTFail(@"");
    } @catch (OperationFailed *ex) {
        test([[ex reason] hasPrefix:@"Operation failed. Expected: 1 + 1 == 3"]);
    }
}

@end
