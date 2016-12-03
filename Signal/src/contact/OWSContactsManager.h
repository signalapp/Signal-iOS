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

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactsManager : NSObject <ContactsManagerProtocol>

@property (nullable, strong) CNContactStore *contactStore;
@property (readonly, nonatomic, strong) NSCache<NSString *, UIImage *> *avatarCache;

- (ObservableValue *)getObservableContacts;

- (NSArray *)getContactsFromAddressBook:(ABAddressBookRef)addressBook;
- (nullable Contact *)latestContactForPhoneNumber:(nullable PhoneNumber *)phoneNumber;

- (void)verifyABPermission;

- (NSArray<Contact *> *)allContacts;
- (NSArray<Contact *> *)signalContacts;

- (void)doAfterEnvironmentInitSetup;

- (NSString *)displayNameForPhoneIdentifier:(nullable NSString *)identifier;
- (BOOL)nameExistsForPhoneIdentifier:(nullable NSString *)identifier;
- (nullable UIImage *)imageForPhoneIdentifier:(nullable NSString *)identifier;

+ (NSComparator)contactComparator;

@end

NS_ASSUME_NONNULL_END
