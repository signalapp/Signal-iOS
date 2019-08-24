//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "BlockListUIUtils.h"
#import "OWSContactsManager.h"
#import "PhoneNumber.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/Contact.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSGroupThread.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^BlockAlertCompletionBlock)(UIAlertAction *action);

@implementation BlockListUIUtils

#pragma mark - Block

+ (void)showBlockThreadActionSheet:(TSThread *)thread
                fromViewController:(UIViewController *)fromViewController
                   blockingManager:(OWSBlockingManager *)blockingManager
                   contactsManager:(OWSContactsManager *)contactsManager
                     messageSender:(OWSMessageSender *)messageSender
                   completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        [self showBlockAddressActionSheet:contactThread.contactAddress
                       fromViewController:fromViewController
                          blockingManager:blockingManager
                          contactsManager:contactsManager
                          completionBlock:completionBlock];
    } else if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        [self showBlockGroupActionSheet:groupThread
                     fromViewController:fromViewController
                        blockingManager:blockingManager
                          messageSender:messageSender
                        completionBlock:completionBlock];
    } else {
        OWSFailDebug(@"unexpected thread type: %@", thread.class);
    }
}

+ (void)showBlockAddressActionSheet:(SignalServiceAddress *)address
                 fromViewController:(UIViewController *)fromViewController
                    blockingManager:(OWSBlockingManager *)blockingManager
                    contactsManager:(OWSContactsManager *)contactsManager
                    completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    NSString *displayName = [contactsManager displayNameForAddress:address];
    [self showBlockAddressesActionSheet:@[ address ]
                            displayName:displayName
                     fromViewController:fromViewController
                        blockingManager:blockingManager
                        completionBlock:completionBlock];
}

+ (void)showBlockSignalAccountActionSheet:(SignalAccount *)signalAccount
                       fromViewController:(UIViewController *)fromViewController
                          blockingManager:(OWSBlockingManager *)blockingManager
                          contactsManager:(OWSContactsManager *)contactsManager
                          completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    NSString *displayName = [contactsManager displayNameForSignalAccount:signalAccount];
    [self showBlockAddressesActionSheet:@[ signalAccount.recipientAddress ]
                            displayName:displayName
                     fromViewController:fromViewController
                        blockingManager:blockingManager
                        completionBlock:completionBlock];
}

+ (void)showBlockAddressesActionSheet:(NSArray<SignalServiceAddress *> *)addresses
                          displayName:(NSString *)displayName
                   fromViewController:(UIViewController *)fromViewController
                      blockingManager:(OWSBlockingManager *)blockingManager
                      completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    OWSAssertDebug(addresses.count > 0);
    OWSAssertDebug(displayName.length > 0);
    OWSAssertDebug(fromViewController);
    OWSAssertDebug(blockingManager);

    for (SignalServiceAddress *address in addresses) {
        OWSAssertDebug(address.isValid);

        if (address.isLocalAddress) {
            [self showOkAlertWithTitle:NSLocalizedString(@"BLOCK_LIST_VIEW_CANT_BLOCK_SELF_ALERT_TITLE",
                                           @"The title of the 'You can't block yourself' alert.")
                               message:NSLocalizedString(@"BLOCK_LIST_VIEW_CANT_BLOCK_SELF_ALERT_MESSAGE",
                                           @"The message of the 'You can't block yourself' alert.")
                    fromViewController:fromViewController
                       completionBlock:^(UIAlertAction *action) {
                           if (completionBlock) {
                               completionBlock(NO);
                           }
                       }];
            return;
        }
    }

    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"BLOCK_LIST_BLOCK_USER_TITLE_FORMAT",
                                                     @"A format for the 'block user' action sheet title. Embeds {{the "
                                                     @"blocked user's name or phone number}}."),
                                [self formatDisplayNameForAlertTitle:displayName]];

    UIAlertController *actionSheet =
        [UIAlertController alertControllerWithTitle:title
                                            message:NSLocalizedString(@"BLOCK_USER_BEHAVIOR_EXPLANATION",
                                                        @"An explanation of the consequences of blocking another user.")
                                     preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *blockAction = [UIAlertAction
                actionWithTitle:NSLocalizedString(@"BLOCK_LIST_BLOCK_BUTTON", @"Button label for the 'block' button")
        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"block")
                          style:UIAlertActionStyleDestructive
                        handler:^(UIAlertAction *_Nonnull action) {
                            [self blockAddresses:addresses
                                       displayName:displayName
                                fromViewController:fromViewController
                                   blockingManager:blockingManager
                                   completionBlock:^(UIAlertAction *ignore) {
                                       if (completionBlock) {
                                           completionBlock(YES);
                                       }
                                   }];
                        }];
    [actionSheet addAction:blockAction];

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:CommonStrings.cancelButton
                                          accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"dismiss")
                                                            style:UIAlertActionStyleCancel
                                                          handler:^(UIAlertAction *_Nonnull action) {
                                                              if (completionBlock) {
                                                                  completionBlock(NO);
                                                              }
                                                          }];
    [actionSheet addAction:dismissAction];
    [fromViewController presentAlert:actionSheet];
}

+ (void)showBlockGroupActionSheet:(TSGroupThread *)groupThread
               fromViewController:(UIViewController *)fromViewController
                  blockingManager:(OWSBlockingManager *)blockingManager
                    messageSender:(OWSMessageSender *)messageSender
                  completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    OWSAssertDebug(groupThread);
    OWSAssertDebug(fromViewController);
    OWSAssertDebug(blockingManager);

    NSString *title = [NSString
        stringWithFormat:NSLocalizedString(@"BLOCK_LIST_BLOCK_GROUP_TITLE_FORMAT",
                             @"A format for the 'block group' action sheet title. Embeds the {{group name}}."),
        [self formatDisplayNameForAlertTitle:groupThread.groupNameOrDefault]];

    UIAlertController *actionSheet =
        [UIAlertController alertControllerWithTitle:title
                                            message:NSLocalizedString(@"BLOCK_GROUP_BEHAVIOR_EXPLANATION",
                                                        @"An explanation of the consequences of blocking a group.")
                                     preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *blockAction = [UIAlertAction
                actionWithTitle:NSLocalizedString(@"BLOCK_LIST_BLOCK_BUTTON", @"Button label for the 'block' button")
        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"block")
                          style:UIAlertActionStyleDestructive
                        handler:^(UIAlertAction *_Nonnull action) {
                            [self blockGroup:groupThread
                                fromViewController:fromViewController
                                   blockingManager:blockingManager
                                     messageSender:messageSender
                                   completionBlock:^(UIAlertAction *ignore) {
                                       if (completionBlock) {
                                           completionBlock(YES);
                                       }
                                   }];
                        }];
    [actionSheet addAction:blockAction];

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:CommonStrings.cancelButton
                                          accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"dismiss")
                                                            style:UIAlertActionStyleCancel
                                                          handler:^(UIAlertAction *_Nonnull action) {
                                                              if (completionBlock) {
                                                                  completionBlock(NO);
                                                              }
                                                          }];
    [actionSheet addAction:dismissAction];
    [fromViewController presentAlert:actionSheet];
}

+ (void)blockAddresses:(NSArray<SignalServiceAddress *> *)addresses
           displayName:(NSString *)displayName
    fromViewController:(UIViewController *)fromViewController
       blockingManager:(OWSBlockingManager *)blockingManager
       completionBlock:(BlockAlertCompletionBlock)completionBlock
{
    OWSAssertDebug(addresses.count > 0);
    OWSAssertDebug(displayName.length > 0);
    OWSAssertDebug(fromViewController);
    OWSAssertDebug(blockingManager);

    for (SignalServiceAddress *address in addresses) {
        OWSAssertDebug(address.isValid);
        [blockingManager addBlockedAddress:address];
    }

    [self showOkAlertWithTitle:NSLocalizedString(
                                   @"BLOCK_LIST_VIEW_BLOCKED_ALERT_TITLE", @"The title of the 'user blocked' alert.")
                       message:[NSString
                                   stringWithFormat:NSLocalizedString(@"BLOCK_LIST_VIEW_BLOCKED_ALERT_MESSAGE_FORMAT",
                                                        @"The message format of the 'conversation blocked' alert. "
                                                        @"Embeds the {{conversation title}}."),
                                   [self formatDisplayNameForAlertMessage:displayName]]
            fromViewController:fromViewController
               completionBlock:completionBlock];
}

+ (void)blockGroup:(TSGroupThread *)groupThread
    fromViewController:(UIViewController *)fromViewController
       blockingManager:(OWSBlockingManager *)blockingManager
         messageSender:(OWSMessageSender *)messageSender
       completionBlock:(BlockAlertCompletionBlock)completionBlock
{
    OWSAssertDebug(groupThread);
    OWSAssertDebug(fromViewController);
    OWSAssertDebug(blockingManager);

    // block the group regardless of the ability to deliver the "leave group" message.
    [blockingManager addBlockedGroup:groupThread.groupModel];

    // blockingManager.addBlocked* creates sneaky transactions, so we can't pass in a transaction
    // via params and instead have to create our own sneaky transaction here.
    [groupThread leaveGroupWithSneakyTransaction];

    [ThreadUtil enqueueLeaveGroupMessageInThread:groupThread];

    NSString *alertTitle
        = NSLocalizedString(@"BLOCK_LIST_VIEW_BLOCKED_GROUP_ALERT_TITLE", @"The title of the 'group blocked' alert.");
    NSString *alertBodyFormat = NSLocalizedString(@"BLOCK_LIST_VIEW_BLOCKED_ALERT_MESSAGE_FORMAT",
        @"The message format of the 'conversation blocked' alert. Embeds the {{conversation title}}.");
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
                     blockingManager:(OWSBlockingManager *)blockingManager
                     contactsManager:(OWSContactsManager *)contactsManager
                     completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        [self showUnblockAddressActionSheet:contactThread.contactAddress
                         fromViewController:fromViewController
                            blockingManager:blockingManager
                            contactsManager:contactsManager
                            completionBlock:completionBlock];
    } else if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        [self showUnblockGroupActionSheet:groupThread.groupModel
                       fromViewController:fromViewController
                          blockingManager:blockingManager
                          completionBlock:completionBlock];
    } else {
        OWSFailDebug(@"unexpected thread type: %@", thread.class);
    }
}

+ (void)showUnblockAddressActionSheet:(SignalServiceAddress *)address
                   fromViewController:(UIViewController *)fromViewController
                      blockingManager:(OWSBlockingManager *)blockingManager
                      contactsManager:(OWSContactsManager *)contactsManager
                      completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    NSString *displayName = [contactsManager displayNameForAddress:address];
    [self showUnblockAddressesActionSheet:@[ address ]
                              displayName:displayName
                       fromViewController:fromViewController
                          blockingManager:blockingManager
                          completionBlock:completionBlock];
}

+ (void)showUnblockSignalAccountActionSheet:(SignalAccount *)signalAccount
                         fromViewController:(UIViewController *)fromViewController
                            blockingManager:(OWSBlockingManager *)blockingManager
                            contactsManager:(OWSContactsManager *)contactsManager
                            completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    NSString *displayName = [contactsManager displayNameForSignalAccount:signalAccount];
    [self showUnblockAddressesActionSheet:@[ signalAccount.recipientAddress ]
                              displayName:displayName
                       fromViewController:fromViewController
                          blockingManager:blockingManager
                          completionBlock:completionBlock];
}

+ (void)showUnblockAddressesActionSheet:(NSArray<SignalServiceAddress *> *)addresses
                            displayName:(NSString *)displayName
                     fromViewController:(UIViewController *)fromViewController
                        blockingManager:(OWSBlockingManager *)blockingManager
                        completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    OWSAssertDebug(addresses.count > 0);
    OWSAssertDebug(displayName.length > 0);
    OWSAssertDebug(fromViewController);
    OWSAssertDebug(blockingManager);

    NSString *title = [NSString
        stringWithFormat:
            NSLocalizedString(@"BLOCK_LIST_UNBLOCK_TITLE_FORMAT",
                @"A format for the 'unblock conversation' action sheet title. Embeds the {{conversation title}}."),
        [self formatDisplayNameForAlertTitle:displayName]];

    UIAlertController *actionSheet =
        [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *unblockAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(
                                           @"BLOCK_LIST_UNBLOCK_BUTTON", @"Button label for the 'unblock' button")
               accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"unblock")
                                 style:UIAlertActionStyleDestructive
                               handler:^(UIAlertAction *_Nonnull action) {
                                   [BlockListUIUtils unblockAddresses:addresses
                                                          displayName:displayName
                                                   fromViewController:fromViewController
                                                      blockingManager:blockingManager
                                                      completionBlock:^(UIAlertAction *ignore) {
                                                          if (completionBlock) {
                                                              completionBlock(NO);
                                                          }
                                                      }];
                               }];
    [actionSheet addAction:unblockAction];

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:CommonStrings.cancelButton
                                          accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"dismiss")
                                                            style:UIAlertActionStyleCancel
                                                          handler:^(UIAlertAction *_Nonnull action) {
                                                              if (completionBlock) {
                                                                  completionBlock(YES);
                                                              }
                                                          }];
    [actionSheet addAction:dismissAction];
    [fromViewController presentAlert:actionSheet];
}

+ (void)unblockAddresses:(NSArray<SignalServiceAddress *> *)addresses
             displayName:(NSString *)displayName
      fromViewController:(UIViewController *)fromViewController
         blockingManager:(OWSBlockingManager *)blockingManager
         completionBlock:(BlockAlertCompletionBlock)completionBlock
{
    OWSAssertDebug(addresses.count > 0);
    OWSAssertDebug(displayName.length > 0);
    OWSAssertDebug(fromViewController);
    OWSAssertDebug(blockingManager);

    for (SignalServiceAddress *address in addresses) {
        OWSAssertDebug(address.isValid);
        [blockingManager removeBlockedAddress:address];
    }

    NSString *titleFormat = NSLocalizedString(@"BLOCK_LIST_VIEW_UNBLOCKED_ALERT_TITLE_FORMAT",
        @"Alert title after unblocking a group or 1:1 chat. Embeds the {{conversation title}}.");
    NSString *title = [NSString stringWithFormat:titleFormat, [self formatDisplayNameForAlertMessage:displayName]];

    [self showOkAlertWithTitle:title message:nil fromViewController:fromViewController completionBlock:completionBlock];
}

+ (void)showUnblockGroupActionSheet:(TSGroupModel *)groupModel
                 fromViewController:(UIViewController *)fromViewController
                    blockingManager:(OWSBlockingManager *)blockingManager
                    completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    OWSAssertDebug(fromViewController);
    OWSAssertDebug(blockingManager);

    NSString *title =
        [NSString stringWithFormat:NSLocalizedString(@"BLOCK_LIST_UNBLOCK_GROUP_TITLE",
                                       @"Action sheet title when confirming you want to unblock a group.")];

    NSString *message = NSLocalizedString(
        @"BLOCK_LIST_UNBLOCK_GROUP_BODY", @"Action sheet body when confirming you want to unblock a group");

    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:title
                                                                         message:message
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *unblockAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"BLOCK_LIST_UNBLOCK_BUTTON",
                                                                      @"Button label for the 'unblock' button")
                                          accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"unblock")
                                                            style:UIAlertActionStyleDestructive
                                                          handler:^(UIAlertAction *_Nonnull action) {
                                                              [BlockListUIUtils unblockGroup:groupModel
                                                                          fromViewController:fromViewController
                                                                             blockingManager:blockingManager
                                                                             completionBlock:^(UIAlertAction *ignore) {
                                                                                 if (completionBlock) {
                                                                                     completionBlock(NO);
                                                                                 }
                                                                             }];
                                                          }];
    [actionSheet addAction:unblockAction];

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:CommonStrings.cancelButton
                                          accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"dismiss")
                                                            style:UIAlertActionStyleCancel
                                                          handler:^(UIAlertAction *_Nonnull action) {
                                                              if (completionBlock) {
                                                                  completionBlock(YES);
                                                              }
                                                          }];
    [actionSheet addAction:dismissAction];
    [fromViewController presentAlert:actionSheet];
}

+ (void)unblockGroup:(TSGroupModel *)groupModel
    fromViewController:(UIViewController *)fromViewController
       blockingManager:(OWSBlockingManager *)blockingManager
       completionBlock:(BlockAlertCompletionBlock)completionBlock
{
    OWSAssertDebug(fromViewController);
    OWSAssertDebug(blockingManager);

    [blockingManager removeBlockedGroupId:groupModel.groupId];

    NSString *titleFormat = NSLocalizedString(@"BLOCK_LIST_VIEW_UNBLOCKED_ALERT_TITLE_FORMAT",
        @"Alert title after unblocking a group or 1:1 chat. Embeds the {{conversation title}}.");
    NSString *title =
        [NSString stringWithFormat:titleFormat, [self formatDisplayNameForAlertMessage:groupModel.groupNameOrDefault]];

    NSString *message
        = NSLocalizedString(@"BLOCK_LIST_VIEW_UNBLOCKED_GROUP_ALERT_BODY", @"Alert body after unblocking a group.");
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

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                     accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"ok")
                                                       style:UIAlertActionStyleDefault
                                                     handler:completionBlock];
    [alert addAction:okAction];
    [fromViewController presentAlert:alert];
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
