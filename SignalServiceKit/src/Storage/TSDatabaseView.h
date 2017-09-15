//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <YapDatabase/YapDatabaseViewTransaction.h>

extern NSString *const kNSNotificationName_DatabaseViewRegistrationComplete;

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

// This method can be called from any thread.
+ (BOOL)hasPendingViewRegistrations;

// This method must be called _AFTER_ registerThreadInteractionsDatabaseView.
+ (void)registerThreadDatabaseView;

+ (void)registerThreadInteractionsDatabaseView;
+ (void)asyncRegisterThreadOutgoingMessagesDatabaseView;

// Instances of OWSReadTracking for wasRead is NO and shouldAffectUnreadCounts is YES.
//
// Should be used for "unread message counts".
+ (void)registerUnreadDatabaseView;

// Should be used for "unread indicator".
//
// Instances of OWSReadTracking for wasRead is NO.
+ (void)asyncRegisterUnseenDatabaseView;

+ (void)asyncRegisterThreadSpecialMessagesDatabaseView;

+ (void)asyncRegisterSecondaryDevicesDatabaseView;

// Returns the "unseen" database view if it is ready;
// otherwise it returns the "unread" database view.
+ (id)unseenDatabaseViewExtension:(YapDatabaseReadTransaction *)transaction;

// NOTE: It is not safe to call this method while hasPendingViewRegistrations is YES.
+ (id)threadOutgoingMessageDatabaseView:(YapDatabaseReadTransaction *)transaction;

// NOTE: It is not safe to call this method while hasPendingViewRegistrations is YES.
+ (id)threadSpecialMessagesDatabaseView:(YapDatabaseReadTransaction *)transaction;

// This method should be called _after_ all async database registrations have been started.
+ (void)asyncRegistrationCompletion;

@end
