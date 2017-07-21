//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSIncomingMessage.h"
#import "TSInvalidIdentityKeySendingErrorMessage.h"
#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class TSNetworkManager;
@class TSStorageManager;
@class OWSSignalServiceProtosEnvelope;
@class OWSSignalServiceProtosDataMessage;
@class ContactsUpdater;
@class OWSMessageSender;
@protocol ContactsManagerProtocol;
@protocol OWSCallMessageHandler;

typedef void (^MessageManagerCompletionBlock)();

@interface TSMessagesManager : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)sharedManager;

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) ContactsUpdater *contactsUpdater;

- (void)handleReceivedEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                    completion:(nullable MessageManagerCompletionBlock)completion;

/**
 * @returns
 *   Group or Contact thread for message, creating a new one if necessary.
 */
- (TSThread *)threadForEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                    dataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage;

- (NSUInteger)unreadMessagesCount;
- (NSUInteger)unreadMessagesCountExcept:(TSThread *)thread;
- (NSUInteger)unreadMessagesInThread:(TSThread *)thread;

@end

NS_ASSUME_NONNULL_END
