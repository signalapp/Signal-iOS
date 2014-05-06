#import <Foundation/Foundation.h>

/**
 *
 * Stores an NSInputStream and an NSOutputStream in one object
 *
**/

@interface StreamPair : NSObject
@property (nonatomic, readonly) NSInputStream* inputStream;
@property (nonatomic, readonly) NSOutputStream* outputStream;

+(StreamPair*) streamPairWithInput:(NSInputStream*)input andOutput:(NSOutputStream*)output;

@end
