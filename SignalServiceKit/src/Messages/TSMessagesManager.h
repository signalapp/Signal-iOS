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

typedef void (^DecryptSuccessBlock)(NSData *_Nullable plaintextData);
typedef void (^DecryptFailureBlock)();
typedef void (^MessageManagerCompletionBlock)();

@interface TSMessagesManager : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)sharedManager;

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) ContactsUpdater *contactsUpdater;

// decryptEnvelope: can be called from any thread.
// successBlock & failureBlock may be called on any thread.
- (void)decryptEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
           successBlock:(DecryptSuccessBlock)successBlock
           failureBlock:(DecryptFailureBlock)failureBlock;

- (void)processEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
          plaintextData:(NSData *_Nullable)plaintextData
            transaction:(YapDatabaseReadWriteTransaction *)transaction;

- (NSUInteger)unreadMessagesCount;
- (NSUInteger)unreadMessagesCountExcept:(TSThread *)thread;
- (NSUInteger)unreadMessagesInThread:(TSThread *)thread;

@end

NS_ASSUME_NONNULL_END
