#import <CoreFoundation/CFSocket.h>
#import <Foundation/Foundation.h>
#import "Constraints.h"
#import "CryptoTools.h"

@interface NSData (Conversions)
- (uint16_t)bigEndianUInt16At:(NSUInteger)offset;
- (uint32_t)bigEndianUInt32At:(NSUInteger)offset;
+ (NSData *)dataWithBigEndianBytesOfUInt16:(uint16_t)value;
+ (NSData *)dataWithBigEndianBytesOfUInt32:(uint32_t)value;
+ (NSData *)switchEndiannessOfData:(NSData *)data;
@end
