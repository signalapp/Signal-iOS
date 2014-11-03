#import "CyclicalBuffer.h"
#import "Constraints.h"
#import "Util.h"

#define INITIAL_CAPACITY 100 // The buffer size can not be longer than an unsigned int.

@interface CyclicalBuffer ()

@property (strong, nonatomic) NSMutableData* buffer;
@property (nonatomic) uint32_t readOffset;
@property (nonatomic) uint32_t count;

@end

@implementation CyclicalBuffer

- (instancetype)init {
    if (self = [super init]) {
        self.buffer = [NSMutableData dataWithLength:INITIAL_CAPACITY];
    }
    return self;
}

- (void)enqueueData:(NSData*)data {
    require(data != nil);
    if (data.length == 0) return;

    NSUInteger incomingDataLength = data.length;
    NSUInteger bufferCapacity = self.buffer.length;
    NSUInteger writeOffset = (self.readOffset + self.count) % bufferCapacity;
    NSUInteger bufferSpaceAvailable = bufferCapacity - self.count;
    NSUInteger writeSlack = bufferCapacity - writeOffset;
    
    if (bufferSpaceAvailable < incomingDataLength) {
        NSUInteger readSlack = bufferCapacity - self.readOffset;
        NSUInteger newCapacity = bufferCapacity * 2 + incomingDataLength;
        NSMutableData* newBuffer = [NSMutableData dataWithLength:newCapacity];
        [newBuffer replaceBytesInRange:NSMakeRange(0, MIN(readSlack, self.count))
                             withBytes:(uint8_t*)[self.buffer bytes] + self.readOffset];
        if (readSlack < self.count) {
            [newBuffer replaceBytesInRange:NSMakeRange(readSlack, self.count - readSlack) withBytes:(uint8_t*)[self.buffer bytes]];
        }
        self.buffer = newBuffer;
        bufferCapacity = newCapacity;
        self.readOffset = 0;
        writeOffset = self.count;
        bufferSpaceAvailable = bufferCapacity - self.count;
        writeSlack = bufferCapacity - writeOffset;
    }
    
    assert(bufferSpaceAvailable >= incomingDataLength);
    
    [self.buffer replaceBytesInRange:NSMakeRange(writeOffset, MIN(writeSlack, incomingDataLength))
                           withBytes:[data bytes]];
    if (incomingDataLength > writeSlack) {
        [self.buffer replaceBytesInRange:NSMakeRange(0, incomingDataLength - writeSlack)
                               withBytes:(uint8_t*)[data bytes] + writeSlack];
    }
    self.count += (unsigned int)data.length;
}

- (NSUInteger)enqueuedLength {
    return self.count;
}

- (void)discard:(NSUInteger)length {
    require(length <= self.count);
    self.count -= (unsigned int)length;
    self.readOffset = (self.readOffset + length)%(unsigned int)self.buffer.length;
}

- (NSData*)peekDataWithLength:(NSUInteger)length {
    require(length <= self.count);
    if (length == 0) return [[NSData alloc] init];
    
    NSUInteger readSlack = self.buffer.length - self.readOffset;
    
    NSMutableData* result = [NSMutableData dataWithLength:length];
    [result replaceBytesInRange:NSMakeRange(0, MIN(readSlack, length)) withBytes:(uint8_t*)[self.buffer bytes] + self.readOffset];
    if (readSlack < length) {
        [result replaceBytesInRange:NSMakeRange(readSlack, length - readSlack) withBytes:[self.buffer bytes]];
    }
    
    return result;
}

- (NSData*)dequeueDataWithLength:(NSUInteger)length {
    NSData* result = [self peekDataWithLength:length];
    [self discard:length];
    return result;
}

- (NSData*)dequeuePotentialyVolatileDataWithLength:(NSUInteger)length {
    NSUInteger readSlack = self.buffer.length - self.readOffset;
    
    if (readSlack < length) return [self dequeueDataWithLength:length];
    
    NSData* result = [self.buffer subdataVolatileWithRange:NSMakeRange(self.readOffset, length)];
    
    [self discard:length];
    return result; 
}

- (NSData*)peekVolatileHeadOfData{
    NSUInteger capacity = self.buffer.length;
    NSUInteger slack = capacity - self.readOffset;
    return [self.buffer subdataVolatileWithRange:NSMakeRange(self.readOffset, MIN(self.count, slack))];
}

@end
