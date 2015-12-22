#import <Foundation/Foundation.h>

@interface Zid : NSObject {
   @private
    NSData *data;
}

+ (instancetype)nullZid;
+ (Zid *)zidWithData:(NSData *)zidData;
- (NSData *)getData;

@end
