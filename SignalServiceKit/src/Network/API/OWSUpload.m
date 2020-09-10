//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSUpload.h"
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
@implementation OWSUploadFormV2

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

+ (nullable OWSUploadFormV2 *)parseDictionary:(nullable NSDictionary *)formResponseObject
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

    return [[OWSUploadFormV2 alloc] initWithAcl:formAcl
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
        dispatch_async(OWSUpload.serialQueue, ^{
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
                        .thenInBackground(^{ return resolve(@(1)); })
                        .catchInBackground(^(NSError *error) { resolve(error); });
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
    OWSUploadFormV2 *_Nullable form = [OWSUploadFormV2 parseDictionary:formResponseObject];
    if (!form) {
        return [AnyPromise
            promiseWithValue:OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Invalid upload form.")];
    }

    self.urlPath = form.key;

    NSString *uploadUrlPath = @"";
    return [OWSUpload uploadV2WithData:self.avatarData uploadForm:form uploadUrlPath:uploadUrlPath progressBlock:nil];
}

@end

NS_ASSUME_NONNULL_END
