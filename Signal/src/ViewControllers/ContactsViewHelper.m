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
            //            contactAccount.displayName = contact.fullName;
            //            contactAccount.attributedDisplayName = [self.contactsManager
            //            formattedFullNameForContact:contact];
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
                // TODO:
                contactAccount.multipleAccountLabel = recipientId;
                [allRecipientContactAccounts addObject:contactAccount];
                contactAccountMap[recipientId] = contactAccount;
            }
        }
    }
    self.allRecipientContactAccounts = [allRecipientContactAccounts copy];
    self.contactAccountMap = [contactAccountMap copy];

    [self.delegate contactsViewHelperDidUpdateContacts];
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

@end

NS_ASSUME_NONNULL_END
