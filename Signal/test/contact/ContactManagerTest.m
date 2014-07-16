#import <XCTest/XCTest.h>
#import "TestUtil.h"
#import "ContactsManager.h"

@interface ContactManagerTest : XCTestCase

@end

@implementation ContactManagerTest

- (void)testQueryMatching {
    test([ContactsManager name:@"big dave" matchesQuery:@"big dave"]);
    test([ContactsManager name:@"big dave" matchesQuery:@"dave big"]);
    test([ContactsManager name:@"big dave" matchesQuery:@"dave"]);
    test([ContactsManager name:@"big dave" matchesQuery:@"big"]);
    test([ContactsManager name:@"big dave" matchesQuery:@"big "]);
    test([ContactsManager name:@"big dave" matchesQuery:@"      big       "]);
    test([ContactsManager name:@"big dave" matchesQuery:@"dav"]);
    test([ContactsManager name:@"big dave" matchesQuery:@"bi dav"]);
    test([ContactsManager name:@"big dave" matchesQuery:@"big big big big big big big big big big dave dave dave dave dave"]);

    test(![ContactsManager name:@"big dave" matchesQuery:@"ave"]);
    test(![ContactsManager name:@"big dave" matchesQuery:@"dare"]);
    test(![ContactsManager name:@"big dave" matchesQuery:@"mike"]);
    test(![ContactsManager name:@"big dave" matchesQuery:@"mike"]);
    test(![ContactsManager name:@"dave" matchesQuery:@"big"]);
}

@end
