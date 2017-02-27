//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "UIViewController+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@implementation UIViewController (OWS)

- (UIBarButtonItem *)createOWSBackButton
{
    UIImage *backImage = [UIImage imageNamed:@"NavBarBack"];
    OWSAssert(backImage);
    UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithImage:backImage
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(backButtonPressed:)];
    return backItem;
}

- (void)useOWSBackButton
{
    self.navigationItem.leftBarButtonItem = [self createOWSBackButton];
}

#pragma mark - Event Handling

- (void)backButtonPressed:(id)sender {
    [self.navigationController popViewControllerAnimated:YES];
}

@end

NS_ASSUME_NONNULL_END
