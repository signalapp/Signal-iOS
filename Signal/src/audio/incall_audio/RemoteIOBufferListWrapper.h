#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

/**
 *
 * RemoteIOBufferListWrapper is used by RemoteIOAudio to manage an audio buffer list.
 *
 **/

@interface RemoteIOBufferListWrapper : NSObject

@property (assign, nonatomic) NSUInteger sampleCount;
@property (readonly, nonatomic) AudioBufferList* audioBufferList;

- (instancetype)initWithMonoBufferSize:(NSUInteger)bufferSize;

@end
