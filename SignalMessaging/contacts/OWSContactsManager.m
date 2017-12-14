//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSContactsManager.h"
#import "Environment.h"
#import "OWSFormat.h"
#import "OWSProfileManager.h"
#import "OWSUserProfile.h"
#import "ViewControllerUtils.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIColor+OWS.h>
#import <SignalMessaging/UIFont+OWS.h>
#import <SignalServiceKit/ContactsUpdater.h>
#import <SignalServiceKit/NSNotificationCenter+OWS.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/PhoneNumber.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/TSStorageManager.h>

@import Contacts;

NSString *const OWSContactsManagerSignalAccountsDidChangeNotification
    = @"OWSContactsManagerSignalAccountsDidChangeNotification";

@interface OWSContactsManager () <SystemContactsFetcherDelegate>

@property (nonatomic) BOOL isContactsUpdateInFlight;
// This reflects the contents of the device phone book and includes
// contacts that do not correspond to any signal account.
@property (atomic) NSArray<Contact *> *allContacts;
@property (atomic) NSDictionary<NSString *, Contact *> *allContactsMap;
@property (atomic) NSArray<SignalAccount *> *signalAccounts;
@property (atomic) NSDictionary<NSString *, SignalAccount *> *signalAccountMap;
@property (nonatomic, readonly) SystemContactsFetcher *systemContactsFetcher;
@property (nonatomic, readonly) YapDatabaseConnection *dbReadConnection;
@property (nonatomic, readonly) YapDatabaseConnection *dbWriteConnection;

@end

@implementation OWSContactsManager

- (id)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    // TODO: We need to configure the limits of this cache.
    _avatarCache = [ImageCache new];

    _dbReadConnection = [TSStorageManager sharedManager].newDatabaseConnection;
    _dbWriteConnection = [TSStorageManager sharedManager].newDatabaseConnection;

    _allContacts = @[];
    _allContactsMap = @{};
    _signalAccountMap = @{};
    _signalAccounts = @[];
    _systemContactsFetcher = [SystemContactsFetcher new];
    _systemContactsFetcher.delegate = self;

    OWSSingletonAssert();

    return self;
}

- (void)loadSignalAccountsFromCache
{
    __block NSMutableArray<SignalAccount *> *signalAccounts;
    [self.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        signalAccounts = [[NSMutableArray alloc]
            initWithCapacity:[SignalAccount numberOfKeysInCollectionWithTransaction:transaction]];

        [SignalAccount enumerateCollectionObjectsWithTransaction:transaction
                                                      usingBlock:^(SignalAccount *signalAccount, BOOL *_Nonnull stop) {
                                                          [signalAccounts addObject:signalAccount];
                                                      }];
    }];

    [self updateSignalAccounts:signalAccounts];
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

- (void)fetchSystemContactsOnceIfAlreadyAuthorized
{
    [self.systemContactsFetcher fetchOnceIfAlreadyAuthorized];
}

- (void)fetchSystemContactsIfAlreadyAuthorizedAndAlwaysNotify
{
    [self.systemContactsFetcher fetchIfAlreadyAuthorizedAndAlwaysNotify];
}

- (BOOL)isSystemContactsAuthorized
{
    return self.systemContactsFetcher.isAuthorized;
}

- (BOOL)systemContactsHaveBeenRequestedAtLeastOnce
{
    return self.systemContactsFetcher.systemContactsHaveBeenRequestedAtLeastOnce;
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
    void (^success)(void) = ^{
        DDLogInfo(@"%@ Successfully intersected contacts.", self.logTag);
        [self buildSignalAccounts];
    };
    void (^failure)(NSError *error) = ^(NSError *error) {
        if ([error.domain isEqualToString:OWSSignalServiceKitErrorDomain]
            && error.code == OWSErrorCodeContactsUpdaterRateLimit) {
            DDLogError(@"Contact intersection hit rate limit with error: %@", error);
            return;
        }

        DDLogWarn(@"%@ Failed to intersect contacts with error: %@. Rescheduling", self.logTag, error);

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

- (void)startObserving
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(otherUsersProfileWillChange:)
                                                 name:kNSNotificationName_OtherUsersProfileWillChange
                                               object:nil];
}

- (void)otherUsersProfileWillChange:(NSNotification *)notification
{
    OWSAssert([NSThread isMainThread]);

    NSString *recipientId = notification.userInfo[kNSNotificationKey_ProfileRecipientId];
    OWSAssert(recipientId.length > 0);

    [self.avatarCache removeAllImagesForKey:recipientId];
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

            [self.avatarCache removeAllImages];

            [self intersectContacts];

            [self buildSignalAccounts];
        });
    });
}

- (void)buildSignalAccounts
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableDictionary<NSString *, SignalAccount *> *signalAccountMap = [NSMutableDictionary new];
        NSMutableArray<SignalAccount *> *signalAccounts = [NSMutableArray new];
        NSArray<Contact *> *contacts = self.allContacts;

        // We use a transaction only to load the SignalRecipients for each contact,
        // in order to avoid database deadlock.
        NSMutableDictionary<NSString *, NSArray<SignalRecipient *> *> *contactIdToSignalRecipientsMap =
            [NSMutableDictionary new];
        [self.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            for (Contact *contact in contacts) {
                NSArray<SignalRecipient *> *signalRecipients = [contact signalRecipientsWithTransaction:transaction];
                contactIdToSignalRecipientsMap[contact.uniqueId] = signalRecipients;
            }
        }];

        for (Contact *contact in contacts) {
            NSArray<SignalRecipient *> *signalRecipients = contactIdToSignalRecipientsMap[contact.uniqueId];
            for (SignalRecipient *signalRecipient in
                [signalRecipients sortedArrayUsingSelector:@selector((compare:))]) {
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
                [signalAccounts addObject:signalAccount];
            }
        }

        // Update cached SignalAccounts on disk
        [self.dbWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            NSArray<NSString *> *allKeys = [transaction allKeysInCollection:[SignalAccount collection]];
            NSMutableSet<NSString *> *orphanedKeys = [NSMutableSet setWithArray:allKeys];

            DDLogInfo(@"%@ Saving %lu SignalAccounts", self.logTag, signalAccounts.count);
            for (SignalAccount *signalAccount in signalAccounts) {
                // TODO only save the ones that changed
                [orphanedKeys removeObject:signalAccount.uniqueId];
                [signalAccount saveWithTransaction:transaction];
            }

            if (orphanedKeys.count > 0) {
                DDLogInfo(@"%@ Removing %lu orphaned SignalAccounts", self.logTag, (unsigned long)orphanedKeys.count);
                [transaction removeObjectsForKeys:orphanedKeys.allObjects inCollection:[SignalAccount collection]];
            }
        }];


        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateSignalAccounts:signalAccounts];
        });
    });
}

- (void)updateSignalAccounts:(NSArray<SignalAccount *> *)signalAccounts
{
    AssertIsOnMainThread();

    NSMutableDictionary<NSString *, SignalAccount *> *signalAccountMap = [NSMutableDictionary new];
    for (SignalAccount *signalAccount in signalAccounts) {
        signalAccountMap[signalAccount.recipientId] = signalAccount;
    }

    self.signalAccountMap = [signalAccountMap copy];
    self.signalAccounts = [signalAccounts copy];
    [self.profileManager setContactRecipientIds:signalAccountMap.allKeys];
}

// TODO dependency inject, avoid circular dependencies.
- (OWSProfileManager *)profileManager
{
    return [OWSProfileManager sharedManager];
}

- (NSString *_Nullable)cachedDisplayNameForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    SignalAccount *_Nullable signalAccount = [self signalAccountForRecipientId:recipientId];
    return signalAccount.displayName;
}

- (NSString *_Nullable)cachedFirstNameForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    SignalAccount *_Nullable signalAccount = [self signalAccountForRecipientId:recipientId];
    return signalAccount.contact.firstName;
}

- (NSString *_Nullable)cachedLastNameForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    SignalAccount *_Nullable signalAccount = [self signalAccountForRecipientId:recipientId];
    return signalAccount.contact.lastName;
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
            [[phoneNumbersWithTheSameName sortedArrayUsingSelector:@selector((compare:))] indexOfObject:recipientId];
        NSString *indexText = [OWSFormat formatInt:(int)index + 1];
        phoneNumberLabel =
            [NSString stringWithFormat:NSLocalizedString(@"PHONE_NUMBER_TYPE_AND_INDEX_NAME_FORMAT",
                                           @"Format for phone number label with an index. Embeds {{Phone number label "
                                           @"(e.g. 'home')}} and {{index, e.g. 2}}."),
                      phoneNumberLabel,
                      indexText];
    }

    return phoneNumberLabel;
}

- (BOOL)phoneNumber:(PhoneNumber *)phoneNumber1 matchesNumber:(PhoneNumber *)phoneNumber2
{
    return [phoneNumber1.toE164 isEqualToString:phoneNumber2.toE164];
}

#pragma mark - Whisper User Management

- (BOOL)hasNameInSystemContactsForRecipientId:(NSString *)recipientId
{
    return [self cachedDisplayNameForRecipientId:recipientId] != nil;
}

- (NSString *)unknownContactName
{
    return NSLocalizedString(
        @"UNKNOWN_CONTACT_NAME", @"Displayed if for some reason we can't determine a contacts phone number *or* name");
}

- (nullable NSString *)formattedProfileNameForRecipientId:(NSString *)recipientId
{
    NSString *_Nullable profileName = [self.profileManager profileNameForRecipientId:recipientId];
    if (profileName.length == 0) {
        return nil;
    }

    NSString *profileNameFormatString = NSLocalizedString(@"PROFILE_NAME_LABEL_FORMAT",
        @"Prepend a simple marker to differentiate the profile name, embeds the contact's {{profile name}}.");

    return [NSString stringWithFormat:profileNameFormatString, profileName];
}

- (nullable NSString *)profileNameForRecipientId:(NSString *)recipientId
{
    return [self.profileManager profileNameForRecipientId:recipientId];
}

- (nullable NSString *)nameFromSystemContactsForRecipientId:(NSString *)recipientId
{
    return [self cachedDisplayNameForRecipientId:recipientId];
}

- (NSString *_Nonnull)displayNameForPhoneIdentifier:(NSString *_Nullable)recipientId
{
    if (!recipientId) {
        return self.unknownContactName;
    }

    NSString *_Nullable displayName = [self nameFromSystemContactsForRecipientId:recipientId];

    // Fall back to just using their recipientId
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
        // Else, fall back to using just their recipientId
        NSString *phoneString =
            [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:recipientId];
        return [[NSAttributedString alloc] initWithString:phoneString attributes:normalFontAttributes];
    }

    // Append unique label for contacts with multiple Signal accounts
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

- (NSString *)contactOrProfileNameForPhoneIdentifier:(NSString *)recipientId
{
    // Prefer a saved name from system contacts, if available
    NSString *_Nullable savedContactName = [self cachedDisplayNameForRecipientId:recipientId];
    if (savedContactName.length > 0) {
        return savedContactName;
    }

    NSString *_Nullable profileName = [self.profileManager profileNameForRecipientId:recipientId];
    if (profileName.length > 0) {
        NSString *numberAndProfileNameFormat = NSLocalizedString(@"PROFILE_NAME_AND_PHONE_NUMBER_LABEL_FORMAT",
            @"Label text combining the phone number and profile name separated by a simple demarcation character. "
            @"Phone number should be most prominent. '%1$@' is replaced with {{phone number}} and '%2$@' is replaced "
            @"with {{profile name}}");

        NSString *numberAndProfileName =
            [NSString stringWithFormat:numberAndProfileNameFormat, recipientId, profileName];
        return numberAndProfileName;
    }

    // else fall back to recipient id
    return recipientId;
}

- (NSAttributedString *)attributedContactOrProfileNameForPhoneIdentifier:(NSString *)recipientId
{
    return [[NSAttributedString alloc] initWithString:[self contactOrProfileNameForPhoneIdentifier:recipientId]];
}

- (NSAttributedString *)attributedStringForConversationTitleWithPhoneIdentifier:(NSString *)recipientId
                                                                    primaryFont:(UIFont *)primaryFont
                                                                  secondaryFont:(UIFont *)secondaryFont
{
    // Prefer a saved name from system contacts, if available
    NSString *_Nullable savedContactName = [self cachedDisplayNameForRecipientId:recipientId];
    if (savedContactName.length > 0) {
        return [[NSAttributedString alloc] initWithString:savedContactName];
    }

    NSString *_Nullable profileName = [self.profileManager profileNameForRecipientId:recipientId];
    if (profileName.length > 0) {
        NSString *numberAndProfileNameFormat = NSLocalizedString(@"PROFILE_NAME_AND_PHONE_NUMBER_LABEL_FORMAT",
            @"Label text combining the phone number and profile name separated by a simple demarcation character. "
            @"Phone number should be most prominent. '%1$@' is replaced with {{phone number}} and '%2$@' is replaced "
            @"with {{profile name}}");

        NSString *numberAndProfileName =
            [NSString stringWithFormat:numberAndProfileNameFormat, recipientId, profileName];

        NSRange recipientIdRange = [numberAndProfileName rangeOfString:recipientId];
        NSMutableAttributedString *attributedString =
            [[NSMutableAttributedString alloc] initWithString:numberAndProfileName
                                                   attributes:@{ NSFontAttributeName : secondaryFont }];
        [attributedString addAttribute:NSFontAttributeName value:primaryFont range:recipientIdRange];

        return [attributedString copy];
    }

    // else fall back to recipient id
    return [[NSAttributedString alloc] initWithString:recipientId];
}

// TODO refactor attributed counterparts to use this as a helper method?
- (NSString *)stringForConversationTitleWithPhoneIdentifier:(NSString *)recipientId
{
    // Prefer a saved name from system contacts, if available
    NSString *_Nullable savedContactName = [self cachedDisplayNameForRecipientId:recipientId];
    if (savedContactName.length > 0) {
        return savedContactName;
    }

    NSString *formattedPhoneNumber =
        [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:recipientId];
    NSString *_Nullable profileName = [self.profileManager profileNameForRecipientId:recipientId];
    if (profileName.length > 0) {
        NSString *numberAndProfileNameFormat = NSLocalizedString(@"PROFILE_NAME_AND_PHONE_NUMBER_LABEL_FORMAT",
            @"Label text combining the phone number and profile name separated by a simple demarcation character. "
            @"Phone number should be most prominent. '%1$@' is replaced with {{phone number}} and '%2$@' is replaced "
            @"with {{profile name}}");

        NSString *numberAndProfileName =
            [NSString stringWithFormat:numberAndProfileNameFormat, formattedPhoneNumber, profileName];

        return numberAndProfileName;
    }

    // else fall back phone number
    return formattedPhoneNumber;
}

- (nullable SignalAccount *)signalAccountForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    __block SignalAccount *signalAccount = self.signalAccountMap[recipientId];

    // If contact intersection hasn't completed, it might exist on disk
    // even if it doesn't exist in memory yet.
    if (!signalAccount) {
        [self.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
            signalAccount = [SignalAccount fetchObjectWithUniqueID:recipientId transaction:transaction];
        }];
    }

    return signalAccount;
}

- (BOOL)hasSignalAccountForRecipientId:(NSString *)recipientId
{
    return [self signalAccountForRecipientId:recipientId] != nil;
}

- (UIImage *_Nullable)imageForPhoneIdentifier:(NSString *_Nullable)identifier
{
    Contact *contact = self.allContactsMap[identifier];
    if (!contact) {
        contact = [self signalAccountForRecipientId:identifier].contact;
    }

    // Prefer the contact image from the local address book if available
    UIImage *_Nullable image = contact.image;

    // Else try to use the image from their profile
    if (image == nil) {
        image = [self.profileManager profileAvatarForRecipientId:identifier];
    }

    return image;
}

- (NSString *)comparableNameForSignalAccount:(SignalAccount *)signalAccount
{
    NSString *_Nullable name;
    if (signalAccount.contact) {
        if (ABPersonGetSortOrdering() == kABPersonSortByFirstName) {
            name = signalAccount.contact.comparableNameFirstLast;
        } else {
            name = signalAccount.contact.comparableNameLastFirst;
        }
    }

    if (name.length < 1) {
        name = signalAccount.recipientId;
    }

    return name;
}

@end
