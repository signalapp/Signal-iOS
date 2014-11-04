#import "InviteContactModal.h"

#import "InviteContactsViewController.h"
#import "LocalizableText.h"
#import "SmsInvite.h"

#define CANCEL_BUTTON_INDEX 0
#define INVITE_BUTTON_INDEX 1

@implementation InviteContactModal {
    UIAlertView* alertView;
    UIViewController* parent;
    SmsInvite* smsInvite;
    PhoneNumber* phoneNumber;
}

+(InviteContactModal*) inviteContactModelWithPhoneNumber:(PhoneNumber*) phoneNumber andParentViewController:(UIViewController*) parent {
    InviteContactModal* inviteModal = [InviteContactModal new];
    inviteModal->alertView = [[UIAlertView alloc] initWithTitle:INVITE_USER_MODAL_TITLE
                                                        message:INVITE_USER_MODAL_TEXT
                                                       delegate:inviteModal
                                              cancelButtonTitle:INVITE_USER_MODAL_BUTTON_CANCEL
                                              otherButtonTitles:INVITE_USER_MODAL_BUTTON_INVITE, nil];
    inviteModal->parent = parent;
    inviteModal->phoneNumber = phoneNumber;
    return inviteModal;
}
-(void) presentModalView{
    [alertView show];
}

-(void) alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if(INVITE_BUTTON_INDEX == buttonIndex){
        smsInvite = [[SmsInvite alloc] initWithParent:parent];
        [smsInvite sendSMSInviteToNumber:phoneNumber];
    }
}






@end
