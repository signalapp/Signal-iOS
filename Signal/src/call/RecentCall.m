#import "RecentCall.h"

static NSString *const DEFAULTS_KEY_CONTACT_ID    = @"DefaultsKeyContactID";
static NSString *const DEFAULTS_KEY_PHONE_NUMBER  = @"DefaultsKeyPhoneNumber";
static NSString *const DEFAULTS_KEY_CALL_TYPE     = @"DefaultsKeycallType";
static NSString *const DEFAULTS_KEY_DATE          = @"DefaultsKeyDate";
static NSString *const DEFAULTS_KEY_IS_ARCHIVED   = @"DefaultsKeyDateIsArchived";
static NSString *const DEFAULTS_KEY_USER_NOTIFIED = @"DefaultsKeyUserNotified";

NSString *const CALL_TYPE_IMAGE_NAME_INCOMING = @"incoming_call_icon";
NSString *const CALL_TYPE_IMAGE_NAME_OUTGOING = @"outgoing_call_icon";

@implementation RecentCall

@synthesize contactRecordID, callType, date, phoneNumber, isArchived, userNotified;

+ (RecentCall *)recentCallWithContactID:(ABRecordID)contactID
                              andNumber:(PhoneNumber *)number
                            andCallType:(RPRecentCallType)type {
    RecentCall *recentCall      = [RecentCall new];
    recentCall->contactRecordID = contactID;
    recentCall->callType        = type;
    recentCall->date            = [NSDate date];
    recentCall->phoneNumber     = number;
    recentCall->userNotified    = type == RPRecentCallTypeMissed ? false : true;
    return recentCall;
}
- (void)updateRecentCallWithContactId:(ABRecordID)contactID {
    contactRecordID = contactID;
}

#pragma mark - Serialization

- (void)encodeWithCoder:(NSCoder *)encoder {
    [encoder encodeObject:@(callType) forKey:DEFAULTS_KEY_CALL_TYPE];
    [encoder encodeObject:phoneNumber forKey:DEFAULTS_KEY_PHONE_NUMBER];
    [encoder encodeObject:@((int)contactRecordID) forKey:DEFAULTS_KEY_CONTACT_ID];
    [encoder encodeObject:date forKey:DEFAULTS_KEY_DATE];
    [encoder encodeBool:isArchived forKey:DEFAULTS_KEY_IS_ARCHIVED];
    [encoder encodeBool:userNotified forKey:DEFAULTS_KEY_USER_NOTIFIED];
}

- (id)initWithCoder:(NSCoder *)decoder {
    if ((self = [super init])) {
        callType        = (RPRecentCallType)[[decoder decodeObjectForKey:DEFAULTS_KEY_CALL_TYPE] intValue];
        contactRecordID = [[decoder decodeObjectForKey:DEFAULTS_KEY_CONTACT_ID] intValue];
        phoneNumber     = [decoder decodeObjectForKey:DEFAULTS_KEY_PHONE_NUMBER];
        date            = [decoder decodeObjectForKey:DEFAULTS_KEY_DATE];
        isArchived      = [decoder decodeBoolForKey:DEFAULTS_KEY_IS_ARCHIVED];
        userNotified    = [decoder decodeBoolForKey:DEFAULTS_KEY_USER_NOTIFIED];
    }
    return self;
}

@end
