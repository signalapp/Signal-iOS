#import "Contact.h"
#import "PhoneNumber.h"
#import "SignalRecipient.h"
#import "TSStorageManager.h"

@implementation Contact

#if TARGET_OS_IOS
- (instancetype)initWithContactWithFirstName:(NSString *)firstName
                                 andLastName:(NSString *)lastName
                     andUserTextPhoneNumbers:(NSArray *)phoneNumbers
                                    andImage:(UIImage *)image
                                andContactID:(ABRecordID)record {
    self = [super init];
    if (self) {
        _firstName            = firstName;
        _lastName             = lastName;
        _userTextPhoneNumbers = phoneNumbers;
        _recordID             = record;
        _image                = image;

        NSMutableArray *parsedPhoneNumbers = [NSMutableArray array];

        for (NSString *phoneNumberString in phoneNumbers) {
            PhoneNumber *phoneNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:phoneNumberString];
            if (phoneNumber) {
                [parsedPhoneNumbers addObject:phoneNumber];
            }
        }

        _parsedPhoneNumbers = parsedPhoneNumbers.copy;
    }

    return self;
}
#endif

- (NSString *)fullName {
    NSMutableString *fullName = [NSMutableString string];
    if (self.firstName)
        [fullName appendString:self.firstName];
    if (self.lastName) {
        [fullName appendString:[NSString stringWithFormat:@" %@", self.lastName]];
    }
    return fullName;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ %@: %@", self.firstName, self.lastName, self.userTextPhoneNumbers];
}

- (BOOL)isSignalContact {
    NSArray *identifiers = [self textSecureIdentifiers];

    return [identifiers count] > 0;
}

- (NSArray<NSString *> *)textSecureIdentifiers {
    __block NSMutableArray *identifiers = [NSMutableArray array];

    [[TSStorageManager sharedManager]
            .dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      for (PhoneNumber *number in self.parsedPhoneNumbers) {
          if ([SignalRecipient recipientWithTextSecureIdentifier:number.toE164 withTransaction:transaction]) {
              [identifiers addObject:number.toE164];
          }
      }
    }];
    return identifiers;
}

@end
