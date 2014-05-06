#import <Foundation/Foundation.h>

#import "PhoneNumber.h"

@interface InviteContactModal : NSObject<UIAlertViewDelegate>

+(InviteContactModal*) inviteContactModelWithPhoneNumber:(PhoneNumber*) phoneNumber andParentViewController:(UIViewController*) parent;
-(void) presentModalView;

@end
