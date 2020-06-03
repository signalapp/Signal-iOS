//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSStorage.h"
#import <YapDatabase/YapDatabaseViewTransaction.h>

NS_ASSUME_NONNULL_BEGIN

// POST GRDB TODO - Some of these views can be removed.
extern NSString *const TSInboxGroup;
extern NSString *const TSArchiveGroup;
extern NSString *const TSUnreadIncomingMessagesGroup;
extern NSString *const TSSecondaryDevicesGroup;

extern NSString *const TSThreadDatabaseViewExtensionName;

extern NSString *const TSMessageDatabaseViewExtensionName;
extern NSString *const TSMessageDatabaseViewExtensionName_Legacy;

extern NSString *const TSThreadOutgoingMessageDatabaseViewExtensionName;
extern NSString *const TSThreadSpecialMessagesDatabaseViewExtensionName;
extern NSString *const TSIncompleteViewOnceMessagesDatabaseViewExtensionName;
extern NSString *const TSIncompleteViewOnceMessagesGroup;

extern NSString *const TSInteractionsBySortIdGroup;
extern NSString *const TSInteractionsBySortIdDatabaseViewExtensionName;

extern NSString *const TSLazyRestoreAttachmentsGroup;
extern NSString *const TSLazyRestoreAttachmentsDatabaseViewExtensionName;

@interface TSDatabaseView : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

#pragma mark - Views

// POST GRDB TODO: Remove these methods?

+ (id)threadOutgoingMessageDatabaseView:(YapDatabaseReadTransaction *)transaction;

+ (id)threadSpecialMessagesDatabaseView:(YapDatabaseReadTransaction *)transaction;

+ (id)incompleteViewOnceMessagesDatabaseView:(YapDatabaseReadTransaction *)transaction;

#pragma mark - Registration

+ (void)registerCrossProcessNotifier:(OWSStorage *)storage;

// This method must be called _AFTER_ asyncRegisterThreadInteractionsDatabaseView.
+ (void)asyncRegisterThreadDatabaseView:(OWSStorage *)storage;

+ (void)asyncRegisterThreadInteractionsDatabaseView:(OWSStorage *)storage;
+ (void)asyncRegisterLegacyThreadInteractionsDatabaseView:(OWSStorage *)storage;
+ (void)asyncRegisterInteractionsBySortIdDatabaseView:(OWSStorage *)storage;

+ (void)asyncRegisterThreadOutgoingMessagesDatabaseView:(OWSStorage *)storage;

+ (void)asyncRegisterThreadSpecialMessagesDatabaseView:(OWSStorage *)storage;

+ (void)asyncRegisterIncompleteViewOnceMessagesDatabaseView:(OWSStorage *)storage;

+ (void)asyncRegisterLazyRestoreAttachmentsDatabaseView:(OWSStorage *)storage;

@end

NS_ASSUME_NONNULL_END
