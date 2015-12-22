#import <Foundation/Foundation.h>

#import "SoundInstance.h"

/**
 *  Factory class for generating Instances of specific Sound files. These are then maintained
 *  and controlled from the SoundPlayer class. This class should mask the use of any specific
 *  soundFiles.
 **/

@interface SoundBoard : NSObject

+ (SoundInstance *)instanceOfInboundRingtone;
+ (SoundInstance *)instanceOfOutboundRingtone;
+ (SoundInstance *)instanceOfHandshakeSound;
+ (SoundInstance *)instanceOfCompletedSound;
+ (SoundInstance *)instanceOfBusySound;
+ (SoundInstance *)instanceOfErrorAlert;
+ (SoundInstance *)instanceOfAlert;

@end
