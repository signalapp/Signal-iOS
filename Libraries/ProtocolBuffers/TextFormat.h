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

@interface PBTextFormat : NSObject {

}

+ (int32_t) parseInt32:(NSString*) text;
+ (int32_t) parseUInt32:(NSString*) text;
+ (int64_t) parseInt64:(NSString*) text;
+ (int64_t) parseUInt64:(NSString*) text;

+ (NSData*) unescapeBytes:(NSString*) input;

@end
