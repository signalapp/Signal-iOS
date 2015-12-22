#import "Constraints.h"
#import "CyclicalBuffer.h"
#import "Util.h"

#define INITIAL_CAPACITY 100 // The buffer size can not be longer than an unsigned int.

@implementation CyclicalBuffer

- (id)init {
    if (self = [super init]) {
        buffer = [NSMutableData dataWithLength:INITIAL_CAPACITY];
    }
    return self;
}

- (void)enqueueData:(NSData *)data {
    ows_require(data != nil);
    if (data.length == 0)
        return;

    NSUInteger incomingDataLength   = data.length;
    NSUInteger bufferCapacity       = buffer.length;
    NSUInteger writeOffset          = (readOffset + count) % bufferCapacity;
    NSUInteger bufferSpaceAvailable = bufferCapacity - count;
    NSUInteger writeSlack           = bufferCapacity - writeOffset;

    if (bufferSpaceAvailable < incomingDataLength) {
        NSUInteger readSlack     = bufferCapacity - readOffset;
        NSUInteger newCapacity   = bufferCapacity * 2 + incomingDataLength;
        NSMutableData *newBuffer = [NSMutableData dataWithLength:newCapacity];
        [newBuffer replaceBytesInRange:NSMakeRange(0, MIN(readSlack, count))
                             withBytes:(uint8_t *)[buffer bytes] + readOffset];
        if (readSlack < count) {
            [newBuffer replaceBytesInRange:NSMakeRange(readSlack, count - readSlack)
                                 withBytes:(uint8_t *)[buffer bytes]];
        }
        buffer               = newBuffer;
        bufferCapacity       = newCapacity;
        readOffset           = 0;
        writeOffset          = count;
        bufferSpaceAvailable = bufferCapacity - count;
        writeSlack           = bufferCapacity - writeOffset;
    }

    assert(bufferSpaceAvailable >= incomingDataLength);

    [buffer replaceBytesInRange:NSMakeRange(writeOffset, MIN(writeSlack, incomingDataLength)) withBytes:[data bytes]];
    if (incomingDataLength > writeSlack) {
        [buffer replaceBytesInRange:NSMakeRange(0, incomingDataLength - writeSlack)
                          withBytes:(uint8_t *)[data bytes] + writeSlack];
    }
    count += data.length;
}

- (NSUInteger)enqueuedLength {
    return count;
}

- (void)discard:(NSUInteger)length {
    ows_require(length <= count);
    count -= length;
    readOffset = (readOffset + length) % (unsigned int)buffer.length;
}

- (NSData *)peekDataWithLength:(NSUInteger)length {
    ows_require(length <= count);
    if (length == 0)
        return [NSData data];

    NSUInteger readSlack = buffer.length - readOffset;

    NSMutableData *result = [NSMutableData dataWithLength:length];
    [result replaceBytesInRange:NSMakeRange(0, MIN(readSlack, length))
                      withBytes:(uint8_t *)[buffer bytes] + readOffset];
    if (readSlack < length) {
        [result replaceBytesInRange:NSMakeRange(readSlack, length - readSlack) withBytes:[buffer bytes]];
    }

    return result;
}

- (NSData *)dequeueDataWithLength:(NSUInteger)length {
    NSData *result = [self peekDataWithLength:length];
    [self discard:length];
    return result;
}

- (NSData *)dequeuePotentialyVolatileDataWithLength:(NSUInteger)length {
    NSUInteger readSlack = buffer.length - readOffset;

    if (readSlack < length)
        return [self dequeueDataWithLength:length];

    NSData *result = [buffer subdataVolatileWithRange:NSMakeRange(readOffset, length)];

    [self discard:length];
    return result;
}

- (NSData *)peekVolatileHeadOfData {
    NSUInteger capacity = buffer.length;
    NSUInteger slack    = capacity - readOffset;
    return [buffer subdataVolatileWithRange:NSMakeRange(readOffset, MIN(count, slack))];
}

@end
