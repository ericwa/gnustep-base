/* Interface for NSDictionary for GNUStep
   Copyright (C) 1995 Free Software Foundation, Inc.

   Written by:  R. Andrew McCallum <mccallum@gnu.ai.mit.edu>
   Date: 1995
   
   This file is part of the GNU Objective C Class Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.
   
   You should have received a copy of the GNU Library General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
   */ 

#ifndef _NSDictionary_h_OBJECTS_INCLUDE
#define _NSDictionary_h_OBJECTS_INCLUDE

#include <objects/stdobjects.h>

@class NSArray, NSString, NSEnumerator;

@interface NSDictionary : NSObject <NSCopying>

+ allocWithZone: (NSZone*)zone;
+ dictionary;
+ dictionaryWithObjects: (id*)objects forKeys: (NSString**)keys
		  count: (unsigned)count;
+ dictionaryWithObjects: (NSArray*)objects forKeys: (NSArray*)keys;
- initWithObjects: (NSArray*)objects forKeys: (NSArray*)keys;
- initWithObjects: (id*)objects forKeys: (NSString**)keys
	    count: (unsigned)count;
- initWithDictionary: (NSDictionary*)otherDictionary;
- initWithContentsOfFile: (NSString*)path;

- (unsigned) count;
- objectForKey: (NSString*)aKey;
- (NSEnumerator*) keyEnumerator;
- (BOOL) isEqualToDictionary: (NSDictionary*)other;
- (NSString*) description;
- (NSString*) descriptionWithIndent: (unsigned)level;
- (NSArray*) allKeys;
- (NSArray*) allValues;
- (NSArray*) allKeysForObject: anObject;
- (BOOL) writeToFile: (NSString*)path atomically: (BOOL)useAuxiliaryFile;
- (NSEnumerator*) objectEnumerator;

@end

@interface NSMutableDictionary: NSDictionary

+ allocWithZone: (NSZone*)zone;
+ dictionaryWithCapacity: (unsigned)numItems;
- initWithCapacity: (unsigned)numItems;

- (void) setObject: anObject forKey: (NSString*)aKey;
- (void) removeObjectForKey: (NSString*)aKey;
- (void) removeAllObjects;
- (void) removeObjectsForKeys: (NSArray*)keyArray;
- (void) addEntriesFromDictionary: (NSDictionary*)otherDictionary;

@end

#endif
