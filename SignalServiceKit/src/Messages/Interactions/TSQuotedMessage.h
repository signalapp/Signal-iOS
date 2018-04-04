//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSYapDatabaseObject.h>

NS_ASSUME_NONNULL_BEGIN

@class TSAttachment;

@interface TSQuotedMessage : TSYapDatabaseObject

@property (nonatomic, readonly) uint64_t timestamp;
@property (nonatomic, readonly) NSString *authorId;

// This property should be set IFF we are quoting a text message
// or attachment with caption.
@property (nullable, nonatomic, readonly) NSString *body;

//// This property can be set IFF we are quoting an attachment message, but it is optional.
//@property (nullable, nonatomic, readonly) NSData *thumbnailData;

// This is a MIME type.
//
// This property should be set IFF we are quoting an attachment message.
@property (nullable, nonatomic, readonly) NSString *contentType;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         authorId:(NSString *)authorId
                             body:(NSString *_Nullable)body
                   sourceFilename:(NSString *_Nullable)sourceFilename
                    thumbnailData:(NSData *_Nullable)thumbnailData
                      contentType:(NSString *_Nullable)contentType;

#pragma mark - Attachments

@property (nonatomic, readonly) NSArray<NSString *> *thumbnailAttachmentIds;
// A map of attachment id-to-"source" filename.
@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSString *> *thumbnailAttachmentFilenameMap;

- (BOOL)hasThumbnailAttachments;
- (nullable TSAttachment *)firstThumbnailAttachmentWithTransaction:(YapDatabaseReadTransaction *)transaction;

@end

#pragma mark -

NS_ASSUME_NONNULL_END
