#import <Foundation/Foundation.h>

/**
 *  Interfaces with OS to control which hardware devices audio is routed to
 **/

@interface AudioRouter : NSObject


+ (void)restoreDefaults;
+ (void)routeAllAudioToInteralSpeaker;
+ (void)routeAllAudioToExternalSpeaker;

+ (BOOL)isOutputRoutedToSpeaker;
+ (BOOL)isOutputRoutedToReciever;
@end
