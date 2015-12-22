#import <Foundation/Foundation.h>
#import "AudioSocket.h"

/**
 *
 * A CallConnectResult is the eventual result of trying to initiate or respond to a call.
 * It includes a secure communication channel and a short authentication string.
 *
 */
@interface CallConnectResult : NSObject

@property (nonatomic, readonly) NSString *shortAuthenticationString;
@property (nonatomic, readonly) AudioSocket *audioSocket;

+ (CallConnectResult *)callConnectResultWithShortAuthenticationString:(NSString *)shortAuthenticationString
                                                       andAudioSocket:(AudioSocket *)audioSocket;

@end
