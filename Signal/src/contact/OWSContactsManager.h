#import <Contacts/Contacts.h>
#import <Foundation/Foundation.h>
#import <SignalServiceKit/ContactsManagerProtocol.h>
#import <SignalServiceKit/PhoneNumber.h>
#import "CollapsingFutures.h"
#import "Contact.h"
#import "ObservableValue.h"

/**
 Get latest Signal contacts, and be notified when they change.
 */

#define SIGNAL_LIST_UPDATED @"Signal_AB_UPDATED"

@interface OWSContactsManager : NSObject <ContactsManagerProtocol>

@property CNContactStore * _Nullable contactStore;
@property NSCache<NSString *, UIImage *> * _Nonnull avatarCache;

- (ObservableValue * _Nonnull)getObservableContacts;

- (NSArray * _Nonnull)getContactsFromAddressBook:(ABAddressBookRef _Nonnull)addressBook;
- (Contact * _Nullable)latestContactForPhoneNumber:(PhoneNumber * _Nullable)phoneNumber;

- (void)verifyABPermission;

- (NSArray<Contact *> * _Nonnull)allContacts;
- (NSArray<Contact *> * _Nonnull)signalContacts;

- (void)doAfterEnvironmentInitSetup;

- (NSString * _Nonnull)displayNameForPhoneIdentifier:(NSString * _Nullable)identifier;
- (BOOL)nameExistsForPhoneIdentifier:(NSString * _Nullable)identifier;
- (UIImage * _Nullable)imageForPhoneIdentifier:(NSString * _Nullable)identifier;

+ (NSComparator)contactComparator;

@end
