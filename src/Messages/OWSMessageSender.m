//  Created by Michael Kirk on 10/7/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSMessageSender.h"
#import "OWSError.h"
#import "TSMessagesManager+sendMessages.h"
#import "TSNetworkManager.h"
#import "TSOutgoingMessage.h"
#import "TSThread.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageSender ()

@property (nonatomic, readonly) TSOutgoingMessage *message;
@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) TSMessagesManager *messagesManager;

@end

@implementation OWSMessageSender

- (instancetype)initWithMessage:(TSOutgoingMessage *)message
                 networkManager:(TSNetworkManager *)networkManager
                 storageManager:(TSStorageManager *)storageManager
                contactsManager:(id<ContactsManagerProtocol>)contactsManager
                contactsUpdater:(ContactsUpdater *)contactsUpdater
{
    self = [super init];
    if (!self) {
        return self;
    }

    _message = message;
    _networkManager = networkManager;
    _messagesManager = [[TSMessagesManager alloc] initWithNetworkManager:networkManager
                                                          storageManager:storageManager
                                                         contactsManager:contactsManager
                                                         contactsUpdater:contactsUpdater];
    return self;
}

- (void)sendWithSuccess:(void (^)())successBlock failure:(void (^)(NSError *error))failureBlock
{
    [self.messagesManager sendMessage:self.message
        inThread:self.message.thread
        success:^{
            successBlock();
        }
        failure:^{
            NSString *localizedError
                = NSLocalizedString(@"NOTIFICATION_SEND_FAILED", @"Generic notice when message failed to send.");
            NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToSendOutgoingMessage, localizedError);
            failureBlock(error);
        }];
}

@end

NS_ASSUME_NONNULL_END
