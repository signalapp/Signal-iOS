//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSUploadV2.h"
#import <AFNetworking/AFURLRequestSerialization.h>
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/OWSRequestFactory.h>
#import <SignalServiceKit/OWSSignalService.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSNetworkManager.h>
#import <SignalServiceKit/TSSocketManager.h>

NS_ASSUME_NONNULL_BEGIN

void AppendMultipartFormPath(id<AFMultipartFormData> formData, NSString *name, NSString *dataString)
{
    NSData *data = [dataString dataUsingEncoding:NSUTF8StringEncoding];

    [formData appendPartWithFormData:data name:name];
}

#pragma mark -

// See: https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-UsingHTTPPOST.html
@implementation OWSUploadForm

- (instancetype)initWithAcl:(NSString *)acl
                        key:(NSString *)key
                     policy:(NSString *)policy
                  algorithm:(NSString *)algorithm
                 credential:(NSString *)credential
                       date:(NSString *)date
                  signature:(NSString *)signature
               attachmentId:(nullable NSNumber *)attachmentId
         attachmentIdString:(nullable NSString *)attachmentIdString
{
    self = [super init];

    if (self) {
        _acl = acl;
        _key = key;
        _policy = policy;
        _algorithm = algorithm;
        _credential = credential;
        _date = date;
        _signature = signature;
        _attachmentId = attachmentId;
        _attachmentIdString = attachmentIdString;
    }
    return self;
}

+ (nullable OWSUploadForm *)parseDictionary:(nullable NSDictionary *)formResponseObject
{
    if (![formResponseObject isKindOfClass:[NSDictionary class]]) {
        OWSFailDebug(@"Invalid upload form.");
        return nil;
    }
    NSDictionary *responseMap = formResponseObject;

    NSString *_Nullable formAcl = responseMap[@"acl"];
    if (![formAcl isKindOfClass:[NSString class]] || formAcl.length < 1) {
        OWSFailDebug(@"Invalid upload form: acl.");
        return nil;
    }
    NSString *_Nullable formKey = responseMap[@"key"];
    if (![formKey isKindOfClass:[NSString class]] || formKey.length < 1) {
        OWSFailDebug(@"Invalid upload form: key.");
        return nil;
    }
    NSString *_Nullable formPolicy = responseMap[@"policy"];
    if (![formPolicy isKindOfClass:[NSString class]] || formPolicy.length < 1) {
        OWSFailDebug(@"Invalid upload form: policy.");
        return nil;
    }
    NSString *_Nullable formAlgorithm = responseMap[@"algorithm"];
    if (![formAlgorithm isKindOfClass:[NSString class]] || formAlgorithm.length < 1) {
        OWSFailDebug(@"Invalid upload form: algorithm.");
        return nil;
    }
    NSString *_Nullable formCredential = responseMap[@"credential"];
    if (![formCredential isKindOfClass:[NSString class]] || formCredential.length < 1) {
        OWSFailDebug(@"Invalid upload form: credential.");
        return nil;
    }
    NSString *_Nullable formDate = responseMap[@"date"];
    if (![formDate isKindOfClass:[NSString class]] || formDate.length < 1) {
        OWSFailDebug(@"Invalid upload form: date.");
        return nil;
    }
    NSString *_Nullable formSignature = responseMap[@"signature"];
    if (![formSignature isKindOfClass:[NSString class]] || formSignature.length < 1) {
        OWSFailDebug(@"Invalid upload form: signature.");
        return nil;
    }

    NSNumber *_Nullable attachmentId = responseMap[@"attachmentId"];
    if (attachmentId == nil) {
        // This value is optional.
    } else if (![attachmentId isKindOfClass:[NSNumber class]]) {
        OWSFailDebug(@"Invalid upload form: attachmentId.");
        return nil;
    }
    NSString *_Nullable attachmentIdString = responseMap[@"attachmentIdString"];
    if (attachmentIdString == nil) {
        // This value is optional.
    } else if (![attachmentIdString isKindOfClass:[NSString class]] || attachmentIdString.length < 1) {
        OWSFailDebug(@"Invalid upload form: attachmentIdString.");
        return nil;
    }

    return [[OWSUploadForm alloc] initWithAcl:formAcl
                                          key:formKey
                                       policy:formPolicy
                                    algorithm:formAlgorithm
                                   credential:formCredential
                                         date:formDate
                                    signature:formSignature
                                 attachmentId:attachmentId
                           attachmentIdString:attachmentIdString];
}

- (void)appendToForm:(id<AFMultipartFormData>)formData
{
    // We have to build up the form manually vs. simply passing in a paramaters dict
    // because AWS is sensitive to the order of the form params (at least the "key"
    // field must occur early on).
    //
    // For consistency, all fields are ordered here in a known working order.
    AppendMultipartFormPath(formData, @"key", self.key);
    AppendMultipartFormPath(formData, @"acl", self.acl);
    AppendMultipartFormPath(formData, @"x-amz-algorithm", self.algorithm);
    AppendMultipartFormPath(formData, @"x-amz-credential", self.credential);
    AppendMultipartFormPath(formData, @"x-amz-date", self.date);
    AppendMultipartFormPath(formData, @"policy", self.policy);
    AppendMultipartFormPath(formData, @"x-amz-signature", self.signature);
}

@end

#pragma mark -

@interface OWSAvatarUploadV2 ()

@property (nonatomic, nullable) NSData *avatarData;

@end

#pragma mark -

@implementation OWSAvatarUploadV2

#pragma mark - Dependencies

- (TSNetworkManager *)networkManager
{
    return SSKEnvironment.shared.networkManager;
}

#pragma mark - Avatars

// If avatarData is nil, we are clearing the avatar.
- (AnyPromise *)uploadAvatarToService:(nullable NSData *)avatarData
{
    OWSAssertDebug(avatarData == nil || avatarData.length > 0);
    self.avatarData = avatarData;

    __weak OWSAvatarUploadV2 *weakSelf = self;
    AnyPromise *promise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            TSRequest *formRequest = [OWSRequestFactory profileAvatarUploadFormRequest];
            [self.networkManager makeRequest:formRequest
                success:^(NSURLSessionDataTask *task, id _Nullable formResponseObject) {
                    OWSAvatarUploadV2 *_Nullable strongSelf = weakSelf;
                    if (!strongSelf) {
                        return resolve(OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Upload deallocated"));
                    }

                    if (avatarData == nil) {
                        OWSLogDebug(@"successfully cleared avatar");
                        return resolve(@(1));
                    }

                    [strongSelf parseFormAndUpload:formResponseObject]
                        .thenInBackground(^{
                            return resolve(@(1));
                        })
                        .catchInBackground(^(NSError *error) {
                            resolve(error);
                        });
                }
                failure:^(NSURLSessionDataTask *task, NSError *error) {
                    OWSLogError(@"Failed to get profile avatar upload form: %@", error);
                    resolve(error);
                }];
        });
    }];
    return promise;
}

- (AnyPromise *)parseFormAndUpload:(nullable id)formResponseObject
{
    OWSUploadForm *_Nullable form = [OWSUploadForm parseDictionary:formResponseObject];
    if (!form) {
        return [AnyPromise
            promiseWithValue:OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Invalid upload form.")];
    }

    self.urlPath = form.key;

    NSString *uploadUrlPath = @"";
    return [OWSUploadV2 uploadObjcWithData:self.avatarData
                                uploadForm:form
                             uploadUrlPath:uploadUrlPath
                             progressBlock:nil];
}

@end

#pragma mark - Attachments

@interface OWSAttachmentUploadV2 ()

@property (nonatomic) TSAttachmentStream *attachmentStream;

@end

#pragma mark -

@implementation OWSAttachmentUploadV2

#pragma mark - Dependencies

- (TSNetworkManager *)networkManager
{
    return SSKEnvironment.shared.networkManager;
}

- (TSSocketManager *)socketManager
{
    return SSKEnvironment.shared.socketManager;
}

#pragma mark -

- (nullable NSData *)attachmentData
{
    OWSAssertDebug(self.attachmentStream);

    NSData *encryptionKey;
    NSData *digest;
    NSError *error;
    NSData *attachmentData = [self.attachmentStream readDataFromFileWithError:&error];
    if (error) {
        OWSLogError(@"Failed to read attachment data with error: %@", error);
        return nil;
    }

    NSData *_Nullable encryptedAttachmentData = [Cryptography encryptAttachmentData:attachmentData
                                                                          shouldPad:YES
                                                                             outKey:&encryptionKey
                                                                          outDigest:&digest];
    if (!encryptedAttachmentData) {
        OWSFailDebug(@"could not encrypt attachment data.");
        return nil;
    }

    self.encryptionKey = encryptionKey;
    self.digest = digest;

    return encryptedAttachmentData;
}

// On success, yields an instance of OWSUploadV2.
- (AnyPromise *)uploadAttachmentToService:(TSAttachmentStream *)attachmentStream
                            progressBlock:(UploadProgressBlock)progressBlock
{
    OWSAssertDebug(attachmentStream);

    self.attachmentStream = attachmentStream;

    AnyPromise *promise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self uploadAttachmentToService:resolve progressBlock:progressBlock skipWebsocket:NO];
        });
    }];
    return promise;
}

- (void)uploadAttachmentToService:(PMKResolver)resolve
                    progressBlock:(UploadProgressBlock)progressBlock
                    skipWebsocket:(BOOL)skipWebsocket
{
    TSRequest *formRequest = [OWSRequestFactory allocAttachmentRequest];

    BOOL shouldUseWebsocket = (self.socketManager.canMakeRequests && !skipWebsocket);

    __weak OWSAttachmentUploadV2 *weakSelf = self;
    void (^formSuccess)(id _Nullable) = ^(id _Nullable formResponseObject) {
        OWSAttachmentUploadV2 *_Nullable strongSelf = weakSelf;
        if (!strongSelf) {
            return resolve(OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Upload deallocated"));
        }

        [strongSelf parseFormAndUpload:formResponseObject progressBlock:progressBlock]
            .thenInBackground(^{
                resolve(@(1));
            })
            .catchInBackground(^(NSError *error) {
                resolve(error);
            });
    };
    void (^formFailure)(NSError *) = ^(NSError *error) {
        OWSLogError(@"Failed to get profile avatar upload form: %@", error);
        resolve(error);
    };

    if (shouldUseWebsocket) {
        [self.socketManager makeRequest:formRequest
            success:^(id _Nullable responseObject) {
                formSuccess(responseObject);
            }
            failure:^(NSInteger statusCode, NSData *_Nullable responseData, NSError *_Nullable error) {
                OWSLogError(@"Websocket request failed: %d, %@", (int)statusCode, error);

                // Try again without websocket.
                [weakSelf uploadAttachmentToService:resolve progressBlock:progressBlock skipWebsocket:YES];
            }];
    } else {
        [self.networkManager makeRequest:formRequest
            success:^(NSURLSessionDataTask *task, id _Nullable formResponseObject) {
                formSuccess(formResponseObject);
            }
            failure:^(NSURLSessionDataTask *task, NSError *error) {
                formFailure(error);
            }];
    }
}

#pragma mark -

- (AnyPromise *)parseFormAndUpload:(nullable id)formResponseObject
                     progressBlock:(UploadProgressBlock)progressBlock
{
    OWSUploadForm *_Nullable form = [OWSUploadForm parseDictionary:formResponseObject];
    if (!form) {
        return [AnyPromise
            promiseWithValue:OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Invalid upload form.")];
    }
    UInt64 serverId = form.attachmentId.unsignedLongLongValue;
    if (serverId < 1) {
        return [AnyPromise
            promiseWithValue:OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Invalid upload form.")];
    }

    self.serverId = serverId;

    __weak OWSAttachmentUploadV2 *weakSelf = self;
    NSString *uploadUrlPath = @"attachments/";
    return [OWSUploadV2 uploadObjcWithData:self.attachmentData
                                uploadForm:form
                             uploadUrlPath:uploadUrlPath
                             progressBlock:progressBlock]
        .then(^{
            weakSelf.uploadTimestamp = NSDate.ows_millisecondTimeStamp;
        });
}

@end

NS_ASSUME_NONNULL_END
