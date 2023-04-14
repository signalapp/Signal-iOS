//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSUpload.h"
#import "HTTPUtils.h"
#import "MIMETypeUtil.h"
#import "OWSError.h"
#import "OWSRequestFactory.h"
#import "TSAttachmentStream.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

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

@end

NS_ASSUME_NONNULL_END
