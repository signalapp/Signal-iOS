//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "BlockListUIUtils.h"
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalServiceKit/Contact.h>
#import <SignalServiceKit/PhoneNumber.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalUI/SignalUI-Swift.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^BlockAlertCompletionBlock)(ActionSheetAction *action);

@implementation BlockListUIUtils

#pragma mark - Block

+ (void)showBlockThreadActionSheet:(TSThread *)thread
                fromViewController:(UIViewController *)fromViewController
                   completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        [self showBlockAddressActionSheet:contactThread.contactAddress
                       fromViewController:fromViewController
                          completionBlock:completionBlock];
    } else if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        [self showBlockGroupActionSheet:groupThread
                     fromViewController:fromViewController
                        completionBlock:completionBlock];
    } else {
        OWSFailDebug(@"unexpected thread type: %@", thread.class);
    }
}

+ (void)showBlockAddressActionSheet:(SignalServiceAddress *)address
                 fromViewController:(UIViewController *)fromViewController
                    completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    NSString *displayName = [self.contactsManager displayNameForAddress:address];
    [self showBlockAddressesActionSheet:@[ address ]
                            displayName:displayName
                     fromViewController:fromViewController
                        completionBlock:completionBlock];
}

+ (void)showBlockAddressesActionSheet:(NSArray<SignalServiceAddress *> *)addresses
                          displayName:(NSString *)displayName
                   fromViewController:(UIViewController *)fromViewController
                      completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    OWSAssertDebug(addresses.count > 0);
    OWSAssertDebug(displayName.length > 0);
    OWSAssertDebug(fromViewController);

    for (SignalServiceAddress *address in addresses) {
        OWSAssertDebug(address.isValid);

        if (address.isLocalAddress) {
            [self showOkAlertWithTitle:OWSLocalizedString(@"BLOCK_LIST_VIEW_CANT_BLOCK_SELF_ALERT_TITLE",
                                           @"The title of the 'You can't block yourself' alert.")
                               message:OWSLocalizedString(@"BLOCK_LIST_VIEW_CANT_BLOCK_SELF_ALERT_MESSAGE",
                                           @"The message of the 'You can't block yourself' alert.")
                    fromViewController:fromViewController
                       completionBlock:^(ActionSheetAction *action) {
                           if (completionBlock) {
                               completionBlock(NO);
                           }
                       }];
            return;
        }
    }

    NSString *title = [NSString stringWithFormat:OWSLocalizedString(@"BLOCK_LIST_BLOCK_USER_TITLE_FORMAT",
                                                     @"A format for the 'block user' action sheet title. Embeds {{the "
                                                     @"blocked user's name or phone number}}."),
                                [self formatDisplayNameForAlertTitle:displayName]];

    ActionSheetController *actionSheet = [[ActionSheetController alloc]
        initWithTitle:title
              message:OWSLocalizedString(@"BLOCK_USER_BEHAVIOR_EXPLANATION",
                          @"An explanation of the consequences of blocking another user.")];

    ActionSheetAction *blockAction = [[ActionSheetAction alloc]
                  initWithTitle:OWSLocalizedString(@"BLOCK_LIST_BLOCK_BUTTON", @"Button label for the 'block' button")
        accessibilityIdentifier:@"BlockListUIUtils.block"
                          style:ActionSheetActionStyleDestructive
                        handler:^(ActionSheetAction *_Nonnull action) {
                            [self blockAddresses:addresses
                                       displayName:displayName
                                fromViewController:fromViewController
                                   completionBlock:^(ActionSheetAction *ignore) {
                                       if (completionBlock) {
                                           completionBlock(YES);
                                       }
                                   }];
                        }];
    [actionSheet addAction:blockAction];

    ActionSheetAction *dismissAction = [[ActionSheetAction alloc] initWithTitle:CommonStrings.cancelButton
                                                        accessibilityIdentifier:@"BlockListUIUtils.dismiss"
                                                                          style:ActionSheetActionStyleCancel
                                                                        handler:^(ActionSheetAction *_Nonnull action) {
                                                                            if (completionBlock) {
                                                                                completionBlock(NO);
                                                                            }
                                                                        }];
    [actionSheet addAction:dismissAction];
    [fromViewController presentActionSheet:actionSheet];
}

+ (void)showBlockGroupActionSheet:(TSGroupThread *)groupThread
               fromViewController:(UIViewController *)fromViewController
                  completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    OWSAssertDebug(groupThread);
    OWSAssertDebug(fromViewController);

    NSString *title = [NSString
        stringWithFormat:OWSLocalizedString(@"BLOCK_LIST_BLOCK_GROUP_TITLE_FORMAT",
                             @"A format for the 'block group' action sheet title. Embeds the {{group name}}."),
        [self formatDisplayNameForAlertTitle:groupThread.groupNameOrDefault]];

    ActionSheetController *actionSheet =
        [[ActionSheetController alloc] initWithTitle:title
                                             message:OWSLocalizedString(@"BLOCK_GROUP_BEHAVIOR_EXPLANATION",
                                                         @"An explanation of the consequences of blocking a group.")];

    ActionSheetAction *blockAction = [[ActionSheetAction alloc]
                  initWithTitle:OWSLocalizedString(@"BLOCK_LIST_BLOCK_BUTTON", @"Button label for the 'block' button")
        accessibilityIdentifier:@"BlockListUIUtils.block"
                          style:ActionSheetActionStyleDestructive
                        handler:^(ActionSheetAction *_Nonnull action) {
                            [self blockGroup:groupThread
                                fromViewController:fromViewController
                                   completionBlock:^(ActionSheetAction *ignore) {
                                       if (completionBlock) {
                                           completionBlock(YES);
                                       }
                                   }];
                        }];
    [actionSheet addAction:blockAction];

    ActionSheetAction *dismissAction = [[ActionSheetAction alloc] initWithTitle:CommonStrings.cancelButton
                                                        accessibilityIdentifier:@"BlockListUIUtils.dismiss"
                                                                          style:ActionSheetActionStyleCancel
                                                                        handler:^(ActionSheetAction *_Nonnull action) {
                                                                            if (completionBlock) {
                                                                                completionBlock(NO);
                                                                            }
                                                                        }];
    [actionSheet addAction:dismissAction];
    [fromViewController presentActionSheet:actionSheet];
}

+ (void)blockAddresses:(NSArray<SignalServiceAddress *> *)addresses
           displayName:(NSString *)displayName
    fromViewController:(UIViewController *)fromViewController
       completionBlock:(BlockAlertCompletionBlock)completionBlock
{
    OWSAssertDebug(addresses.count > 0);
    OWSAssertDebug(displayName.length > 0);
    OWSAssertDebug(fromViewController);

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        for (SignalServiceAddress *address in addresses) {
            OWSAssertDebug(address.isValid);
            [self.blockingManager addBlockedAddress:address
                                          blockMode:BlockModeLocalShouldLeaveGroups
                                        transaction:transaction];
        }
    });

    [self showOkAlertWithTitle:OWSLocalizedString(
                                   @"BLOCK_LIST_VIEW_BLOCKED_ALERT_TITLE", @"The title of the 'user blocked' alert.")
                       message:[NSString
                                   stringWithFormat:OWSLocalizedString(@"BLOCK_LIST_VIEW_BLOCKED_ALERT_MESSAGE_FORMAT",
                                                        @"The message format of the 'conversation blocked' alert. "
                                                        @"Embeds the {{conversation title}}."),
                                   [self formatDisplayNameForAlertMessage:displayName]]
            fromViewController:fromViewController
               completionBlock:completionBlock];
}

+ (void)blockGroup:(TSGroupThread *)groupThread
    fromViewController:(UIViewController *)fromViewController
       completionBlock:(BlockAlertCompletionBlock)completionBlock
{
    OWSAssertDebug(groupThread);
    OWSAssertDebug(fromViewController);

    if (!groupThread.isLocalUserMemberOfAnyKind) {
        [self blockGroupStep2:groupThread fromViewController:fromViewController completionBlock:completionBlock];
        return;
    }

    [GroupManager leaveGroupOrDeclineInviteAsyncWithUIWithGroupThread:groupThread
                                                   fromViewController:fromViewController
                                                 replacementAdminUuid:nil
                                                              success:^{
                                                                  [self blockGroupStep2:groupThread
                                                                      fromViewController:fromViewController
                                                                         completionBlock:completionBlock];
                                                              }];
}

+ (void)blockGroupStep2:(TSGroupThread *)groupThread
     fromViewController:(UIViewController *)fromViewController
        completionBlock:(BlockAlertCompletionBlock)completionBlock
{
    OWSAssertDebug(groupThread);
    OWSAssertDebug(fromViewController);

    // block the group regardless of the ability to deliver the
    // "leave group" message.
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.blockingManager addBlockedGroupWithGroupModel:groupThread.groupModel
                                                  blockMode:BlockModeLocalShouldLeaveGroups
                                                transaction:transaction];
    });

    NSString *alertTitle
        = OWSLocalizedString(@"BLOCK_LIST_VIEW_BLOCKED_GROUP_ALERT_TITLE", @"The title of the 'group blocked' alert.");
    NSString *alertBodyFormat = OWSLocalizedString(@"BLOCK_LIST_VIEW_BLOCKED_ALERT_MESSAGE_FORMAT",
        @"The message format of the 'conversation blocked' alert. "
        @"Embeds the "
        @"{{conversation title}}.");
    NSString *alertBody = [NSString
        stringWithFormat:alertBodyFormat, [self formatDisplayNameForAlertMessage:groupThread.groupNameOrDefault]];

    [self showOkAlertWithTitle:alertTitle
                       message:alertBody
            fromViewController:fromViewController
               completionBlock:completionBlock];
}

#pragma mark - Unblock

+ (void)showUnblockThreadActionSheet:(TSThread *)thread
                  fromViewController:(UIViewController *)fromViewController
                     completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        [self showUnblockAddressActionSheet:contactThread.contactAddress
                         fromViewController:fromViewController
                            completionBlock:completionBlock];
    } else if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        [self showUnblockGroupActionSheet:groupThread.groupModel
                       fromViewController:fromViewController
                          completionBlock:completionBlock];
    } else {
        OWSFailDebug(@"unexpected thread type: %@", thread.class);
    }
}

+ (void)showUnblockAddressActionSheet:(SignalServiceAddress *)address
                   fromViewController:(UIViewController *)fromViewController
                      completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    NSString *displayName = [self.contactsManager displayNameForAddress:address];
    [self showUnblockAddressesActionSheet:@[ address ]
                              displayName:displayName
                       fromViewController:fromViewController
                          completionBlock:completionBlock];
}

+ (void)showUnblockAddressesActionSheet:(NSArray<SignalServiceAddress *> *)addresses
                            displayName:(NSString *)displayName
                     fromViewController:(UIViewController *)fromViewController
                        completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    OWSAssertDebug(addresses.count > 0);
    OWSAssertDebug(displayName.length > 0);
    OWSAssertDebug(fromViewController);

    NSString *title = [NSString
        stringWithFormat:
                           OWSLocalizedString(@"BLOCK_LIST_UNBLOCK_TITLE_FORMAT",
                @"A format for the 'unblock conversation' action sheet title. Embeds the {{conversation title}}."),
        [self formatDisplayNameForAlertTitle:displayName]];

    ActionSheetController *actionSheet = [[ActionSheetController alloc] initWithTitle:title message:nil];

    ActionSheetAction *unblockAction =
        [[ActionSheetAction alloc] initWithTitle:OWSLocalizedString(@"BLOCK_LIST_UNBLOCK_BUTTON",
                                                     @"Button label for the 'unblock' button")
                         accessibilityIdentifier:@"BlockListUIUtils.unblock"
                                           style:ActionSheetActionStyleDestructive
                                         handler:^(ActionSheetAction *_Nonnull action) {
                                             [BlockListUIUtils unblockAddresses:addresses
                                                                    displayName:displayName
                                                             fromViewController:fromViewController
                                                                completionBlock:^(ActionSheetAction *ignore) {
                                                                    if (completionBlock) {
                                                                        completionBlock(NO);
                                                                    }
                                                                }];
                                         }];
    [actionSheet addAction:unblockAction];

    ActionSheetAction *dismissAction = [[ActionSheetAction alloc] initWithTitle:CommonStrings.cancelButton
                                                        accessibilityIdentifier:@"BlockListUIUtils.dismiss"
                                                                          style:ActionSheetActionStyleCancel
                                                                        handler:^(ActionSheetAction *_Nonnull action) {
                                                                            if (completionBlock) {
                                                                                completionBlock(YES);
                                                                            }
                                                                        }];
    [actionSheet addAction:dismissAction];
    [fromViewController presentActionSheet:actionSheet];
}

+ (void)unblockAddresses:(NSArray<SignalServiceAddress *> *)addresses
             displayName:(NSString *)displayName
      fromViewController:(UIViewController *)fromViewController
         completionBlock:(BlockAlertCompletionBlock)completionBlock
{
    OWSAssertDebug(addresses.count > 0);
    OWSAssertDebug(displayName.length > 0);
    OWSAssertDebug(fromViewController);

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        for (SignalServiceAddress *address in addresses) {
            OWSAssertDebug(address.isValid);
            [self.blockingManager removeBlockedAddress:address wasLocallyInitiated:YES transaction:transaction];
        }
    });

    NSString *titleFormat = OWSLocalizedString(@"BLOCK_LIST_VIEW_UNBLOCKED_ALERT_TITLE_FORMAT",
        @"Alert title after unblocking a group or 1:1 chat. Embeds the {{conversation title}}.");
    NSString *title = [NSString stringWithFormat:titleFormat, [self formatDisplayNameForAlertMessage:displayName]];

    [self showOkAlertWithTitle:title message:nil fromViewController:fromViewController completionBlock:completionBlock];
}

+ (void)showUnblockGroupActionSheet:(TSGroupModel *)groupModel
                 fromViewController:(UIViewController *)fromViewController
                    completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    OWSAssertDebug(fromViewController);

    NSString *title =
        [NSString stringWithFormat:OWSLocalizedString(@"BLOCK_LIST_UNBLOCK_GROUP_TITLE",
                                       @"Action sheet title when confirming you want to unblock a group.")];

    NSString *message = OWSLocalizedString(
        @"BLOCK_LIST_UNBLOCK_GROUP_BODY", @"Action sheet body when confirming you want to unblock a group");

    ActionSheetController *actionSheet = [[ActionSheetController alloc] initWithTitle:title message:message];

    ActionSheetAction *unblockAction =
        [[ActionSheetAction alloc] initWithTitle:OWSLocalizedString(@"BLOCK_LIST_UNBLOCK_BUTTON",
                                                     @"Button label for the 'unblock' button")
                         accessibilityIdentifier:@"BlockListUIUtils.unblock"
                                           style:ActionSheetActionStyleDestructive
                                         handler:^(ActionSheetAction *_Nonnull action) {
                                             [BlockListUIUtils unblockGroup:groupModel
                                                         fromViewController:fromViewController
                                                            completionBlock:^(ActionSheetAction *ignore) {
                                                                if (completionBlock) {
                                                                    completionBlock(NO);
                                                                }
                                                            }];
                                         }];
    [actionSheet addAction:unblockAction];

    ActionSheetAction *dismissAction = [[ActionSheetAction alloc] initWithTitle:CommonStrings.cancelButton
                                                        accessibilityIdentifier:@"BlockListUIUtils.dismiss"
                                                                          style:ActionSheetActionStyleCancel
                                                                        handler:^(ActionSheetAction *_Nonnull action) {
                                                                            if (completionBlock) {
                                                                                completionBlock(YES);
                                                                            }
                                                                        }];
    [actionSheet addAction:dismissAction];
    [fromViewController presentActionSheet:actionSheet];
}

+ (void)unblockGroup:(TSGroupModel *)groupModel
    fromViewController:(UIViewController *)fromViewController
       completionBlock:(BlockAlertCompletionBlock)completionBlock
{
    OWSAssertDebug(fromViewController);

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.blockingManager removeBlockedGroupWithGroupId:groupModel.groupId
                                        wasLocallyInitiated:YES
                                                transaction:transaction];
    });

    NSString *titleFormat = OWSLocalizedString(@"BLOCK_LIST_VIEW_UNBLOCKED_ALERT_TITLE_FORMAT",
        @"Alert title after unblocking a group or 1:1 chat. Embeds the {{conversation title}}.");
    NSString *title =
        [NSString stringWithFormat:titleFormat, [self formatDisplayNameForAlertMessage:groupModel.groupNameOrDefault]];

    NSString *message
        = OWSLocalizedString(@"BLOCK_LIST_VIEW_UNBLOCKED_GROUP_ALERT_BODY", @"Alert body after unblocking a group.");
    [self showOkAlertWithTitle:title
                       message:message
            fromViewController:fromViewController
               completionBlock:completionBlock];
}

#pragma mark - UI

+ (void)showOkAlertWithTitle:(NSString *)title
                     message:(nullable NSString *)message
          fromViewController:(UIViewController *)fromViewController
             completionBlock:(BlockAlertCompletionBlock)completionBlock
{
    OWSAssertDebug(title.length > 0);
    OWSAssertDebug(fromViewController);

    ActionSheetController *alert = [[ActionSheetController alloc] initWithTitle:title message:message];

    ActionSheetAction *okAction = [[ActionSheetAction alloc] initWithTitle:CommonStrings.okButton
                                                   accessibilityIdentifier:@"BlockListUIUtils.ok"
                                                                     style:ActionSheetActionStyleDefault
                                                                   handler:completionBlock];
    [alert addAction:okAction];
    [fromViewController presentActionSheet:alert];
}

+ (NSString *)formatDisplayNameForAlertTitle:(NSString *)displayName
{
    return [self formatDisplayName:displayName withMaxLength:20];
}

+ (NSString *)formatDisplayNameForAlertMessage:(NSString *)displayName
{
    return [self formatDisplayName:displayName withMaxLength:127];
}

+ (NSString *)formatDisplayName:(NSString *)displayName withMaxLength:(NSUInteger)maxLength
{
    OWSAssertDebug(displayName.length > 0);

    if (displayName.length > maxLength) {
        return [[displayName substringToIndex:maxLength] stringByAppendingString:@"…"];
    }

    return displayName;
}

@end

NS_ASSUME_NONNULL_END
