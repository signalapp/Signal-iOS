//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSContactsSearcher.h"
#import <SignalServiceKit/PhoneNumber.h>

@interface OWSContactsSearcher ()

@property (copy) NSArray<Contact *> *contacts;

@end

@implementation OWSContactsSearcher

- (instancetype)initWithContacts:(NSArray<Contact *> *)contacts {
    self = [super init];
    if (!self) return self;

    _contacts = contacts;
    return self;
}

- (NSArray<Contact *> *)filterWithString:(NSString *)string {
    NSString *searchTerm = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if ([searchTerm isEqualToString:@""]) {
        return self.contacts;
    }

    NSString *formattedNumber = [PhoneNumber removeFormattingCharacters:searchTerm];

    // TODO: This assumes there's a single search term.
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(fullName contains[c] %@) OR (ANY parsedPhoneNumbers.toE164 contains[c] %@)", searchTerm, formattedNumber];

    return [self.contacts filteredArrayUsingPredicate:predicate];
}

@end
