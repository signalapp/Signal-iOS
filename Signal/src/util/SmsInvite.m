#import "SmsInvite.h"

#import "LocalizableText.h"

@implementation SmsInvite
    
+ (SmsInvite*) smsInviteWithParent:(UIViewController *)parent {
    SmsInvite* invite = [SmsInvite new];
    invite->parent = parent;
    return invite;
}

- (void)sendSMSInviteToNumber:(PhoneNumber *)number{
    if ([MFMessageComposeViewController canSendText] && [[UIDevice currentDevice].model isEqualToString:@"iPhone"]){
        MFMessageComposeViewController *messageController = [MFMessageComposeViewController new];
        
        NSString *inviteMessage = INVITE_USERS_MESSAGE;
        
        messageController.body = [inviteMessage stringByAppendingString:@" https://itunes.apple.com/app/id874139669"];
        messageController.recipients = @[[number toE164]];
        messageController.messageComposeDelegate = self;
        
        [parent presentViewController:messageController
                             animated:YES
                           completion:nil];
    }
}

- (void)messageComposeViewController:(MFMessageComposeViewController *)controller didFinishWithResult:(MessageComposeResult)result {
    [controller dismissViewControllerAnimated:YES
                                   completion:nil];
}


@end
