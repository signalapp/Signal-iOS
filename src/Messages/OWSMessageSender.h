//  Created by Michael Kirk on 10/7/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class TSOutgoingMessage;
@class TSNetworkManager;
@class TSStorageManager;
@class ContactsUpdater;
@protocol ContactsManagerProtocol;

@interface OWSMessageSender : NSObject

- (instancetype)initWithMessage:(TSOutgoingMessage *)message
                 networkManager:(TSNetworkManager *)networkManager
                 storageManager:(TSStorageManager *)storageManager
                contactsManager:(id<ContactsManagerProtocol>)contactsManager
                contactsUpdater:(ContactsUpdater *)contactsUpdater;

- (void)sendWithSuccess:(void (^)())successBlock failure:(void (^)(NSError *error))failureBlock;

@end

NS_ASSUME_NONNULL_END
