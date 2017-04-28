//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Contacts/Contacts.h>
#import <Foundation/Foundation.h>
#import <SignalServiceKit/ContactsManagerProtocol.h>
#import <SignalServiceKit/PhoneNumber.h>
#import "CollapsingFutures.h"
#import "Contact.h"
#import "ObservableValue.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const OWSContactsManagerSignalRecipientsDidChangeNotification;

@class UIFont;
@class ContactAccount;

/**
 * Get latest Signal contacts, and be notified when they change.
 */
@interface OWSContactsManager : NSObject <ContactsManagerProtocol>

@property (nullable, strong) CNContactStore *contactStore;
@property (nonnull, readonly, strong) NSCache<NSString *, UIImage *> *avatarCache;

- (nonnull ObservableValue *)getObservableContacts;

- (nonnull NSArray *)getContactsFromAddressBook:(nonnull ABAddressBookRef)addressBook;
- (nullable Contact *)latestContactForPhoneNumber:(nullable PhoneNumber *)phoneNumber;
- (nullable Contact *)contactForPhoneIdentifier:(nullable NSString *)identifier;
- (Contact *)getOrBuildContactForPhoneIdentifier:(NSString *)identifier;

- (void)verifyABPermission;

- (NSArray<Contact *> *)allContacts;
- (NSArray<Contact *> *)signalContacts;

- (void)doAfterEnvironmentInitSetup;

- (NSString *)displayNameForPhoneIdentifier:(nullable NSString *)identifier;
- (NSString *)displayNameForContact:(Contact *)contact;
- (NSString *_Nonnull)displayNameForContactAccount:(ContactAccount *)contactAccount;
- (nullable UIImage *)imageForPhoneIdentifier:(nullable NSString *)identifier;
- (NSAttributedString *)formattedFullNameForContact:(Contact *)contact font:(UIFont *)font;
- (NSAttributedString *)formattedFullNameForRecipientId:(NSString *)recipientId font:(UIFont *)font;

- (BOOL)hasAddressBook;

+ (NSComparator _Nonnull)contactComparator;

@end

NS_ASSUME_NONNULL_END
