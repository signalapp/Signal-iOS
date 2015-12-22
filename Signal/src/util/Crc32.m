#import "Crc32.h"

#define DEFAULT_POLYNOMIAL 0xEDB88320L
#define DEFAULT_SEED 0xFFFFFFFFL

void generateCRC32Table(uint32_t *pTable, uint32_t poly);

@implementation NSData (CRC)

void generateCRC32Table(uint32_t *pTable, uint32_t poly) {
    for (uint32_t i = 0; i <= 255; i++) {
        uint32_t crc = i;

        for (uint32_t j = 8; j > 0; j--) {
            if ((crc & 1) == 1)
                crc = (crc >> 1) ^ poly;
            else
                crc >>= 1;
        }
        pTable[i] = crc;
    }
}

- (uint32_t)crc32 {
    return [self crc32WithSeed:DEFAULT_SEED usingPolynomial:DEFAULT_POLYNOMIAL];
}

- (uint32_t)crc32WithSeed:(uint32_t)seed usingPolynomial:(uint32_t)poly {
    uint32_t *pTable = malloc(sizeof(uint32_t) * 256);
    generateCRC32Table(pTable, poly);

    uint32_t crc      = seed;
    uint8_t *pBytes   = (uint8_t *)[self bytes];
    NSUInteger length = self.length;

    while (length--) {
        crc = (crc >> 8) ^ pTable[(crc & 0xFF) ^ *pBytes++];
    }

    free(pTable);
    return crc ^ 0xFFFFFFFFL;
}

@end
