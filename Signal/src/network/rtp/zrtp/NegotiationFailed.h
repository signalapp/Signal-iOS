#import <Foundation/Foundation.h>

@interface NegotiationFailed : NSObject

@property (nonatomic,readonly) NSString* reason;

+(NegotiationFailed*) negotiationFailedWithReason:(NSString*)reason;

@end
