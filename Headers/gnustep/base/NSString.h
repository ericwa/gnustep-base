/* Interface for NSObject for GNUStep
   Copyright (C) 1994 NeXT Computer, Inc.
   
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

#ifndef __NSString_h_OBJECTS_INCLUDE
#define __NSString_h_OBJECTS_INCLUDE

#include <objects/stdobjects.h>
#include <objects/String.h>

#include <foundation/NSRange.h>

typedef unsigned short unichar;

@class NSData;
@class NSArray;
@class NSCharacterSet;
@class NSDictionary;

#define NSMaximumStringLength	(INT_MAX-1)
#define NSHashStringLength	63

enum 
{
  NSCaseInsensitiveSearch = 1,
  NSLiteralSearch = 2,
  NSBackwardsSearch = 4,
  NSAnchoredSearch = 8
};

typedef enum _NSStringEncoding 
{
  NSUnicodeStringEncoding = 0,
  NSASCIIStringEncoding,
  NSNEXTSTEPStringEncoding,
  NSEUCStringEncoding,
  NSUTFStringEncoding,
  NSISOLatin1StringEncoding,
  NSSymbolStringEncoding,
  NSNonLossyASCIIStringEncoding
} NSStringEncoding;

@interface NSString : String <NSCopying, NSMutableCopying>

#if 0

// Creating Temporary Strings

+ (NSString*) localizedStringWithFormat: (NSString*) format, ...;
+ (NSString*) stringWithCString: (const char*) byteString;
+ (NSString*) stringWithCString: (const char*)byteString
   length: (unsigned int)length;

+ (NSString*) stringWithCharacters: (const unichar*)chars
   length: (unsigned int)length;
+ (NSString*) stringWithFormat: (NSString*)format,...;

// Initializing Newly Allocated Strings

- (id) init;
- (id) initWithCString: (const char*)byteString;
- (id) initWithCString: (const char*)byteString
   length: (unsigned int)length;
- (id) initWithCStringNoCopy: (char*)byteString
   length: (unsigned int)length
   freeWhenDone: (BOOL)flag;
- (id) initWithCharacters: (const unichar*)chars
   length: (unsigned int)length;
- (id) initWithCharactersNoCopy: (unichar*)chars
   length: (unsigned int)length
   freeWhenDone: (BOOL)flag;
- (id) initWithContentsOfFile: (NSString*)path;
- (id) initWithData: (NSData*)data
   encoding: (NSStringEncoding)encoding;
- (id) initWithFormat: (NSString*)format,...;
- (id) initWithFormat: (NSString*)format
   arguments: (va_list)argList;
- (id) initWithFormat: (NSString*)format
   locale: (NSDictionary*)dictionary;
- (id) initWithFormat: (NSString*)format
   locale: (NSDictionary*)dictionary
   arguments: (va_list)argList;
- (id) initWithString: (NSString*)string;

// Getting a String's Length

- (unsigned int) length;

// Accessing Characters

- (unichar) characterAtIndex: (unsigned int)index;
- (void) getCharacters: (unichar*)buffer;
- (void) getCharacters: (unichar*)buffer
   range: (NSRange)aRange;

// Combining Strings

- (NSString*) stringByAppendingFormat: (NSString*)format,...;
- (NSString*) stringByAppendingString: (NSString*)aString;

// Dividing Strings into Substrings

- (NSArray*) componentsSeparatedByString: (NSString*)separator;
- (NSString*) substringFromIndex: (unsigned int)index;
- (NSString*) substringFromRange: (NSRange)aRange;
- (NSString*) substringToIndex: (unsigned int)index;

// Finding Ranges of Characters and Substrings

- (NSRange) rangeOfCharacterFromSet: (NSCharacterSet*)aSet;
- (NSRange) rangeOfCharacterFromSet: (NSCharacterSet*)aSet
   options: (unsigned int)mask;
- (NSRange) rangeOfCharacterFromSet: (NSCharacterSet*)aSet
    options: (unsigned int)mask
    range: (NSRange)aRange;
- (NSRange) rangeOfString: (NSString*)string;
 
- (NSRange) rangeOfString: (NSString*)string
   options: (unsigned int)mask;
- (NSRange) rangeOfString: (NSString*)aString
   options: (unsigned int)mask
   range: (NSRange)aRange;

// Determining Composed Character Sequences

- (NSRange) rangeOfComposedCharacterSequenceAtIndex: (unsigned int)anIndex;

// Identifying and Comparing Strings

- (NSComparisonResult) caseInsensitiveCompare: (NSString*)aString;
- (NSComparisonResult) compare: (NSString*)aString;
- (NSComparisonResult) compare: (NSString*)aString	
   options: (unsigned int)mask;
- (NSComparisonResult) compare: (NSString*)aString
   options: (unsigned int)mask
   range: (NSRange)aRange;
- (BOOL) hasPrefix: (NSString*)aString;
- (BOOL) hasSuffix: (NSString*)aString;
- (unsigned int) hash;
- (BOOL) isEqual: (id)anObject;
- (BOOL) isEqualToString: (NSString*)aString;

// Storing the String

- (NSString*) description;
- (BOOL) writeToFile: (NSString*)filename
   atomically: (BOOL)useAuxiliaryFile;

// Getting a Shared Prefix

- (NSString*) commonPrefixWithString: (NSString*)aString
   options: (unsigned int)mask;

// Changing Case

- (NSString*) capitalizedString;
- (NSString*) lowercaseString;
- (NSString*) uppercaseString;

// Getting C Strings

- (const char*) cString;
- (unsigned int) cStringLength;
- (void) getCString: (char*)buffer;
- (void) getCString: (char*)buffer
    maxLength: (unsigned int)maxLength;
- (void) getCString: (char*)buffer
   maxLength: (unsigned int)maxLength
   range: (NSRange)aRange
   remainingRange: (NSRange*)leftoverRange;

// Getting Numeric Values

- (double) doubleValue;
- (float) floatValue;
- (int) intValue;

// Working With Encodings

+ (NSStringEncoding) defaultCStringEncoding;
- (BOOL) canBeConvertedToEncoding: (NSStringEncoding)encoding;
- (NSData*) dataUsingEncoding: (NSStringEncoding)encoding;
- (NSData*) dataUsingEncoding: (NSStringEncoding)encoding
   allowLossyConversion: (BOOL)flag;
- (NSStringEncoding) fastestEncoding;
- (NSStringEncoding) smallestEncoding;

// Converting String Contents into a Property List

- (id)propertyList;
- (NSDictionary*) propertyListFromStringsFileFormat;

// Manipulating File System Paths

- (unsigned int) completePathIntoString: (NSString**)outputName
   caseSensitive: (BOOL)flag
   matchesIntoArray: (NSArray**)outputArray
   filterTypes: (NSArray*)filterTypes;
- (NSString*) lastPathComponent;
- (NSString*) pathExtension;
- (NSString*) stringByAbbreviatingWithTildeInPath;
- (NSString*) stringByAppendingPathComponent: (NSString*)aString;
- (NSString*) stringByAppendingPathExtension: (NSString*)aString;
- (NSString*) stringByDeletingLastPathComponent;
- (NSString*) stringByDeletingPathExtension;
- (NSString*) stringByExpandingTildeInPath;
- (NSString*) stringByResolvingSymlinksInPath;
- (NSString*) stringByStandardizingPath;

#endif

@end

#endif /* __NSString_h_OBJECTS_INCLUDE */
