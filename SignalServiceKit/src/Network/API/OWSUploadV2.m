//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSUploadV2.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/OWSRequestFactory.h>
#import <SignalServiceKit/OWSSignalService.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSNetworkManager.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSUploadV2

#pragma mark - Dependencies

// TODO: Rename
+ (AFHTTPSessionManager *)uploadHTTPManager
{
    return [OWSSignalService sharedInstance].CDNSessionManager;
}

+ (TSNetworkManager *)networkManager
{
    return SSKEnvironment.shared.networkManager;
}

#pragma mark -

// If avatarData is nil, we are clearing the avatar.
+ (AnyPromise *)uploadAvatarToService:(NSData *_Nullable)avatarData clearLocalAvatar:(dispatch_block_t)clearLocalAvatar
{
    OWSAssertDebug(avatarData == nil || avatarData.length > 0);

    AnyPromise *promise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            // See: https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-UsingHTTPPOST.html
            TSRequest *formRequest = [OWSRequestFactory profileAvatarUploadFormRequest];

            [self.networkManager makeRequest:formRequest
                success:^(NSURLSessionDataTask *task, id formResponseObject) {
                    if (avatarData == nil) {
                        OWSLogDebug(@"successfully cleared avatar");
                        clearLocalAvatar();
                        return resolve([OWSUploadV2 new]);
                    }

                    if (![formResponseObject isKindOfClass:[NSDictionary class]]) {
                        OWSCFailDebug(@"Invalid response.");
                        return resolve(
                            OWSErrorWithCodeDescription(OWSErrorCodeAvatarUploadFailed, @"Avatar upload failed."));
                    }
                    NSDictionary *responseMap = formResponseObject;

                    // TODO: urlPath?
                    [[self parseFormAndUpload:responseMap urlPath:@"" uploadData:avatarData]
                            .thenInBackground(^(OWSUploadV2 *upload) {
                                resolve(upload);
                            })
                            .catchInBackground(^(NSError *error) {
                                clearLocalAvatar();

                                resolve(error);
                            }) retainUntilComplete];
                }
                failure:^(NSURLSessionDataTask *task, NSError *error) {
                    // Only clear the local avatar if we have a response. Otherwise, we
                    // had a network failure and probably didn't reach the service.
                    if (task.response != nil) {
                        clearLocalAvatar();
                    }

                    OWSLogError(@"Failed to get profile avatar upload form: %@", error);
                    resolve(error);
                }];
        });
    }];
    return promise;
}

+ (AnyPromise *)parseFormAndUpload:(NSDictionary *)formResponseObject
                           urlPath:(NSString *)urlPath
                        uploadData:(NSData *)uploadData
{
    OWSAssertDebug(uploadData.length > 0);

    if (![formResponseObject isKindOfClass:[NSDictionary class]]) {
        OWSLogError(@"Invalid upload form.");
        return [AnyPromise
            promiseWithValue:OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Invalid upload form.")];
    }
    NSDictionary *responseMap = formResponseObject;

    NSString *formAcl = responseMap[@"acl"];
    if (![formAcl isKindOfClass:[NSString class]] || formAcl.length < 1) {
        OWSLogError(@"Invalid upload form: acl.");
        return [AnyPromise
            promiseWithValue:OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Invalid upload form.")];
    }
    NSString *formKey = responseMap[@"key"];
    if (![formKey isKindOfClass:[NSString class]] || formKey.length < 1) {
        OWSLogError(@"Invalid upload form: key.");
        return [AnyPromise
            promiseWithValue:OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Invalid upload form.")];
    }
    NSString *formPolicy = responseMap[@"policy"];
    if (![formPolicy isKindOfClass:[NSString class]] || formPolicy.length < 1) {
        OWSLogError(@"Invalid upload form: policy.");
        return [AnyPromise
            promiseWithValue:OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Invalid upload form.")];
    }
    NSString *formAlgorithm = responseMap[@"algorithm"];
    if (![formAlgorithm isKindOfClass:[NSString class]] || formAlgorithm.length < 1) {
        OWSLogError(@"Invalid upload form: algorithm.");
        return [AnyPromise
            promiseWithValue:OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Invalid upload form.")];
    }
    NSString *formCredential = responseMap[@"credential"];
    if (![formCredential isKindOfClass:[NSString class]] || formCredential.length < 1) {
        OWSLogError(@"Invalid upload form: credential.");
        return [AnyPromise
            promiseWithValue:OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Invalid upload form.")];
    }
    NSString *formDate = responseMap[@"date"];
    if (![formDate isKindOfClass:[NSString class]] || formDate.length < 1) {
        OWSLogError(@"Invalid upload form: date.");
        return [AnyPromise
            promiseWithValue:OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Invalid upload form.")];
    }
    NSString *formSignature = responseMap[@"signature"];
    if (![formSignature isKindOfClass:[NSString class]] || formSignature.length < 1) {
        OWSLogError(@"Invalid upload form: signature.");
        return [AnyPromise
            promiseWithValue:OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Invalid upload form.")];
    }

    AnyPromise *promise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        [self.uploadHTTPManager POST:urlPath
            parameters:nil
            constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
                NSData * (^formDataForString)(NSString *formString) = ^(NSString *formString) {
                    return [formString dataUsingEncoding:NSUTF8StringEncoding];
                };

                // We have to build up the form manually vs. simply passing in a paramaters dict
                // because AWS is sensitive to the order of the form params (at least the "key"
                // field must occur early on).
                // For consistency, all fields are ordered here in a known working order.
                [formData appendPartWithFormData:formDataForString(formKey) name:@"key"];
                [formData appendPartWithFormData:formDataForString(formAcl) name:@"acl"];
                [formData appendPartWithFormData:formDataForString(formAlgorithm) name:@"x-amz-algorithm"];
                [formData appendPartWithFormData:formDataForString(formCredential) name:@"x-amz-credential"];
                [formData appendPartWithFormData:formDataForString(formDate) name:@"x-amz-date"];
                [formData appendPartWithFormData:formDataForString(formPolicy) name:@"policy"];
                [formData appendPartWithFormData:formDataForString(formSignature) name:@"x-amz-signature"];
                [formData appendPartWithFormData:formDataForString(OWSMimeTypeApplicationOctetStream)
                                            name:@"Content-Type"];
                [formData appendPartWithFormData:uploadData name:@"file"];

                OWSLogVerbose(@"constructed body");
            }
            progress:^(NSProgress *uploadProgress) {
                OWSLogVerbose(@"Upload progress: %.2f%%", uploadProgress.fractionCompleted * 100);
            }
            success:^(NSURLSessionDataTask *uploadTask, id _Nullable responseObject) {
                OWSLogInfo(@"Upload succeeded with key: %@", formKey);
                OWSUploadV2 *upload = [OWSUploadV2 new];
                upload.urlPath = formKey;
                return resolve(upload);
            }
            failure:^(NSURLSessionDataTask *_Nullable uploadTask, NSError *error) {
                OWSLogError(@"Upload failed with error: %@", error);
                resolve(error);
            }];
    }];
    return promise;
}

@end

NS_ASSUME_NONNULL_END
