#import <Foundation/Foundation.h>

/**
 *
 * Stores an NSInputStream and an NSOutputStream in one object
 *
**/

@interface StreamPair : NSObject

@property (strong, readonly, nonatomic) NSInputStream* inputStream;
@property (strong, readonly, nonatomic) NSOutputStream* outputStream;

- (instancetype)initWithInput:(NSInputStream*)input andOutput:(NSOutputStream*)output;

@end
