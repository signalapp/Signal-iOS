//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class TSErrorMessage;
@class TSIncomingMessage;
@class TSThread;
@class YapDatabaseReadTransaction;
@class YapDatabaseReadWriteTransaction;

@protocol ContactsManagerProtocol;

@protocol NotificationsProtocol <NSObject>

- (void)notifyUserForIncomingMessage:(TSIncomingMessage *)incomingMessage
                            inThread:(TSThread *)thread
                         transaction:(YapDatabaseReadTransaction *)transaction;

- (void)cancelNotification:(NSString *)identifier;
- (void)clearAllNotifications;

@end

NS_ASSUME_NONNULL_END
