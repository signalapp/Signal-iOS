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

#import "AbstractMessage_Builder.h"

#import "CodedInputStream.h"
#import "ExtensionRegistry.h"
#import "UnknownFieldSet.h"
#import "UnknownFieldSet_Builder.h"


@implementation PBAbstractMessage_Builder

- (id<PBMessage_Builder>) clone {
  @throw [NSException exceptionWithName:@"ImproperSubclassing" reason:@"" userInfo:nil];
}


- (id<PBMessage_Builder>) clear {
  @throw [NSException exceptionWithName:@"ImproperSubclassing" reason:@"" userInfo:nil];
}


- (id<PBMessage_Builder>) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}


- (id<PBMessage_Builder>) mergeFromCodedInputStream:(PBCodedInputStream*) input
                                  extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  @throw [NSException exceptionWithName:@"ImproperSubclassing" reason:@"" userInfo:nil];
}


- (id<PBMessage_Builder>) mergeUnknownFields:(PBUnknownFieldSet*) unknownFields {
  PBUnknownFieldSet* merged =
  [[[PBUnknownFieldSet builderWithUnknownFields:self.unknownFields]
    mergeUnknownFields:unknownFields] build];

  [self setUnknownFields:merged];
  return self;
}


- (id<PBMessage_Builder>) mergeFromData:(NSData*) data {
  PBCodedInputStream* input = [PBCodedInputStream streamWithData:data];
  [self mergeFromCodedInputStream:input];
  [input checkLastTagWas:0];
  return self;
}


- (id<PBMessage_Builder>) mergeFromData:(NSData*) data
                      extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBCodedInputStream* input = [PBCodedInputStream streamWithData:data];
  [self mergeFromCodedInputStream:input extensionRegistry:extensionRegistry];
  [input checkLastTagWas:0];
  return self;
}


- (id<PBMessage_Builder>) mergeFromInputStream:(NSInputStream*) input {
  PBCodedInputStream* codedInput = [PBCodedInputStream streamWithInputStream:input];
  [self mergeFromCodedInputStream:codedInput];
  [codedInput checkLastTagWas:0];
  return self;
}


- (id<PBMessage_Builder>) mergeFromInputStream:(NSInputStream*) input
                             extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBCodedInputStream* codedInput = [PBCodedInputStream streamWithInputStream:input];
  [self mergeFromCodedInputStream:codedInput extensionRegistry:extensionRegistry];
  [codedInput checkLastTagWas:0];
  return self;
}


- (id<PBMessage>) build {
  @throw [NSException exceptionWithName:@"ImproperSubclassing" reason:@"" userInfo:nil];
}


- (id<PBMessage>) buildPartial {
  @throw [NSException exceptionWithName:@"ImproperSubclassing" reason:@"" userInfo:nil];
}


- (BOOL) isInitialized {
  @throw [NSException exceptionWithName:@"ImproperSubclassing" reason:@"" userInfo:nil];
}


- (id<PBMessage>) defaultInstance {
  @throw [NSException exceptionWithName:@"ImproperSubclassing" reason:@"" userInfo:nil];
}


- (PBUnknownFieldSet*) unknownFields {
  @throw [NSException exceptionWithName:@"ImproperSubclassing" reason:@"" userInfo:nil];
}


- (id<PBMessage_Builder>) setUnknownFields:(PBUnknownFieldSet*) unknownFields {
  @throw [NSException exceptionWithName:@"ImproperSubclassing" reason:@"" userInfo:nil];
}

@end
