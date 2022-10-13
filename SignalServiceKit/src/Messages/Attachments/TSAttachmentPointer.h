//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/TSAttachment.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSBackupFragment;
@class SDSAnyWriteTransaction;
@class SSKProtoAttachmentPointer;
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
    TSAttachmentPointerStatePendingMessageRequest = 3,
    // Either:
    //
    // * Download of this attachment is blocking by the auto-download
    //   preferences.
    // * Download was manually paused/stopped and needs to be manually
    //   resumed.
    TSAttachmentPointerStatePendingManualDownload = 4,
};

NSString *NSStringForTSAttachmentPointerState(TSAttachmentPointerState value);

#pragma mark -

/**
 * A TSAttachmentPointer is a yet-to-be-downloaded attachment.
 */
@interface TSAttachmentPointer : TSAttachment

@property (nonatomic, readonly) TSAttachmentPointerType pointerType;
@property (nonatomic, readonly) TSAttachmentPointerState state;

// Though now required, `digest` may be null for pre-existing records or from
// messages received from other clients
@property (nullable, nonatomic, readonly) NSData *digest;

@property (nonatomic, readonly) CGSize mediaSize;

// Non-nil for attachments which need "lazy backup restore."
- (nullable OWSBackupFragment *)lazyRestoreFragmentWithTransaction:(SDSAnyReadTransaction *)transaction;

- (instancetype)initWithServerId:(UInt64)serverId
                          cdnKey:(NSString *)cdnKey
                       cdnNumber:(UInt32)cdnNumber
                   encryptionKey:(NSData *)encryptionKey
                       byteCount:(UInt32)byteCount
                     contentType:(NSString *)contentType
                  sourceFilename:(nullable NSString *)sourceFilename
                         caption:(nullable NSString *)caption
                  albumMessageId:(nullable NSString *)albumMessageId
                        blurHash:(nullable NSString *)blurHash
                 uploadTimestamp:(unsigned long long)uploadTimestamp NS_UNAVAILABLE;
- (instancetype)initForRestoreWithUniqueId:(NSString *)uniqueId
                               contentType:(NSString *)contentType
                            sourceFilename:(nullable NSString *)sourceFilename
                                   caption:(nullable NSString *)caption
                            albumMessageId:(nullable NSString *)albumMessageId NS_UNAVAILABLE;
- (instancetype)initAttachmentWithContentType:(NSString *)contentType
                                    byteCount:(UInt32)byteCount
                               sourceFilename:(nullable NSString *)sourceFilename
                                      caption:(nullable NSString *)caption
                               albumMessageId:(nullable NSString *)albumMessageId NS_UNAVAILABLE;
- (instancetype)initWithPointer:(TSAttachmentPointer *)pointer
                    transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
                albumMessageId:(nullable NSString *)albumMessageId
                attachmentType:(TSAttachmentType)attachmentType
                      blurHash:(nullable NSString *)blurHash
                     byteCount:(unsigned int)byteCount
                       caption:(nullable NSString *)caption
                        cdnKey:(NSString *)cdnKey
                     cdnNumber:(unsigned int)cdnNumber
                   contentType:(NSString *)contentType
                 encryptionKey:(nullable NSData *)encryptionKey
                      serverId:(unsigned long long)serverId
                sourceFilename:(nullable NSString *)sourceFilename
               uploadTimestamp:(unsigned long long)uploadTimestamp NS_UNAVAILABLE;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithServerId:(UInt64)serverId
                          cdnKey:(NSString *)cdnKey
                       cdnNumber:(UInt32)cdnNumber
                             key:(NSData *)key
                          digest:(nullable NSData *)digest
                       byteCount:(UInt32)byteCount
                     contentType:(NSString *)contentType
                  sourceFilename:(nullable NSString *)sourceFilename
                         caption:(nullable NSString *)caption
                  albumMessageId:(nullable NSString *)albumMessageId
                  attachmentType:(TSAttachmentType)attachmentType
                       mediaSize:(CGSize)mediaSize
                        blurHash:(nullable NSString *)blurHash
                 uploadTimestamp:(unsigned long long)uploadTimestamp NS_DESIGNATED_INITIALIZER;

- (instancetype)initForRestoreWithAttachmentStream:(TSAttachmentStream *)attachmentStream NS_DESIGNATED_INITIALIZER;

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
                  albumMessageId:(nullable NSString *)albumMessageId
         attachmentSchemaVersion:(NSUInteger)attachmentSchemaVersion
                  attachmentType:(TSAttachmentType)attachmentType
                        blurHash:(nullable NSString *)blurHash
                       byteCount:(unsigned int)byteCount
                         caption:(nullable NSString *)caption
                          cdnKey:(NSString *)cdnKey
                       cdnNumber:(unsigned int)cdnNumber
                     contentType:(NSString *)contentType
                   encryptionKey:(nullable NSData *)encryptionKey
                        serverId:(unsigned long long)serverId
                  sourceFilename:(nullable NSString *)sourceFilename
                 uploadTimestamp:(unsigned long long)uploadTimestamp
                          digest:(nullable NSData *)digest
           lazyRestoreFragmentId:(nullable NSString *)lazyRestoreFragmentId
                       mediaSize:(CGSize)mediaSize
                     pointerType:(TSAttachmentPointerType)pointerType
                           state:(TSAttachmentPointerState)state
NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init(grdbId:uniqueId:albumMessageId:attachmentSchemaVersion:attachmentType:blurHash:byteCount:caption:cdnKey:cdnNumber:contentType:encryptionKey:serverId:sourceFilename:uploadTimestamp:digest:lazyRestoreFragmentId:mediaSize:pointerType:state:));

// clang-format on

// --- CODE GENERATION MARKER

+ (nullable TSAttachmentPointer *)attachmentPointerFromProto:(SSKProtoAttachmentPointer *)attachmentProto
                                                albumMessage:(nullable TSMessage *)message;

+ (NSArray<TSAttachmentPointer *> *)attachmentPointersFromProtos:
                                        (NSArray<SSKProtoAttachmentPointer *> *)attachmentProtos
                                                    albumMessage:(TSMessage *)message;

#pragma mark - Update With... Methods

// Marks attachment as needing "lazy backup restore."
- (void)markForLazyRestoreWithFragment:(OWSBackupFragment *)lazyRestoreFragment
                           transaction:(SDSAnyWriteTransaction *)transaction;

#if TESTABLE_BUILD
- (void)setAttachmentPointerStateDebug:(TSAttachmentPointerState)state;
#endif

- (void)updateWithAttachmentPointerState:(TSAttachmentPointerState)state
                             transaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(updateAttachmentPointerState(_:transaction:));

- (void)updateAttachmentPointerStateFrom:(TSAttachmentPointerState)oldState
                                      to:(TSAttachmentPointerState)newState
                             transaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(updateAttachmentPointerState(from:to:transaction:));

@end

NS_ASSUME_NONNULL_END
