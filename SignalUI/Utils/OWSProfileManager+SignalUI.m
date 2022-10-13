//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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

    NSString *shareTitle = OWSLocalizedString(@"CONVERSATION_SETTINGS_VIEW_SHARE_PROFILE",
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

    [OWSProfileManager.shared addThreadToProfileWhitelist:thread];

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        OWSProfileKeyMessage *message = [[OWSProfileKeyMessage alloc] initWithThread:thread transaction:transaction];
        [self.messageSenderJobQueue addMessage:message.asPreparer transaction:transaction];
    });
}

@end

NS_ASSUME_NONNULL_END
