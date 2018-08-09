#import <Foundation/Foundation.h>

@interface NSArray (Util)
- (NSData *)ows_toUint8Data;
- (NSData *)ows_concatDatas;
- (NSArray *)ows_concatArrays;
@end
