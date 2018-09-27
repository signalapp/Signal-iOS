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

extern NSString *const TSLazyRestoreAttachmentsGroup;
extern NSString *const TSLazyRestoreAttachmentsDatabaseViewExtensionName;

@interface TSDatabaseView : NSObject

- (instancetype)init NS_UNAVAILABLE;

#pragma mark - Views

// Returns the "unseen" database view if it is ready;
// otherwise it returns the "unread" database view.
+ (id)unseenDatabaseViewExtension:(YapDatabaseReadTransaction *)transaction;

+ (id)threadOutgoingMessageDatabaseView:(YapDatabaseReadTransaction *)transaction;

+ (id)threadSpecialMessagesDatabaseView:(YapDatabaseReadTransaction *)transaction;

#pragma mark - Registration

+ (void)registerCrossProcessNotifier:(OWSStorage *)storage;

// This method must be called _AFTER_ asyncRegisterThreadInteractionsDatabaseView.
+ (void)asyncRegisterThreadDatabaseView:(OWSStorage *)storage;

+ (void)asyncRegisterThreadInteractionsDatabaseView:(OWSStorage *)storage;
+ (void)asyncRegisterThreadOutgoingMessagesDatabaseView:(OWSStorage *)storage;

// Instances of OWSReadTracking for wasRead is NO and shouldAffectUnreadCounts is YES.
//
// Should be used for "unread message counts".
+ (void)asyncRegisterUnreadDatabaseView:(OWSStorage *)storage;

// Should be used for "unread indicator".
//
// Instances of OWSReadTracking for wasRead is NO.
+ (void)asyncRegisterUnseenDatabaseView:(OWSStorage *)storage;

+ (void)asyncRegisterThreadSpecialMessagesDatabaseView:(OWSStorage *)storage;

+ (void)asyncRegisterSecondaryDevicesDatabaseView:(OWSStorage *)storage;

+ (void)asyncRegisterLazyRestoreAttachmentsDatabaseView:(OWSStorage *)storage;

@end
