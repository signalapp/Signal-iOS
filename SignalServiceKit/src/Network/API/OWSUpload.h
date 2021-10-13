//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class AnyPromise;
@class TSAttachmentStream;

@protocol AFMultipartFormData;

void AppendMultipartFormPath(id<AFMultipartFormData> formData, NSString *name, NSString *dataString);

@interface OWSUploadFormV2 : NSObject

// These properties will be set for all uploads.
@property (nonatomic, readonly) NSString *acl;
@property (nonatomic, readonly) NSString *key;
@property (nonatomic, readonly) NSString *policy;
@property (nonatomic, readonly) NSString *algorithm;
@property (nonatomic, readonly) NSString *credential;
@property (nonatomic, readonly) NSString *date;
@property (nonatomic, readonly) NSString *signature;

// These properties will be set for all attachment uploads.
@property (nonatomic, readonly, nullable) NSNumber *attachmentId;
@property (nonatomic, readonly, nullable) NSString *attachmentIdString;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithAcl:(NSString *)acl
                        key:(NSString *)key
                     policy:(NSString *)policy
                  algorithm:(NSString *)algorithm
                 credential:(NSString *)credential
                       date:(NSString *)date
                  signature:(NSString *)signature
               attachmentId:(nullable NSNumber *)attachmentId
         attachmentIdString:(nullable NSString *)attachmentIdString NS_DESIGNATED_INITIALIZER;

+ (nullable OWSUploadFormV2 *)parseDictionary:(nullable NSDictionary *)formResponseObject;

- (void)appendToForm:(id<AFMultipartFormData>)formData;

@end

NS_ASSUME_NONNULL_END
