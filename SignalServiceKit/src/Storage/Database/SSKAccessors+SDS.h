//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// This header exposes private properties for SDS serialization.

@interface TSThread (SDS)

@property (nonatomic, nullable, readonly) NSNumber *archivedAsOfMessageSortId;
@property (nonatomic, copy, nullable, readonly) NSString *messageDraft;

@property (nonatomic, nullable, readonly) NSDate *lastMessageDate DEPRECATED_ATTRIBUTE;
@property (nonatomic, nullable, readonly) NSDate *archivalDate DEPRECATED_ATTRIBUTE;

@end

#pragma mark -

@interface TSMessage (SDS)

@property (nonatomic, readonly) NSUInteger schemaVersion;

@end

#pragma mark -

@interface TSInfoMessage (SDS)

@property (nonatomic, readonly) NSUInteger infoMessageSchemaVersion;

@property (nonatomic, getter=wasRead) BOOL read;

@end

#pragma mark -

@interface TSErrorMessage (SDS)

@property (nonatomic, getter=wasRead) BOOL read;

@property (nonatomic, readonly) NSUInteger errorMessageSchemaVersion;

@end

#pragma mark -

@interface TSOutgoingMessage (SDS)

@property (nonatomic, readonly) TSOutgoingMessageState legacyMessageState;
@property (nonatomic, readonly) BOOL legacyWasDelivered;
@property (nonatomic, readonly) BOOL hasLegacyMessageState;

@property (atomic, nullable, readonly) NSDictionary<NSString *, TSOutgoingMessageRecipientState *> *recipientStateMap;

@end

#pragma mark -

@interface OWSDisappearingConfigurationUpdateInfoMessage (SDS)

@property (nonatomic, readonly) uint32_t configurationDurationSeconds;

@property (nonatomic, readonly, nullable) NSString *createdByRemoteName;
@property (nonatomic, readonly) BOOL createdInExistingGroup;
//@property (nonatomic, readonly) uint32_t configurationDurationSeconds;

@end

#pragma mark -

@interface TSCall (SDS)

@property (nonatomic, getter=wasRead) BOOL read;

@property (nonatomic, readonly) NSUInteger callSchemaVersion;

@end

#pragma mark -

@interface TSIncomingMessage (SDS)

@property (nonatomic, getter=wasRead) BOOL read;

@end

#pragma mark -

@interface TSAttachment (SDS)

@property (nonatomic, readonly) NSUInteger attachmentSchemaVersion;

@end

#pragma mark -

@interface TSAttachmentPointer (SDS)

@property (nonatomic, nullable, readonly) NSString *lazyRestoreFragmentId;

@end

#pragma mark -

@interface TSAttachmentStream (SDS)

@property (nullable, nonatomic, readonly) NSString *localRelativeFilePath;

@property (nullable, nonatomic, readonly) NSNumber *cachedImageWidth;
@property (nullable, nonatomic, readonly) NSNumber *cachedImageHeight;

@property (nullable, nonatomic, readonly) NSNumber *cachedAudioDurationSeconds;

@property (atomic, nullable, readonly) NSNumber *isValidImageCached;
@property (atomic, nullable, readonly) NSNumber *isValidVideoCached;

@end

#pragma mark -

NS_ASSUME_NONNULL_END
