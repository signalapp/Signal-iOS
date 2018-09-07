//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "BlockListUIUtils.h"
#import "OWSContactsManager.h"
#import "PhoneNumber.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/Contact.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/TSAccountManager.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^BlockAlertCompletionBlock)(UIAlertAction *action);

@implementation BlockListUIUtils

#pragma mark - Block

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

    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"BLOCK_LIST_BLOCK_TITLE_FORMAT",
                                                     @"A format for the 'block user' action sheet title. Embeds {{the "
                                                     @"blocked user's name or phone number}}."),
                                [self formatDisplayNameForAlertTitle:displayName]];

    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:title
                                            message:NSLocalizedString(@"BLOCK_BEHAVIOR_EXPLANATION",
                                                        @"An explanation of the consequences of blocking another user.")
                                     preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *unblockAction = [UIAlertAction
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
    [actionSheetController addAction:unblockAction];

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
                                                        @"The message format of the 'user blocked' "
                                                        @"alert. Embeds {{the blocked user's name or phone number}}."),
                                   [self formatDisplayNameForAlertMessage:displayName]]
            fromViewController:fromViewController
               completionBlock:completionBlock];
}

#pragma mark - Unblock

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

    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"BLOCK_LIST_UNBLOCK_TITLE_FORMAT",
                                                     @"A format for the 'unblock user' action sheet title. Embeds "
                                                     @"{{the blocked user's name or phone number}}."),
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

    [self showOkAlertWithTitle:NSLocalizedString(@"BLOCK_LIST_VIEW_UNBLOCKED_ALERT_TITLE",
                                   @"The title of the 'user unblocked' alert.")
                       message:[NSString
                                   stringWithFormat:NSLocalizedString(@"BLOCK_LIST_VIEW_UNBLOCKED_ALERT_MESSAGE_FORMAT",
                                                        @"The message format of the 'user unblocked' "
                                                        @"alert. Embeds {{the blocked user's name or phone number}}."),
                                   [self formatDisplayNameForAlertMessage:displayName]]
            fromViewController:fromViewController
               completionBlock:completionBlock];
}

+ (void)showBlockFailedAlert:(UIViewController *)fromViewController
             completionBlock:(BlockAlertCompletionBlock)completionBlock
{
    OWSAssertDebug(fromViewController);

    [self showOkAlertWithTitle:NSLocalizedString(@"BLOCK_LIST_VIEW_BLOCK_FAILED_ALERT_TITLE",
                                   @"The title of the 'block user failed' alert.")
                       message:NSLocalizedString(@"BLOCK_LIST_VIEW_BLOCK_FAILED_ALERT_MESSAGE",
                                   @"The title of the 'block user failed' alert.")
            fromViewController:fromViewController
               completionBlock:completionBlock];
}

+ (void)showUnblockFailedAlert:(UIViewController *)fromViewController
               completionBlock:(BlockAlertCompletionBlock)completionBlock
{
    OWSAssertDebug(fromViewController);

    [self showOkAlertWithTitle:NSLocalizedString(@"BLOCK_LIST_VIEW_UNBLOCK_FAILED_ALERT_TITLE",
                                   @"The title of the 'unblock user failed' alert.")
                       message:NSLocalizedString(@"BLOCK_LIST_VIEW_UNBLOCK_FAILED_ALERT_MESSAGE",
                                   @"The title of the 'unblock user failed' alert.")
            fromViewController:fromViewController
               completionBlock:completionBlock];
}

#pragma mark - UI

+ (void)showOkAlertWithTitle:(NSString *)title
                     message:(NSString *)message
          fromViewController:(UIViewController *)fromViewController
             completionBlock:(BlockAlertCompletionBlock)completionBlock
{
    OWSAssertDebug(title.length > 0);
    OWSAssertDebug(message.length > 0);
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
