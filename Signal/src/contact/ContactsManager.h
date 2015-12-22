#import <Contacts/Contacts.h>
#import <Foundation/Foundation.h>
#import <TextSecureKit/ContactsManagerProtocol.h>
#import <TextSecureKit/PhoneNumber.h>
#import "CollapsingFutures.h"
#import "Contact.h"
#import "ObservableValue.h"

/**
 *
 * ContactsManager provides access to an updated list of contacts with optional categorizations -
 * such as searching and favourite-attributed contacts (favourites are also managed through this class)
 * Others can subscribe for contact and/or favourite updates
 * Contacts can be grouped by first letter into an NSDictionary in order to display in individual sections-
 * in the ContactBrowseViewController.
 *
 */

#define SIGNAL_LIST_UPDATED @"Signal_AB_UPDATED"

typedef void (^ABAccessRequestCompletionBlock)(BOOL hasAccess);
typedef void (^ABReloadRequestCompletionBlock)(NSArray *contacts);

@interface ContactsManager : NSObject <ContactsManagerProtocol> {
   @private
    TOCFuture *futureAddressBook;
   @private
    ObservableValueController *observableContactsController;
   @private
    TOCCancelTokenSource *life;
   @private
    NSDictionary *latestContactsById;
   @private
    NSDictionary *latestWhisperUsersById;
}

@property CNContactStore *contactStore;

- (ObservableValue *)getObservableContacts;

- (NSArray *)getContactsFromAddressBook:(ABAddressBookRef)addressBook;
- (Contact *)latestContactWithRecordId:(ABRecordID)recordId;
- (Contact *)latestContactForPhoneNumber:(PhoneNumber *)phoneNumber;
- (NSArray *)latestContactsWithSearchString:(NSString *)searchString;

+ (NSDictionary *)groupContactsByFirstLetter:(NSArray *)contacts matchingSearchString:(NSString *)optionalSearchString;

- (void)verifyABPermission;

- (NSArray<Contact *> *)allContacts;
- (NSArray *)signalContacts;
- (NSArray *)textSecureContacts;

- (void)doAfterEnvironmentInitSetup;

- (NSString *)nameStringForPhoneIdentifier:(NSString *)identifier;
- (UIImage *)imageForPhoneIdentifier:(NSString *)identifier;

+ (NSComparator)contactComparator;

@end
