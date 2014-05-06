#import <Foundation/Foundation.h>
#import <MessageUI/MessageUI.h>
#import "PhoneNumber.h"

@interface SmsInvite : NSObject<MFMessageComposeViewControllerDelegate> {
    UIViewController* parent;
}

+(SmsInvite*) smsInviteWithParent:(UIViewController*) parent;

-(void)sendSMSInviteToNumber:(PhoneNumber *)number;

@end
