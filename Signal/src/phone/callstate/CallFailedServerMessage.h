#import <Foundation/Foundation.h>

@interface CallFailedServerMessage : NSObject

@property (readonly, nonatomic) NSString* text;

- (instancetype)initWithText:(NSString*)text;

@end
