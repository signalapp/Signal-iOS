# **libPhoneNumber for iOS** 

 - NBPhoneNumberUtil
 - NBAsYouTypeFormatter

> ARC only, or add the **"-fobjc-arc"** flag for non-ARC
 
### Using [CocoaPods](http://cocoapods.org/?q=libPhoneNumber-iOS)
> pod 'libPhoneNumber-iOS', '~> 0.7'

### Setting up Manually
##### Add source files to your projects from libPhoneNumber
    - NBPhoneNumberUtil.h, .m
    - NBAsYouTypeFormatter.h, .m
    
    - NBNumberFormat.h, .m
    - NBPhoneNumber.h, .m
    - NBPhoneNumberDesc.h, .m
    - NBPhoneNumberDefines.h
    - NBPhoneMetaData.h, .m
    
    - NSArray+NBAdditions.h, .m
    
    - Add "NBPhoneNumberMetadata.plist" and "NBPhoneNumberMetadataForTesting.plist" to bundle resources
    - Add "CoreTelephony.framework"

See sample test code from
> libPhoneNumber-iOS/libPhoneNumberTests/libPhoneNumberTests.m 

### Usage - **NBPhoneNumberUtil**
```obj-c
    NBPhoneNumberUtil *phoneUtil = [NBPhoneNumberUtil sharedInstance];
    
    NSError *aError = nil;
    NBPhoneNumber *myNumber = [phoneUtil parse:@"6766077303"
                                 defaultRegion:@"AT" error:&aError];
    
    if (aError == nil) {
        // Should check error
        NSLog(@"isValidPhoneNumber ? [%@]", [phoneUtil isValidNumber:myNumber] ? @"YES":@"NO");
        
        // E164          : +436766077303
        NSLog(@"E164          : %@", [phoneUtil format:myNumber 
                                          numberFormat:NBEPhoneNumberFormatE164
                                                 error:&aError]);
        // INTERNATIONAL : +43 676 6077303
        NSLog(@"INTERNATIONAL : %@", [phoneUtil format:myNumber 
                                          numberFormat:NBEPhoneNumberFormatINTERNATIONAL 
                                                 error:&aError]);
        // NATIONAL      : 0676 6077303
        NSLog(@"NATIONAL      : %@", [phoneUtil format:myNumber 
                                          numberFormat:NBEPhoneNumberFormatNATIONAL 
                                                 error:&aError]);
        // RFC3966       : tel:+43-676-6077303
        NSLog(@"RFC3966       : %@", [phoneUtil format:myNumber
                                          numberFormat:NBEPhoneNumberFormatRFC3966 
                                                 error:&aError]);
    } else {
        NSLog(@"Error : %@", [aError localizedDescription]);
    }
    
    NSLog (@"extractCountryCode [%ld]", [phoneUtil extractCountryCode:@"823213123123" 
                                                       nationalNumber:nil]);
    
    NSString *res = nil;
    UInt32 dRes = [phoneUtil extractCountryCode:@"823213123123" nationalNumber:&res];
    
    NSLog (@"extractCountryCode [%lu] [%@]", dRes, res);
```

### Usage - **NBAsYouTypeFormatter**
```obj-c
    NBAsYouTypeFormatter *f = [[NBAsYouTypeFormatter alloc] initWithRegionCode:@"US"];
    NSLog(@"%@", [f inputDigit:@"6"]); // "6"
    NSLog(@"%@", [f inputDigit:@"5"]); // "65"
    NSLog(@"%@", [f inputDigit:@"0"]); // "650"
    NSLog(@"%@", [f inputDigit:@"2"]); // "650 2"
    NSLog(@"%@", [f inputDigit:@"5"]); // "650 25"
    NSLog(@"%@", [f inputDigit:@"3"]); // "650 253"
    
    // Note this is how a US local number (without area code) should be formatted.
    NSLog(@"%@", [f inputDigit:@"2"]); // "650 2532"
    NSLog(@"%@", [f inputDigit:@"2"]); // "650 253 22"
    NSLog(@"%@", [f inputDigit:@"2"]); // "650 253 222"
    NSLog(@"%@", [f inputDigit:@"2"]); // "650 253 2222"
    // Can remove last digit
    NSLog(@"%@", [f removeLastDigit]); // "650 253 222"
```

##### Visit [libphonenumber](http://code.google.com/p/libphonenumber/) for more information or mail (zen.isis@gmail.com)

##### **Metadata managing (updating metadata)**

###### Step1. Fetch "metadata.js" and "metadatafortesting.js" from Repositories
    svn checkout http://libphonenumber.googlecode.com/svn/trunk/ libphonenumber-read-only
    
###### Step2. Convert Javascript Object to JSON using PHP scripts 
    Output - "PhoneNumberMetaData.json" and "PhoneNumberMetaDataForTesting.json"
    
###### Step3. Generate binary file from NBPhoneMetaDataGenerator
    Output - "NBPhoneNumberMetadata.plist" and "NBPhoneNumberMetadataForTesting.plist"
    
###### Step4. Update exists "NBPhoneNumberMetadata.plist" and "NBPhoneNumberMetadataForTesting.plist" files
