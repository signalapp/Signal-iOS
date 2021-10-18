//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSProfileManager+SignalUI.h"
#import <SignalUI/SignalUI-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSProfileManager (SignalUI)

- (void)presentAddThreadToProfileWhitelist:(TSThread *)thread
                        fromViewController:(UIViewController *)fromViewController
                                   success:(void (^)(void))successHandler
{
    OWSAssertIsOnMainThread();

    ActionSheetController *actionSheet = [[ActionSheetController alloc] init];

    NSString *shareTitle = NSLocalizedString(@"CONVERSATION_SETTINGS_VIEW_SHARE_PROFILE",
        @"Button to confirm that user wants to share their profile with a user or group.");
    [actionSheet
        addAction:[[ActionSheetAction alloc] initWithTitle:shareTitle
                                   accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"share_profile")
                                                     style:ActionSheetActionStyleDefault
                                                   handler:^(ActionSheetAction *_Nonnull action) {
                                                       [self userAddedThreadToProfileWhitelist:thread];
                                                       successHandler();
                                                   }]];
    [actionSheet addAction:[OWSActionSheets cancelAction]];

    [fromViewController presentActionSheet:actionSheet];
}

- (void)userAddedThreadToProfileWhitelist:(TSThread *)thread
{
    OWSAssertIsOnMainThread();

    BOOL isFeatureEnabled = NO;
    if (!isFeatureEnabled) {
        OWSLogWarn(@"skipping sending profile-key message because the feature is not yet fully available.");
        [OWSProfileManager.shared addThreadToProfileWhitelist:thread];
        return;
    }

    OWSProfileKeyMessage *message = [[OWSProfileKeyMessage alloc] initWithThread:thread];
    [OWSProfileManager.shared addThreadToProfileWhitelist:thread];

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.messageSenderJobQueue addMessage:message.asPreparer transaction:transaction];
    });
}

@end

NS_ASSUME_NONNULL_END
