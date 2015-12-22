#import <Foundation/Foundation.h>
#import "CyclicalBuffer.h"

/**
 *
 * An AudioCallbackHandler is called when audio is played or recorded.
 *
 **/
@protocol AudioCallbackHandler <NSObject>
- (void)handleNewDataRecorded:(CyclicalBuffer *)data;
- (void)handlePlaybackOccurredWithBytesRequested:(NSUInteger)requested andBytesRemaining:(NSUInteger)bytesRemaining;
@end
