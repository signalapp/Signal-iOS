//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSStorage.h"
#import <YapDatabase/YapDatabaseViewTransaction.h>

extern NSString *const TSInboxGroup;
extern NSString *const TSArchiveGroup;
extern NSString *const TSUnreadIncomingMessagesGroup;
extern NSString *const TSSecondaryDevicesGroup;

extern NSString *const TSThreadDatabaseViewExtensionName;

extern NSString *const TSMessageDatabaseViewExtensionName;
extern NSString *const TSUnreadDatabaseViewExtensionName;

extern NSString *const TSSecondaryDevicesDatabaseViewExtensionName;

@interface TSDatabaseView : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (void)registerCrossProcessNotifier:(OWSStorage *)storage;

// This method must be called _AFTER_ registerThreadInteractionsDatabaseView.
+ (void)registerThreadDatabaseView:(OWSStorage *)storage;

+ (void)registerThreadInteractionsDatabaseView:(OWSStorage *)storage;
+ (void)asyncRegisterThreadOutgoingMessagesDatabaseView:(OWSStorage *)storage;

// Instances of OWSReadTracking for wasRead is NO and shouldAffectUnreadCounts is YES.
//
// Should be used for "unread message counts".
+ (void)registerUnreadDatabaseView:(OWSStorage *)storage;

// Should be used for "unread indicator".
//
// Instances of OWSReadTracking for wasRead is NO.
+ (void)asyncRegisterUnseenDatabaseView:(OWSStorage *)storage;

+ (void)asyncRegisterThreadSpecialMessagesDatabaseView:(OWSStorage *)storage;

+ (void)asyncRegisterSecondaryDevicesDatabaseView:(OWSStorage *)storage;

// Returns the "unseen" database view if it is ready;
// otherwise it returns the "unread" database view.
+ (id)unseenDatabaseViewExtension:(YapDatabaseReadTransaction *)transaction;

// NOTE: It is not safe to call this method while hasPendingViewRegistrations is YES.
+ (id)threadOutgoingMessageDatabaseView:(YapDatabaseReadTransaction *)transaction;

// NOTE: It is not safe to call this method while hasPendingViewRegistrations is YES.
+ (id)threadSpecialMessagesDatabaseView:(YapDatabaseReadTransaction *)transaction;

@end
