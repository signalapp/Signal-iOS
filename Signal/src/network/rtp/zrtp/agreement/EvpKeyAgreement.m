#import "EvpKeyAgreement.h"
#import "Constraints.h"
#import "NumberUtil.h"
#import <OpenSSL/bn.h>
#import <OpenSSL/dh.h>
#import <OpenSSL/ec.h>
#import <OpenSSL/pem.h>

#define checkEvpSucess(expr, desc)  checkSecurityOperation((expr) == 1, desc)
#define checkEvpNotNull(expr, desc) checkSecurityOperation((expr) != NULL, desc)

#define EC25_COORDINATE_LENGTH 32
#define NAMED_ELLIPTIC_CURVE NID_X9_62_prime256v1

enum KeyAgreementType {
    KeyAgreementType_DH = EVP_PKEY_DH,
    KeyAgreementType_ECDH = EVP_PKEY_EC
};

@implementation EvpKeyAgreement {
    EVP_PKEY *params;
    EVP_PKEY *pkey;
    enum KeyAgreementType keyAgreementType;
}

#pragma mark Constructors / Initialization

+(EvpKeyAgreement*) evpDh3kKeyAgreementWithModulus:(NSData*) modulus andGenerator:(NSData*) generator{
    EvpKeyAgreement* evpKeyAgreement = [[EvpKeyAgreement alloc] initWithKeyType:KeyAgreementType_DH ];
    assert(nil != modulus);
    assert(nil != generator);
    
    [evpKeyAgreement generateDhParametersWithModulus:modulus andGenerator:generator];
    [evpKeyAgreement generateKeyPair];
    return evpKeyAgreement;
}

+(EvpKeyAgreement*) evpEc25KeyAgreement {
    EvpKeyAgreement* evpKeyAgreement = [[EvpKeyAgreement alloc] initWithKeyType:KeyAgreementType_ECDH ];
    [evpKeyAgreement generateEc25Parameters];
    [evpKeyAgreement generateKeyPair];
    return evpKeyAgreement;
}


-(EvpKeyAgreement*) initWithKeyType:(enum KeyAgreementType) keyType {
    if( nil == [super init]){
        return nil;
    }
    
    keyAgreementType = keyType;
    return self;
}

-(void)dealloc {
    [self freeKey:params];
    [self freeKey:pkey];
}



-(EVP_PKEY_CTX*) createParameterContext{
    EVP_PKEY_CTX* ctx;
    ctx = EVP_PKEY_CTX_new_id(keyAgreementType, NULL);
    checkEvpNotNull(ctx , @"pctx_new_id");
    
    int ret = EVP_PKEY_paramgen_init(ctx);
    checkEvpSucess(ret, @"paramgen_init");
    
    return ctx;
}


#pragma mark Parameter/Key Generation
-(void) generateDhParametersWithModulus:(NSData*) modulus andGenerator:(NSData*) generator {
    
    EVP_PKEY_CTX* pctx = [self createParameterContext];
    DH* dh = DH_new();
    
    @try{
        checkEvpNotNull(dh, @"dh_new");
    
        dh->p= [self generateBignumberFor:modulus];
        dh->g= [self generateBignumberFor:generator];
    
        if ((dh->p == NULL) || (dh->g == NULL))
        {
            [self reportError:@"DH Parameters uninitialized"];
        }
    
        [self createNewEvpKeyFreePreviousIfNessesary:&params];
        EVP_PKEY_set1_DH(params, dh);
        
    } @finally {
        DH_free(dh);
        EVP_PKEY_CTX_free(pctx);
    }
}

-(void) generateEc25Parameters {
    EVP_PKEY_CTX* pctx = [self createParameterContext];
    
    int ret;
    ret = EVP_PKEY_CTX_set_ec_paramgen_curve_nid(pctx, NAMED_ELLIPTIC_CURVE);
    checkEvpSucess(ret, @"pctx_ec_init");
    
    ret = EVP_PKEY_paramgen(pctx, &params);
    checkEvpSucess(ret,@"pctx_paramgen" );
    
    EVP_PKEY_CTX_free(pctx);
}


-(void) generateKeyPair {
    int ret;
    EVP_PKEY_CTX* kctx;
    
    checkEvpNotNull(params, @"parameters uninitialized");
    
    kctx = EVP_PKEY_CTX_new(params, NULL);
    checkEvpNotNull(kctx, @"key_ctx");
    
    ret = EVP_PKEY_keygen_init(kctx);
    checkEvpSucess(ret, @"keygen_init");

    ret = EVP_PKEY_keygen(kctx, &pkey);
    checkEvpSucess(ret, @"keygen");
    
    EVP_PKEY_CTX_free(kctx);
}


-(NSData*) getSharedSecretForRemotePublicKey:(NSData*) publicKey{
    size_t secret_len;
    unsigned char* secret;
    
    EVP_PKEY* peerkey = [self deserializePublicKey:[publicKey bytes] withLength:[publicKey length]];
    EVP_PKEY_CTX* ctx;
    
    
    ctx = EVP_PKEY_CTX_new(pkey, NULL);
    checkEvpNotNull(ctx, @"ctx_new");
    
    checkEvpSucess(EVP_PKEY_derive_init(ctx),                   @"derive_init");
    checkEvpSucess(EVP_PKEY_derive_set_peer(ctx, peerkey),      @"set_peer");
    checkEvpSucess(EVP_PKEY_derive(ctx, NULL, &secret_len),     @"derive_step1");
    
    secret = OPENSSL_malloc(secret_len);
    checkEvpNotNull(secret, @"secret_malloc");

    checkEvpSucess(EVP_PKEY_derive(ctx, secret, &secret_len),   @"derive_step2");

    NSData* secretData = [NSData dataWithBytes:secret length:secret_len];
    
    EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_free(peerkey);
    OPENSSL_free(secret);
    
    return secretData;
}

#pragma mark Public Key Serialization

-(NSData*) getPublicKey{
    switch (keyAgreementType) {
        case KeyAgreementType_DH:
            return [self serializeDhPublicKey:pkey];
        case KeyAgreementType_ECDH:
            return [self serializeEcPublicKey:pkey];
        default:
            [self reportError:@"Undefined KeyType"];
    }
}

-(NSData*) serializeDhPublicKey:(EVP_PKEY*)evkey  {
    
    DH* dh;
    unsigned char* buf;
    
    dh = EVP_PKEY_get1_DH(evkey);
    
    int bufsize = BN_num_bytes(dh->pub_key);
    buf = OPENSSL_malloc(bufsize);
    checkEvpNotNull(buf, @"dh_pubkey_buffer");
    
    BN_bn2bin(dh->pub_key, buf);
    NSData* pub_key = [NSData dataWithBytes:buf length:(unsigned int)bufsize];
    
    DH_free(dh);
    OPENSSL_free(buf);
    
    return pub_key;
}


-(NSData*) serializeEcPublicKey:(EVP_PKEY*)evkey {
    
    EC_KEY* ec_key              = EVP_PKEY_get1_EC_KEY(evkey);
    const EC_POINT* ec_pub      = EC_KEY_get0_public_key(ec_key);
    const EC_GROUP* ec_group    = EC_KEY_get0_group(ec_key);
    
    NSData* data = [self packEcCoordinatesFromEcPoint:ec_pub withEcGroup:ec_group];
    
    EC_KEY_free(ec_key);
    
    return data;
}

-(EVP_PKEY*) deserializePublicKey:(const unsigned char*) buf withLength:(size_t) bufsize {
    switch (keyAgreementType) {
        case KeyAgreementType_DH:
            return [self deserializeDhPublicKey:buf withLength:bufsize];
        case KeyAgreementType_ECDH:
            return [self deserializeEcPublicKey:buf withLength:bufsize];
        default:
            [self reportError:@"Undefined KeyType"];
    }
}

-(EVP_PKEY*) deserializeDhPublicKey:(const unsigned char*) buf withLength:(size_t) bufsize {
   
    EVP_PKEY* evpk = EVP_PKEY_new();
    DH* dh = DH_new();
   
    BIGNUM* bn = BN_new();
    BN_bin2bn(buf, [NumberUtil assertConvertNSUIntegerToInt:bufsize], bn);
    dh->pub_key = bn;
    
    EVP_PKEY_assign_DH(evpk, dh);
    
    return evpk;
}


-(EVP_PKEY*) deserializeEcPublicKey:(const unsigned char*) buf withLength:(size_t) bufsize {
    EC_KEY* eck = EC_KEY_new_by_curve_name(NAMED_ELLIPTIC_CURVE);
    const EC_GROUP* ecg = EC_KEY_get0_group(eck);
    
    EC_POINT* ecp =  EC_POINT_new(ecg);
    [self unpackEcCoordinatesFromBuffer:buf ofSize:bufsize toEcPoint:ecp withEcGroup:ecg];
    
    EVP_PKEY* evpk = EVP_PKEY_new();
    EC_KEY_set_public_key(eck, ecp);
    EVP_PKEY_assign_EC_KEY(evpk, eck);
    
    EC_POINT_free(ecp);
    
    return evpk;

}

-(NSData*) packEcCoordinatesFromEcPoint:(const EC_POINT*) ec_point withEcGroup:(const EC_GROUP*) ec_group {
    BIGNUM *x = BN_new();
    BIGNUM *y = BN_new();
    
    unsigned char* buf_x;  size_t bufsize_x;
    unsigned char* buf_y;  size_t bufsize_y;
    
    EC_POINT_get_affine_coordinates_GFp(ec_group, ec_point, x, y, NULL);
    
    bufsize_x = [NumberUtil assertConvertIntToNSUInteger:BN_num_bytes(x)];
    bufsize_y = [NumberUtil assertConvertIntToNSUInteger:BN_num_bytes(y)];
    
    checkEvpNotNull( buf_x = OPENSSL_malloc(bufsize_x), @"ec_x_buffer");
    checkEvpNotNull( buf_y = OPENSSL_malloc(bufsize_y), @"ec_y_buffer");
    
    BN_bn2bin(x, buf_x);
    BN_bn2bin(y, buf_y);
    
    NSMutableData* data = [NSMutableData dataWithBytes:buf_x length:bufsize_x];
    [data appendData:[NSData dataWithBytes:buf_y length:bufsize_y]];
    
    OPENSSL_free(buf_x);
    OPENSSL_free(buf_y);
    
    BN_free(x);
    BN_free(y);
    
    return data;
}

-(void) unpackEcCoordinatesFromBuffer:(const unsigned char*) buffer
                                  ofSize:(size_t) bufsize
                               toEcPoint:(EC_POINT*) ecp
                             withEcGroup:(const EC_GROUP*) ecg {
    
    checkOperation(2*EC25_COORDINATE_LENGTH == bufsize);
    
    BIGNUM* x = BN_new();
    BIGNUM* y = BN_new();
    
    BN_bin2bn(buffer,                           EC25_COORDINATE_LENGTH, x);
    BN_bin2bn(buffer+EC25_COORDINATE_LENGTH,    EC25_COORDINATE_LENGTH, y);
    
    EC_POINT_set_affine_coordinates_GFp(ecg, ecp, x, y, NULL);
    
    BN_free(x);
    BN_free(y);
}

#pragma mark Helper Functions

-(void) createNewEvpKeyFreePreviousIfNessesary:(EVP_PKEY**) evpKey{
    if(NULL != evpKey){
        [self freeKey:(*evpKey)];
    }
    (*evpKey) = EVP_PKEY_new();
}

-(void) freeKey:(EVP_PKEY*) evpKey{
    if (NULL != evpKey){
        EVP_PKEY_free(evpKey);
    }
}

-(BIGNUM*) generateBignumberFor:(NSData*) data{
    assert([data length] <= INT_MAX );
    return BN_bin2bn([data bytes], (int)data.length, NULL);
}

-(void) reportError:(NSString*) errorString{
    [SecurityFailure raise:[NSString stringWithFormat:@"Security related failure: %@ (in %s at line %d)", errorString,__FILE__,__LINE__]];
}






@end
