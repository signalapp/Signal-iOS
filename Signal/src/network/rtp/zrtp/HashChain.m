#import "CryptoTools.h"
#import "Constraints.h"
#import "HashChain.h"

@implementation HashChain

@synthesize h0,h1,h2,h3;

+(HashChain*) hashChainWithSeed:(NSData*)seed {
    ows_require(seed != nil);
    ows_require(seed.length == HASH_CHAIN_ITEM_LENGTH);
    HashChain* s = [HashChain new];
    s->h0 = seed;
    s->h1 = [s->h0 hashWithSha256];
    s->h2 = [s->h1 hashWithSha256];
    s->h3 = [s->h2 hashWithSha256];
    return s;
}
+(HashChain*) hashChainWithSecureGeneratedData {
    return [HashChain hashChainWithSeed:[CryptoTools generateSecureRandomData:HASH_CHAIN_ITEM_LENGTH]];
}

@end
