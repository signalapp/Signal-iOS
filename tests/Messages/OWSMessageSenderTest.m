//  Created by Michael Kirk on 10/7/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSError.h"
#import "OWSFakeContactsManager.h"
#import "OWSFakeContactsUpdater.h"
#import "OWSMessageSender.h"
#import "TSContactThread.h"
#import "TSNetworkManager.h"
#import "TSOutgoingMessage.h"
#import "TSStorageManager+keyingMaterial.h"
#import "TSStorageManager.h"
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSFakeURLSessionDataTask : NSURLSessionDataTask

@property (copy) NSHTTPURLResponse *response;

- (instancetype)initWithStatusCode:(long)statusCode;

@end

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

@interface OWSMessageSenderFakeNetworkManager : TSNetworkManager

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithSuccess:(BOOL)shouldSucceed NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) BOOL shouldSucceed;

@end

@implementation OWSMessageSenderFakeNetworkManager

- (instancetype)initWithSuccess:(BOOL)shouldSucceed
{
    // intentionally skipping super init which explodes without setup.
    _shouldSucceed = shouldSucceed;

    return self;
}

- (void)makeRequest:(TSRequest *)request
            success:(void (^)(NSURLSessionDataTask *task, id responseObject))success
            failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failure
{
    if ([request isKindOfClass:[TSSubmitMessageRequest class]]) {
        if (self.shouldSucceed) {
            success([NSURLSessionDataTask new], @{});
        } else {
            NSError *error
                = OWSErrorWithCodeDescription(OWSErrorCodeFailedToSendOutgoingMessage, @"fake error description");
            OWSFakeURLSessionDataTask *task = [[OWSFakeURLSessionDataTask alloc] initWithStatusCode:500];
            failure(task, error);
        }
    } else {
        NSLog(@"Ignoring unhandled request: %@", request);
    }
}

@end

@interface OWSMessageSenderTest : XCTestCase

@property (nonatomic) TSThread *thread;
@property (nonatomic) TSOutgoingMessage *expiringMessage;
@property (nonatomic) OWSMessageSenderFakeNetworkManager *networkManager;

@end

@implementation OWSMessageSenderTest

- (void)setUp
{
    [super setUp];

    // Hack to make sure we don't explode when sending sync message.
    [TSStorageManager storePhoneNumber:@"+13231231234"];

    self.thread = [[TSContactThread alloc] initWithUniqueId:@"fake-thread-id"];
    [self.thread save];

    self.expiringMessage = [[TSOutgoingMessage alloc] initWithTimestamp:1
                                                               inThread:self.thread
                                                            messageBody:@"outgoing message"
                                                          attachmentIds:[NSMutableArray new]
                                                       expiresInSeconds:30];
    [self.expiringMessage save];
}

- (void)testExpiringMessageTimerStartsOnSuccess
{
    TSNetworkManager *networkManager = [[OWSMessageSenderFakeNetworkManager alloc] initWithSuccess:YES];
    OWSMessageSender *messageSender = [[OWSMessageSender alloc] initWithMessage:self.expiringMessage
                                                                 networkManager:networkManager
                                                                 storageManager:[TSStorageManager sharedManager]
                                                                contactsManager:[OWSFakeContactsManager new]
                                                                contactsUpdater:[OWSFakeContactsUpdater new]];

    // Sanity Check
    XCTAssertEqual(0, self.expiringMessage.expiresAt);

    XCTestExpectation *messageStartedExpiration = [self expectationWithDescription:@"messageStartedExpiration"];
    [messageSender sendWithSuccess:^() {
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

- (void)testExpiringMessageTimerDoesNotStartsOnFailure
{
    TSNetworkManager *networkManager = [[OWSMessageSenderFakeNetworkManager alloc] initWithSuccess:NO];
    OWSMessageSender *messageSender = [[OWSMessageSender alloc] initWithMessage:self.expiringMessage
                                                                 networkManager:networkManager
                                                                 storageManager:[TSStorageManager sharedManager]
                                                                contactsManager:[OWSFakeContactsManager new]
                                                                contactsUpdater:[OWSFakeContactsUpdater new]];

    // Sanity Check
    XCTAssertEqual(0, self.expiringMessage.expiresAt);

    XCTestExpectation *messageDidNotStartExpiration = [self expectationWithDescription:@"messageStartedExpiration"];
    [messageSender sendWithSuccess:^() {
        XCTFail(@"Message sending was supposed to fail.");
    }
        failure:^(NSError *error) {
            if (self.expiringMessage.expiresAt == 0) {
                [messageDidNotStartExpiration fulfill];
            } else {
                XCTFail(@"Message expiration was not supposed to start.");
            }
        }];

    [self waitForExpectationsWithTimeout:5
                                 handler:^(NSError *error) {
                                     NSLog(@"Wasn't able to verify.");
                                 }];
}

@end

NS_ASSUME_NONNULL_END
