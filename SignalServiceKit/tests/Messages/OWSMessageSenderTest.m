//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageSender.h"
#import "Cryptography.h"
#import "NSError+MessageSending.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSError.h"
#import "OWSFakeContactsManager.h"
#import "OWSFakeNetworkManager.h"
#import "OWSPrimaryStorage.h"
#import "OWSUploadOperation.h"
#import "SSKBaseTest.h"
#import "TSAccountManager.h"
#import "TSContactThread.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"
#import "TSNetworkManager.h"
#import "TSOutgoingMessage.h"
#import "TSRequest.h"
#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/SessionBuilder.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef BROKEN_TESTS

@interface OWSUploadOperation (Testing)

- (instancetype)initWithAttachmentId:(NSString *)attachmentId
                        dbConnection:(YapDatabaseConnection *)dbConnection
                      networkManager:(TSNetworkManager *)networkManager;

@end

#pragma mark -

@interface OWSMessageSender (Testing)

@property (nonatomic) OWSUploadOperation *uploadingService;

- (void)sendMessageToService:(TSOutgoingMessage *)message
                     success:(void (^)(void))successHandler
                     failure:(RetryableFailureHandler)failureHandler;

@end

#pragma mark -

@implementation OWSMessageSender (Testing)

- (NSArray<NSDictionary *> *)deviceMessages:(TSOutgoingMessage *)message
                               forRecipient:(SignalRecipient *)recipient
                                   inThread:(TSThread *)thread
{
    NSLog(@"[OWSFakeMessagesManager] Faking deviceMessages.");
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

- (instancetype)initWithAttachmentId:(NSString *)attachmentId
                        dbConnection:(YapDatabaseConnection *)dbConnection
                       shouldSucceed:(BOOL)shouldSucceed
{
    self =
        [super initWithAttachmentId:attachmentId dbConnection:dbConnection networkManager:[OWSFakeNetworkManager new]];
    if (!self) {
        return self;
    }

    _shouldSucceed = shouldSucceed;

    return self;
}

- (void)uploadAttachmentStream:(TSAttachmentStream *)attachmentStream
                       message:(TSOutgoingMessage *)outgoingMessage
                       success:(void (^)(void))successHandler
                       failure:(void (^)(NSError *error))failureHandler
{
    if (self.shouldSucceed) {
        successHandler();
    } else {
        NSError *error = OWSErrorMakeFailedToSendOutgoingMessageError();
        [error setIsRetryable:NO];

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

@interface OWSMessageSenderFakeNetworkManager : OWSFakeNetworkManager

- (instancetype)init;
- (instancetype)initWithSuccess:(BOOL)shouldSucceed NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) BOOL shouldSucceed;

@end

#pragma mark -

@implementation OWSMessageSenderFakeNetworkManager

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
            NSError *error
                = OWSErrorWithCodeDescription(OWSErrorCodeFailedToSendOutgoingMessage, @"fake error description");
            OWSFakeURLSessionDataTask *task = [[OWSFakeURLSessionDataTask alloc] initWithStatusCode:500];
            failure(task, error);
        }
    } else {
        [super makeRequest:request success:success failure:failure];
    }
}

@end

#pragma mark -

@interface TSAccountManager (Testing)

- (void)storeLocalNumber:(NSString *)localNumber;

@end

#pragma mark -

@interface OWSMessageSenderTest : SSKBaseTest

@property (nonatomic) TSThread *thread;
@property (nonatomic) TSOutgoingMessage *expiringMessage;
@property (nonatomic) TSOutgoingMessage *unexpiringMessage;
@property (nonatomic) OWSMessageSenderFakeNetworkManager *networkManager;
@property (nonatomic) OWSMessageSender *successfulMessageSender;
@property (nonatomic) OWSMessageSender *unsuccessfulMessageSender;

@end

#pragma mark -

@implementation OWSMessageSenderTest

- (void)setUp
{
    [super setUp];

    // Hack to make sure we don't explode when sending sync message.
    [[TSAccountManager sharedInstance] storeLocalNumber:@"+13231231234"];

    self.thread = [[TSContactThread alloc] initWithUniqueId:@"fake-thread-id"];
    [self.thread save];

    self.unexpiringMessage = [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:1
                                                                                inThread:self.thread
                                                                             messageBody:@"outgoing message"
                                                                           attachmentIds:[NSMutableArray new]
                                                                        expiresInSeconds:0
                                                                         expireStartedAt:0
                                                                          isVoiceMessage:NO
                                                                        groupMetaMessage:TSGroupMetaMessageUnspecified
                                                                           quotedMessage:nil
                                                                            contactShare:nil];
    [self.unexpiringMessage save];

    self.expiringMessage = [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:1
                                                                              inThread:self.thread
                                                                           messageBody:@"outgoing message"
                                                                         attachmentIds:[NSMutableArray new]
                                                                      expiresInSeconds:30
                                                                       expireStartedAt:0
                                                                        isVoiceMessage:NO
                                                                      groupMetaMessage:TSGroupMetaMessageUnspecified
                                                                         quotedMessage:nil
                                                                          contactShare:nil];
    [self.expiringMessage save];

    OWSPrimaryStorage *storageManager = [OWSPrimaryStorage sharedManager];
    OWSFakeContactsManager *contactsManager = [OWSFakeContactsManager new];

    // Successful Sending
    TSNetworkManager *successfulNetworkManager = [[OWSMessageSenderFakeNetworkManager alloc] initWithSuccess:YES];
    self.successfulMessageSender = [[OWSMessageSender alloc] initWithNetworkManager:successfulNetworkManager
                                                                     primaryStorage:primaryStorage
                                                                    contactsManager:contactsManager];

    // Unsuccessful Sending
    TSNetworkManager *unsuccessfulNetworkManager = [[OWSMessageSenderFakeNetworkManager alloc] initWithSuccess:NO];
    self.unsuccessfulMessageSender = [[OWSMessageSender alloc] initWithNetworkManager:unsuccessfulNetworkManager
                                                                       primaryStorage:primaryStorage
                                                                      contactsManager:contactsManager];
}

- (void)testExpiringMessageTimerStartsOnSuccessWhenDisappearingMessagesEnabled
{
    [[[OWSDisappearingMessagesConfiguration alloc] initWithThreadId:self.thread.uniqueId enabled:YES durationSeconds:10]
        save];

    OWSMessageSender *messageSender = self.successfulMessageSender;

    // Sanity Check
    XCTAssertEqual(0, self.expiringMessage.expiresAt);

    XCTestExpectation *messageStartedExpiration = [self expectationWithDescription:@"messageStartedExpiration"];
    [messageSender sendMessage:self.expiringMessage
        success:^() {
            //FIXME remove sleep hack in favor of expiringMessage completion handler
            sleep(2);
            if (self.expiringMessage.expiresAt > 0) {
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
                                     NSLog(@"Expiration timer not set in time.");
                                 }];
}

- (void)testExpiringMessageTimerDoesNotStartsWhenDisabled
{
    [[[OWSDisappearingMessagesConfiguration alloc] initWithThreadId:self.thread.uniqueId enabled:NO durationSeconds:10]
        save];

    OWSMessageSender *messageSender = self.successfulMessageSender;

    XCTestExpectation *messageDidNotStartExpiration = [self expectationWithDescription:@"messageDidNotStartExpiration"];
    [messageSender sendMessageToService:self.unexpiringMessage
        success:^() {
            if (self.unexpiringMessage.isExpiringMessage || self.unexpiringMessage.expiresAt > 0) {
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
                                     NSLog(@"Expiration timer not set in time.");
                                 }];
}

- (void)testExpiringMessageTimerDoesNotStartsOnFailure
{
    OWSMessageSender *messageSender = self.unsuccessfulMessageSender;

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
    OWSMessageSender *messageSender = self.successfulMessageSender;

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
    OWSMessageSender *messageSender = self.successfulMessageSender;
    messageSender.uploadingService = [[OWSFakeUploadingService alloc] initWithSuccess:YES];

    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:1
                                                                     inThread:self.thread
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
    OWSMessageSender *messageSender = self.unsuccessfulMessageSender;
    messageSender.uploadingService = [[OWSFakeUploadingService alloc] initWithSuccess:YES];

    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:1
                                                                     inThread:self.thread
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
    OWSMessageSender *messageSender = self.unsuccessfulMessageSender;
    // Assume that upload will go well, but that failure happens elsewhere in message sender.
    messageSender.uploadingService = [[OWSFakeUploadingService alloc] initWithSuccess:YES];

    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:1
                                                                     inThread:self.thread
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
    OWSMessageSender *messageSender = self.successfulMessageSender;
    // Assume that upload fails, but other sending stuff would succeed.
    messageSender.uploadingService = [[OWSFakeUploadingService alloc] initWithSuccess:NO];

    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:1
                                                                     inThread:self.thread
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
    OWSMessageSender *messageSender = self.successfulMessageSender;


    NSData *groupIdData = [Cryptography generateRandomBytes:32];
    SignalRecipient *successfulRecipient =
        [[SignalRecipient alloc] initWithTextSecureIdentifier:@"successful-recipient-id" relay:nil];
    SignalRecipient *successfulRecipient2 =
        [[SignalRecipient alloc] initWithTextSecureIdentifier:@"successful-recipient-id2" relay:nil];

    TSGroupModel *groupModel = [[TSGroupModel alloc]
        initWithTitle:@"group title"
            memberIds:[@[ successfulRecipient.uniqueId, successfulRecipient2.uniqueId ] mutableCopy]
                image:nil
              groupId:groupIdData];
    TSGroupThread *groupThread = [TSGroupThread getOrCreateThreadWithGroupModel:groupModel];
    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:1
                                                                     inThread:groupThread
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

    OWSMessageSender *messageSender = self.successfulMessageSender;

    NSError *error;
    NSArray<SignalRecipient *> *recipients = [messageSender getRecipients:@[ recipient.uniqueId ] error:&error];

    XCTAssertNil(error);
    XCTAssertEqualObjects(recipient, recipients.firstObject);
}

@end

#endif

NS_ASSUME_NONNULL_END
