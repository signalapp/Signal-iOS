//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class AnyPromise;
@class TSAttachmentStream;

@protocol AFMultipartFormData;

void AppendMultipartFormPath(id<AFMultipartFormData> formData, NSString *name, NSString *dataString);

@interface OWSUploadForm : NSObject

// These properties will bet set for all uploads.
@property (nonatomic) NSString *formAcl;
@property (nonatomic) NSString *formKey;
@property (nonatomic) NSString *formPolicy;
@property (nonatomic) NSString *formAlgorithm;
@property (nonatomic) NSString *formCredential;
@property (nonatomic) NSString *formDate;
@property (nonatomic) NSString *formSignature;

// These properties will bet set for all attachment uploads.
@property (nonatomic, nullable) NSNumber *attachmentId;
@property (nonatomic, nullable) NSString *attachmentIdString;

+ (nullable OWSUploadForm *)parse:(nullable NSDictionary *)formResponseObject;

- (void)appendToForm:(id<AFMultipartFormData>)formData;

@end

#pragma mark -

typedef void (^UploadProgressBlock)(NSProgress *progress);

// A strong reference should be maintained to this object
// until it completes.  If it is deallocated, the upload
// may be cancelled.
//
// This class can be safely accessed and used from any thread.
@interface OWSAvatarUploadV2 : NSObject

// This property is set on success for non-nil uploads.
@property (nonatomic, nullable) NSString *urlPath;

- (AnyPromise *)uploadAvatarToService:(NSData *_Nullable)avatarData
                        progressBlock:(UploadProgressBlock)progressBlock;

@end

#pragma mark -

// A strong reference should be maintained to this object
// until it completes.  If it is deallocated, the upload
// may be cancelled.
//
// This class can be safely accessed and used from any thread.
@interface OWSAttachmentUploadV2 : NSObject

// These properties are set on success.
@property (nonatomic, nullable) NSData *encryptionKey;
@property (nonatomic, nullable) NSData *digest;
@property (nonatomic) UInt64 serverId;

- (AnyPromise *)uploadAttachmentToService:(TSAttachmentStream *)attachmentStream
                            progressBlock:(UploadProgressBlock)progressBlock;

@end

NS_ASSUME_NONNULL_END
