#import <Foundation/Foundation.h>

@interface Zid : NSObject

@property (strong, nonatomic, readonly) NSData* data;

- (instancetype)initWithData:(NSData*)zidData;

@end
