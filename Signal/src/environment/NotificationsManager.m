//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "NotificationsManager.h"
#import "PushManager.h"
#import "Signal-Swift.h"
#import <AudioToolbox/AudioServices.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/NSString+OWS.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/OWSSounds.h>
#import <SignalServiceKit/NSString+SSK.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSErrorMessage.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/Threading.h>
#import <YapDatabase/YapDatabaseTransaction.h>

@interface NotificationsManager ()

@property (nonatomic, readonly) NSMutableDictionary<NSString *, UILocalNotification *> *currentNotifications;
@property (nonatomic, readonly) NotificationType notificationPreviewType;

@property (nonatomic, readonly) NSMutableArray<NSDate *> *notificationHistory;
@property (nonatomic, nullable) OWSAudioPlayer *audioPlayer;

@end

#pragma mark -

@implementation NotificationsManager

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _currentNotifications = [NSMutableDictionary new];

    _notificationHistory = [NSMutableArray new];

    OWSSingletonAssert();

    return self;
}

#pragma mark - Signal Calls

/**
 * Notify user for incoming WebRTC Call
 */
- (void)presentIncomingCall:(SignalCall *)call callerName:(NSString *)callerName
{
    OWSLogDebug(@"incoming call from: %@", call.remotePhoneNumber);

    UILocalNotification *notification = [UILocalNotification new];
    notification.category = PushManagerCategoriesIncomingCall;
    // Rather than using notification sounds, we control the ringtone and repeat vibrations with the CallAudioManager.
    notification.soundName = [OWSSounds filenameForSound:OWSSound_DefaultiOSIncomingRingtone];
    NSString *localCallId = call.localId.UUIDString;
    notification.userInfo = @{ PushManagerUserInfoKeysLocalCallId : localCallId };

    NSString *alertMessage;
    switch (self.notificationPreviewType) {
        case NotificationNoNameNoPreview: {
            alertMessage = NSLocalizedString(@"INCOMING_CALL", @"notification body");
            break;
        }
        case NotificationNameNoPreview:
        case NotificationNamePreview: {
            alertMessage =
                [NSString stringWithFormat:NSLocalizedString(@"INCOMING_CALL_FROM", @"notification body"), callerName];
            break;
        }
    }
    notification.alertBody = [NSString stringWithFormat:@"☎️ %@", alertMessage];

    [self presentNotification:notification identifier:localCallId];
}

/**
 * Notify user for missed WebRTC Call
 */
- (void)presentMissedCall:(SignalCall *)call callerName:(NSString *)callerName
{
    TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactId:call.remotePhoneNumber];
    OWSAssertDebug(thread != nil);

    UILocalNotification *notification = [UILocalNotification new];
    notification.category = PushManagerCategoriesMissedCall;
    NSString *localCallId = call.localId.UUIDString;
    notification.userInfo = @{
        PushManagerUserInfoKeysLocalCallId : localCallId,
        PushManagerUserInfoKeysCallBackSignalRecipientId : call.remotePhoneNumber,
        Signal_Thread_UserInfo_Key : thread.uniqueId
    };

    if ([self shouldPlaySoundForNotification]) {
        OWSSound sound = [OWSSounds notificationSoundForThread:thread];
        notification.soundName = [OWSSounds filenameForSound:sound];
    }

    NSString *alertMessage;
    switch (self.notificationPreviewType) {
        case NotificationNoNameNoPreview: {
            alertMessage = [CallStrings missedCallNotificationBodyWithoutCallerName];
            break;
        }
        case NotificationNameNoPreview:
        case NotificationNamePreview: {
            alertMessage =
                [NSString stringWithFormat:[CallStrings missedCallNotificationBodyWithCallerName], callerName];
            break;
        }
    }
    notification.alertBody = [NSString stringWithFormat:@"☎️ %@", alertMessage];

    [self presentNotification:notification identifier:localCallId];
}


- (void)presentMissedCallBecauseOfNewIdentity:(SignalCall *)call callerName:(NSString *)callerName
{
    TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactId:call.remotePhoneNumber];
    OWSAssertDebug(thread != nil);

    UILocalNotification *notification = [UILocalNotification new];
    // Use category which allows call back
    notification.category = PushManagerCategoriesMissedCall;
    NSString *localCallId = call.localId.UUIDString;
    notification.userInfo = @{
        PushManagerUserInfoKeysLocalCallId : localCallId,
        PushManagerUserInfoKeysCallBackSignalRecipientId : call.remotePhoneNumber,
        Signal_Thread_UserInfo_Key : thread.uniqueId
    };
    if ([self shouldPlaySoundForNotification]) {
        OWSSound sound = [OWSSounds notificationSoundForThread:thread];
        notification.soundName = [OWSSounds filenameForSound:sound];
    }

    NSString *alertMessage;
    switch (self.notificationPreviewType) {
        case NotificationNoNameNoPreview: {
            alertMessage = [CallStrings missedCallWithIdentityChangeNotificationBodyWithoutCallerName];
            break;
        }
        case NotificationNameNoPreview:
        case NotificationNamePreview: {
            alertMessage = [NSString
                stringWithFormat:[CallStrings missedCallWithIdentityChangeNotificationBodyWithCallerName], callerName];
            break;
        }
    }
    notification.alertBody = [NSString stringWithFormat:@"☎️ %@", alertMessage];

    [self presentNotification:notification identifier:localCallId];
}

- (void)presentMissedCallBecauseOfNoLongerVerifiedIdentity:(SignalCall *)call callerName:(NSString *)callerName
{
    TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactId:call.remotePhoneNumber];
    OWSAssertDebug(thread != nil);

    UILocalNotification *notification = [UILocalNotification new];
    // Use category which does not allow call back
    notification.category = PushManagerCategoriesMissedCallFromNoLongerVerifiedIdentity;
    NSString *localCallId = call.localId.UUIDString;
    notification.userInfo = @{
        PushManagerUserInfoKeysLocalCallId : localCallId,
        PushManagerUserInfoKeysCallBackSignalRecipientId : call.remotePhoneNumber,
        Signal_Thread_UserInfo_Key : thread.uniqueId
    };
    if ([self shouldPlaySoundForNotification]) {
        OWSSound sound = [OWSSounds notificationSoundForThread:thread];
        notification.soundName = [OWSSounds filenameForSound:sound];
    }

    NSString *alertMessage;
    switch (self.notificationPreviewType) {
        case NotificationNoNameNoPreview: {
            alertMessage = [CallStrings missedCallWithIdentityChangeNotificationBodyWithoutCallerName];
            break;
        }
        case NotificationNameNoPreview:
        case NotificationNamePreview: {
            alertMessage = [NSString
                stringWithFormat:[CallStrings missedCallWithIdentityChangeNotificationBodyWithCallerName], callerName];
            break;
        }
    }
    notification.alertBody = [NSString stringWithFormat:@"☎️ %@", alertMessage];

    [self presentNotification:notification identifier:localCallId];
}

#pragma mark - Signal Messages

- (void)notifyUserForErrorMessage:(TSErrorMessage *)message
                           thread:(TSThread *)thread
                      transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(message);

    if (!thread) {
        OWSFailDebug(@"unexpected notification not associated with a thread: %@.", [message class]);
        [self notifyUserForThreadlessErrorMessage:message transaction:transaction];
        return;
    }

    NSString *messageText = [message previewTextWithTransaction:transaction];

    [transaction
        addCompletionQueue:nil
           completionBlock:^() {
               if (thread.isMuted) {
                   return;
               }

               BOOL shouldPlaySound = [self shouldPlaySoundForNotification];

               if (([UIApplication sharedApplication].applicationState != UIApplicationStateActive) && messageText) {
                   UILocalNotification *notification = [[UILocalNotification alloc] init];
                   notification.userInfo = @{ Signal_Thread_UserInfo_Key : thread.uniqueId };
                   if (shouldPlaySound) {
                       OWSSound sound = [OWSSounds notificationSoundForThread:thread];
                       notification.soundName = [OWSSounds filenameForSound:sound];
                   }

                   NSString *alertBodyString = @"";

                   NSString *authorName = [thread name];
                   switch (self.notificationPreviewType) {
                       case NotificationNamePreview:
                       case NotificationNameNoPreview:
                           alertBodyString = [NSString stringWithFormat:@"%@: %@", authorName, messageText];
                           break;
                       case NotificationNoNameNoPreview:
                           alertBodyString = messageText;
                           break;
                   }
                   notification.alertBody = alertBodyString;

                   [[PushManager sharedManager] presentNotification:notification checkForCancel:NO];
               } else {
                   if (shouldPlaySound && [Environment.shared.preferences soundInForeground]) {
                       OWSSound sound = [OWSSounds notificationSoundForThread:thread];
                       SystemSoundID soundId = [OWSSounds systemSoundIDForSound:sound quiet:YES];
                       // Vibrate, respect silent switch, respect "Alert" volume, not media volume.
                       AudioServicesPlayAlertSound(soundId);
                   }
               }
           }];
}

- (void)notifyUserForThreadlessErrorMessage:(TSErrorMessage *)message
                                transaction:(YapDatabaseReadWriteTransaction *)transaction;
{
    OWSAssertDebug(message);

    NSString *messageText = [message previewTextWithTransaction:transaction];

    [transaction
        addCompletionQueue:nil
           completionBlock:^() {
               BOOL shouldPlaySound = [self shouldPlaySoundForNotification];

               if (([UIApplication sharedApplication].applicationState != UIApplicationStateActive) && messageText) {
                   UILocalNotification *notification = [[UILocalNotification alloc] init];
                   if (shouldPlaySound) {
                       OWSSound sound = [OWSSounds globalNotificationSound];
                       notification.soundName = [OWSSounds filenameForSound:sound];
                   }

                   NSString *alertBodyString = messageText;
                   notification.alertBody = alertBodyString;

                   [[PushManager sharedManager] presentNotification:notification checkForCancel:NO];
               } else {
                   if (shouldPlaySound && [Environment.shared.preferences soundInForeground]) {
                       OWSSound sound = [OWSSounds globalNotificationSound];
                       SystemSoundID soundId = [OWSSounds systemSoundIDForSound:sound quiet:YES];
                       // Vibrate, respect silent switch, respect "Alert" volume, not media volume.
                       AudioServicesPlayAlertSound(soundId);
                   }
               }
           }];
}

- (void)notifyUserForIncomingMessage:(TSIncomingMessage *)message
                            inThread:(TSThread *)thread
                     contactsManager:(id<ContactsManagerProtocol>)contactsManager
                         transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(message);
    OWSAssertDebug(thread);
    OWSAssertDebug(contactsManager);

    // While batch processing, some of the necessary changes have not been commited.
    NSString *rawMessageText = [message previewTextWithTransaction:transaction];

    // iOS strips anything that looks like a printf formatting character from
    // the notification body, so if we want to dispay a literal "%" in a notification
    // it must be escaped.
    // see https://developer.apple.com/documentation/uikit/uilocalnotification/1616646-alertbody
    // for more details.
    NSString *messageText = [DisplayableText filterNotificationText:rawMessageText];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (thread.isMuted) {
            return;
        }

        BOOL shouldPlaySound = [self shouldPlaySoundForNotification];

        NSString *senderName = [contactsManager displayNameForPhoneIdentifier:message.authorId];
        NSString *groupName = [thread.name ows_stripped];
        if (groupName.length < 1) {
            groupName = [MessageStrings newGroupDefaultTitle];
        }

        if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive && messageText) {
            UILocalNotification *notification = [[UILocalNotification alloc] init];
            if (shouldPlaySound) {
                OWSSound sound = [OWSSounds notificationSoundForThread:thread];
                notification.soundName = [OWSSounds filenameForSound:sound];
            }

            switch (self.notificationPreviewType) {
                case NotificationNamePreview: {

                    // Don't reply from lockscreen if anyone in this conversation is
                    // "no longer verified".
                    BOOL isNoLongerVerified = NO;
                    for (NSString *recipientId in thread.recipientIdentifiers) {
                        if ([OWSIdentityManager.sharedManager verificationStateForRecipientId:recipientId]
                            == OWSVerificationStateNoLongerVerified) {
                            isNoLongerVerified = YES;
                            break;
                        }
                    }

                    notification.category = (isNoLongerVerified ? Signal_Full_New_Message_Category_No_Longer_Verified
                                                                : Signal_Full_New_Message_Category);
                    notification.userInfo = @{
                        Signal_Thread_UserInfo_Key : thread.uniqueId,
                        Signal_Message_UserInfo_Key : message.uniqueId
                    };

                    if ([thread isGroupThread]) {
                        NSString *threadName = [NSString stringWithFormat:@"\"%@\"", groupName];

                        // TODO: Format parameters might change order in l10n.  We should use named parameters.
                        notification.alertBody =
                            [NSString stringWithFormat:NSLocalizedString(@"APN_MESSAGE_IN_GROUP_DETAILED", nil),
                                      senderName,
                                      threadName,
                                      messageText];

                    } else {
                        notification.alertBody = [NSString stringWithFormat:@"%@: %@", senderName, messageText];
                    }
                    break;
                }
                case NotificationNameNoPreview: {
                    notification.userInfo = @{ Signal_Thread_UserInfo_Key : thread.uniqueId };
                    if ([thread isGroupThread]) {
                        notification.alertBody = [NSString
                            stringWithFormat:@"%@ \"%@\"", NSLocalizedString(@"APN_MESSAGE_IN_GROUP", nil), groupName];
                    } else {
                        notification.alertBody = [NSString
                            stringWithFormat:@"%@ %@", NSLocalizedString(@"APN_MESSAGE_FROM", nil), senderName];
                    }
                    break;
                }
                case NotificationNoNameNoPreview:
                    notification.alertBody = NSLocalizedString(@"APN_Message", nil);
                    break;
                default:
                    OWSLogWarn(@"unknown notification preview type: %lu", (unsigned long)self.notificationPreviewType);
                    notification.alertBody = NSLocalizedString(@"APN_Message", nil);
                    break;
            }

            [[PushManager sharedManager] presentNotification:notification checkForCancel:YES];
        } else {
            if (shouldPlaySound && [Environment.shared.preferences soundInForeground]) {
                OWSSound sound = [OWSSounds notificationSoundForThread:thread];
                SystemSoundID soundId = [OWSSounds systemSoundIDForSound:sound quiet:YES];
                // Vibrate, respect silent switch, respect "Alert" volume, not media volume.
                AudioServicesPlayAlertSound(soundId);
            }
        }
    });
}

- (BOOL)shouldPlaySoundForNotification
{
    @synchronized(self)
    {
        // Play no more than 2 notification sounds in a given
        // five-second window.
        const CGFloat kNotificationWindowSeconds = 5.f;
        const NSUInteger kMaxNotificationRate = 2;

        // Cull obsolete notification timestamps from the thread's notification history.
        while (self.notificationHistory.count > 0) {
            NSDate *notificationTimestamp = self.notificationHistory[0];
            CGFloat notificationAgeSeconds = fabs(notificationTimestamp.timeIntervalSinceNow);
            if (notificationAgeSeconds > kNotificationWindowSeconds) {
                [self.notificationHistory removeObjectAtIndex:0];
            } else {
                break;
            }
        }

        // Ignore notifications if necessary.
        BOOL shouldPlaySound = self.notificationHistory.count < kMaxNotificationRate;

        if (shouldPlaySound) {
            // Add new notification timestamp to the thread's notification history.
            NSDate *newNotificationTimestamp = [NSDate new];
            [self.notificationHistory addObject:newNotificationTimestamp];

            return YES;
        } else {
            OWSLogDebug(@"Skipping sound for notification");
            return NO;
        }
    }
}

#pragma mark - Util

- (NotificationType)notificationPreviewType
{
    OWSPreferences *prefs = Environment.shared.preferences;
    return prefs.notificationPreviewType;
}

- (void)presentNotification:(UILocalNotification *)notification identifier:(NSString *)identifier
{
    notification.alertBody = notification.alertBody.filterStringForDisplay;

    DispatchMainThreadSafe(^{
        if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
            OWSLogWarn(@"skipping notification; app is in foreground and active.");
            return;
        }

        // Replace any existing notification
        // e.g. when an "Incoming Call" notification gets replaced with a "Missed Call" notification.
        if (self.currentNotifications[identifier]) {
            [self cancelNotificationWithIdentifier:identifier];
        }

        [[UIApplication sharedApplication] scheduleLocalNotification:notification];
        OWSLogDebug(@"presenting notification with identifier: %@", identifier);

        self.currentNotifications[identifier] = notification;
    });
}

- (void)cancelNotificationWithIdentifier:(NSString *)identifier
{
    DispatchMainThreadSafe(^{
        UILocalNotification *notification = self.currentNotifications[identifier];
        if (!notification) {
            OWSLogWarn(@"Couldn't cancel notification because none was found with identifier: %@", identifier);
            return;
        }
        [self.currentNotifications removeObjectForKey:identifier];

        [[UIApplication sharedApplication] cancelLocalNotification:notification];
    });
}

#ifdef DEBUG

+ (void)presentDebugNotification
{
    OWSAssertIsOnMainThread();

    UILocalNotification *notification = [UILocalNotification new];
    notification.category = Signal_Full_New_Message_Category;
    notification.soundName = [OWSSounds filenameForSound:OWSSound_DefaultiOSIncomingRingtone];
    notification.alertBody = @"test";

    [[UIApplication sharedApplication] scheduleLocalNotification:notification];
}

#endif

- (void)clearAllNotifications
{
    OWSAssertIsOnMainThread();

    [self.currentNotifications removeAllObjects];
}

@end
