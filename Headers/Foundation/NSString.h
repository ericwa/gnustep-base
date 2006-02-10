/* Interface for NSObject for GNUStep
   Copyright (C) 1995, 1996, 1999 Free Software Foundation, Inc.

   Written by:  Andrew Kachites McCallum <mccallum@gnu.ai.mit.edu>
   Date: 1995
   
   This file is part of the GNUstep Base Library.

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
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02111 USA.
   */ 

#ifndef __NSString_h_GNUSTEP_BASE_INCLUDE
#define __NSString_h_GNUSTEP_BASE_INCLUDE

#include <Foundation/NSObject.h>
#include <Foundation/NSRange.h>

/**
 * Type for representing unicode characters.  (16-bit)
 */
typedef unsigned short unichar;

@class NSArray;
@class NSCharacterSet;
@class NSData;
@class NSDictionary;
#ifndef STRICT_OPENSTEP
@class NSURL;
#endif

#define NSMaximumStringLength	(INT_MAX-1)

enum 
{
  NSCaseInsensitiveSearch = 1,
  NSLiteralSearch = 2,
  NSBackwardsSearch = 4,
  NSAnchoredSearch = 8
};

/**
 *  <p>Enumeration of available encodings for converting between bytes and
 *  characters (in [NSString]s).  The ones that are shared with OpenStep and
 *  Cocoa are: <code>NSASCIIStringEncoding, NSNEXTSTEPStringEncoding,
 *  NSJapaneseEUCStringEncoding, NSUTF8StringEncoding,
 *  NSISOLatin1StringEncoding, NSSymbolStringEncoding,
 *  NSNonLossyASCIIStringEncoding, NSShiftJISStringEncoding,
 *  NSISOLatin2StringEncoding, NSUnicodeStringEncoding,
 *  NSWindowsCP1251StringEncoding, NSWindowsCP1252StringEncoding,
 *  NSWindowsCP1253StringEncoding, NSWindowsCP1254StringEncoding,
 *  NSWindowsCP1250StringEncoding, NSISO2022JPStringEncoding,
 *  NSMacOSRomanStringEncoding, NSProprietaryStringEncoding</code>.</p>
 *  
 *  <p>Additional encodings available under GNUstep are:
 *  <code>NSKOI8RStringEncoding, NSISOLatin3StringEncoding,
 *  NSISOLatin4StringEncoding, NSISOCyrillicStringEncoding,
 *  NSISOArabicStringEncoding, NSISOGreekStringEncoding,
 *  NSISOHebrewStringEncoding, NSISOLatin5StringEncoding,
 *  NSISOLatin6StringEncoding, NSISOThaiStringEncoding,
 *  NSISOLatin7StringEncoding, NSISOLatin8StringEncoding,
 *  NSISOLatin9StringEncoding, NSGB2312StringEncoding, NSUTF7StringEncoding,
 *  NSGSM0338StringEncoding, NSBIG5StringEncoding,
 *  NSKoreanEUCStringEncoding</code>.</p>
 */
typedef enum _NSStringEncoding
{
/* NB. Must not have an encoding with value zero - so we can use zero to
   tell that a variable that should contain an encoding has not yet been
   initialised */
  GSUndefinedEncoding = 0,
  NSASCIIStringEncoding = 1,
  NSNEXTSTEPStringEncoding = 2,
  NSJapaneseEUCStringEncoding = 3,
  NSUTF8StringEncoding = 4,
  NSISOLatin1StringEncoding = 5,	// ISO-8859-1; West European
  NSSymbolStringEncoding = 6,
  NSNonLossyASCIIStringEncoding = 7,
  NSShiftJISStringEncoding = 8,
  NSISOLatin2StringEncoding = 9,	// ISO-8859-2; East European
  NSUnicodeStringEncoding = 10,
  NSWindowsCP1251StringEncoding = 11,
  NSWindowsCP1252StringEncoding = 12,	// WinLatin1
  NSWindowsCP1253StringEncoding = 13,	// Greek
  NSWindowsCP1254StringEncoding = 14,	// Turkish
  NSWindowsCP1250StringEncoding = 15,	// WinLatin2
  NSISO2022JPStringEncoding = 21,
  NSMacOSRomanStringEncoding = 30,
  NSProprietaryStringEncoding = 31,

// GNUstep additions
  NSKOI8RStringEncoding = 50,		// Russian/Cyrillic
  NSISOLatin3StringEncoding = 51,	// ISO-8859-3; South European
  NSISOLatin4StringEncoding = 52,	// ISO-8859-4; North European
  NSISOCyrillicStringEncoding = 22,	// ISO-8859-5
  NSISOArabicStringEncoding = 53,	// ISO-8859-6
  NSISOGreekStringEncoding = 54,	// ISO-8859-7
  NSISOHebrewStringEncoding = 55,	// ISO-8859-8
  NSISOLatin5StringEncoding = 57,	// ISO-8859-9; Turkish
  NSISOLatin6StringEncoding = 58,	// ISO-8859-10; Nordic
  NSISOThaiStringEncoding = 59,		// ISO-8859-11
/* Possible future ISO-8859 additions
					// ISO-8859-12
*/
  NSISOLatin7StringEncoding = 61,	// ISO-8859-13
  NSISOLatin8StringEncoding = 62,	// ISO-8859-14
  NSISOLatin9StringEncoding = 63,	// ISO-8859-15; Replaces ISOLatin1
  NSGB2312StringEncoding = 56,
  NSUTF7StringEncoding = 64,		// RFC 2152
  NSGSM0338StringEncoding,		// GSM (mobile phone) default alphabet
  NSBIG5StringEncoding,			// Traditional chinese
  NSKoreanEUCStringEncoding		// Korean
} NSStringEncoding;

enum {
  NSOpenStepUnicodeReservedBase = 0xF400
};

/**
 * <p>
 *   <code>NSString</code> objects represent an immutable string of Unicode 3.0
 *   characters.  These may be accessed individually as type
 *   <code>unichar</code>, an unsigned short.<br/>
 *   The [NSMutableString] subclass represents a modifiable string.  Both are
 *   implemented as part of a class cluster and the instances you receive may
 *   actually be of unspecified concrete subclasses.
 * </p>
 * <p>
 *   A constant <code>NSString</code> can be created using the following syntax:
 *   <code>@"..."</code>, where the contents of the quotes are the
 *   string, using only ASCII characters.
 * </p>
 * <p>
 *   A variable string can be created using a C printf-like <em>format</em>,
 *   as in <code>[NSString stringWithFormat: @"Total is %f", t]</code>.
 * </p>
 * <p>
 *   To create a concrete subclass of <code>NSString</code>, you must have your
 *   class inherit from <code>NSString</code> and override at least the two
 *   primitive methods - -length and -characterAtIndex:
 * </p>
 * <p>
 *   In general the rule is that your subclass must override any
 *   initialiser that you want to use with it.  The GNUstep
 *   implementation relaxes that to say that, you may override
 *   only the <em>designated initialiser</em> and the other
 *   initialisation methods should work.
 * </p>
 * <p>
 *   Where an NSString instance method returns an NSString object,
 *   the class of the actual object returned may be any subclass
 *   of NSString.  The actual value returned may be a new
 *   autoreleased object, an autoreleased copy of the receiver,
 *   or the receiver itsself.  While the abstract base class
 *   implementations of methods (other than initialisers) will
 *   avoid returning mutable strings by returning an autoreleased
 *   copy of a mutable receiver, concrete subclasses may behave
 *   differently, so code should not rely upon the mutability of
 *   returned strings nor upon their lifetime being greater than
 *   that of the receiver which returned them.
 * </p>
 */
@interface NSString :NSObject <NSCoding, NSCopying, NSMutableCopying>

+ (id) string;
+ (id) stringWithCharacters: (const unichar*)chars
		     length: (unsigned int)length;
#ifndef	STRICT_OPENSTEP
+ (id) stringWithCString: (const char*)byteString
		encoding: (NSStringEncoding)encoding;
#endif
+ (id) stringWithCString: (const char*)byteString
		  length: (unsigned int)length;
+ (id) stringWithCString: (const char*)byteString;
+ (id) stringWithFormat: (NSString*)format,...;
+ (id) stringWithContentsOfFile:(NSString *)path;

// Initializing Newly Allocated Strings
- (id) init;
#ifndef	STRICT_OPENSTEP
- (id) initWithBytes: (const void*)bytes
	      length: (unsigned int)length
	    encoding: (NSStringEncoding)encoding;
- (id) initWithBytesNoCopy: (const void*)bytes
		    length: (unsigned int)length
		  encoding: (NSStringEncoding)encoding 
	      freeWhenDone: (BOOL)flag;
#endif
- (id) initWithCharactersNoCopy: (unichar*)chars
			 length: (unsigned int)length
		   freeWhenDone: (BOOL)flag;
- (id) initWithCharacters: (const unichar*)chars
		   length: (unsigned int)length;
- (id) initWithCStringNoCopy: (char*)byteString
		      length: (unsigned int)length
	        freeWhenDone: (BOOL)flag;
- (id) initWithCString: (const char*)byteString
	        length: (unsigned int)length;
- (id) initWithCString: (const char*)byteString;
- (id) initWithString: (NSString*)string;
- (id) initWithFormat: (NSString*)format, ...;
- (id) initWithFormat: (NSString*)format
	    arguments: (va_list)argList;
- (id) initWithData: (NSData*)data
	   encoding: (NSStringEncoding)encoding;
- (id) initWithContentsOfFile: (NSString*)path;
- (id) init;

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

// Converting String Contents into a Property List
- (id)propertyList;
- (NSDictionary*) propertyListFromStringsFileFormat;

// Identifying and Comparing Strings
- (NSComparisonResult) compare: (NSString*)aString;
- (NSComparisonResult) compare: (NSString*)aString	
		       options: (unsigned int)mask;
- (NSComparisonResult) compare: (NSString*)aString
		       options: (unsigned int)mask
			 range: (NSRange)aRange;
- (BOOL) hasPrefix: (NSString*)aString;
- (BOOL) hasSuffix: (NSString*)aString;
- (BOOL) isEqual: (id)anObject;
- (BOOL) isEqualToString: (NSString*)aString;
- (unsigned int) hash;

// Getting a Shared Prefix
- (NSString*) commonPrefixWithString: (NSString*)aString
			     options: (unsigned int)mask;

// Changing Case
- (NSString*) capitalizedString;
- (NSString*) lowercaseString;
- (NSString*) uppercaseString;

// Getting C Strings
- (const char*) cString;
#ifndef	STRICT_OPENSTEP

#if OS_API_VERSION(100400,GS_API_LATEST) && GS_API_VERSION(010200,GS_API_LATEST)
- (const char*) cStringUsingEncoding: (NSStringEncoding)encoding;
- (void) getCString: (char*)buffer
	  maxLength: (unsigned int)maxLength
	   encoding: (NSStringEncoding)encoding;
- (id) initWithCString: (const char*)byteString
	      encoding: (NSStringEncoding)encoding;
- (unsigned) lengthOfBytesUsingEncoding: (NSStringEncoding)encoding;
- (unsigned) maximumLengthOfBytesUsingEncoding: (NSStringEncoding)encoding;
#endif

#endif
- (unsigned int) cStringLength;
- (void) getCString: (char*)buffer;
- (void) getCString: (char*)buffer
	  maxLength: (unsigned int)maxLength;
- (void) getCString: (char*)buffer
	  maxLength: (unsigned int)maxLength
	      range: (NSRange)aRange
     remainingRange: (NSRange*)leftoverRange;

// Getting Numeric Values
- (float) floatValue;
- (int) intValue;

// Working With Encodings
- (BOOL) canBeConvertedToEncoding: (NSStringEncoding)encoding;
- (NSData*) dataUsingEncoding: (NSStringEncoding)encoding;
- (NSData*) dataUsingEncoding: (NSStringEncoding)encoding
	 allowLossyConversion: (BOOL)flag;
+ (NSStringEncoding) defaultCStringEncoding;
- (NSString*) description;
- (NSStringEncoding) fastestEncoding;
- (NSStringEncoding) smallestEncoding;

/**
 * Attempts to complete this string as a path in the filesystem by finding
 * a unique completion if one exists and returning it by reference in
 * outputName (which must be a non-nil pointer), or if it finds a set of
 * completions they are returned by reference in outputArray, if it is non-nil.
 * filterTypes can be an array of strings specifying extensions to consider;
 * files without these extensions will be ignored and will not constitute
 * completions.  Returns 0 if no match found, else a positive number that is
 * only accurate if outputArray was non-nil.
 */
- (unsigned int) completePathIntoString: (NSString**)outputName
			  caseSensitive: (BOOL)flag
		       matchesIntoArray: (NSArray**)outputArray
			    filterTypes: (NSArray*)filterTypes;

/**
 * Converts the receiver to a C string path expressed in the character
 * encoding appropriate for the local host file system.  This string will be
 * automatically freed soon after it is returned, so copy it if you need it
 * for long.<br />
 * NB. On mingw32 systems the filesystem representation of a path is a 16-bit
 * unicode character string, so you should only pass the value returned by
 * this method to functions expecting wide characters.<br />
 * This method uses [NSFileManager-fileSystemRepresentationWithPath:] to
 * perform the conversion.
 */
- (const GSNativeChar*) fileSystemRepresentation;

/**
 * Converts the receiver to a C string path using the character encoding
 * appropriate to the local file system.  This string will be stored
 * into buffer if it is shorter (number of characters) than size,
 * otherwise NO is returned.<br />
 * NB. On mingw32 systems the filesystem representation of a path is a 16-bit
 * unicode character string, so the buffer you pass to this method must be
 * twice as many bytes as the size (number of characters) you expect to
 * receive.<br />
 * This method uses [NSFileManager-fileSystemRepresentationWithPath:] to
 * perform the conversion.
 */
- (BOOL) getFileSystemRepresentation: (GSNativeChar*)buffer
			   maxLength: (unsigned int)size;

/**
 * Returns a string containing the last path component of the receiver.<br />
 * The path component is the last non-empty substring delimited by the ends
 * of the string, or by path separator characters.<br />
 * If the receiver only contains a root part, this method returns it.<br />
 * If there are no non-empty substrings, this returns an empty string.<br />
 * NB. In a windows UNC path, the host and share specification is treated as
 * a single path component, even though it contains separators.
 * So a string of the form '//host/share' may be returned.<br />
 * Other special cases are apply when the string is the root.
 * <example>
 *   @"foo/bar" produces @"bar"
 *   @"foo/bar/" produces @"bar"
 *   @"/foo/bar" produces @"bar"
 *   @"/foo" produces @"foo"
 *   @"/" produces @"/" (root is a special case)
 *   @"" produces @""
 *   @"C:/" produces @"C:/" (root is a special case)
 *   @"C:" produces @"C:"
 *   @"//host/share/" produces @"//host/share/" (root is a special case)
 *   @"//host/share" produces @"//host/share"
 * </example>
 */
- (NSString*) lastPathComponent;

/**
 * Returns a new string containing the path extension of the receiver.<br />
 * The path extension is a suffix on the last path component which starts
 * with the extension separator (a '.') (for example .tiff is the
 * pathExtension for /foo/bar.tiff).<br />
 * Returns an empty string if no such extension exists.
 * <example>
 *   @"a.b" produces @"b"
 *   @"a.b/" produces @"b"
 *   @"/path/a.ext" produces @"ext"
 *   @"/path/a." produces @""
 *   @"/path/.a" produces @"" (.a is not an extension to a file)
 *   @".a" produces @"" (.a is not an extension to a file)
 * </example>
 */
- (NSString*) pathExtension;

/**
 * Returns a string where a prefix of the current user's home directory is
 * abbreviated by '~', or returns the receiver (or an immutable copy) if
 * it was not found to have the home directory as a prefix.
 */
- (NSString*) stringByAbbreviatingWithTildeInPath;

/**
 * Returns a new string with the path component given in aString
 * appended to the receiver.<br />
 * This removes trailing path separators from the receiver and the root
 * part from aString and replaces them with a single slash as a path
 * separator.<br />
 * Also condenses any multiple separator sequences in the result into
 * single path separators.
 * <example>
 *   @"" with @"file" produces @"file"
 *   @"path" with @"file" produces @"path/file"
 *   @"/" with @"file" produces @"/file"
 *   @"/" with @"file" produces @"/file"
 *   @"/" with @"/file" produces @"/file"
 *   @"path with @"C:/file" produces @"path/file"
 * </example>
 */
- (NSString*) stringByAppendingPathComponent: (NSString*)aString;

/**
 * Returns a new string with the path extension given in aString
 * appended to the receiver after an extensionSeparator ('.').<br />
 * If the receiver has trailing path separator characters, they are
 * stripped before the extension separator is added.<br />
 * If the receiver contains no components after the root, the extension
 * cannot be appended (an extension can only be appended to a file name),
 * so a copy of the unmodified receiver is returned.<br />
 * An empty string may be used as an extension ... in which case the extension
 * separator is appended.<br />
 * This behavior mirrors that of the -stringByDeletingPathExtension method.
 * <example>
 *   @"Mail" with @"app" produces @"Mail.app"
 *   @"Mail.app" with @"old" produces @"Mail.app.old"
 *   @"file" with @"" produces @"file."
 *   @"/" with @"app" produces @"/" (no file name to append to)
 *   @"" with @"app" produces @"" (no file name to append to)
 * </example>
 */
- (NSString*) stringByAppendingPathExtension: (NSString*)aString;

/**
 * Returns a new string with the last path component (including any final
 * path separators) removed from the receiver.<br />
 * A string without a path component other than the root is returned
 * without alteration.<br />
 * See -lastPathComponent for a definition of a path component.
 * <example>
 *   @"hello/there" produces @"hello"
 *   @"hello" produces @""
 *   @"/hello" produces @"/"
 *   @"/" produces @"/"
 *   @"C:file" produces @"C:"
 *   @"C:" produces @"C:"
 *   @"C:/file" produces @"C:/"
 *   @"C:/" produces @"C:/"
 *   @"//host/share/file" produces @"//host/share/"
 *   @"//host/share/" produces @"/host/share/"
 *   @"//host/share" produces @"/host/share"
 * </example>
 */
- (NSString*) stringByDeletingLastPathComponent;

/**
 * Returns a new string with the path extension removed from the receiver.<br />
 * Strips any trailing path separators before checking for the extension
 * separator.<br />
 * NB. This method does not consider a string which contains nothing
 * between the root part and the extension separator ('.') to be a path
 * extension. This mirrors the behavior of the -stringByAppendingPathExtension:
 * method.
 * <example>
 *   @"file.ext" produces @"file"
 *   @"/file.ext" produces @"/file"
 *   @"/file.ext/" produces @"/file" (trailing path separators are ignored)
 *   @"/file..ext" produces @"/file."
 *   @"/file." produces @"/file"
 *   @"/.ext" produces @"/.ext" (there is no file to strip from)
 *   @".ext" produces @".ext" (there is no file to strip from)
 * </example>
 */
- (NSString*) stringByDeletingPathExtension;

/**
 * Returns a string created by expanding the initial tilde ('~') and any
 * following username to be the home directory of the current user or the
 * named user.<br />
 * Returns the receiver or an immutable copy if it was not possible to
 * expand it.
 */
- (NSString*) stringByExpandingTildeInPath;

/**
 * Replaces path string by one in which path components representing symbolic
 * links have been replaced by their referents.<br />
 * If links cannot be resolved, returns an unmodified copy of the receiver.
 */
- (NSString*) stringByResolvingSymlinksInPath;

/**
 * Returns a standardised form of the receiver, with unnecessary parts
 * removed, tilde characters expanded, and symbolic links resolved
 * where possible.<br />
 * NB. Refers to the local filesystem to resolve symbolic links in
 * absolute paths, and to expand tildes ... so this can't be used for
 * general path manipulation.<br />
 * If the string is an invalid path, the unmodified receiver is returned.<br />
 * <p>
 *   Uses -stringByExpandingTildeInPath to expand tilde expressions.<br />
 *   Simplifies '//' and '/./' sequences and removes trailing '/' or '.'.<br />
 * </p>
 * <p>
 *  For absolute paths, uses -stringByResolvingSymlinksInPath to resolve
 *  any links, then gets rid of '/../' sequences and removes any '/private'
 *  prefix.
 * </p>
 */
- (NSString*) stringByStandardizingPath;


// for methods working with decomposed strings
- (int) _baseLength;

#ifndef STRICT_OPENSTEP
/**
 * Concatenates the path components in the array and returns the result.<br />
 * This method does not remove empty path components, but does recognize an
 * empty initial component as a special case meaning that the string
 * returned will begin with a slash.
 */
+ (NSString*) pathWithComponents: (NSArray*)components;

/**
 * Returns YES if the receiver represents an absolute path ...<br />
 * Returns NO otherwise.<br />
 * An absolute path in unix mode is one which begins
 * with a slash or tilde.<br />
 * In windows mode a drive specification (eg C:) followed by a slash or
 * backslash, is an absolute path, as is any path beginning with a tilde.<br />
 * In any mode a UNC path (//host/share...) is always absolute.<br />
 * In gnustep path handling mode, the rules are the same as for windows,
 * except that a path whose root is a slash denotes an absolute path
 * when running on unix and a relative path when running under windows.
 */
- (BOOL) isAbsolutePath;

/**
 * Returns the path components of the receiver separated into an array.<br />
 * If the receiver begins with a root sequence such as the path separator
 * character (or a drive specification in windows) then that is used as the
 * first element in the array.<br />
 * Empty components are removed.<br />
 * If a trailing path separator (which was not part of the root) was present,
 * it is added as the last element in the array.
 */
- (NSArray*) pathComponents;

/**
 * Returns an array of strings made by appending the values in paths
 * to the receiver.
 */
- (NSArray*) stringsByAppendingPaths: (NSArray*)paths;

+ (NSString*) localizedStringWithFormat: (NSString*)format, ...;

+ (id) stringWithString: (NSString*)aString;
+ (id) stringWithContentsOfURL: (NSURL*)url;
+ (id) stringWithUTF8String: (const char*)bytes;
- (id) initWithFormat: (NSString*)format
	       locale: (NSDictionary*)locale, ...;
- (id) initWithFormat: (NSString*)format
	       locale: (NSDictionary*)locale
	    arguments: (va_list)argList;
- (id) initWithUTF8String: (const char *)bytes;
- (id) initWithContentsOfURL: (NSURL*)url;
- (NSString*) substringWithRange: (NSRange)aRange;
- (NSComparisonResult) caseInsensitiveCompare: (NSString*)aString;
- (NSComparisonResult) compare: (NSString*)string 
		       options: (unsigned int)mask 
			 range: (NSRange)compareRange 
			locale: (NSDictionary*)dict;
- (NSComparisonResult) localizedCompare: (NSString *)string;
- (NSComparisonResult) localizedCaseInsensitiveCompare: (NSString *)string;
- (BOOL) writeToFile: (NSString*)filename
	  atomically: (BOOL)useAuxiliaryFile;
- (BOOL) writeToURL: (NSURL*)anURL atomically: (BOOL)atomically;
- (double) doubleValue;
+ (NSStringEncoding*) availableStringEncodings;
+ (NSString*) localizedNameOfStringEncoding: (NSStringEncoding)encoding;
- (void) getLineStart: (unsigned int *)startIndex
                  end: (unsigned int *)lineEndIndex
          contentsEnd: (unsigned int *)contentsEndIndex
             forRange: (NSRange)aRange;
- (NSRange) lineRangeForRange: (NSRange)aRange;
- (const char*) lossyCString;
- (NSString*) stringByAddingPercentEscapesUsingEncoding: (NSStringEncoding)e;
- (NSString*) stringByPaddingToLength: (unsigned int)newLength
			   withString: (NSString*)padString
		      startingAtIndex: (unsigned int)padIndex;
- (NSString*) stringByReplacingPercentEscapesUsingEncoding: (NSStringEncoding)e;
- (NSString*) stringByTrimmingCharactersInSet: (NSCharacterSet*)aSet;
- (const char *)UTF8String;
#endif

#ifndef NO_GNUSTEP
+ (Class) constantStringClass;
- (BOOL) boolValue;
#endif /* NO_GNUSTEP */

@end

@interface NSMutableString : NSString

// Creating Temporary Strings
+ (id) string;
+ (id) stringWithCharacters: (const unichar*)characters
		     length: (unsigned int)length;
+ (id) stringWithCString: (const char*)byteString
		  length: (unsigned int)length;
+ (id) stringWithCString: (const char*)byteString;
+ (id) stringWithFormat: (NSString*)format,...;
+ (id) stringWithContentsOfFile: (NSString*)path;
+ (NSMutableString*) stringWithCapacity: (unsigned int)capacity;

// Initializing Newly Allocated Strings
- (id) initWithCapacity: (unsigned int)capacity;

// Modify A String
- (void) appendFormat: (NSString*)format, ...;
- (void) appendString: (NSString*)aString;
- (void) deleteCharactersInRange: (NSRange)range;
- (void) insertString: (NSString*)aString atIndex: (unsigned int)loc;
- (void) replaceCharactersInRange: (NSRange)range 
		       withString: (NSString*)aString;
- (unsigned int) replaceOccurrencesOfString: (NSString*)replace
				 withString: (NSString*)by
				    options: (unsigned int)opts
				      range: (NSRange)searchRange;
- (void) setString: (NSString*)aString;

@end

/**
 * <p>The NXConstantString class is used to hold constant 8-bit character
 * string objects produced by the compiler where it sees @"..." in the
 * source.  The compiler generates the instances of this class - which
 * has three instance variables -</p>
 * <list>
 * <item>a pointer to the class (this is the sole ivar of NSObject)</item>
 * <item>a pointer to the 8-bit data</item>
 * <item>the length of the string</item>
 * </list>
 * <p>In older versions of the compiler, the isa variable is always set to
 * the NXConstantString class.  In newer versions a compiler option was
 * added for GNUstep, to permit the isa variable to be set to another
 * class, and GNUstep uses this to avoid conflicts with the default
 * implementation of NXConstantString in the ObjC runtime library (the
 * preprocessor is used to change all occurrences of NXConstantString
 * in the source code to NSConstantString).</p>
 * <p>Since GNUstep will generally use the GNUstep extension to the
 * compiler, you should never refer to the constant string class by
 * name, but should use the [NSString+constantStringClass] method to
 * get the actual class being used for constant strings.</p>
 * What follows is a dummy declaration of the class to keep the compiler
 * happy.
 */
@interface NXConstantString : NSString
{
  const char * const nxcsptr;
  const unsigned int nxcslen;
}
@end

#ifdef NeXT_RUNTIME
/** For internal use with NeXT runtime;
    needed, until Apple Radar 2870817 is fixed. */
extern struct objc_class _NSConstantStringClassReference;
#endif

#ifndef NO_GNUSTEP

@interface NSMutableString (GNUstep)
- (NSString*) immutableProxy;
@end

/**
 * Provides some additional (non-standard) utility methods.
 */
@interface NSString (GSCategories)
/**
 * Alternate way to invoke <code>stringWithFormat</code> if you have or wish
 * to build an explicit <code>va_list</code> structure.
 */
+ (id) stringWithFormat: (NSString*)format
	      arguments: (va_list)argList;

/**
 * Returns a string formed by removing the prefix string from the
 * receiver.  Raises an exception if the prefix is not present.
 */
- (NSString*) stringByDeletingPrefix: (NSString*)prefix;

/**
 * Returns a string formed by removing the suffix string from the
 * receiver.  Raises an exception if the suffix is not present.
 */
- (NSString*) stringByDeletingSuffix: (NSString*)suffix;

/**
 * Returns a string formed by removing leading white space from the
 * receiver.
 */
- (NSString*) stringByTrimmingLeadSpaces;

/**
 * Returns a string formed by removing trailing white space from the
 * receiver.
 */
- (NSString*) stringByTrimmingTailSpaces;

/**
 * Returns a string formed by removing both leading and trailing
 * white space from the receiver.
 */
- (NSString*) stringByTrimmingSpaces;

/**
 * Returns a string in which any (and all) occurrences of
 * replace in the receiver have been replaced with by.
 * Returns the receiver if replace
 * does not occur within the receiver.  NB. an empty string is
 * not considered to exist within the receiver.
 */
- (NSString*) stringByReplacingString: (NSString*)replace
			   withString: (NSString*)by;
@end


/**
 * GNUstep specific (non-standard) additions to the NSMutableString class.
 */
@interface NSMutableString (GSCategories)

/**
 * Removes the specified suffix from the string.  Raises an exception
 * if the suffix is not present.
 */
- (void) deleteSuffix: (NSString*)suffix;

/**
 * Removes the specified prefix from the string.  Raises an exception
 * if the prefix is not present.
 */
- (void) deletePrefix: (NSString*)prefix;

/**
 * Replaces all occurrences of the string replace with the string by
 * in the receiver.<br />
 * Has no effect if replace does not occur within the
 * receiver.  NB. an empty string is not considered to exist within
 * the receiver.<br />
 * Calls - replaceOccurrencesOfString:withString:options:range: passing
 * zero for the options and a range from 0 with the length of the receiver.
 */
- (void) replaceString: (NSString*)replace
	    withString: (NSString*)by;

/**
 * Removes all leading white space from the receiver.
 */
- (void) trimLeadSpaces;

/**
 * Removes all trailing white space from the receiver.
 */
- (void) trimTailSpaces;

/**
 * Removes all leading or trailing white space from the receiver.
 */
- (void) trimSpaces;
@end

#endif /* NO_GNUSTEP */

#endif /* __NSString_h_GNUSTEP_BASE_INCLUDE */
