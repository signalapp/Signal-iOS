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
extern NSString *TSThreadIncomingMessageDatabaseViewExtensionName;
extern NSString *TSThreadOutgoingMessageDatabaseViewExtensionName;
extern NSString *TSUnreadDatabaseViewExtensionName;
extern NSString *TSUnseenDatabaseViewExtensionName;
extern NSString *TSDynamicMessagesDatabaseViewExtensionName;
extern NSString *TSSafetyNumberChangeDatabaseViewExtensionName;
extern NSString *TSSecondaryDevicesDatabaseViewExtensionName;

+ (BOOL)registerThreadDatabaseView;
+ (BOOL)registerThreadInteractionsDatabaseView;
+ (BOOL)registerThreadIncomingMessagesDatabaseView;
+ (BOOL)registerThreadOutgoingMessagesDatabaseView;

// Instances of OWSReadTracking for wasRead is NO and shouldAffectUnreadCounts is YES.
//
// Should be used for "unread message counts".
+ (BOOL)registerUnreadDatabaseView;

// Should be used for "unread indicator".
//
// Instances of OWSReadTracking for wasRead is NO.
+ (BOOL)registerUnseenDatabaseView;

+ (BOOL)registerDynamicMessagesDatabaseView;
+ (BOOL)registerSafetyNumberChangeDatabaseView;
+ (void)asyncRegisterSecondaryDevicesDatabaseView;

@end
