#import <AddressBook/AddressBook.h>
#import <Foundation/Foundation.h>
#import <TextSecureKit/TSCall.h>
#import "Contact.h"
#import "ContactsManager.h"
#import "PhoneNumber.h"

/**
 *
 * RecentCall is used for storing a call history with information about
 * who (person), what (phone number), when (date) and why (type)
 * The object is serialized in a list and managed by RecentCallManager.
 *
 */


extern NSString *const CALL_TYPE_IMAGE_NAME_INCOMING;
extern NSString *const CALL_TYPE_IMAGE_NAME_OUTGOING;

@interface RecentCall : NSObject

@property (nonatomic, readonly) ABRecordID contactRecordID;
@property (nonatomic, readonly) PhoneNumber *phoneNumber;
@property (nonatomic, readonly) RPRecentCallType callType;
@property (nonatomic, readonly) NSDate *date;
@property (nonatomic) BOOL isArchived;
@property (nonatomic) BOOL userNotified;

+ (RecentCall *)recentCallWithContactID:(ABRecordID)contactID
                              andNumber:(PhoneNumber *)number
                            andCallType:(RPRecentCallType)type;

- (void)updateRecentCallWithContactId:(ABRecordID)contactID;
@end
