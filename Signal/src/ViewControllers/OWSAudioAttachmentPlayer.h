//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

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
