#import <SessionMessagingKit/TSAttachment.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSBackupFragment;
@class SNProtoAttachmentPointer;
@class TSAttachmentStream;
@class TSMessage;

typedef NS_ENUM(NSUInteger, TSAttachmentPointerType) {
    TSAttachmentPointerTypeUnknown = 0,
    TSAttachmentPointerTypeIncoming = 1,
    TSAttachmentPointerTypeRestoring = 2,
};

typedef NS_ENUM(NSUInteger, TSAttachmentPointerState) {
    TSAttachmentPointerStateEnqueued = 0,
    TSAttachmentPointerStateDownloading = 1,
    TSAttachmentPointerStateFailed = 2,
};

/**
 * A TSAttachmentPointer is a yet-to-be-downloaded attachment.
 */
@interface TSAttachmentPointer : TSAttachment

@property (nonatomic) TSAttachmentPointerType pointerType;
@property (atomic) TSAttachmentPointerState state;
@property (nullable, atomic) NSString *mostRecentFailureLocalizedText;

// Though now required, `digest` may be null for pre-existing records or from
// messages received from other clients
@property (nullable, nonatomic, readonly) NSData *digest;

@property (nonatomic, readonly) CGSize mediaSize;

// Optional property.  Only set for attachments which need "lazy backup restore."
@property (nonatomic, nullable) NSString *lazyRestoreFragmentId;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithServerId:(UInt64)serverId
                             key:(nullable NSData *)key
                          digest:(nullable NSData *)digest
                       byteCount:(UInt32)byteCount
                     contentType:(NSString *)contentType
                  sourceFilename:(nullable NSString *)sourceFilename
                         caption:(nullable NSString *)caption
                  albumMessageId:(nullable NSString *)albumMessageId
                  attachmentType:(TSAttachmentType)attachmentType
                       mediaSize:(CGSize)mediaSize NS_DESIGNATED_INITIALIZER;

- (instancetype)initForRestoreWithAttachmentStream:(TSAttachmentStream *)attachmentStream NS_DESIGNATED_INITIALIZER;

+ (nullable TSAttachmentPointer *)attachmentPointerFromProto:(SNProtoAttachmentPointer *)attachmentProto
                                                albumMessage:(nullable TSMessage *)message;

+ (NSArray<TSAttachmentPointer *> *)attachmentPointersFromProtos:
                                        (NSArray<SNProtoAttachmentPointer *> *)attachmentProtos
                                                    albumMessage:(TSMessage *)message;

// Non-nil for attachments which need "lazy backup restore."
- (nullable OWSBackupFragment *)lazyRestoreFragment;

// Marks attachment as needing "lazy backup restore."
- (void)markForLazyRestoreWithFragment:(OWSBackupFragment *)lazyRestoreFragment
                           transaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
