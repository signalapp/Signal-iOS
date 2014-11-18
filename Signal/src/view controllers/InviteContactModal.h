#import <Foundation/Foundation.h>
#import "PhoneNumber.h"

@interface InviteContactModal : NSObject <UIAlertViewDelegate>

- (instancetype)initWithPhoneNumber:(PhoneNumber*)phoneNumber
            andParentViewController:(UIViewController*)parent;
- (void)presentModalView;

@end
