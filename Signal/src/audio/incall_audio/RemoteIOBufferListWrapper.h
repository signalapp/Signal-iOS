#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>

/**
 *
 * RemoteIOBufferListWrapper is used by RemoteIOAudio to manage an audio buffer list.
 *
 **/
@interface RemoteIOBufferListWrapper : NSObject

@property (nonatomic, assign) NSUInteger sampleCount;
@property (nonatomic, readonly) AudioBufferList *audioBufferList;

+ (RemoteIOBufferListWrapper *)remoteIOBufferListWithMonoBufferSize:(NSUInteger)bufferSize;


@end
