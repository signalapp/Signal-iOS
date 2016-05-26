#import "Contact.h"
#import "PhoneNumber.h"
#import "SignalRecipient.h"
#import "TSStorageManager.h"

static NSString *const DEFAULTS_KEY_CONTACT      = @"DefaultsKeyContact";
static NSString *const DEFAULTS_KEY_PHONE_NUMBER = @"DefaultsKeyPhoneNumber";
static NSString *const DEFAULTS_KEY_CALL_TYPE    = @"DefaultsKeycallType";
static NSString *const DEFAULTS_KEY_DATE         = @"DefaultsKeyDate";

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
    if (_firstName)
        [fullName appendString:_firstName];
    if (_lastName) {
        [fullName appendString:[NSString stringWithFormat:@" %@", _lastName]];
    }
    return fullName;
}

- (NSString *)allPhoneNumbers {
    NSString *allNumbers = @"";
    for (PhoneNumber *number in self.parsedPhoneNumbers) {
        allNumbers = [allNumbers stringByAppendingString:number.toE164];
        allNumbers = [allNumbers stringByAppendingString:@";"];
    }
    return allNumbers;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ %@: %@", _firstName, _lastName, _userTextPhoneNumbers];
}

- (BOOL)isTextSecureContact {
    NSArray *identifiers = [self textSecureIdentifiers];

    if ([identifiers count] > 0) {
        return YES;
    }

    return NO;
}

- (NSArray *)textSecureIdentifiers {
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

- (BOOL)isRedPhoneContact {
    NSArray *identifiers = [self redPhoneIdentifiers];

    if ([identifiers count] > 0) {
        return YES;
    }

    return NO;
}

- (NSArray *)redPhoneIdentifiers {
    __block NSMutableArray *identifiers = [NSMutableArray array];

    [[TSStorageManager sharedManager]
            .dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      for (PhoneNumber *number in self.parsedPhoneNumbers) {
          SignalRecipient *recipient =
              [SignalRecipient recipientWithTextSecureIdentifier:number.toE164 withTransaction:transaction];
          if (recipient && recipient.supportsVoice) {
              [identifiers addObject:number.toE164];
          }
      }
    }];
    return identifiers;
}

@end
