//
//  NotificationsManager.m
//  Signal
//
//  Created by Frederic Jacobs on 22/12/15.
//  Copyright © 2015 Open Whisper Systems. All rights reserved.
//

#import <AudioToolbox/AudioServices.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSErrorMessage.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TextSecureKitEnv.h>
#import "Environment.h"
#import "NotificationsManager.h"
#import "PreferencesUtil.h"
#import "PushManager.h"

@interface NotificationsManager ()

@property SystemSoundID newMessageSound;

@end

@implementation NotificationsManager

- (instancetype)init
{
    self = [super init];

    if (!self) {
        return self;
    }

    NSURL *newMessageURL = [[NSBundle mainBundle] URLForResource:@"NewMessage" withExtension:@"aifc"];
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)newMessageURL, &_newMessageSound);

    return self;
}

- (void)notifyUserForCall:(TSCall *)call inThread:(TSThread *)thread {
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        // Remove previous notification of call and show missed notification.
        UILocalNotification *notif = [[PushManager sharedManager] closeVOIPBackgroundTask];
        TSContactThread *cThread   = (TSContactThread *)thread;

        if (call.callType == RPRecentCallTypeMissed) {
            if (notif) {
                [[UIApplication sharedApplication] cancelLocalNotification:notif];
            }

            UILocalNotification *notification = [[UILocalNotification alloc] init];
            notification.soundName            = @"NewMessage.aifc";
            if ([[Environment preferences] notificationPreviewType] == NotificationNoNameNoPreview) {
                notification.alertBody = [NSString stringWithFormat:NSLocalizedString(@"MISSED_CALL", nil)];
            } else {
                notification.userInfo = @{Signal_Call_UserInfo_Key : cThread.contactIdentifier};
                notification.category = Signal_CallBack_Category;
                notification.alertBody =
                    [NSString stringWithFormat:NSLocalizedString(@"MSGVIEW_MISSED_CALL", nil), [thread name]];
            }

            [[PushManager sharedManager] presentNotification:notification];
        }
    }
}

- (void)notifyUserForErrorMessage:(TSErrorMessage *)message inThread:(TSThread *)thread {
    NSString *messageDescription = message.description;

    if (([UIApplication sharedApplication].applicationState != UIApplicationStateActive) && messageDescription) {
        UILocalNotification *notification = [[UILocalNotification alloc] init];
        notification.userInfo             = @{Signal_Thread_UserInfo_Key : thread.uniqueId};
        notification.soundName            = @"NewMessage.aifc";

        NSString *alertBodyString = @"";

        NSString *authorName = [thread name];
        switch ([[Environment preferences] notificationPreviewType]) {
            case NotificationNamePreview:
            case NotificationNameNoPreview:
                alertBodyString = [NSString stringWithFormat:@"%@: %@", authorName, messageDescription];
                break;
            case NotificationNoNameNoPreview:
                alertBodyString = messageDescription;
                break;
        }
        notification.alertBody = alertBodyString;

        [[PushManager sharedManager] presentNotification:notification];
    } else {
        if ([Environment.preferences soundInForeground]) {
            AudioServicesPlayAlertSound(_newMessageSound);
        }
    }
}

- (void)notifyUserForIncomingMessage:(TSIncomingMessage *)message from:(NSString *)name inThread:(TSThread *)thread {
    NSString *messageDescription = message.description;

    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive && messageDescription) {
        UILocalNotification *notification = [[UILocalNotification alloc] init];
        notification.soundName            = @"NewMessage.aifc";

        switch ([[Environment preferences] notificationPreviewType]) {
            case NotificationNamePreview:
                notification.category = Signal_Full_New_Message_Category;
                notification.userInfo =
                    @{Signal_Thread_UserInfo_Key : thread.uniqueId, Signal_Message_UserInfo_Key : message.uniqueId};

                if ([thread isGroupThread]) {
                    NSString *sender =
                        [[TextSecureKitEnv sharedEnv].contactsManager nameStringForPhoneIdentifier:message.authorId];
                    if (!sender) {
                        sender = message.authorId;
                    }

                    NSString *threadName = [NSString stringWithFormat:@"\"%@\"", name];
                    notification.alertBody =
                        [NSString stringWithFormat:NSLocalizedString(@"APN_MESSAGE_IN_GROUP_DETAILED", nil),
                                                   sender,
                                                   threadName,
                                                   messageDescription];
                } else {
                    notification.alertBody = [NSString stringWithFormat:@"%@: %@", name, messageDescription];
                }
                break;
            case NotificationNameNoPreview: {
                notification.userInfo = @{Signal_Thread_UserInfo_Key : thread.uniqueId};
                if ([thread isGroupThread]) {
                    notification.alertBody =
                        [NSString stringWithFormat:@"%@ \"%@\"", NSLocalizedString(@"APN_MESSAGE_IN_GROUP", nil), name];
                } else {
                    notification.alertBody =
                        [NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"APN_MESSAGE_FROM", nil), name];
                }
                break;
            }
            case NotificationNoNameNoPreview:
                notification.alertBody = NSLocalizedString(@"APN_Message", nil);
                break;
            default:
                notification.alertBody = NSLocalizedString(@"APN_Message", nil);
                break;
        }

        [[PushManager sharedManager] presentNotification:notification];
    } else {
        if ([Environment.preferences soundInForeground]) {
            AudioServicesPlayAlertSound(_newMessageSound);
        }
    }
}

@end
