//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSContactsManager.h"
#import "Environment.h"
#import "SignalAccount.h"
#import "Util.h"
#import <SignalServiceKit/ContactsUpdater.h>
#import <SignalServiceKit/OWSError.h>

#define ADDRESSBOOK_QUEUE dispatch_get_main_queue()

typedef BOOL (^ContactSearchBlock)(id, NSUInteger, BOOL *);

NSString *const OWSContactsManagerSignalAccountsDidChangeNotification =
    @"OWSContactsManagerSignalAccountsDidChangeNotification";

@interface OWSContactsManager ()

@property (atomic, nullable) CNContactStore *contactStore;
@property (atomic) id addressBookReference;
@property (atomic) TOCFuture *futureAddressBook;
@property (nonatomic) BOOL isContactsUpdateInFlight;
// This reflects the contents of the device phone book and includes
// contacts that do not correspond to any signal account.
@property (atomic) NSArray<Contact *> *allContacts;
@property (atomic) NSDictionary<NSString *, Contact *> *allContactsMap;
@property (atomic) NSArray<SignalAccount *> *signalAccounts;
@property (atomic) NSDictionary<NSString *, SignalAccount *> *signalAccountMap;

@end

@implementation OWSContactsManager

- (id)init {
    self = [super init];
    if (!self) {
        return self;
    }

    _avatarCache = [NSCache new];
    _allContacts = @[];
    _signalAccountMap = @{};
    _signalAccounts = @[];

    OWSSingletonAssert();

    return self;
}

- (void)doAfterEnvironmentInitSetup {
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(9, 0) &&
        !self.contactStore) {
        OWSAssert(!self.contactStore);
        self.contactStore = [[CNContactStore alloc] init];
        [self.contactStore requestAccessForEntityType:CNEntityTypeContacts
                                    completionHandler:^(BOOL granted, NSError *_Nullable error) {
                                      if (!granted) {
                                          // We're still using the old addressbook API.
                                          // User warned if permission not granted in that setup.
                                      }
                                    }];
    }

    [self setupAddressBookIfNecessary];
}

- (void)verifyABPermission {
    [self setupAddressBookIfNecessary];
}

#pragma mark - Address Book callbacks

void onAddressBookChanged(ABAddressBookRef notifyAddressBook, CFDictionaryRef info, void *context);
void onAddressBookChanged(ABAddressBookRef notifyAddressBook, CFDictionaryRef info, void *context) {
    OWSContactsManager *contactsManager = (__bridge OWSContactsManager *)context;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [contactsManager handleAddressBookChanged];
    });
}

- (void)handleAddressBookChanged
{
    [self.avatarCache removeAllObjects];
    [self pullLatestAddressBook];
}

#pragma mark - Setup

- (void)setupAddressBookIfNecessary
{
    dispatch_async(ADDRESSBOOK_QUEUE, ^{
        // De-bounce address book setup.
        if (self.isContactsUpdateInFlight) {
            return;
        }
        // We only need to set up our address book once;
        // after that we only need to respond to onAddressBookChanged.
        if (self.addressBookReference) {
            return;
        }
        self.isContactsUpdateInFlight = YES;

        TOCFuture *future = [OWSContactsManager asyncGetAddressBook];
        [future thenDo:^(id addressBook) {
            // Success.
            OWSAssert(self.isContactsUpdateInFlight);
            OWSAssert(!self.addressBookReference);

            self.addressBookReference = addressBook;
            self.isContactsUpdateInFlight = NO;

            ABAddressBookRef cfAddressBook = (__bridge ABAddressBookRef)addressBook;
            ABAddressBookRegisterExternalChangeCallback(cfAddressBook, onAddressBookChanged, (__bridge void *)self);
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self handleAddressBookChanged];
            });
        }];
        [future catchDo:^(id failure) {
            // Failure.
            OWSAssert(self.isContactsUpdateInFlight);
            OWSAssert(!self.addressBookReference);

            self.isContactsUpdateInFlight = NO;
        }];
    });
}

- (void)intersectContacts
{
    [self intersectContactsWithRetryDelay:1];
}

- (void)intersectContactsWithRetryDelay:(double)retryDelaySeconds
{
    void (^success)() = ^{
        DDLogInfo(@"%@ Successfully intersected contacts.", self.tag);
        [self updateSignalAccounts];
    };
    void (^failure)(NSError *error) = ^(NSError *error) {
        if ([error.domain isEqualToString:OWSSignalServiceKitErrorDomain]
            && error.code == OWSErrorCodeContactsUpdaterRateLimit) {
            DDLogError(@"Contact intersection hit rate limit with error: %@", error);
            return;
        }

        DDLogWarn(@"%@ Failed to intersect contacts with error: %@. Rescheduling", self.tag, error);

        // Retry with exponential backoff.
        //
        // TODO: Abort if another contact intersection succeeds in the meantime.
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(retryDelaySeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self intersectContactsWithRetryDelay:retryDelaySeconds * 2];
            });
    };
    [[ContactsUpdater sharedUpdater] updateSignalContactIntersectionWithABContacts:self.allContacts
                                                                           success:success
                                                                           failure:failure];
}

- (void)pullLatestAddressBook {
    dispatch_async(ADDRESSBOOK_QUEUE, ^{
        CFErrorRef creationError = nil;
        ABAddressBookRef addressBookRef = ABAddressBookCreateWithOptions(NULL, &creationError);
        checkOperationDescribe(nil == creationError, [((__bridge NSError *)creationError)localizedDescription]);
        ABAddressBookRequestAccessWithCompletion(addressBookRef, ^(bool granted, CFErrorRef error) {
            if (!granted) {
                [OWSContactsManager blockingContactDialog];
            }
        });
        NSArray<Contact *> *contacts = [self getContactsFromAddressBook:addressBookRef];
        [self updateWithContacts:contacts];
    });
}

- (void)updateWithContacts:(NSArray<Contact *> *)contacts
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        NSMutableDictionary<NSString *, Contact *> *allContactsMap = [NSMutableDictionary new];
        for (Contact *contact in contacts) {
            for (PhoneNumber *phoneNumber in contact.parsedPhoneNumbers) {
                NSString *phoneNumberE164 = phoneNumber.toE164;
                if (phoneNumberE164.length > 0) {
                    allContactsMap[phoneNumberE164] = contact;
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.allContacts = contacts;
            self.allContactsMap = [allContactsMap copy];

            [self intersectContacts];

            [self updateSignalAccounts];
        });
    });
}

- (void)updateSignalAccounts
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableDictionary<NSString *, SignalAccount *> *signalAccountMap = [NSMutableDictionary new];
        NSMutableArray<SignalAccount *> *signalAccounts = [NSMutableArray new];
        NSArray<Contact *> *contacts = self.allContacts;
        [[TSStorageManager sharedManager].dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            for (Contact *contact in contacts) {
                NSArray<SignalRecipient *> *signalRecipients = [contact signalRecipientsWithTransaction:transaction];
                for (SignalRecipient *signalRecipient in
                    [signalRecipients sortedArrayUsingSelector:@selector(compare:)]) {
                    SignalAccount *signalAccount = [[SignalAccount alloc] initWithSignalRecipient:signalRecipient];
                    signalAccount.contact = contact;
                    if (signalRecipients.count > 1) {
                        signalAccount.isMultipleAccountContact = YES;
                        signalAccount.multipleAccountLabel =
                            [[self class] accountLabelForContact:contact recipientId:signalRecipient.recipientId];
                    }
                    if (signalAccountMap[signalAccount.recipientId]) {
                        DDLogInfo(@"Ignoring duplicate contact: %@, %@", signalAccount.recipientId, contact.fullName);
                        continue;
                    }
                    signalAccountMap[signalAccount.recipientId] = signalAccount;
                    [signalAccounts addObject:signalAccount];
                }
            }
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.signalAccountMap = [signalAccountMap copy];
            self.signalAccounts = [signalAccounts copy];

            [[NSNotificationCenter defaultCenter]
                postNotificationName:OWSContactsManagerSignalAccountsDidChangeNotification
                              object:nil];
        });
    });
}

+ (NSString *)accountLabelForContact:(Contact *)contact recipientId:(NSString *)recipientId
{
    OWSAssert(contact);
    OWSAssert(recipientId.length > 0);
    OWSAssert([contact.textSecureIdentifiers containsObject:recipientId]);

    if (contact.textSecureIdentifiers.count <= 1) {
        return nil;
    }

    // 1. Find the phone number type of this account.
    OWSPhoneNumberType phoneNumberType = [contact phoneNumberTypeForPhoneNumber:recipientId];

    NSString *phoneNumberLabel;
    switch (phoneNumberType) {
        case OWSPhoneNumberTypeMobile:
            phoneNumberLabel = NSLocalizedString(@"PHONE_NUMBER_TYPE_MOBILE", @"Label for 'Mobile' phone numbers.");
            break;
        case OWSPhoneNumberTypeIPhone:
            phoneNumberLabel = NSLocalizedString(@"PHONE_NUMBER_TYPE_IPHONE", @"Label for 'IPhone' phone numbers.");
            break;
        case OWSPhoneNumberTypeMain:
            phoneNumberLabel = NSLocalizedString(@"PHONE_NUMBER_TYPE_MAIN", @"Label for 'Main' phone numbers.");
            break;
        case OWSPhoneNumberTypeHomeFAX:
            phoneNumberLabel = NSLocalizedString(@"PHONE_NUMBER_TYPE_HOME_FAX", @"Label for 'HomeFAX' phone numbers.");
            break;
        case OWSPhoneNumberTypeWorkFAX:
            phoneNumberLabel = NSLocalizedString(@"PHONE_NUMBER_TYPE_WORK_FAX", @"Label for 'Work FAX' phone numbers.");
            break;
        case OWSPhoneNumberTypeOtherFAX:
            phoneNumberLabel
                = NSLocalizedString(@"PHONE_NUMBER_TYPE_OTHER_FAX", @"Label for 'Other FAX' phone numbers.");
            break;
        case OWSPhoneNumberTypePager:
            phoneNumberLabel = NSLocalizedString(@"PHONE_NUMBER_TYPE_PAGER", @"Label for 'Pager' phone numbers.");
            break;
        case OWSPhoneNumberTypeUnknown:
            phoneNumberLabel = NSLocalizedString(@"PHONE_NUMBER_TYPE_UNKNOWN", @"Label for 'Unknown' phone numbers.");
            break;
    }

    // 2. Find all phone numbers for this contact of the same type.
    NSMutableArray *phoneNumbersOfTheSameType = [NSMutableArray new];
    for (NSString *textSecureIdentifier in contact.textSecureIdentifiers) {
        if (phoneNumberType == [contact phoneNumberTypeForPhoneNumber:textSecureIdentifier]) {
            [phoneNumbersOfTheSameType addObject:textSecureIdentifier];
        }
    }

    OWSAssert([phoneNumbersOfTheSameType containsObject:recipientId]);
    if (phoneNumbersOfTheSameType.count > 0) {
        NSUInteger index =
            [[phoneNumbersOfTheSameType sortedArrayUsingSelector:@selector(compare:)] indexOfObject:recipientId];
        phoneNumberLabel =
            [NSString stringWithFormat:NSLocalizedString(@"PHONE_NUMBER_TYPE_AND_INDEX_FORMAT",
                                           @"Format for phone number label with an index. Embeds {{Phone number label "
                                           @"(e.g. 'home')}} and {{index, e.g. 2}}."),
                      phoneNumberLabel,
                      (int)index];
    }

    return phoneNumberLabel;
}

+ (void)blockingContactDialog {
    switch (ABAddressBookGetAuthorizationStatus()) {
        case kABAuthorizationStatusRestricted: {
            UIAlertController *controller =
                [UIAlertController alertControllerWithTitle:NSLocalizedString(@"AB_PERMISSION_MISSING_TITLE", nil)
                                                    message:NSLocalizedString(@"ADDRESSBOOK_RESTRICTED_ALERT_BODY", nil)
                                             preferredStyle:UIAlertControllerStyleAlert];

            [controller
                addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"ADDRESSBOOK_RESTRICTED_ALERT_BUTTON", nil)
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *action) {
                                                     [DDLog flushLog];
                                                     exit(0);
                                                 }]];

            [[UIApplication sharedApplication]
                    .keyWindow.rootViewController presentViewController:controller
                                                               animated:YES
                                                             completion:nil];

            break;
        }
        case kABAuthorizationStatusDenied: {
            UIAlertController *controller =
                [UIAlertController alertControllerWithTitle:NSLocalizedString(@"AB_PERMISSION_MISSING_TITLE", nil)
                                                    message:NSLocalizedString(@"AB_PERMISSION_MISSING_BODY", nil)
                                             preferredStyle:UIAlertControllerStyleAlert];

            [controller addAction:[UIAlertAction
                                      actionWithTitle:NSLocalizedString(@"AB_PERMISSION_MISSING_ACTION", nil)
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction *action) {
                                                [[UIApplication sharedApplication]
                                                    openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
                                              }]];

            [[[UIApplication sharedApplication] keyWindow]
                    .rootViewController presentViewController:controller
                                                     animated:YES
                                                   completion:nil];
            break;
        }

        case kABAuthorizationStatusNotDetermined: {
            DDLogInfo(@"AddressBook access not granted but status undetermined.");
            [[Environment getCurrent].contactsManager pullLatestAddressBook];
            break;
        }

        case kABAuthorizationStatusAuthorized: {
            DDLogInfo(@"AddressBook access not granted but status authorized.");
            break;
        }

        default:
            break;
    }
}

#pragma mark - Address Book utils

+ (TOCFuture *)asyncGetAddressBook {
    CFErrorRef creationError        = nil;
    ABAddressBookRef addressBookRef = ABAddressBookCreateWithOptions(NULL, &creationError);
    assert((addressBookRef == nil) == (creationError != nil));
    if (creationError != nil) {
        [self blockingContactDialog];
        return [TOCFuture futureWithFailure:(__bridge_transfer id)creationError];
    }

    TOCFutureSource *futureAddressBookSource = [TOCFutureSource new];

    id addressBook = (__bridge_transfer id)addressBookRef;
    ABAddressBookRequestAccessWithCompletion(addressBookRef, ^(bool granted, CFErrorRef requestAccessError) {
      if (granted && ABAddressBookGetAuthorizationStatus() == kABAuthorizationStatusAuthorized) {
          dispatch_async(ADDRESSBOOK_QUEUE, ^{
            [futureAddressBookSource trySetResult:addressBook];
          });
      } else {
          [self blockingContactDialog];
          [futureAddressBookSource trySetFailure:(__bridge id)requestAccessError];
      }
    });

    return futureAddressBookSource.future;
}

- (NSArray<Contact *> *)getContactsFromAddressBook:(ABAddressBookRef _Nonnull)addressBook
{
    CFArrayRef allPeople = ABAddressBookCopyArrayOfAllPeople(addressBook);

    CFMutableArrayRef allPeopleMutable =
        CFArrayCreateMutableCopy(kCFAllocatorDefault, CFArrayGetCount(allPeople), allPeople);

    CFArraySortValues(allPeopleMutable,
                      CFRangeMake(0, CFArrayGetCount(allPeopleMutable)),
                      (CFComparatorFunction)ABPersonComparePeopleByName,
                      (void *)(unsigned long)ABPersonGetSortOrdering());

    NSArray *sortedPeople = (__bridge_transfer NSArray *)allPeopleMutable;

    // This predicate returns all contacts from the addressbook having at least one phone number

    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(id record, NSDictionary *bindings) {
      ABMultiValueRef phoneNumbers = ABRecordCopyValue((__bridge ABRecordRef)record, kABPersonPhoneProperty);
      BOOL result                  = NO;

      for (CFIndex i = 0; i < ABMultiValueGetCount(phoneNumbers); i++) {
          NSString *phoneNumber = (__bridge_transfer NSString *)ABMultiValueCopyValueAtIndex(phoneNumbers, i);
          if (phoneNumber.length > 0) {
              result = YES;
              break;
          }
      }
      CFRelease(phoneNumbers);
      return result;
    }];
    CFRelease(allPeople);
    NSArray *filteredContacts = [sortedPeople filteredArrayUsingPredicate:predicate];

    return [filteredContacts map:^id(id item) {
        Contact *contact = [self contactForRecord:(__bridge ABRecordRef)item];
        return contact;
    }];
}

#pragma mark - Contact/Phone Number util

- (Contact *)contactForRecord:(ABRecordRef)record {
    ABRecordID recordID = ABRecordGetRecordID(record);

    NSString *firstName = (__bridge_transfer NSString *)ABRecordCopyValue(record, kABPersonFirstNameProperty);
    NSString *lastName = (__bridge_transfer NSString *)ABRecordCopyValue(record, kABPersonLastNameProperty);
    NSDictionary<NSString *, NSNumber *> *phoneNumberTypeMap = [self phoneNumbersForRecord:record];
    NSArray *phoneNumbers = [phoneNumberTypeMap.allKeys sortedArrayUsingSelector:@selector(compare:)];

    if (!firstName && !lastName) {
        NSString *companyName = (__bridge_transfer NSString *)ABRecordCopyValue(record, kABPersonOrganizationProperty);
        if (companyName) {
            firstName = companyName;
        } else if (phoneNumbers.count) {
            firstName = phoneNumbers.firstObject;
        }
    }

    NSData *imageData
        = (__bridge_transfer NSData *)ABPersonCopyImageDataWithFormat(record, kABPersonImageFormatThumbnail);
    UIImage *img = [UIImage imageWithData:imageData];

    return [[Contact alloc] initWithContactWithFirstName:firstName
                                             andLastName:lastName
                                 andUserTextPhoneNumbers:phoneNumbers
                                      phoneNumberTypeMap:phoneNumberTypeMap
                                                andImage:img
                                            andContactID:recordID];
}

- (BOOL)phoneNumber:(PhoneNumber *)phoneNumber1 matchesNumber:(PhoneNumber *)phoneNumber2 {
    return [phoneNumber1.toE164 isEqualToString:phoneNumber2.toE164];
}

- (NSDictionary<NSString *, NSNumber *> *)phoneNumbersForRecord:(ABRecordRef)record
{
    ABMultiValueRef phoneNumberRefs = NULL;

    @try {
        phoneNumberRefs = ABRecordCopyValue(record, kABPersonPhoneProperty);

        CFIndex phoneNumberCount = ABMultiValueGetCount(phoneNumberRefs);
        NSMutableDictionary<NSString *, NSNumber *> *result = [NSMutableDictionary new];
        for (int i = 0; i < phoneNumberCount; i++) {
            NSString *phoneNumberLabel = (__bridge_transfer NSString *)ABMultiValueCopyLabelAtIndex(phoneNumberRefs, i);
            NSString *phoneNumber = (__bridge_transfer NSString *)ABMultiValueCopyValueAtIndex(phoneNumberRefs, i);

            if ([phoneNumberLabel isEqualToString:(NSString *)kABPersonPhoneMobileLabel]) {
                result[phoneNumber] = @(OWSPhoneNumberTypeMobile);
            } else if ([phoneNumberLabel isEqualToString:(NSString *)kABPersonPhoneIPhoneLabel]) {
                result[phoneNumber] = @(OWSPhoneNumberTypeIPhone);
            } else if ([phoneNumberLabel isEqualToString:(NSString *)kABPersonPhoneMainLabel]) {
                result[phoneNumber] = @(OWSPhoneNumberTypeMain);
            } else if ([phoneNumberLabel isEqualToString:(NSString *)kABPersonPhoneHomeFAXLabel]) {
                result[phoneNumber] = @(OWSPhoneNumberTypeHomeFAX);
            } else if ([phoneNumberLabel isEqualToString:(NSString *)kABPersonPhoneWorkFAXLabel]) {
                result[phoneNumber] = @(OWSPhoneNumberTypeWorkFAX);
            } else if ([phoneNumberLabel isEqualToString:(NSString *)kABPersonPhoneOtherFAXLabel]) {
                result[phoneNumber] = @(OWSPhoneNumberTypeOtherFAX);
            } else if ([phoneNumberLabel isEqualToString:(NSString *)kABPersonPhonePagerLabel]) {
                result[phoneNumber] = @(OWSPhoneNumberTypePager);
            } else {
                result[phoneNumber] = @(OWSPhoneNumberTypeUnknown);
            }
        }
        return [result copy];
    } @finally {
        if (phoneNumberRefs) {
            CFRelease(phoneNumberRefs);
        }
    }
}

#pragma mark - Whisper User Management

- (NSArray *)getSignalUsersFromContactsArray:(NSArray *)contacts {
    NSMutableDictionary *signalContacts = [NSMutableDictionary new];
    for (Contact *contact in contacts) {
        if ([contact isSignalContact]) {
            signalContacts[contact.textSecureIdentifiers.firstObject] = contact;
        }
    }

    return [signalContacts.allValues sortedArrayUsingComparator:[[self class] contactComparator]];
}

+ (NSComparator)contactComparator
{
    BOOL firstNameOrdering = ABPersonGetSortOrdering() == kABPersonCompositeNameFormatFirstNameFirst ? YES : NO;
    return [Contact comparatorSortingNamesByFirstThenLast:firstNameOrdering];
}

- (NSArray<Contact *> * _Nonnull)signalContacts {
    return [self getSignalUsersFromContactsArray:[self allContacts]];
}

- (NSString *)unknownContactName
{
    return NSLocalizedString(@"UNKNOWN_CONTACT_NAME",
                             @"Displayed if for some reason we can't determine a contacts phone number *or* name");
}

- (NSString * _Nonnull)displayNameForPhoneIdentifier:(NSString * _Nullable)identifier {
    if (!identifier) {
        return self.unknownContactName;
    }

    // TODO: There's some overlap here with displayNameForSignalAccount.
    SignalAccount *signalAccount = [self signalAccountForRecipientId:identifier];

    NSString *displayName = (signalAccount.contact.fullName.length > 0) ? signalAccount.contact.fullName : identifier;

    return displayName;
}

- (NSString *_Nonnull)displayNameForContact:(Contact *)contact
{
    OWSAssert(contact);

    NSString *displayName = (contact.fullName.length > 0) ? contact.fullName : self.unknownContactName;

    return displayName;
}

- (NSString *_Nonnull)displayNameForSignalAccount:(SignalAccount *)signalAccount
{
    OWSAssert(signalAccount);

    NSString *baseName = (signalAccount.contact ? [self displayNameForContact:signalAccount.contact]
                                                : [self displayNameForPhoneIdentifier:signalAccount.recipientId]);
    OWSAssert(signalAccount.isMultipleAccountContact == (signalAccount.multipleAccountLabel != nil));
    if (signalAccount.multipleAccountLabel) {
        return [NSString stringWithFormat:@"%@ (%@)", baseName, signalAccount.multipleAccountLabel];
    } else {
        return baseName;
    }
}

- (NSAttributedString *_Nonnull)formattedDisplayNameForSignalAccount:(SignalAccount *)signalAccount
                                                                font:(UIFont *_Nonnull)font
{
    OWSAssert(signalAccount);
    OWSAssert(font);

    NSAttributedString *baseName = [self formattedFullNameForContact:signalAccount.contact font:font];
    OWSAssert(signalAccount.isMultipleAccountContact == (signalAccount.multipleAccountLabel != nil));
    if (signalAccount.multipleAccountLabel) {
        NSMutableAttributedString *result = [NSMutableAttributedString new];
        [result appendAttributedString:baseName];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:@" ("
                                                                       attributes:@{
                                                                           NSFontAttributeName : font,
                                                                       }]];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:signalAccount.multipleAccountLabel]];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:@")"
                                                                       attributes:@{
                                                                           NSFontAttributeName : font,
                                                                       }]];
        return result;
    } else {
        return baseName;
    }
}

- (NSAttributedString *_Nonnull)formattedFullNameForContact:(Contact *)contact font:(UIFont *_Nonnull)font
{
    UIFont *boldFont = [UIFont ows_mediumFontWithSize:font.pointSize];

    NSDictionary<NSString *, id> *boldFontAttributes =
        @{ NSFontAttributeName : boldFont, NSForegroundColorAttributeName : [UIColor blackColor] };

    NSDictionary<NSString *, id> *normalFontAttributes =
        @{ NSFontAttributeName : font, NSForegroundColorAttributeName : [UIColor ows_darkGrayColor] };

    NSAttributedString *_Nullable firstName, *_Nullable lastName;
    if (ABPersonGetSortOrdering() == kABPersonSortByFirstName) {
        if (contact.firstName) {
            firstName = [[NSAttributedString alloc] initWithString:contact.firstName attributes:boldFontAttributes];
        }
        if (contact.lastName) {
            lastName = [[NSAttributedString alloc] initWithString:contact.lastName attributes:normalFontAttributes];
        }
    } else {
        if (contact.firstName) {
            firstName = [[NSAttributedString alloc] initWithString:contact.firstName attributes:normalFontAttributes];
        }
        if (contact.lastName) {
            lastName = [[NSAttributedString alloc] initWithString:contact.lastName attributes:boldFontAttributes];
        }
    }

    NSAttributedString *_Nullable leftName, *_Nullable rightName;
    if (ABPersonGetCompositeNameFormat() == kABPersonCompositeNameFormatFirstNameFirst) {
        leftName = firstName;
        rightName = lastName;
    } else {
        leftName = lastName;
        rightName = firstName;
    }

    NSMutableAttributedString *fullNameString = [NSMutableAttributedString new];
    if (leftName) {
        [fullNameString appendAttributedString:leftName];
    }
    if (leftName && rightName) {
        [fullNameString appendAttributedString:[[NSAttributedString alloc] initWithString:@" "]];
    }
    if (rightName) {
        [fullNameString appendAttributedString:rightName];
    }

    return fullNameString;
}

- (NSAttributedString *)formattedFullNameForRecipientId:(NSString *)recipientId font:(UIFont *)font
{
    NSDictionary<NSString *, id> *normalFontAttributes =
        @{ NSFontAttributeName : font, NSForegroundColorAttributeName : [UIColor ows_darkGrayColor] };

    return [[NSAttributedString alloc]
        initWithString:[PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:recipientId]
            attributes:normalFontAttributes];
}

- (nullable SignalAccount *)signalAccountForRecipientId:(nullable NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    return self.signalAccountMap[recipientId];
}

- (Contact *)getOrBuildContactForPhoneIdentifier:(NSString *)identifier
{
    Contact *savedContact = self.allContactsMap[identifier];
    if (savedContact) {
        return savedContact;
    } else {
        return [[Contact alloc] initWithContactWithFirstName:self.unknownContactName
                                                 andLastName:nil
                                     andUserTextPhoneNumbers:@[ identifier ]
                                          phoneNumberTypeMap:nil
                                                    andImage:nil
                                                andContactID:0];
    }
}

- (UIImage * _Nullable)imageForPhoneIdentifier:(NSString * _Nullable)identifier {
    Contact *contact = self.allContactsMap[identifier];

    return contact.image;
}

- (BOOL)hasAddressBook
{
    return (BOOL)self.addressBookReference;
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end
