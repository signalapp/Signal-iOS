//
//  TSMessagesHandler.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 11/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IncomingPushMessageSignal.pb.h"
#import "TSIncomingMessage.h"
#import "TSInvalidIdentityKeySendingErrorMessage.h"
#import "TSOutgoingMessage.h"
@class TSCall;

@interface TSMessagesManager : NSObject

+ (instancetype)sharedManager;

@property (readonly) YapDatabaseConnection *dbConnection;

- (void)handleMessageSignal:(IncomingPushMessageSignal *)messageSignal;

- (void)processException:(NSException *)exception
         outgoingMessage:(TSOutgoingMessage *)message
                inThread:(TSThread *)thread;
- (void)handleReceivedMessage:(IncomingPushMessageSignal *)message
                  withContent:(PushMessageContent *)content
                  attachments:(NSArray *)attachments;
- (void)handleReceivedMessage:(IncomingPushMessageSignal *)message
                  withContent:(PushMessageContent *)content
                  attachments:(NSArray *)attachments
              completionBlock:(void (^)(NSString *messageIdentifier))completionBlock;

- (void)handleSendToMyself:(TSOutgoingMessage *)outgoingMessage;

- (NSUInteger)unreadMessagesCount;
- (NSUInteger)unreadMessagesCountExcept:(TSThread *)thread;
- (NSUInteger)unreadMessagesInThread:(TSThread *)thread;

@end
