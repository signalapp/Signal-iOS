#import <Foundation/Foundation.h>

@interface NegotiationFailed : NSObject

@property (strong, readonly, nonatomic) NSString* reason;

- (instancetype)initWithReason:(NSString*)reason;

@end
