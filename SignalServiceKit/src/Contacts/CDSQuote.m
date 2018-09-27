//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "CDSQuote.h"
#import "ByteParser.h"

NS_ASSUME_NONNULL_BEGIN

static const long SGX_FLAGS_INITTED = 0x0000000000000001L;
static const long SGX_FLAGS_DEBUG = 0x0000000000000002L;
static const long SGX_FLAGS_MODE64BIT = 0x0000000000000004L;
static const long __unused SGX_FLAGS_PROVISION_KEY = 0x0000000000000004L;
static const long __unused SGX_FLAGS_EINITTOKEN_KEY = 0x0000000000000004L;
static const long SGX_FLAGS_RESERVED = 0xFFFFFFFFFFFFFFC8L;
static const long __unused SGX_XFRM_LEGACY = 0x0000000000000003L;
static const long __unused SGX_XFRM_AVX = 0x0000000000000006L;
static const long SGX_XFRM_RESERVED = 0xFFFFFFFFFFFFFFF8L;

#pragma mark -

@interface CDSQuote ()

@property (nonatomic) uint16_t version;
@property (nonatomic) uint16_t signType;
@property (nonatomic) BOOL isSigLinkable;
@property (nonatomic) uint32_t gid;
@property (nonatomic) uint16_t qeSvn;
@property (nonatomic) uint16_t pceSvn;
@property (nonatomic) NSData *basename;
@property (nonatomic) NSData *cpuSvn;
@property (nonatomic) uint64_t flags;
@property (nonatomic) uint64_t xfrm;
@property (nonatomic) NSData *mrenclave;
@property (nonatomic) NSData *mrsigner;
@property (nonatomic) uint16_t isvProdId;
@property (nonatomic) uint16_t isvSvn;
@property (nonatomic) NSData *reportData;
@property (nonatomic) NSData *signature;

@end

#pragma mark -

@implementation CDSQuote

+ (nullable CDSQuote *)parseQuoteFromData:(NSData *)quoteData
{
    ByteParser *_Nullable parser = [[ByteParser alloc] initWithData:quoteData littleEndian:YES];

    // NOTE: This version is separate from and does _NOT_ match the signature body entity version.
    uint16_t version = parser.nextShort;
    if (version < 1 || version > 2) {
        OWSFailDebug(@"unexpected quote version: %d", (int)version);
        return nil;
    }

    uint16_t signType = parser.nextShort;
    if ((signType & ~1) != 0) {
        OWSFailDebug(@"invalid signType: %d", (int)signType);
        return nil;
    }

    BOOL isSigLinkable = signType == 1;
    uint32_t gid = parser.nextInt;
    uint16_t qeSvn = parser.nextShort;

    uint16_t pceSvn = 0;
    if (version > 1) {
        pceSvn = parser.nextShort;
    } else {
        if (![parser readZero:2]) {
            OWSFailDebug(@"non-zero pceSvn.");
            return nil;
        }
    }

    if (![parser readZero:4]) {
        OWSFailDebug(@"non-zero xeid.");
        return nil;
    }

    NSData *_Nullable basename = [parser readBytes:32];
    if (!basename) {
        OWSFailDebug(@"couldn't read basename.");
        return nil;
    }

    // report_body

    NSData *_Nullable cpuSvn = [parser readBytes:16];
    if (!cpuSvn) {
        OWSFailDebug(@"couldn't read cpuSvn.");
        return nil;
    }
    if (![parser readZero:4]) {
        OWSFailDebug(@"non-zero misc_select.");
        return nil;
    }
    if (![parser readZero:28]) {
        OWSFailDebug(@"non-zero reserved1.");
        return nil;
    }

    uint64_t flags = parser.nextLong;
    if ((flags & SGX_FLAGS_RESERVED) != 0 || (flags & SGX_FLAGS_INITTED) == 0 || (flags & SGX_FLAGS_MODE64BIT) == 0) {
        OWSFailDebug(@"invalid flags.");
        return nil;
    }

    uint64_t xfrm = parser.nextLong;
    if ((xfrm & SGX_XFRM_RESERVED) != 0) {
        OWSFailDebug(@"invalid xfrm.");
        return nil;
    }

    NSData *_Nullable mrenclave = [parser readBytes:32];
    if (!mrenclave) {
        OWSFailDebug(@"couldn't read mrenclave.");
        return nil;
    }
    if (![parser readZero:32]) {
        OWSFailDebug(@"non-zero reserved2.");
        return nil;
    }
    NSData *_Nullable mrsigner = [parser readBytes:32];
    if (!mrsigner) {
        OWSFailDebug(@"couldn't read mrsigner.");
        return nil;
    }
    if (![parser readZero:96]) {
        OWSFailDebug(@"non-zero reserved3.");
        return nil;
    }
    uint16_t isvProdId = parser.nextShort;
    uint16_t isvSvn = parser.nextShort;
    if (![parser readZero:60]) {
        OWSFailDebug(@"non-zero reserved4.");
        return nil;
    }
    NSData *_Nullable reportData = [parser readBytes:64];
    if (!reportData) {
        OWSFailDebug(@"couldn't read reportData.");
        return nil;
    }

    // quote signature
    uint32_t signatureLength = parser.nextInt;
    if (signatureLength != quoteData.length - 436) {
        OWSFailDebug(@"invalid signatureLength.");
        return nil;
    }
    NSData *_Nullable signature = [parser readBytes:signatureLength];
    if (!signature) {
        OWSFailDebug(@"couldn't read signature.");
        return nil;
    }

    if (parser.hasError) {
        return nil;
    }

    CDSQuote *quote = [CDSQuote new];
    quote.version = version;
    quote.signType = signType;
    quote.isSigLinkable = isSigLinkable;
    quote.gid = gid;
    quote.qeSvn = qeSvn;
    quote.pceSvn = pceSvn;
    quote.basename = basename;
    quote.cpuSvn = cpuSvn;
    quote.flags = flags;
    quote.xfrm = xfrm;
    quote.mrenclave = mrenclave;
    quote.mrsigner = mrsigner;
    quote.isvProdId = isvProdId;
    quote.isvSvn = isvSvn;
    quote.reportData = reportData;
    quote.signature = signature;

    return quote;
}

- (BOOL)isDebugQuote
{
    return (self.flags & SGX_FLAGS_DEBUG) != 0;
}

@end

NS_ASSUME_NONNULL_END
