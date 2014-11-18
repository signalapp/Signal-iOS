#import "RecentCall.h"
#import "Environment.h"
#import "PropertyListPreferences+Util.h"
#import "Util.h"

static NSString *const DEFAULTS_KEY_CONTACT_ID = @"DefaultsKeyContactID";
static NSString *const DEFAULTS_KEY_PHONE_NUMBER = @"DefaultsKeyPhoneNumber";
static NSString *const DEFAULTS_KEY_CALL_TYPE = @"DefaultsKeycallType";
static NSString *const DEFAULTS_KEY_DATE = @"DefaultsKeyDate";
static NSString *const DEFAULTS_KEY_IS_ARCHIVED = @"DefaultsKeyDateIsArchived";
static NSString *const DEFAULTS_KEY_USER_NOTIFIED = @"DefaultsKeyUserNotified";

NSString *const CALL_TYPE_IMAGE_NAME_INCOMING = @"incoming_call_icon";
NSString *const CALL_TYPE_IMAGE_NAME_OUTGOING = @"outgoing_call_icon";

@interface RecentCall ()

@property (readwrite, nonatomic) RPRecentCallType callType;
@property (strong, readwrite, nonatomic) PhoneNumber *phoneNumber;
@property (strong, readwrite, nonatomic) NSDate *date;

@end

@implementation RecentCall

- (instancetype)initWithContactID:(ABRecordID)contactID
                        andNumber:(PhoneNumber*)number
                      andCallType:(RPRecentCallType)type {
    if (self = [super init]) {
        self.contactRecordID = contactID;
        self.callType        = type;
        self.date            = [NSDate date];
        self.phoneNumber     = number;
        self.userNotified    = type == RPRecentCallTypeMissed ? false : true;
    }
    
    return self;
}

#pragma mark - Serialization

- (void)encodeWithCoder:(NSCoder*)encoder {
    [encoder encodeObject:@(self.callType) forKey:DEFAULTS_KEY_CALL_TYPE];
    [encoder encodeObject:self.phoneNumber forKey:DEFAULTS_KEY_PHONE_NUMBER];
    [encoder encodeObject:@((int)self.contactRecordID) forKey:DEFAULTS_KEY_CONTACT_ID];
    [encoder encodeObject:self.date forKey:DEFAULTS_KEY_DATE];
    [encoder encodeBool:self.isArchived forKey:DEFAULTS_KEY_IS_ARCHIVED];
    [encoder encodeBool:self.userNotified forKey:DEFAULTS_KEY_USER_NOTIFIED];
}

- (instancetype)initWithCoder:(NSCoder*)decoder {
    if (self = [super init]) {
        self.callType        = (RPRecentCallType)[[decoder decodeObjectForKey:DEFAULTS_KEY_CALL_TYPE] intValue];
        self.contactRecordID = [[decoder decodeObjectForKey:DEFAULTS_KEY_CONTACT_ID] intValue];
        self.phoneNumber     = [decoder decodeObjectForKey:DEFAULTS_KEY_PHONE_NUMBER];
        self.date            = [decoder decodeObjectForKey:DEFAULTS_KEY_DATE];
        self.isArchived      = [decoder decodeBoolForKey:DEFAULTS_KEY_IS_ARCHIVED];
        self.userNotified    = [decoder decodeBoolForKey:DEFAULTS_KEY_USER_NOTIFIED];
    }
    
    return self;
}

@end
