#import <Foundation/Foundation.h>

@interface Zid : NSObject {
@private NSData* data;
}
+(Zid*) zidWithData:(NSData*)zidData;
-(NSData*) getData;
@end
