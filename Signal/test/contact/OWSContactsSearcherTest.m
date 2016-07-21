//
//  OWSContactSearcherTest.m
//  Signal
//
//  Created by Michael Kirk on 6/27/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "OWSContactsSearcher.h"

@interface OWSContactsSearcherTest : XCTestCase

@property Contact *meow;
@property Contact *clement;
@property OWSContactsSearcher *contactsSearcher;

@end

@implementation OWSContactsSearcherTest

- (void)setUp {
    [super setUp];

    self.meow = [[Contact alloc] initWithContactWithFirstName:@"Chairman"
                                                  andLastName:@"Meow"
                                      andUserTextPhoneNumbers:@[ @"1-323-555-1234", @"+86 10 1111 2222" ]
                                                     andImage:nil
                                                 andContactID:1];

    self.clement = [[Contact alloc] initWithContactWithFirstName:@"Clément"
                                                     andLastName:@"Duval"
                                         andUserTextPhoneNumbers:@[ @"33 123456789" ]
                                                        andImage:nil
                                                    andContactID:2];

    self.contactsSearcher = [[OWSContactsSearcher alloc] initWithContacts:@[self.meow, self.clement]];
}

- (void)testFilterWithStringMatchAllOnEmtpy {
    XCTAssertEqualObjects((@[self.meow, self.clement]), [self.contactsSearcher filterWithString:@""]);
    XCTAssertEqualObjects((@[self.meow, self.clement]), [self.contactsSearcher filterWithString:@"  "]);
}

- (void)testFilterWithStringMatchByName {
    XCTAssertEqualObjects(@[self.meow], [self.contactsSearcher filterWithString:@"Chairman"]);
    XCTAssertEqualObjects(@[self.meow], [self.contactsSearcher filterWithString:@"Chair"]);
    XCTAssertEqualObjects(@[self.meow], [self.contactsSearcher filterWithString:@"Meow"]);
    XCTAssertEqualObjects(@[self.meow], [self.contactsSearcher filterWithString:@"Chairman Meow"]);
    XCTAssertEqualObjects(@[self.meow], [self.contactsSearcher filterWithString:@" Chairman Meow "]);
    XCTAssertEqualObjects((@[self.meow, self.clement]), ([self.contactsSearcher filterWithString:@"C"]));
    XCTAssertEqualObjects(@[], [self.contactsSearcher filterWithString:@"Chairman Meowww"]);
}

- (void)testFilterWithStringByNumber {
    XCTAssertEqualObjects(@[self.meow], [self.contactsSearcher filterWithString:@"1-323-555-1234"]);
    XCTAssertEqualObjects(@[self.meow], [self.contactsSearcher filterWithString:@"+86 10 1111 2222"]);
    XCTAssertEqualObjects(@[self.meow], [self.contactsSearcher filterWithString:@"323-555-1234"]);
    XCTAssertEqualObjects(@[self.meow], [self.contactsSearcher filterWithString:@"323.555.1234"]);
    XCTAssertEqualObjects(@[self.meow], [self.contactsSearcher filterWithString:@"3235551234"]);
    XCTAssertEqualObjects(@[self.meow], [self.contactsSearcher filterWithString:@"323"]);
    XCTAssertEqualObjects(@[self.meow], [self.contactsSearcher filterWithString:@"323 555 1234"]);
    XCTAssertEqualObjects(@[self.meow], [self.contactsSearcher filterWithString:@"+1 323 555 1234"]);
    XCTAssertEqualObjects(@[self.meow], [self.contactsSearcher filterWithString:@"+13235551234"]);
    XCTAssertEqualObjects((@[self.meow, self.clement]), [self.contactsSearcher filterWithString:@"1234"]);
}

@end
