#import <Foundation/Foundation.h>
#import <AddressBook/AddressBook.h>
#import "PhoneNumber.h"
#import "ContactsManager.h"
#import "Contact.h"

/**
 *
 * RecentCall is used for storing a call history with information about
 * who (person), what (phone number), when (date) and why (type)
 * The object is serialized in a list and managed by RecentCallManager.
 *
 */

typedef NS_ENUM(NSInteger, RPRecentCallType) {
    RPRecentCallTypeIncoming = 1,
    RPRecentCallTypeOutgoing,
    RPRecentCallTypeMissed
};

extern NSString* const CALL_TYPE_IMAGE_NAME_INCOMING;
extern NSString* const CALL_TYPE_IMAGE_NAME_OUTGOING;

@interface RecentCall : NSObject

@property (readonly, nonatomic) RPRecentCallType callType;
@property (strong, readonly, nonatomic) PhoneNumber *phoneNumber;
@property (strong, readonly, nonatomic) NSDate *date;
@property (nonatomic) BOOL isArchived;
@property (nonatomic) BOOL userNotified;

@property (nonatomic, setter=updateRecentCallWithContactID:) ABRecordID contactRecordID;

- (instancetype)initWithContactID:(ABRecordID)contactID
                        andNumber:(PhoneNumber*)number
                      andCallType:(RPRecentCallType)type;

@end
