//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ContactsViewHelper.h"
#import "ContactAccount.h"
#import "ContactTableViewCell.h"
#import "Environment.h"
#import <SignalServiceKit/Contact.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/TSAccountManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface ContactsViewHelper ()

@property (nonatomic, nullable) NSArray<Contact *> *allRecipientContacts;
@property (nonatomic, nullable) NSArray<ContactAccount *> *allRecipientContactAccounts;
// A map of recipient id-to-contact account.
@property (nonatomic, nullable) NSDictionary<NSString *, ContactAccount *> *contactAccountMap;

@property (nonatomic, nullable) NSArray<NSString *> *blockedPhoneNumbers;

@end

#pragma mark -

@implementation ContactsViewHelper

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _blockingManager = [OWSBlockingManager sharedManager];
    self.blockedPhoneNumbers = [_blockingManager blockedPhoneNumbers];

    _contactsManager = [Environment getCurrent].contactsManager;
    [self updateContacts];

    [self observeNotifications];

    return self;
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(signalRecipientsDidChange:)
                                                 name:OWSContactsManagerSignalRecipientsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(blockedPhoneNumbersDidChange:)
                                                 name:kNSNotificationName_BlockedPhoneNumbersDidChange
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)signalRecipientsDidChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateContacts];
    });
}

- (void)blockedPhoneNumbersDidChange:(id)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.blockedPhoneNumbers = [_blockingManager blockedPhoneNumbers];

        [self updateContacts];
    });
}

#pragma mark - Contacts

- (nullable ContactAccount *)contactAccountForRecipientId:(NSString *)recipientId
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(recipientId.length > 0);

    return self.contactAccountMap[recipientId];
}

- (void)updateContacts
{
    OWSAssert([NSThread isMainThread]);

    self.allRecipientContacts = [self filteredContacts];
}

- (void)setAllRecipientContacts:(nullable NSArray<Contact *> *)allRecipientContacts
{
    OWSAssert([NSThread isMainThread]);

    _allRecipientContacts = allRecipientContacts;

    NSMutableArray<ContactAccount *> *allRecipientContactAccounts = [NSMutableArray new];
    NSMutableDictionary<NSString *, ContactAccount *> *contactAccountMap = [NSMutableDictionary new];
    for (Contact *contact in allRecipientContacts) {
        if (contact.textSecureIdentifiers.count == 1) {
            ContactAccount *contactAccount = [ContactAccount new];
            contactAccount.contact = contact;
            NSString *recipientId = contact.textSecureIdentifiers[0];
            contactAccount.recipientId = recipientId;
            [allRecipientContactAccounts addObject:contactAccount];
            contactAccountMap[recipientId] = contactAccount;
        } else if (contact.textSecureIdentifiers.count > 1) {
            for (NSString *recipientId in
                [contact.textSecureIdentifiers sortedArrayUsingSelector:@selector(compare:)]) {
                ContactAccount *contactAccount = [ContactAccount new];
                contactAccount.contact = contact;
                contactAccount.recipientId = recipientId;
                contactAccount.isMultipleAccountContact = YES;
                contactAccount.multipleAccountLabel = [self accountLabelForContact:contact recipientId:recipientId];
                [allRecipientContactAccounts addObject:contactAccount];
                contactAccountMap[recipientId] = contactAccount;
            }
        }
    }
    self.allRecipientContactAccounts = [allRecipientContactAccounts copy];
    self.contactAccountMap = [contactAccountMap copy];

    [self.delegate contactsViewHelperDidUpdateContacts];
}

- (NSString *)accountLabelForContact:(Contact *)contact recipientId:(NSString *)recipientId
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

- (BOOL)isContactHidden:(Contact *)contact
{
    OWSAssert([NSThread isMainThread]);

    if (contact.parsedPhoneNumbers.count < 1) {
        // Hide contacts without any valid phone numbers.
        return YES;
    }

    if ([self.delegate shouldHideLocalNumber] && [self isCurrentUserContact:contact]) {
        // We never want to add ourselves to a group.
        return YES;
    }

    return NO;
}

- (BOOL)isCurrentUserContact:(Contact *)contact
{
    OWSAssert([NSThread isMainThread]);

    for (PhoneNumber *phoneNumber in contact.parsedPhoneNumbers) {
        if ([[phoneNumber toE164] isEqualToString:[TSAccountManager localNumber]]) {
            return YES;
        }
    }

    return NO;
}

- (NSString *)localNumber
{
    return [TSAccountManager localNumber];
}

- (BOOL)isContactBlocked:(Contact *)contact
{
    OWSAssert([NSThread isMainThread]);

    if (contact.parsedPhoneNumbers.count < 1) {
        // Do not consider contacts without any valid phone numbers to be blocked.
        return NO;
    }

    for (PhoneNumber *phoneNumber in contact.parsedPhoneNumbers) {
        if ([_blockedPhoneNumbers containsObject:phoneNumber.toE164]) {
            return YES;
        }
    }

    return NO;
}

- (BOOL)isRecipientIdBlocked:(NSString *)recipientId
{
    AssertIsOnMainThread();

    return [_blockedPhoneNumbers containsObject:recipientId];
}

- (NSArray<Contact *> *_Nonnull)filteredContacts
{
    AssertIsOnMainThread();

    NSMutableArray<Contact *> *result = [NSMutableArray new];
    for (Contact *contact in self.contactsManager.signalContacts) {
        if (![self isContactHidden:contact]) {
            [result addObject:contact];
        }
    }
    return [result copy];
}

- (BOOL)doesContactAccount:(ContactAccount *)contactAccount matchSearchTerm:(NSString *)searchTerm
{
    OWSAssert(contactAccount);
    OWSAssert(searchTerm.length > 0);

    if ([contactAccount.contact.fullName.lowercaseString containsString:searchTerm.lowercaseString]) {
        return YES;
    }

    NSString *asPhoneNumber = [PhoneNumber removeFormattingCharacters:searchTerm];
    if (asPhoneNumber.length > 0 && [contactAccount.recipientId containsString:asPhoneNumber]) {
        return YES;
    }

    return NO;
}

- (BOOL)doesContactAccount:(ContactAccount *)contactAccount matchSearchTerms:(NSArray<NSString *> *)searchTerms
{
    OWSAssert(contactAccount);
    OWSAssert(searchTerms.count > 0);

    for (NSString *searchTerm in searchTerms) {
        if (![self doesContactAccount:contactAccount matchSearchTerm:searchTerm]) {
            return NO;
        }
    }

    return YES;
}

- (NSArray<ContactAccount *> *)contactAccountsMatchingSearchString:(NSString *)searchText
{
    NSArray<NSString *> *searchTerms =
        [[searchText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
            componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (searchTerms.count < 1) {
        return self.allRecipientContactAccounts;
    }

    return [self.allRecipientContactAccounts
        filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(ContactAccount *contactAccount,
                                        NSDictionary<NSString *, id> *_Nullable bindings) {
            return [self doesContactAccount:contactAccount matchSearchTerms:searchTerms];
        }]];
}

@end

NS_ASSUME_NONNULL_END
