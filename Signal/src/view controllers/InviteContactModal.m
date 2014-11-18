#import "InviteContactModal.h"
#import "InviteContactsViewController.h"
#import "LocalizableText.h"
#import "SMSInvite.h"

#define CANCEL_BUTTON_INDEX 0
#define INVITE_BUTTON_INDEX 1

@interface InviteContactModal ()

@property (strong, nonatomic) UIAlertView* alertView;
@property (strong, nonatomic) UIViewController* parent;
@property (strong, nonatomic) SMSInvite* smsInvite;
@property (strong, nonatomic) PhoneNumber* phoneNumber;

@end

@implementation InviteContactModal

- (instancetype)initWithPhoneNumber:(PhoneNumber*)phoneNumber
            andParentViewController:(UIViewController*)parent {
    if (self = [super init]) {
#warning Deprecated method
        self.alertView = [[UIAlertView alloc] initWithTitle:INVITE_USER_MODAL_TITLE
                                                    message:INVITE_USER_MODAL_TEXT
                                                   delegate:self
                                          cancelButtonTitle:INVITE_USER_MODAL_BUTTON_CANCEL
                                          otherButtonTitles:INVITE_USER_MODAL_BUTTON_INVITE, nil];
        self.parent = parent;
        self.phoneNumber = phoneNumber;
    }
    
    return self;
}

- (void)presentModalView {
    [self.alertView show];
}

- (void)alertView:(UIAlertView*)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (INVITE_BUTTON_INDEX == buttonIndex) {
        self.smsInvite = [[SMSInvite alloc] initWithParent:self.parent];
        [self.smsInvite sendSMSInviteToNumber:self.phoneNumber];
    }
}

@end
