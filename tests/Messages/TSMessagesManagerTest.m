//  Created by Michael Kirk on 9/23/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import <XCTest/XCTest.h>

#import "ContactsUpdater.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSMessagesManager.h"
#import "TSNetworkManager.h"
#import "TSStorageManager.h"
#import "objc/runtime.h"

@interface TSMessagesManagerTest : XCTestCase

@end

@interface TSMessagesManager (Testing)

// private method we are testing
- (void)handleIncomingEnvelope:(OWSSignalServiceProtosEnvelope *)messageEnvelope
               withSyncMessage:(OWSSignalServiceProtosSyncMessage *)syncMessage;

// private method we are stubbing via swizzle.
- (BOOL)uploadDataWithProgress:(NSData *)cipherText location:(NSString *)location attachmentID:(NSString *)attachmentID;

@end

@implementation TSMessagesManager (Testing)

+ (void)swapOriginalSelector:(SEL)originalSelector replacement:(SEL)replacementSelector
{
    Class class = [self class];
    Method originalMethod = class_getInstanceMethod(class, originalSelector);
    Method replacementMethod = class_getInstanceMethod(class, replacementSelector);

    // When swizzling a class method, use the following:
    // Class class = object_getClass((id)self);
    // ...
    // Method originalMethod = class_getClassMethod(class, originalSelector);
    // Method swizzledMethod = class_getClassMethod(class, swizzledSelector);

    BOOL didAddMethod = class_addMethod(class,
        originalSelector,
        method_getImplementation(replacementMethod),
        method_getTypeEncoding(replacementMethod));

    if (didAddMethod) {
        class_replaceMethod(class,
            replacementSelector,
            method_getImplementation(originalMethod),
            method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, replacementMethod);
    }
}

+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self swapOriginalSelector:@selector(uploadDataWithProgress:location:attachmentID:)
                       replacement:@selector(stubbedUploadDataWithProgress:location:attachmentID:)];

        [self swapOriginalSelector:@selector(deviceMessages:forRecipient:inThread:)
                       replacement:@selector(stubbedDeviceMessages:forRecipient:inThread:)];
    });
}

#pragma mark - Method Swizzling

- (BOOL)stubbedUploadDataWithProgress:(NSData *)cipherText
                             location:(NSString *)location
                         attachmentID:(NSString *)attachmentID
{
    NSLog(@"Faking successful upload.");
    return YES;
}

- (NSArray<NSDictionary *> *)stubbedDeviceMessages:(TSOutgoingMessage *)message
                                      forRecipient:(SignalRecipient *)recipient
                                          inThread:(TSThread *)thread
{
    // Upon originally provisioning, we won't have a device to send to.
    NSLog(@"Stubbed device message to return empty list.");
    return @[];
}

@end


@interface OWSTSMessagesManagerTestNetworkManager : TSNetworkManager

- (instancetype)initWithExpectation:(XCTestExpectation *)messageWasSubmitted;

@property XCTestExpectation *messageWasSubmitted;

@end

@implementation OWSTSMessagesManagerTestNetworkManager

- (instancetype)initWithExpectation:(XCTestExpectation *)messageWasSubmitted
{
    _messageWasSubmitted = messageWasSubmitted;

    return self;
}

- (void)makeRequest:(TSRequest *)request
            success:(void (^)(NSURLSessionDataTask *task, id responseObject))success
            failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failure
{
    if ([request isKindOfClass:[TSAllocAttachmentRequest class]]) {
        NSDictionary *fakeResponse = @{ @"id" : @(1234), @"location" : @"fake-location" };
        success(nil, fakeResponse);
    } else if ([request isKindOfClass:[TSSubmitMessageRequest class]]) {
        [self.messageWasSubmitted fulfill];
    } else {
        NSLog(@"Ignoring unhandled request: %@", request);
    }
}

@end

@interface OWSFakeContactsUpdater : ContactsUpdater

@end

@implementation OWSFakeContactsUpdater

- (void)synchronousLookup:(NSString *)identifier
                  success:(void (^)(SignalRecipient *))success
                  failure:(void (^)(NSError *error))failure
{
    NSLog(@"Fake contact lookup.");
    SignalRecipient *fakeRecipient =
        [[SignalRecipient alloc] initWithTextSecureIdentifier:@"fake-recipient-id" relay:nil supportsVoice:YES];
    success(fakeRecipient);
}

@end

@implementation TSMessagesManagerTest

- (void)testIncomingSyncContactMessage
{
    OWSFakeContactsUpdater *fakeContactsUpdater = [OWSFakeContactsUpdater new];
    XCTestExpectation *messageWasSubmitted = [self expectationWithDescription:@"message was submitted"];
    OWSTSMessagesManagerTestNetworkManager *fakeNetworkManager =
        [[OWSTSMessagesManagerTestNetworkManager alloc] initWithExpectation:messageWasSubmitted];
    TSMessagesManager *messagesManager =
        [[TSMessagesManager alloc] initWithNetworkManager:fakeNetworkManager
                                             dbConnection:[TSStorageManager sharedManager].newDatabaseConnection
                                          contactsUpdater:fakeContactsUpdater];

    OWSSignalServiceProtosEnvelopeBuilder *envelopeBuilder = [OWSSignalServiceProtosEnvelopeBuilder new];
    OWSSignalServiceProtosSyncMessageBuilder *messageBuilder = [OWSSignalServiceProtosSyncMessageBuilder new];
    OWSSignalServiceProtosSyncMessageRequestBuilder *requestBuilder =
        [OWSSignalServiceProtosSyncMessageRequestBuilder new];
    [requestBuilder setType:OWSSignalServiceProtosSyncMessageRequestTypeGroups];
    [messageBuilder setRequest:[requestBuilder build]];

    [messagesManager handleIncomingEnvelope:[envelopeBuilder build] withSyncMessage:[messageBuilder build]];

    [self waitForExpectationsWithTimeout:5
                                 handler:^(NSError *error) {
                                     NSLog(@"No message submitted.");
                                 }];
}


@end
