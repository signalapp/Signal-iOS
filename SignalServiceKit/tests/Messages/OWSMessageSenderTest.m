//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "AxolotlExceptions.h"
#import "HTTPUtils.h"
#import "MessageSender.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSError.h"
#import "OWSUploadOperation.h"
#import "SSKBaseTestObjC.h"
#import "TSAccountManager.h"
#import "TSContactThread.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"
#import "TSOutgoingMessage.h"
#import "TSRequest.h"
#import <SignalCoreKit/Cryptography.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef BROKEN_TESTS

@interface OWSUploadOperation (Testing)

@end

#pragma mark -

@interface MessageSender (Testing)

@property (nonatomic) OWSUploadOperation *uploadingService;

- (void)sendMessageToService:(OutgoingMessagePreparer *)message
                     success:(void (^)(void))successHandler
                     failure:(RetryableFailureHandler)failureHandler;

@end

#pragma mark -

@implementation MessageSender (Testing)

- (NSArray<NSDictionary *> *)deviceMessages:(TSOutgoingMessage *)message
                               forRecipient:(SignalRecipient *)recipient
                                     thread:(TSThread *)thread
{
    OWSLogInfo(@"[OWSFakeMessagesManager] Faking deviceMessages.");
    return @[];
}

- (void)setUploadingService:(OWSUploadingService *)uploadingService
{
    _uploadingService = uploadingService;
}

- (OWSUploadingService *)uploadingService
{
    return _uploadingService;
}

@end

#pragma mark -

@interface OWSFakeUploadingService : OWSUploadOperation

@property (nonatomic, readonly) BOOL shouldSucceed;

@end

#pragma mark -

@implementation OWSFakeUploadingService

- (void)uploadAttachmentStream:(TSAttachmentStream *)attachmentStream
                       message:(TSOutgoingMessage *)outgoingMessage
                       success:(void (^)(void))successHandler
                       failure:(void (^)(NSError *error))failureHandler
{
    if (self.shouldSucceed) {
        successHandler();
    } else {
        NSError *error = [OWSUnretryableError new];
        failureHandler(error);
    }
}

@end

#pragma mark -

@interface OWSFakeURLSessionDataTask : NSURLSessionDataTask

@property (copy) NSHTTPURLResponse *response;

- (instancetype)initWithStatusCode:(long)statusCode;

@end

#pragma mark -

@implementation OWSFakeURLSessionDataTask

@synthesize response = _response;

- (instancetype)initWithStatusCode:(long)statusCode
{
    self = [super init];

    if (!self) {
        return self;
    }

    NSURL *fakeURL = [NSURL URLWithString:@"http://127.0.0.1"];
    _response = [[NSHTTPURLResponse alloc] initWithURL:fakeURL statusCode:statusCode HTTPVersion:nil headerFields:nil];

    return self;
}

@end

#pragma mark -

@interface MessageSenderFakeNetworkManager : OWSFakeNetworkManager

- (instancetype)init;
- (instancetype)initWithSuccess:(BOOL)shouldSucceed NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) BOOL shouldSucceed;

@end

#pragma mark -

@implementation MessageSenderFakeNetworkManager

- (instancetype)initWithSuccess:(BOOL)shouldSucceed
{
    self = [self init];
    if (!self) {
        return self;
    }

    _shouldSucceed = shouldSucceed;

    return self;
}

- (void)makeRequest:(TSRequest *)request
            success:(void (^)(NSURLSessionDataTask *task, id responseObject))success
            failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failure
{
    BOOL isSubmitMessageRequest
        = ([request.HTTPMethod isEqualToString:@"PUT"] && [request.URL.path hasPrefix:textSecureMessagesAPI]);

    if (isSubmitMessageRequest) {
        if (self.shouldSucceed) {
            success([NSURLSessionDataTask new], @{});
        } else {
            NSError *error = [OWSError withError:OWSErrorCodeFailedToSendOutgoingMessage
                                     description:@"fake error description")
                                     isRetryable:NO];
            OWSFakeURLSessionDataTask *task = [[OWSFakeURLSessionDataTask alloc] initWithStatusCode:500];
            failure(task, error);
        }
    } else {
        [super makeRequest:request success:success failure:failure];
    }
}

@end

#pragma mark -

@interface MessageSenderTest : SSKBaseTestObjC

@property (nonatomic) TSThread *thread;
@property (nonatomic) TSOutgoingMessage *expiringMessage;
@property (nonatomic) TSOutgoingMessage *unexpiringMessage;
@property (nonatomic) MessageSenderFakeNetworkManager *networkManager;
@property (nonatomic) MessageSender *successfulMessageSender;
@property (nonatomic) MessageSender *unsuccessfulMessageSender;

@end

#pragma mark -

@implementation MessageSenderTest

- (void)setUp
{
    [super setUp];

    // Hack to make sure we don't explode when sending sync message.
    [[TSAccountManager shared] storeLocalNumber:@"+13231231234"];

    self.thread = [[TSContactThread alloc] initWithUniqueId:@"fake-thread-id"];
    [self.thread save];

    self.unexpiringMessage = [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:1
                                                                                  thread:self.thread
                                                                             messageBody:@"outgoing message"
                                                                           attachmentIds:@[]
                                                                        expiresInSeconds:0
                                                                         expireStartedAt:0
                                                                          isVoiceMessage:NO
                                                                        groupMetaMessage:TSGroupMetaMessageUnspecified
                                                                           quotedMessage:nil
                                                                            contactShare:nil
                                                                             linkPreview:nil];
    [self.unexpiringMessage save];

    self.expiringMessage = [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:1
                                                                                thread:self.thread
                                                                           messageBody:@"outgoing message"
                                                                         attachmentIds:@[]
                                                                      expiresInSeconds:30
                                                                       expireStartedAt:0
                                                                        isVoiceMessage:NO
                                                                      groupMetaMessage:TSGroupMetaMessageUnspecified
                                                                         quotedMessage:nil
                                                                          contactShare:nil
                                                                           linkPreview:nil];
    [self.expiringMessage save];

    OWSFakeContactsManager *contactsManager = [OWSFakeContactsManager new];

    // Successful Sending
    NetworkManager *successfulNetworkManager = [[MessageSenderFakeNetworkManager alloc] initWithSuccess:YES];
    self.successfulMessageSender = [[MessageSender alloc] initWithNetworkManager:successfulNetworkManager
                                                                 contactsManager:contactsManager];

    // Unsuccessful Sending
    NetworkManager *unsuccessfulNetworkManager = [[MessageSenderFakeNetworkManager alloc] initWithSuccess:NO];
    self.unsuccessfulMessageSender = [[MessageSender alloc] initWithNetworkManager:unsuccessfulNetworkManager
                                                                   contactsManager:contactsManager];
}

- (void)testExpiringMessageTimerStartsOnSuccessWhenDisappearingMessagesEnabled
{
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        OWSDisappearingMessagesConfiguration *configuration =
            [self.thread disappearingMessagesDurationWithTransaction:transaction];
        configuration = [configuration copyAsEnabledWithDurationSeconds:10];

        [configuration anyUpsertWithTransaction:transaction];
    }];

    MessageSender *messageSender = self.successfulMessageSender;

    // Sanity Check
    XCTAssertEqual(0, self.expiringMessage.expiresAt);

    XCTestExpectation *messageStartedExpiration = [self expectationWithDescription:@"messageStartedExpiration"];
    [messageSender sendMessage:self.expiringMessage
        success:^() {
            __block TSMessage *_Nullable reloadedMessage;
            [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
                reloadedMessage = [TSMessage anyFetchMessageWithUniqueId:self.expiringMessage.uniqueId
                                                             transaction:transaction];
            }];
            if (reloadedMessage == nil) {
                XCTFail(@"Couldn't reload message.");
                return;
            } else if (reloadedMessage.hasPerConversationExpirationStarted) {
                [messageStartedExpiration fulfill];
            } else {
                XCTFail(@"Message expiration was supposed to start.");
            }
        }
        failure:^(NSError *error) {
            XCTFail(@"Message failed to send");
        }];

    [self waitForExpectationsWithTimeout:5
                                 handler:^(NSError *error) {
                                     OWSLogInfo(@"Expiration timer not set in time.");
                                 }];
}

- (void)testExpiringMessageTimerDoesNotStartsWhenDisabled
{
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        OWSDisappearingMessagesConfiguration *configuration =
            [self.thread disappearingMessagesDurationWithTransaction:transaction];
        configuration = [configuration copyAsEnabledWithDurationSeconds:10];

        [configuration anyUpsertWithTransaction:transaction];
    }];

    MessageSender *messageSender = self.successfulMessageSender;

    XCTestExpectation *messageDidNotStartExpiration = [self expectationWithDescription:@"messageDidNotStartExpiration"];
    [messageSender sendMessageToService:self.unexpiringMessage
        success:^() {
            if (self.unexpiringMessage.hasPerConversationExpiration || self.unexpiringMessage.expiresAt > 0) {
                XCTFail(@"Message expiration was not supposed to start.");
            } else {
                [messageDidNotStartExpiration fulfill];
            }
        }
        failure:^(NSError *error) {
            XCTFail(@"Message failed to send");
        }];

    [self waitForExpectationsWithTimeout:5
                                 handler:^(NSError *error) {
                                     OWSLogInfo(@"Expiration timer not set in time.");
                                 }];
}

- (void)testExpiringMessageTimerDoesNotStartsOnFailure
{
    MessageSender *messageSender = self.unsuccessfulMessageSender;

    // Sanity Check
    XCTAssertEqual(0, self.expiringMessage.expiresAt);

    XCTestExpectation *messageDidNotStartExpiration = [self expectationWithDescription:@"messageStartedExpiration"];
    [messageSender sendMessageToService:self.expiringMessage
        success:^() {
            XCTFail(@"Message sending was supposed to fail.");
        }
        failure:^(NSError *error) {
            if (self.expiringMessage.expiresAt == 0) {
                [messageDidNotStartExpiration fulfill];
            } else {
                XCTFail(@"Message expiration was not supposed to start.");
            }
        }];

    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testTextMessageIsMarkedAsSentOnSuccess
{
    MessageSender *messageSender = self.successfulMessageSender;

    TSOutgoingMessage *message = [TSOutgoingMessage outgoingMessageInThread:self.thread
                                                                messageBody:@"We want punks in the palace."
                                                               attachmentId:nil];

    XCTestExpectation *markedAsSent = [self expectationWithDescription:@"markedAsSent"];
    [messageSender sendMessageToService:message
        success:^() {
            if (message.messageState == TSOutgoingMessageStateSent) {
                [markedAsSent fulfill];
            } else {
                XCTFail(@"Unexpected message state");
            }
        }
        failure:^(NSError *error) {
            XCTFail(@"sendMessage should succeed.");
        }];

    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testMediaMessageIsMarkedAsSentOnSuccess
{
    MessageSender *messageSender = self.successfulMessageSender;
    messageSender.uploadingService = [[OWSFakeUploadingService alloc] initWithSuccess:YES];

    TSOutgoingMessageBuilder *messageBuilder = [[TSOutgoingMessageBuilder alloc] init];
    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:1
                                                                       thread:self.thread
                                                                  messageBody:@"We want punks in the palace."];

    XCTestExpectation *markedAsSent = [self expectationWithDescription:@"markedAsSent"];
    [messageSender sendAttachmentData:[NSData new]
        contentType:@"image/gif"
        sourceFilename:nil
        inMessage:message
        success:^() {
            if (message.messageState == TSOutgoingMessageStateSentToService) {
                [markedAsSent fulfill];
            } else {
                XCTFail(@"Unexpected message state");
            }
        }
        failure:^(NSError *error) {
            XCTFail(@"sendMessage should succeed.");
        }];

    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testTextMessageIsMarkedAsUnsentOnFailure
{
    MessageSender *messageSender = self.unsuccessfulMessageSender;
    messageSender.uploadingService = [[OWSFakeUploadingService alloc] initWithSuccess:YES];

    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:1
                                                                       thread:self.thread
                                                                  messageBody:@"We want punks in the palace."];

    XCTestExpectation *markedAsUnsent = [self expectationWithDescription:@"markedAsUnsent"];
    [messageSender sendMessage:message
        success:^() {
            XCTFail(@"sendMessage should fail.");
        }
        failure:^(NSError *error) {
            if (message.messageState == TSOutgoingMessageStateUnsent) {
                [markedAsUnsent fulfill];
            } else {
                XCTFail(@"Unexpected message state");
            }
        }];

    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testMediaMessageIsMarkedAsUnsentOnFailureToSend
{
    MessageSender *messageSender = self.unsuccessfulMessageSender;
    // Assume that upload will go well, but that failure happens elsewhere in message sender.
    messageSender.uploadingService = [[OWSFakeUploadingService alloc] initWithSuccess:YES];

    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:1
                                                                       thread:self.thread
                                                                  messageBody:@"We want punks in the palace."];

    XCTestExpectation *markedAsUnsent = [self expectationWithDescription:@"markedAsUnsent"];
    [messageSender sendAttachmentData:[NSData new]
        contentType:@"image/gif"
        sourceFilename:nil
        inMessage:message
        success:^{
            XCTFail(@"sendMessage should fail.");
        }
        failure:^(NSError *_Nonnull error) {
            if (message.messageState == TSOutgoingMessageStateUnsent) {
                [markedAsUnsent fulfill];
            } else {
                XCTFail(@"Unexpected message state");
            }
        }];

    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testMediaMessageIsMarkedAsUnsentOnFailureToUpload
{
    MessageSender *messageSender = self.successfulMessageSender;
    // Assume that upload fails, but other sending stuff would succeed.
    messageSender.uploadingService = [[OWSFakeUploadingService alloc] initWithSuccess:NO];

    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:1
                                                                       thread:self.thread
                                                                  messageBody:@"We want punks in the palace."];

    XCTestExpectation *markedAsUnsent = [self expectationWithDescription:@"markedAsUnsent"];
    [messageSender sendAttachmentData:[NSData new]
        contentType:@"image/gif"
        sourceFilename:nil
        inMessage:message
        success:^{
            XCTFail(@"sendMessage should fail.");
        }
        failure:^(NSError *_Nonnull error) {
            if (message.messageState == TSOutgoingMessageStateUnsent) {
                [markedAsUnsent fulfill];
            } else {
                XCTFail(@"Unexpected message state");
            }
        }];

    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testGroupSend
{
    MessageSender *messageSender = self.successfulMessageSender;

    SignalRecipient *successfulRecipient =
        [[SignalRecipient alloc] initWithTextSecureIdentifier:@"successful-recipient-id" relay:nil];
    SignalRecipient *successfulRecipient2 =
        [[SignalRecipient alloc] initWithTextSecureIdentifier:@"successful-recipient-id2" relay:nil];

    __block TSGroupThread *thread;
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        thread = [GroupManager createGroupForTestsObjcWithMembers:@[
            successfulRecipient.address,
            successfulRecipient2.address,
        ]
                                                             name:@"group title"
                                                       avatarData:nil
                                                      transaction:transaction];
    }];

    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:1
                                                                       thread:groupThread
                                                                  messageBody:@"We want punks in the palace."];

    XCTestExpectation *markedAsSent = [self expectationWithDescription:@"markedAsSent"];
    [messageSender sendMessage:message
        success:^{
            if (message.messageState == TSOutgoingMessageStateSentToService) {
                [markedAsSent fulfill];
            } else {
                XCTFail(@"Unexpected message state");
            }
        }
        failure:^(NSError *_Nonnull error) {
            XCTFail(@"sendMessage should not fail.");
        }];

    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testGetRecipients
{
    SignalRecipient *recipient = [[SignalRecipient alloc] initWithTextSecureIdentifier:@"fake-recipient-id" relay:nil];
    [recipient save];

    MessageSender *messageSender = self.successfulMessageSender;

    NSError *error;
    NSArray<SignalRecipient *> *recipients = [messageSender getRecipients:@[ recipient.address ] error:&error];

    XCTAssertNil(error);
    XCTAssertEqualObjects(recipient, recipients.firstObject);
}

@end

#endif

NS_ASSUME_NONNULL_END
