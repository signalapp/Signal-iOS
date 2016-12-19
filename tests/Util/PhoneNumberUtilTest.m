//
//  PhoneNumberTest.m
//  Signal
//
//  Created by Michael Kirk on 6/28/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "PhoneNumberUtil.h"

@interface PhoneNumberUtilTest : XCTestCase

@end

@implementation PhoneNumberUtilTest

- (void)testQueryMatching {
    XCTAssertTrue([PhoneNumberUtil name:@"big dave" matchesQuery:@"big dave"]);
    XCTAssertTrue([PhoneNumberUtil name:@"big dave" matchesQuery:@"dave big"]);
    XCTAssertTrue([PhoneNumberUtil name:@"big dave" matchesQuery:@"dave"]);
    XCTAssertTrue([PhoneNumberUtil name:@"big dave" matchesQuery:@"big"]);
    XCTAssertTrue([PhoneNumberUtil name:@"big dave" matchesQuery:@"big "]);
    XCTAssertTrue([PhoneNumberUtil name:@"big dave" matchesQuery:@"      big       "]);
    XCTAssertTrue([PhoneNumberUtil name:@"big dave" matchesQuery:@"dav"]);
    XCTAssertTrue([PhoneNumberUtil name:@"big dave" matchesQuery:@"bi dav"]);
    XCTAssertTrue([PhoneNumberUtil name:@"big dave" matchesQuery:@"big big big big big big big big big big dave dave dave dave dave"]);
    
    XCTAssertFalse([PhoneNumberUtil name:@"big dave" matchesQuery:@"ave"]);
    XCTAssertFalse([PhoneNumberUtil name:@"big dave" matchesQuery:@"dare"]);
    XCTAssertFalse([PhoneNumberUtil name:@"big dave" matchesQuery:@"mike"]);
    XCTAssertFalse([PhoneNumberUtil name:@"big dave" matchesQuery:@"mike"]);
    XCTAssertFalse([PhoneNumberUtil name:@"dave" matchesQuery:@"big"]);
}

@end
