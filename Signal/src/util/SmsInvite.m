#import "SmsInvite.h"
#import "LocalizableText.h"

@interface SmsInvite ()

@property (strong, nonatomic, readwrite) UIViewController* parent;

@end

@implementation SmsInvite
    
+ (SmsInvite*)smsInviteWithParent:(UIViewController*)parent {
    return [[SmsInvite alloc] initWithParent:parent];
}

- (instancetype)initWithParent:(UIViewController*)parent {
    if (self = [super init]) {
        self.parent = parent;
    }
    return self;
}

- (UIViewController*)parent {
    if (!_parent) {
        _parent = [[UIViewController alloc] init];
    }
    return _parent;
}

- (void)sendSMSInviteToNumber:(PhoneNumber*)number{
    if (MFMessageComposeViewController.canSendText && [UIDevice.currentDevice.model isEqualToString:@"iPhone"]){
        MFMessageComposeViewController* messageController = [MFMessageComposeViewController new];
        
        NSString* inviteMessage = INVITE_USERS_MESSAGE;
        
        messageController.body = [inviteMessage stringByAppendingString:@" https://itunes.apple.com/app/id874139669"];
        messageController.recipients = @[number.toE164];
        messageController.messageComposeDelegate = self;
        
        [self.parent presentViewController:messageController
                                  animated:YES
                                completion:nil];
    }
}

- (void)messageComposeViewController:(MFMessageComposeViewController*)controller
                 didFinishWithResult:(MessageComposeResult)result {
    [controller dismissViewControllerAnimated:YES
                                   completion:nil];
}

@end
