#import <Foundation/Foundation.h>

#define RAISE_EXCEPTION [NSException raise:@"OPENSSL_Exception" format:@"Line:%d File:%s ", __LINE__, __FILE__]
#define RAISE_EXCEPTION_ON_FAILURE(X) \
    if (1 != X) {                     \
        RAISE_EXCEPTION;              \
    }
