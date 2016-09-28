//
//  TSDatabaseView.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 17/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabaseViewTransaction.h>

@interface TSDatabaseView : NSObject

extern NSString *TSInboxGroup;
extern NSString *TSArchiveGroup;
extern NSString *TSUnreadIncomingMessagesGroup;
extern NSString *TSSecondaryDevicesGroup;

extern NSString *TSThreadDatabaseViewExtensionName;
extern NSString *TSMessageDatabaseViewExtensionName;
extern NSString *TSUnreadDatabaseViewExtensionName;
extern NSString *TSSecondaryDevicesDatabaseViewExtensionName;

+ (BOOL)registerThreadDatabaseView;
+ (BOOL)registerBuddyConversationDatabaseView;
+ (BOOL)registerUnreadDatabaseView;
+ (void)asyncRegisterSecondaryDevicesDatabaseView;

@end
