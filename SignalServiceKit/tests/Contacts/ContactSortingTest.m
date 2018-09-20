//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "Contact.h"
#import "SSKBaseTest.h"

@import Contacts;

NS_ASSUME_NONNULL_BEGIN

@interface ContactSortingTest : SSKBaseTest

@end

@implementation ContactSortingTest

- (void)setUp
{
    [super setUp];

    srandom((unsigned int)time(NULL));
}

- (void)testSortingNamesByFirstLast
{
    NSComparator comparator = [Contact comparatorSortingNamesByFirstThenLast:YES];
    NSArray<Contact *>*sortedContacts = [self.class contactArrayForNames:@[@[@"Adam", @"Smith"],
                                                                           @[@"Adam", @"West"],
                                                                           @[@"", @"Daisy"],
                                                                           @[@"Daisy", @"Chain"],
                                                                           @[@"Daisy", @"Duke"],
                                                                           @[@"James", @"Smith"],
                                                                           @[@"James", @"Van"],
                                                                           @[@"James", @"Van Der Beek"],
                                                                           @[@"Kevin", @"Smith"],
                                                                           @[@"Mae", @"West"],
                                                                           @[@"Mary", @"Oliver"],
                                                                           @[@"Mary Jo", @"Catlett"],
                                                                           ]];
    NSUInteger numContacts = sortedContacts.count;
    
    for (NSUInteger i = 0; i < 20; i++) {
        NSArray *shuffledContacts = [self.class shuffleArray:sortedContacts];
        NSArray *resortedContacts = [shuffledContacts sortedArrayUsingComparator:comparator];
        for (NSUInteger j = 0; j < numContacts; j++) {
            Contact *a = sortedContacts[j];
            Contact *b = resortedContacts[j];
            BOOL correct = ([a.firstName isEqualToString:b.firstName] && [a.lastName isEqualToString:b.lastName]);
            if (!correct) {
                XCTAssert(@"Contacts failed to sort names by first, last");
                break;
            }
        }
    }
}

- (void)testSortingNamesByLastFirst
{
    NSComparator comparator = [Contact comparatorSortingNamesByFirstThenLast:NO];
    NSArray<Contact *>*sortedContacts = [self.class contactArrayForNames:@[@[@"Mary Jo", @"Catlett"],
                                                                           @[@"Daisy", @"Chain"],
                                                                           @[@"", @"Daisy"],
                                                                           @[@"Daisy", @"Duke"],
                                                                           @[@"Mary", @"Oliver"],
                                                                           @[@"Adam", @"Smith"],
                                                                           @[@"James", @"Smith"],
                                                                           @[@"Kevin", @"Smith"],
                                                                           @[@"James", @"Van"],
                                                                           @[@"James", @"Van Der Beek"],
                                                                           @[@"Adam", @"West"],
                                                                           @[@"Mae", @"West"],
                                                                           ]];
    NSUInteger numContacts = sortedContacts.count;
    
    for (NSUInteger i = 0; i < 20; i++) {
        NSArray *shuffledContacts = [self.class shuffleArray:sortedContacts];
        NSArray *resortedContacts = [shuffledContacts sortedArrayUsingComparator:comparator];
        for (NSUInteger j = 0; j < numContacts; j++) {
            Contact *a = sortedContacts[j];
            Contact *b = resortedContacts[j];
            BOOL correct = ([a.firstName isEqualToString:b.firstName] && [a.lastName isEqualToString:b.lastName]);
            if (!correct) {
                XCTAssert(@"Contacts failed to sort names by last, first");
                break;
            }
        }
    }
}

+ (NSArray<Contact *> *)contactArrayForNames:(NSArray<NSArray<NSString *>*>*)namePairs
{
    NSMutableArray<Contact *>*contacts = [[NSMutableArray alloc] initWithCapacity:namePairs.count];
    for (NSArray<NSString *>*namePair in namePairs) {

        CNMutableContact *cnContact = [CNMutableContact new];
        cnContact.givenName = namePair[0];
        cnContact.familyName = namePair[1];

        Contact *c = [[Contact alloc] initWithSystemContact:cnContact];

        [contacts addObject:c];
    }
    
    return [contacts copy]; // Return an immutable for good hygene
}

+ (NSArray*)shuffleArray:(NSArray *)array
{
    NSMutableArray *shuffled = [[NSMutableArray alloc] initWithArray:array];
    
    for(NSUInteger i = [array count]; i > 1; i--) {
        NSUInteger j = arc4random_uniform((uint32_t)i);
        [shuffled exchangeObjectAtIndex:(i - 1) withObjectAtIndex:j];
    }
    
    return [shuffled copy]; // Return an immutable for good hygene
}

@end

NS_ASSUME_NONNULL_END
