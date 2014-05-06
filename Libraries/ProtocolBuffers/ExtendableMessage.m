// Copyright 2008 Cyrus Najmabadi
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "ExtendableMessage.h"

#import "ExtensionField.h"

@implementation PBExtendableMessage

@synthesize extensionMap;
@synthesize extensionRegistry;

- (void) dealloc {
  self.extensionMap = nil;
  self.extensionRegistry = nil;
}


- (BOOL) isInitialized:(id) object {
  if ([object isKindOfClass:[NSArray class]]) {
    for (id child in object) {
      if (![self isInitialized:child]) {
        return NO;
      }
    }
  } else if ([object conformsToProtocol:@protocol(PBMessage)]) {
    return [object isInitialized];
  }

  return YES;
}


- (BOOL) extensionsAreInitialized {
  return [self isInitialized:extensionMap.allValues];
}


- (id) getExtension:(id<PBExtensionField>) extension {
  [self ensureExtensionIsRegistered:extension];
  id value = [extensionMap objectForKey:[NSNumber numberWithInt:[extension fieldNumber]]];
  if (value != nil) {
    return value;
  }

  return [extension defaultValue];
}


- (void) ensureExtensionIsRegistered:(id<PBExtensionField>) extension {
  if ([extension extendedClass] != [self class]) {
    @throw [NSException exceptionWithName:@"IllegalArgument" reason:@"Trying to use an extension for another type" userInfo:nil];
  }

  if (extensionRegistry == nil) {
    self.extensionRegistry = [NSMutableDictionary dictionary];
  }
  [extensionRegistry setObject:extension
                        forKey:[NSNumber numberWithInt:[extension fieldNumber]]];
}


- (BOOL) hasExtension:(id<PBExtensionField>) extension {
  return nil != [extensionMap objectForKey:[NSNumber numberWithInt:[extension fieldNumber]]];
}


- (void) writeExtensionsToCodedOutputStream:(PBCodedOutputStream*) output
                                       from:(int32_t) startInclusive
                                         to:(int32_t) endExclusive {
  // man, i really wish Cocoa had a Sorted/TreeMap
  NSArray* sortedKeys = [extensionMap.allKeys sortedArrayUsingSelector:@selector(compare:)];
  for (NSNumber* number in sortedKeys) {
    int32_t fieldNumber = [number intValue];
    if (fieldNumber >= startInclusive && fieldNumber < endExclusive) {
      id<PBExtensionField> extension = [extensionRegistry objectForKey:number];
      id value = [extensionMap objectForKey:number];
      [extension writeValue:value includingTagToCodedOutputStream:output];
    }
  }
}


- (int32_t) extensionsSerializedSize {
  int32_t size = 0;
  for (NSNumber* number in extensionMap) {
    id<PBExtensionField> extension = [extensionRegistry objectForKey:number];
    id value = [extensionMap objectForKey:number];
    size += [extension computeSerializedSizeIncludingTag:value];
  }

  return size;
}

@end
