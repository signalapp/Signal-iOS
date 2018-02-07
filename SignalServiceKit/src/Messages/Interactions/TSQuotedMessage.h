//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSYapDatabaseObject.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSQuotedMessage : TSYapDatabaseObject

@property (nonatomic, readonly) uint32_t timestamp;
@property (nonatomic, readonly) NSString *recipientId;

@property (nullable, nonatomic, readonly) NSString *body;
@property (nullable, nonatomic, readonly) NSString *sourceFilename;
@property (nullable, nonatomic, readonly) NSData *thumbnailData;

@end

#pragma mark -

NS_ASSUME_NONNULL_END
