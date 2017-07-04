//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSContactsManager.h"
#import "Environment.h"
#import "Signal-Swift.h"
#import "Util.h"
#import <SignalServiceKit/ContactsUpdater.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/TSStorageManager.h>

@import Contacts;

NSString *const OWSContactsManagerSignalAccountsDidChangeNotification =
    @"OWSContactsManagerSignalAccountsDidChangeNotification";

NSString *const kTSStorageManager_AccountDisplayNames = @"kTSStorageManager_AccountDisplayNames";
NSString *const kTSStorageManager_AccountFirstNames = @"kTSStorageManager_AccountFirstNames";
NSString *const kTSStorageManager_AccountLastNames = @"kTSStorageManager_AccountLastNames";

@interface OWSContactsManager () <SystemContactsFetcherDelegate>

@property (atomic) id addressBookReference;
@property (atomic) TOCFuture *futureAddressBook;
@property (nonatomic) BOOL isContactsUpdateInFlight;
// This reflects the contents of the device phone book and includes
// contacts that do not correspond to any signal account.
@property (atomic) NSArray<Contact *> *allContacts;
@property (atomic) NSDictionary<NSString *, Contact *> *allContactsMap;
@property (atomic) NSArray<SignalAccount *> *signalAccounts;
@property (atomic) NSDictionary<NSString *, SignalAccount *> *signalAccountMap;
@property (nonatomic, readonly) SystemContactsFetcher *systemContactsFetcher;

@property (atomic) NSDictionary<NSString *, NSString *> *cachedAccountNameMap;
@property (atomic) NSDictionary<NSString *, NSString *> *cachedFirstNameMap;
@property (atomic) NSDictionary<NSString *, NSString *> *cachedLastNameMap;

@end

@implementation OWSContactsManager

- (id)init {
    self = [super init];
    if (!self) {
        return self;
    }

    // TODO: We need to configure the limits of this cache.
    _avatarCache = [NSCache new];
    _allContacts = @[];
    _signalAccountMap = @{};
    _signalAccounts = @[];
    _systemContactsFetcher = [SystemContactsFetcher new];
    _systemContactsFetcher.delegate = self;

    OWSSingletonAssert();

    [self loadCachedDisplayNames];

    return self;
}

#pragma mark - System Contact Fetching

// Request contacts access if you haven't asked recently.
- (void)requestSystemContactsOnce
{
    [self requestSystemContactsOnceWithCompletion:nil];
}

- (void)requestSystemContactsOnceWithCompletion:(void (^_Nullable)(NSError *_Nullable error))completion
{
    [self.systemContactsFetcher requestOnceWithCompletion:completion];
}


- (void)fetchSystemContactsIfAlreadyAuthorized
{
    [self.systemContactsFetcher fetchIfAlreadyAuthorized];
}

- (BOOL)isSystemContactsAuthorized
{
    return self.systemContactsFetcher.isAuthorized;
}

- (BOOL)supportsContactEditing
{
    return self.systemContactsFetcher.supportsContactEditing;
}

#pragma mark SystemContactsFetcherDelegate

- (void)systemContactsFetcher:(SystemContactsFetcher *)systemsContactsFetcher
              updatedContacts:(NSArray<Contact *> *)contacts
{
    [self updateWithContacts:contacts];
}

#pragma mark - Intersection

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

            [self.avatarCache removeAllObjects];

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

        // We use a transaction only to load the SignalRecipients for each contact,
        // in order to avoid database deadlock.
        NSMutableDictionary<NSString *, NSArray<SignalRecipient *> *> *contactIdToSignalRecipientsMap =
            [NSMutableDictionary new];
        [[TSStorageManager sharedManager].dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            for (Contact *contact in contacts) {
                NSArray<SignalRecipient *> *signalRecipients = [contact signalRecipientsWithTransaction:transaction];
                contactIdToSignalRecipientsMap[contact.uniqueId] = signalRecipients;
            }
        }];

        for (Contact *contact in contacts) {
            NSArray<SignalRecipient *> *signalRecipients = contactIdToSignalRecipientsMap[contact.uniqueId];
            for (SignalRecipient *signalRecipient in [signalRecipients sortedArrayUsingSelector:@selector(compare:)]) {
                SignalAccount *signalAccount = [[SignalAccount alloc] initWithSignalRecipient:signalRecipient];
                signalAccount.contact = contact;
                if (signalRecipients.count > 1) {
                    signalAccount.hasMultipleAccountContact = YES;
                    signalAccount.multipleAccountLabelText =
                        [[self class] accountLabelForContact:contact recipientId:signalRecipient.recipientId];
                }
                if (signalAccountMap[signalAccount.recipientId]) {
                    DDLogDebug(@"Ignoring duplicate contact: %@, %@", signalAccount.recipientId, contact.fullName);
                    continue;
                }
                signalAccountMap[signalAccount.recipientId] = signalAccount;
                [signalAccounts addObject:signalAccount];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.signalAccountMap = [signalAccountMap copy];
            self.signalAccounts = [signalAccounts copy];

            [self updateCachedDisplayNames];

            [[NSNotificationCenter defaultCenter]
                postNotificationName:OWSContactsManagerSignalAccountsDidChangeNotification
                              object:nil];
        });
    });
}

- (void)updateCachedDisplayNames
{
    OWSAssert([NSThread isMainThread]);

    NSMutableDictionary<NSString *, NSString *> *cachedAccountNameMap = [NSMutableDictionary new];
    NSMutableDictionary<NSString *, NSString *> *cachedFirstNameMap = [NSMutableDictionary new];
    NSMutableDictionary<NSString *, NSString *> *cachedLastNameMap = [NSMutableDictionary new];

    for (SignalAccount *signalAccount in self.signalAccounts) {
        NSString *baseName
            = (signalAccount.contact.fullName.length > 0 ? signalAccount.contact.fullName : signalAccount.recipientId);
        OWSAssert(signalAccount.hasMultipleAccountContact == (signalAccount.multipleAccountLabelText != nil));
        NSString *displayName = (signalAccount.multipleAccountLabelText
                ? [NSString stringWithFormat:@"%@ (%@)", baseName, signalAccount.multipleAccountLabelText]
                : baseName);
        if (![displayName isEqualToString:signalAccount.recipientId]) {
            cachedAccountNameMap[signalAccount.recipientId] = displayName;
        }

        if (signalAccount.contact.firstName.length > 0) {
            cachedFirstNameMap[signalAccount.recipientId] = signalAccount.contact.firstName;
        }
        if (signalAccount.contact.lastName.length > 0) {
            cachedLastNameMap[signalAccount.recipientId] = signalAccount.contact.lastName;
        }
    }

    self.cachedAccountNameMap = [cachedAccountNameMap copy];
    self.cachedFirstNameMap = [cachedFirstNameMap copy];
    self.cachedLastNameMap = [cachedLastNameMap copy];

    // Write to database off the main thread.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [TSStorageManager.sharedManager.newDatabaseConnection readWriteWithBlock:^(
            YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            for (NSString *recipientId in cachedAccountNameMap) {
                NSString *displayName = cachedAccountNameMap[recipientId];
                [transaction setObject:displayName
                                forKey:recipientId
                          inCollection:kTSStorageManager_AccountDisplayNames];
            }
            for (NSString *recipientId in cachedFirstNameMap) {
                NSString *firstName = cachedFirstNameMap[recipientId];
                [transaction setObject:firstName forKey:recipientId inCollection:kTSStorageManager_AccountFirstNames];
            }
            for (NSString *recipientId in cachedLastNameMap) {
                NSString *lastName = cachedLastNameMap[recipientId];
                [transaction setObject:lastName forKey:recipientId inCollection:kTSStorageManager_AccountLastNames];
            }
        }];
    });
}

- (void)loadCachedDisplayNames
{
    // Read from database off the main thread.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableDictionary<NSString *, NSString *> *cachedAccountNameMap = [NSMutableDictionary new];
        NSMutableDictionary<NSString *, NSString *> *cachedFirstNameMap = [NSMutableDictionary new];
        NSMutableDictionary<NSString *, NSString *> *cachedLastNameMap = [NSMutableDictionary new];

        [TSStorageManager.sharedManager.newDatabaseConnection readWithBlock:^(
            YapDatabaseReadTransaction *_Nonnull transaction) {
            [transaction
                enumerateKeysAndObjectsInCollection:kTSStorageManager_AccountDisplayNames
                                         usingBlock:^(
                                             NSString *_Nonnull key, NSString *_Nonnull object, BOOL *_Nonnull stop) {
                                             cachedAccountNameMap[key] = object;
                                         }];
            [transaction
                enumerateKeysAndObjectsInCollection:kTSStorageManager_AccountFirstNames
                                         usingBlock:^(
                                             NSString *_Nonnull key, NSString *_Nonnull object, BOOL *_Nonnull stop) {
                                             cachedFirstNameMap[key] = object;
                                         }];
            [transaction
                enumerateKeysAndObjectsInCollection:kTSStorageManager_AccountLastNames
                                         usingBlock:^(
                                             NSString *_Nonnull key, NSString *_Nonnull object, BOOL *_Nonnull stop) {
                                             cachedLastNameMap[key] = object;
                                         }];
        }];

        if (self.cachedAccountNameMap || self.cachedFirstNameMap || self.cachedLastNameMap) {
            // If these properties have already been populated from system contacts,
            // don't overwrite.  In practice this should never happen.
            OWSAssert(0);
            return;
        }

        self.cachedAccountNameMap = [cachedAccountNameMap copy];
        self.cachedFirstNameMap = [cachedFirstNameMap copy];
        self.cachedLastNameMap = [cachedLastNameMap copy];
    });
}

- (NSString *_Nullable)cachedDisplayNameForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    return self.cachedAccountNameMap[recipientId];
}

- (NSString *_Nullable)cachedFirstNameForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    return self.cachedFirstNameMap[recipientId];
}

- (NSString *_Nullable)cachedLastNameForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    return self.cachedLastNameMap[recipientId];
}

#pragma mark - View Helpers

// TODO move into Contact class.
+ (NSString *)accountLabelForContact:(Contact *)contact recipientId:(NSString *)recipientId
{
    OWSAssert(contact);
    OWSAssert(recipientId.length > 0);
    OWSAssert([contact.textSecureIdentifiers containsObject:recipientId]);

    if (contact.textSecureIdentifiers.count <= 1) {
        return nil;
    }

    // 1. Find the phone number type of this account.
    NSString *phoneNumberLabel = [contact nameForPhoneNumber:recipientId];

    // 2. Find all phone numbers for this contact of the same type.
    NSMutableArray *phoneNumbersWithTheSameName = [NSMutableArray new];
    for (NSString *textSecureIdentifier in contact.textSecureIdentifiers) {
        if ([phoneNumberLabel isEqualToString:[contact nameForPhoneNumber:textSecureIdentifier]]) {
            [phoneNumbersWithTheSameName addObject:textSecureIdentifier];
        }
    }

    OWSAssert([phoneNumbersWithTheSameName containsObject:recipientId]);
    if (phoneNumbersWithTheSameName.count > 1) {
        NSUInteger index =
            [[phoneNumbersWithTheSameName sortedArrayUsingSelector:@selector(compare:)] indexOfObject:recipientId];
        phoneNumberLabel =
            [NSString stringWithFormat:NSLocalizedString(@"PHONE_NUMBER_TYPE_AND_INDEX_FORMAT",
                                           @"Format for phone number label with an index. Embeds {{Phone number label "
                                           @"(e.g. 'home')}} and {{index, e.g. 2}}."),
                      phoneNumberLabel,
                      (int)index];
    }

    return phoneNumberLabel;
}

- (BOOL)phoneNumber:(PhoneNumber *)phoneNumber1 matchesNumber:(PhoneNumber *)phoneNumber2 {
    return [phoneNumber1.toE164 isEqualToString:phoneNumber2.toE164];
}

#pragma mark - Whisper User Management

- (NSString *)unknownContactName
{
    return NSLocalizedString(@"UNKNOWN_CONTACT_NAME",
                             @"Displayed if for some reason we can't determine a contacts phone number *or* name");
}

- (NSString *_Nonnull)displayNameForPhoneIdentifier:(NSString *_Nullable)recipientId
{
    if (!recipientId) {
        return self.unknownContactName;
    }

    NSString *displayName = [self cachedDisplayNameForRecipientId:recipientId];
    if (displayName.length < 1) {
        displayName = recipientId;
    }
    return displayName;
}

- (NSString *_Nonnull)displayNameForSignalAccount:(SignalAccount *)signalAccount
{
    OWSAssert(signalAccount);

    return [self displayNameForPhoneIdentifier:signalAccount.recipientId];
}

- (NSAttributedString *_Nonnull)formattedDisplayNameForSignalAccount:(SignalAccount *)signalAccount
                                                                font:(UIFont *_Nonnull)font
{
    OWSAssert(signalAccount);
    OWSAssert(font);

    return [self formattedFullNameForRecipientId:signalAccount.recipientId font:font];
}

- (NSAttributedString *)formattedFullNameForRecipientId:(NSString *)recipientId font:(UIFont *)font
{
    OWSAssert(recipientId.length > 0);
    OWSAssert(font);

    UIFont *boldFont = [UIFont ows_mediumFontWithSize:font.pointSize];

    NSDictionary<NSString *, id> *boldFontAttributes =
        @{ NSFontAttributeName : boldFont, NSForegroundColorAttributeName : [UIColor blackColor] };
    NSDictionary<NSString *, id> *normalFontAttributes =
        @{ NSFontAttributeName : font, NSForegroundColorAttributeName : [UIColor ows_darkGrayColor] };
    NSDictionary<NSString *, id> *firstNameAttributes
        = (ABPersonGetSortOrdering() == kABPersonSortByFirstName ? boldFontAttributes : normalFontAttributes);
    NSDictionary<NSString *, id> *lastNameAttributes
        = (ABPersonGetSortOrdering() == kABPersonSortByFirstName ? normalFontAttributes : boldFontAttributes);

    NSString *cachedFirstName = [self cachedFirstNameForRecipientId:recipientId];
    NSString *cachedLastName = [self cachedLastNameForRecipientId:recipientId];

    NSMutableAttributedString *formattedName = [NSMutableAttributedString new];

    if (cachedFirstName.length > 0 && cachedLastName.length > 0) {
        NSAttributedString *firstName =
            [[NSAttributedString alloc] initWithString:cachedFirstName attributes:firstNameAttributes];
        NSAttributedString *lastName =
            [[NSAttributedString alloc] initWithString:cachedLastName attributes:lastNameAttributes];

        NSAttributedString *_Nullable leftName, *_Nullable rightName;
        if (ABPersonGetCompositeNameFormat() == kABPersonCompositeNameFormatFirstNameFirst) {
            leftName = firstName;
            rightName = lastName;
        } else {
            leftName = lastName;
            rightName = firstName;
        }

        [formattedName appendAttributedString:leftName];
        [formattedName
            appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:normalFontAttributes]];
        [formattedName appendAttributedString:rightName];
    } else if (cachedFirstName.length > 0) {
        [formattedName appendAttributedString:[[NSAttributedString alloc] initWithString:cachedFirstName
                                                                              attributes:firstNameAttributes]];
    } else if (cachedLastName.length > 0) {
        [formattedName appendAttributedString:[[NSAttributedString alloc] initWithString:cachedLastName
                                                                              attributes:lastNameAttributes]];
    } else {
        return [[NSAttributedString alloc]
            initWithString:[PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:recipientId]
                attributes:normalFontAttributes];
    }

    SignalAccount *signalAccount = [self signalAccountForRecipientId:recipientId];
    if (signalAccount && signalAccount.multipleAccountLabelText) {
        OWSAssert(signalAccount.multipleAccountLabelText.length > 0);

        [formattedName
            appendAttributedString:[[NSAttributedString alloc] initWithString:@" (" attributes:normalFontAttributes]];
        [formattedName
            appendAttributedString:[[NSAttributedString alloc] initWithString:signalAccount.multipleAccountLabelText
                                                                   attributes:normalFontAttributes]];
        [formattedName
            appendAttributedString:[[NSAttributedString alloc] initWithString:@")" attributes:normalFontAttributes]];
    }

    return formattedName;
}

- (nullable SignalAccount *)signalAccountForRecipientId:(NSString *)recipientId
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
                                                    andImage:nil
                                                andContactID:0];
    }
}

- (UIImage * _Nullable)imageForPhoneIdentifier:(NSString * _Nullable)identifier {
    Contact *contact = self.allContactsMap[identifier];

    return contact.image;
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
