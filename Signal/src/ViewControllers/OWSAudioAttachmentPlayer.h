//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@class TSVideoAttachmentAdapter;
@class YapDatabaseConnection;

@interface OWSAudioAttachmentPlayer : NSObject <AVAudioPlayerDelegate>

@property (nonatomic, readonly) TSVideoAttachmentAdapter *mediaAdapter;

- (instancetype)initWithMediaAdapter:(TSVideoAttachmentAdapter *)mediaAdapter
                  databaseConnection:(YapDatabaseConnection *)databaseConnection;

- (void)play;
- (void)pause;
- (void)stop;
- (void)togglePlayState;

@end

NS_ASSUME_NONNULL_END
