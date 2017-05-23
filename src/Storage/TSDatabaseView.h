//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
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
extern NSString *TSDynamicMessagesDatabaseViewExtensionName;
extern NSString *TSSecondaryDevicesDatabaseViewExtensionName;

+ (BOOL)registerThreadDatabaseView;
+ (BOOL)registerBuddyConversationDatabaseView;
+ (BOOL)registerUnreadDatabaseView;
+ (BOOL)registerDynamicMessagesDatabaseView;
+ (void)asyncRegisterSecondaryDevicesDatabaseView;

@end
