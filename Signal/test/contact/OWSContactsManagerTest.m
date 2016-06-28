#import <XCTest/XCTest.h>
#import "TestUtil.h"
#import "OWSContactsManager.h"

@interface OWSContactsManagerTest : XCTestCase

@end


@implementation OWSContactsManagerTest

- (void)testQueryMatching {
    test([OWSContactsManager name:@"big dave" matchesQuery:@"big dave"]);
    test([OWSContactsManager name:@"big dave" matchesQuery:@"dave big"]);
    test([OWSContactsManager name:@"big dave" matchesQuery:@"dave"]);
    test([OWSContactsManager name:@"big dave" matchesQuery:@"big"]);
    test([OWSContactsManager name:@"big dave" matchesQuery:@"big "]);
    test([OWSContactsManager name:@"big dave" matchesQuery:@"      big       "]);
    test([OWSContactsManager name:@"big dave" matchesQuery:@"dav"]);
    test([OWSContactsManager name:@"big dave" matchesQuery:@"bi dav"]);
    test([OWSContactsManager name:@"big dave" matchesQuery:@"big big big big big big big big big big dave dave dave dave dave"]);

    test(![OWSContactsManager name:@"big dave" matchesQuery:@"ave"]);
    test(![OWSContactsManager name:@"big dave" matchesQuery:@"dare"]);
    test(![OWSContactsManager name:@"big dave" matchesQuery:@"mike"]);
    test(![OWSContactsManager name:@"big dave" matchesQuery:@"mike"]);
    test(![OWSContactsManager name:@"dave" matchesQuery:@"big"]);
}

@end
