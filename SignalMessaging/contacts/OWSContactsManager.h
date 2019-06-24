//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/Contact.h>
#import <SignalServiceKit/ContactsManagerProtocol.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const OWSContactsManagerSignalAccountsDidChangeNotification;

@class ImageCache;
@class OWSPrimaryStorage;
@class SDSKeyValueStore;
@class SignalAccount;
@class SignalServiceAddress;
@class UIFont;

/**
 * Get latest Signal contacts, and be notified when they change.
 */
@interface OWSContactsManager : NSObject <ContactsManagerProtocol>

#pragma mark - Setup

- (instancetype)init NS_UNAVAILABLE;

- (id)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage;

#pragma mark - Accessors

@property (nonatomic, readonly) SDSKeyValueStore *keyValueStore;

@property (nonnull, readonly) ImageCache *avatarCache;

@property (atomic, readonly) NSArray<Contact *> *allContacts;

@property (atomic, readonly) NSDictionary<NSString *, Contact *> *allContactsMap;

// order of the signalAccounts array respects the systems contact sorting preference
@property (atomic, readonly) NSArray<SignalAccount *> *signalAccounts;

// This will return an instance of SignalAccount for _known_ signal accounts.
- (nullable SignalAccount *)fetchSignalAccountForSignalServiceAddress:(SignalServiceAddress *)address;
// This will always return an instance of SignalAccount.
- (SignalAccount *)fetchOrBuildSignalAccountForSignalServiceAddress:(SignalServiceAddress *)address;
- (BOOL)hasSignalAccountForSignalServiceAddress:(SignalServiceAddress *)address;

#pragma mark - System Contact Fetching

// Must call `requestSystemContactsOnce` before accessing this method
@property (nonatomic, readonly) BOOL isSystemContactsAuthorized;
@property (nonatomic, readonly) BOOL isSystemContactsDenied;
@property (nonatomic, readonly) BOOL systemContactsHaveBeenRequestedAtLeastOnce;

@property (nonatomic, readonly) BOOL supportsContactEditing;

@property (atomic, readonly) BOOL isSetup;

// Request systems contacts and start syncing changes. The user will see an alert
// if they haven't previously.
- (void)requestSystemContactsOnce;
- (void)requestSystemContactsOnceWithCompletion:(void (^_Nullable)(NSError *_Nullable error))completion;

// Ensure's the app has the latest contacts, but won't prompt the user for contact
// access if they haven't granted it.
- (void)fetchSystemContactsOnceIfAlreadyAuthorized;

// This variant will fetch system contacts if contact access has already been granted,
// but not prompt for contact access. Also, it will always notify delegates, even if
// contacts haven't changed, and will clear out any stale cached SignalAccounts
- (void)userRequestedSystemContactsRefreshWithCompletion:(void (^)(NSError *_Nullable error))completionHandler;

#pragma mark - Util

- (BOOL)isSystemContact:(NSString *)phoneNumber;
- (BOOL)isSystemContactWithSignalAccount:(NSString *)phoneNumber;
- (BOOL)hasNameInSystemContactsForSignalServiceAddress:(SignalServiceAddress *)address;
- (NSString *)displayNameForSignalAccount:(SignalAccount *)signalAccount;

/**
 * Used for sorting, respects system contacts name sort order preference.
 */
- (NSString *)comparableNameForSignalAccount:(SignalAccount *)signalAccount;

// Generally we prefer the formattedProfileName over the raw profileName so as to
// distinguish a profile name apart from a name pulled from the system's contacts.
// This helps clarify when the remote person chooses a potentially confusing profile name.
- (nullable NSString *)formattedProfileNameForSignalServiceAddress:(SignalServiceAddress *)address;
- (nullable NSString *)profileNameForSignalServiceAddress:(SignalServiceAddress *)address;
- (nullable NSString *)nameFromSystemContactsForSignalServiceAddress:(SignalServiceAddress *)address;

- (nullable UIImage *)systemContactImageForSignalServiceAddress:(nullable SignalServiceAddress *)address;
- (nullable UIImage *)profileImageForSignalServiceAddress:(nullable SignalServiceAddress *)address;
- (nullable NSData *)profileImageDataForSignalServiceAddress:(nullable SignalServiceAddress *)address;

- (nullable UIImage *)imageForSignalServiceAddress:(nullable SignalServiceAddress *)address;
- (NSAttributedString *)formattedDisplayNameForSignalAccount:(SignalAccount *)signalAccount font:(UIFont *)font;
- (NSAttributedString *)formattedFullNameForSignalServiceAddress:(SignalServiceAddress *)address font:(UIFont *)font;
- (NSString *)contactOrProfileNameForSignalServiceAddress:(SignalServiceAddress *)address;
- (NSAttributedString *)attributedContactOrProfileNameForSignalServiceAddress:(SignalServiceAddress *)address;
- (NSAttributedString *)attributedContactOrProfileNameForSignalServiceAddress:(SignalServiceAddress *)address
                                                                  primaryFont:(UIFont *)primaryFont
                                                                secondaryFont:(UIFont *)secondaryFont;
- (NSAttributedString *)attributedContactOrProfileNameForSignalServiceAddress:(SignalServiceAddress *)address
                                                            primaryAttributes:(NSDictionary *)primaryAttributes
                                                          secondaryAttributes:(NSDictionary *)secondaryAttributes;
@end

NS_ASSUME_NONNULL_END
