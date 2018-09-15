//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
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
        [self showBlockPhoneNumberActionSheet:contactThread.contactIdentifier
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

+ (void)showBlockPhoneNumberActionSheet:(NSString *)phoneNumber
                     fromViewController:(UIViewController *)fromViewController
                        blockingManager:(OWSBlockingManager *)blockingManager
                        contactsManager:(OWSContactsManager *)contactsManager
                        completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    NSString *displayName = [contactsManager displayNameForPhoneIdentifier:phoneNumber];
    [self showBlockPhoneNumbersActionSheet:@[ phoneNumber ]
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
    [self showBlockPhoneNumbersActionSheet:@[ signalAccount.recipientId ]
                               displayName:displayName
                        fromViewController:fromViewController
                           blockingManager:blockingManager
                           completionBlock:completionBlock];
}

+ (void)showBlockPhoneNumbersActionSheet:(NSArray<NSString *> *)phoneNumbers
                             displayName:(NSString *)displayName
                      fromViewController:(UIViewController *)fromViewController
                         blockingManager:(OWSBlockingManager *)blockingManager
                         completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    OWSAssertDebug(phoneNumbers.count > 0);
    OWSAssertDebug(displayName.length > 0);
    OWSAssertDebug(fromViewController);
    OWSAssertDebug(blockingManager);

    NSString *localContactId = [TSAccountManager localNumber];
    OWSAssertDebug(localContactId.length > 0);
    for (NSString *phoneNumber in phoneNumbers) {
        OWSAssertDebug(phoneNumber.length > 0);

        if ([localContactId isEqualToString:phoneNumber]) {
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

    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:title
                                            message:NSLocalizedString(@"BLOCK_USER_BEHAVIOR_EXPLANATION",
                                                        @"An explanation of the consequences of blocking another user.")
                                     preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *blockAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"BLOCK_LIST_BLOCK_BUTTON", @"Button label for the 'block' button")
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *_Nonnull action) {
                    [self blockPhoneNumbers:phoneNumbers
                                displayName:displayName
                         fromViewController:fromViewController
                            blockingManager:blockingManager
                            completionBlock:^(UIAlertAction *ignore) {
                                if (completionBlock) {
                                    completionBlock(YES);
                                }
                            }];
                }];
    [actionSheetController addAction:blockAction];

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:CommonStrings.cancelButton
                                                            style:UIAlertActionStyleCancel
                                                          handler:^(UIAlertAction *_Nonnull action) {
                                                              if (completionBlock) {
                                                                  completionBlock(NO);
                                                              }
                                                          }];
    [actionSheetController addAction:dismissAction];

    [fromViewController presentViewController:actionSheetController animated:YES completion:nil];
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

    NSString *groupName = groupThread.name.length > 0 ? groupThread.name : TSGroupThread.defaultGroupName;
    NSString *title = [NSString
        stringWithFormat:NSLocalizedString(@"BLOCK_LIST_BLOCK_GROUP_TITLE_FORMAT",
                             @"A format for the 'block group' action sheet title. Embeds the {{group name}}."),
        [self formatDisplayNameForAlertTitle:groupName]];

    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:title
                                            message:NSLocalizedString(@"BLOCK_GROUP_BEHAVIOR_EXPLANATION",
                                                        @"An explanation of the consequences of blocking a group.")
                                     preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *blockAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"BLOCK_LIST_BLOCK_BUTTON", @"Button label for the 'block' button")
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
    [actionSheetController addAction:blockAction];

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:CommonStrings.cancelButton
                                                            style:UIAlertActionStyleCancel
                                                          handler:^(UIAlertAction *_Nonnull action) {
                                                              if (completionBlock) {
                                                                  completionBlock(NO);
                                                              }
                                                          }];
    [actionSheetController addAction:dismissAction];

    [fromViewController presentViewController:actionSheetController animated:YES completion:nil];
}

+ (void)blockPhoneNumbers:(NSArray<NSString *> *)phoneNumbers
              displayName:(NSString *)displayName
       fromViewController:(UIViewController *)fromViewController
          blockingManager:(OWSBlockingManager *)blockingManager
          completionBlock:(BlockAlertCompletionBlock)completionBlock
{
    OWSAssertDebug(phoneNumbers.count > 0);
    OWSAssertDebug(displayName.length > 0);
    OWSAssertDebug(fromViewController);
    OWSAssertDebug(blockingManager);

    for (NSString *phoneNumber in phoneNumbers) {
        OWSAssertDebug(phoneNumber.length > 0);
        [blockingManager addBlockedPhoneNumber:phoneNumber];
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

    [ThreadUtil
        sendLeaveGroupMessageInThread:groupThread
             presentingViewController:fromViewController
                        messageSender:messageSender
                           completion:^(NSError *_Nullable error) {
                               if (error) {
                                   OWSLogError(@"Failed to leave blocked group with error: %@", error);
                               }

                               NSString *groupName
                                   = groupThread.name.length > 0 ? groupThread.name : TSGroupThread.defaultGroupName;

                               [self
                                   showOkAlertWithTitle:NSLocalizedString(@"BLOCK_LIST_VIEW_BLOCKED_GROUP_ALERT_TITLE",
                                                            @"The title of the 'group blocked' alert.")
                                                message:[NSString
                                                            stringWithFormat:
                                                                NSLocalizedString(
                                                                    @"BLOCK_LIST_VIEW_BLOCKED_ALERT_MESSAGE_FORMAT",
                                                                    @"The message format of the 'conversation blocked' "
                                                                    @"alert. "
                                                                    @"Embeds the {{conversation title}}."),
                                                            [self formatDisplayNameForAlertMessage:groupName]]
                                     fromViewController:fromViewController
                                        completionBlock:completionBlock];
                           }];
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
        [self showUnblockPhoneNumberActionSheet:contactThread.contactIdentifier
                             fromViewController:fromViewController
                                blockingManager:blockingManager
                                contactsManager:contactsManager
                                completionBlock:completionBlock];
    } else if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        NSString *groupName = groupThread.name.length > 0 ? groupThread.name : TSGroupThread.defaultGroupName;
        [self showUnblockGroupActionSheet:groupThread.groupModel
                              displayName:groupName
                       fromViewController:fromViewController
                          blockingManager:blockingManager
                          completionBlock:completionBlock];
    } else {
        OWSFailDebug(@"unexpected thread type: %@", thread.class);
    }
}

+ (void)showUnblockPhoneNumberActionSheet:(NSString *)phoneNumber
                       fromViewController:(UIViewController *)fromViewController
                          blockingManager:(OWSBlockingManager *)blockingManager
                          contactsManager:(OWSContactsManager *)contactsManager
                          completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    NSString *displayName = [contactsManager displayNameForPhoneIdentifier:phoneNumber];
    [self showUnblockPhoneNumbersActionSheet:@[ phoneNumber ]
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
    [self showUnblockPhoneNumbersActionSheet:@[ signalAccount.recipientId ]
                                 displayName:displayName
                          fromViewController:fromViewController
                             blockingManager:blockingManager
                             completionBlock:completionBlock];
}

+ (void)showUnblockPhoneNumbersActionSheet:(NSArray<NSString *> *)phoneNumbers
                               displayName:(NSString *)displayName
                        fromViewController:(UIViewController *)fromViewController
                           blockingManager:(OWSBlockingManager *)blockingManager
                           completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    OWSAssertDebug(phoneNumbers.count > 0);
    OWSAssertDebug(displayName.length > 0);
    OWSAssertDebug(fromViewController);
    OWSAssertDebug(blockingManager);

    NSString *title = [NSString
        stringWithFormat:
            NSLocalizedString(@"BLOCK_LIST_UNBLOCK_TITLE_FORMAT",
                @"A format for the 'unblock conversation' action sheet title. Embeds the {{conversation title}}."),
        [self formatDisplayNameForAlertTitle:displayName]];

    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *unblockAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"BLOCK_LIST_UNBLOCK_BUTTON", @"Button label for the 'unblock' button")
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *_Nonnull action) {
                    [BlockListUIUtils unblockPhoneNumbers:phoneNumbers
                                              displayName:displayName
                                       fromViewController:fromViewController
                                          blockingManager:blockingManager
                                          completionBlock:^(UIAlertAction *ignore) {
                                              if (completionBlock) {
                                                  completionBlock(NO);
                                              }
                                          }];
                }];
    [actionSheetController addAction:unblockAction];

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:CommonStrings.cancelButton
                                                            style:UIAlertActionStyleCancel
                                                          handler:^(UIAlertAction *_Nonnull action) {
                                                              if (completionBlock) {
                                                                  completionBlock(YES);
                                                              }
                                                          }];
    [actionSheetController addAction:dismissAction];

    [fromViewController presentViewController:actionSheetController animated:YES completion:nil];
}

+ (void)unblockPhoneNumbers:(NSArray<NSString *> *)phoneNumbers
                displayName:(NSString *)displayName
         fromViewController:(UIViewController *)fromViewController
            blockingManager:(OWSBlockingManager *)blockingManager
            completionBlock:(BlockAlertCompletionBlock)completionBlock
{
    OWSAssertDebug(phoneNumbers.count > 0);
    OWSAssertDebug(displayName.length > 0);
    OWSAssertDebug(fromViewController);
    OWSAssertDebug(blockingManager);

    for (NSString *phoneNumber in phoneNumbers) {
        OWSAssertDebug(phoneNumber.length > 0);
        [blockingManager removeBlockedPhoneNumber:phoneNumber];
    }

    NSString *titleFormat = NSLocalizedString(@"BLOCK_LIST_VIEW_UNBLOCKED_ALERT_TITLE_FORMAT",
        @"Alert title after unblocking a group or 1:1 chat. Embeds the {{conversation title}}.");
    NSString *title = [NSString stringWithFormat:titleFormat, [self formatDisplayNameForAlertMessage:displayName]];

    [self showOkAlertWithTitle:title message:nil fromViewController:fromViewController completionBlock:completionBlock];
}

+ (void)showUnblockGroupActionSheet:(TSGroupModel *)groupModel
                        displayName:(NSString *)displayName
                 fromViewController:(UIViewController *)fromViewController
                    blockingManager:(OWSBlockingManager *)blockingManager
                    completionBlock:(nullable BlockActionCompletionBlock)completionBlock
{
    OWSAssertDebug(displayName.length > 0);
    OWSAssertDebug(fromViewController);
    OWSAssertDebug(blockingManager);

    NSString *title =
        [NSString stringWithFormat:NSLocalizedString(@"BLOCK_LIST_UNBLOCK_GROUP_TITLE",
                                       @"Action sheet title when confirming you want to unblock a group.")];

    NSString *message = NSLocalizedString(
        @"BLOCK_LIST_UNBLOCK_GROUP_BODY", @"Action sheet body when confirming you want to unblock a group");

    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:title
                                            message:message
                                     preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *unblockAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"BLOCK_LIST_UNBLOCK_BUTTON", @"Button label for the 'unblock' button")
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *_Nonnull action) {
                    [BlockListUIUtils unblockGroup:groupModel
                                       displayName:displayName
                                fromViewController:fromViewController
                                   blockingManager:blockingManager
                                   completionBlock:^(UIAlertAction *ignore) {
                                       if (completionBlock) {
                                           completionBlock(NO);
                                       }
                                   }];
                }];
    [actionSheetController addAction:unblockAction];

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:CommonStrings.cancelButton
                                                            style:UIAlertActionStyleCancel
                                                          handler:^(UIAlertAction *_Nonnull action) {
                                                              if (completionBlock) {
                                                                  completionBlock(YES);
                                                              }
                                                          }];
    [actionSheetController addAction:dismissAction];

    [fromViewController presentViewController:actionSheetController animated:YES completion:nil];
}

+ (void)unblockGroup:(TSGroupModel *)groupModel
           displayName:(NSString *)displayName
    fromViewController:(UIViewController *)fromViewController
       blockingManager:(OWSBlockingManager *)blockingManager
       completionBlock:(BlockAlertCompletionBlock)completionBlock
{
    OWSAssertDebug(displayName.length > 0);
    OWSAssertDebug(fromViewController);
    OWSAssertDebug(blockingManager);

    [blockingManager removeBlockedGroupId:groupModel.groupId];

    NSString *titleFormat = NSLocalizedString(@"BLOCK_LIST_VIEW_UNBLOCKED_ALERT_TITLE_FORMAT",
        @"Alert title after unblocking a group or 1:1 chat. Embeds the {{conversation title}}.");
    NSString *title = [NSString stringWithFormat:titleFormat, [self formatDisplayNameForAlertMessage:displayName]];

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

    UIAlertController *controller =
        [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];

    [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                   style:UIAlertActionStyleDefault
                                                 handler:completionBlock]];
    [fromViewController presentViewController:controller animated:YES completion:nil];
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
