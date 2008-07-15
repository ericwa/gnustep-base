/** Implementation of GNUSTEP string class
   Copyright (C) 1995, 1996, 1997, 1998 Free Software Foundation, Inc.

   Written by:  Andrew Kachites McCallum <mccallum@gnu.ai.mit.edu>
   Date: January 1995

   Unicode implementation by Stevo Crvenkovski <stevo@btinternet.com>
   Date: February 1997

   Optimisations by Richard Frith-Macdonald <richard@brainstorm.co.uk>
   Date: October 1998 - 2000

   This file is part of the GNUstep Base Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02111 USA.

   <title>NSString class reference</title>
   $Date$ $Revision$
*/

/* Caveats:

   Some implementations will need to be changed.
   Does not support all justification directives for `%@' in format strings
   on non-GNU-libc systems.
*/

/*
   Locales somewhat supported.
   Limited choice of default encodings.
*/

/* Needed for visiblity of fwprintf prototype.  */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include "config.h"
#include <stdio.h>
#include <string.h>
#include "GNUstepBase/preface.h"
#include "Foundation/NSAutoreleasePool.h"
#include "Foundation/NSString.h"
#include "Foundation/NSCalendarDate.h"
#include "Foundation/NSDecimal.h"
#include "Foundation/NSArray.h"
#include "Foundation/NSCharacterSet.h"
#include "Foundation/NSException.h"
#include "Foundation/NSValue.h"
#include "Foundation/NSDictionary.h"
#include "Foundation/NSFileManager.h"
#include "Foundation/NSPortCoder.h"
#include "Foundation/NSPathUtilities.h"
#include "Foundation/NSRange.h"
#include "Foundation/NSException.h"
#include "Foundation/NSData.h"
#include "Foundation/NSBundle.h"
#include "Foundation/NSURL.h"
#include "Foundation/NSMapTable.h"
#include "Foundation/NSLock.h"
#include "Foundation/NSNotification.h"
#include "Foundation/NSUserDefaults.h"
#include "Foundation/FoundationErrors.h"
#include "Foundation/NSDebug.h"
// For private method _decodePropertyListForKey:
#include "Foundation/NSKeyedArchiver.h"
#include "GNUstepBase/GSMime.h"
#include "GSPrivate.h"
#ifdef HAVE_LIMITS_H
#include <limits.h>
#endif
#ifdef HAVE_STDLIB_H
#include <stdlib.h>
#endif
#include <sys/stat.h>
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#include <sys/types.h>
#include <fcntl.h>
#include <stdio.h>
#include <wchar.h>

#include "GNUstepBase/Unicode.h"

#include "GSPrivate.h"

extern BOOL GSScanDouble(unichar*, unsigned, double*);

@class	GSString;
@class	GSMutableString;
@class	GSPlaceholderString;
@interface GSPlaceholderString : NSObject	// Help the compiler
@end
@class	GSMutableArray;
@class	GSMutableDictionary;
@class	NSImmutableString;
@interface NSImmutableString : NSObject	// Help the compiler
@end
@class	GSImmutableString;
@interface GSImmutableString : NSObject	// Help the compiler
@end

/*
 * Cache classes and method implementations for speed.
 */
static Class	NSDataClass;
static Class	NSStringClass;
static Class	NSMutableStringClass;

static Class	GSStringClass;
static Class	GSMutableStringClass;
static Class	GSPlaceholderStringClass;

static GSPlaceholderString	*defaultPlaceholderString;
static NSMapTable		*placeholderMap;
static NSLock			*placeholderLock;

static SEL	cMemberSel = 0;

#define	IMMUTABLE(S)	AUTORELEASE([(S) copyWithZone: NSDefaultMallocZone()])

#define IS_BIT_SET(a,i) ((((a) & (1<<(i)))) > 0)

static unsigned const char *whitespaceBitmapRep = NULL;
#define GS_IS_WHITESPACE(X) IS_BIT_SET(whitespaceBitmapRep[(X)/8], (X) % 8)

static void setupWhitespace(void)
{
  if (whitespaceBitmapRep == NULL)
    {
      NSCharacterSet *whitespace;
      NSData *bitmap;

/*
  We can not use whitespaceAndNewlineCharacterSet here as this would lead
  to a recursion, as this also reads in a property list.
      whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
*/
      whitespace = [NSCharacterSet characterSetWithCharactersInString:
				    @" \t\r\n\f\b"];

      bitmap = RETAIN([whitespace bitmapRepresentation]);
      whitespaceBitmapRep = [bitmap bytes];
    }
}

/*
 *	Include sequence handling code with instructions to generate search
 *	and compare functions for NSString objects.
 */
#define	GSEQ_STRCOMP	strCompNsNs
#define	GSEQ_STRRANGE	strRangeNsNs
#define	GSEQ_O	GSEQ_NS
#define	GSEQ_S	GSEQ_NS
#include "GSeq.h"

/*
 * The path handling mode.
 */
static enum {
  PH_DO_THE_RIGHT_THING,
  PH_UNIX,
  PH_WINDOWS
} pathHandling = PH_DO_THE_RIGHT_THING;

/**
 * This function is intended to be called at startup (before anything else
 * which needs to use paths, such as reading config files and user defaults)
 * to allow a program to control the style of path handling required.<br />
 * Almost all programs should avoid using this.<br />
 * Changing the path handling mode is not thread-safe.<br />
 * If mode is "windows" this sets path handling to be windows specific,<br />
 * If mode is "unix" it sets path handling to be unix specific,<br />
 * Any other none-null string sets do-the-right-thing mode.<br />
 * The function returns a C String describing the old mode.
 */
const char*
GSPathHandling(const char *mode)
{
  int	old = pathHandling;

  if (mode != 0)
    {
      if (strcasecmp(mode, "windows") == 0)
	{
	  pathHandling = PH_WINDOWS;
	}
      else if (strcasecmp(mode, "unix") == 0)
	{
	  pathHandling = PH_UNIX;
	}
      else
	{
	  pathHandling = PH_DO_THE_RIGHT_THING;
	}
    }
  switch (old)
    {
      case PH_WINDOWS:		return "windows";
      case PH_UNIX:		return "unix";
      default:			return "right";
    }
}

#define	GSPathHandlingRight()	\
  ((pathHandling == PH_DO_THE_RIGHT_THING) ? YES : NO)
#define	GSPathHandlingUnix()	\
  ((pathHandling == PH_UNIX) ? YES : NO)
#define	GSPathHandlingWindows()	\
  ((pathHandling == PH_WINDOWS) ? YES : NO)

/*
 * The pathSeps character set is used for parsing paths ... it *must*
 * contain the '/' character, which is the internal path separator,
 * and *may* contain additiona system specific separators.
 *
 * We can't have a 'pathSeps' variable initialized in the +initialize
 * method because that would cause recursion.
 */
static NSCharacterSet*
pathSeps(void)
{
  static NSCharacterSet	*wPathSeps = nil;
  static NSCharacterSet	*uPathSeps = nil;
  static NSCharacterSet	*rPathSeps = nil;
  if (GSPathHandlingRight())
    {
      if (rPathSeps == nil)
	{
	  [placeholderLock lock];
	  if (rPathSeps == nil)
	    {
	      rPathSeps
		= [NSCharacterSet characterSetWithCharactersInString: @"/\\"];
	      IF_NO_GC(RETAIN(rPathSeps));
	    }
	  [placeholderLock unlock];
	}
      return rPathSeps;
    }
  if (GSPathHandlingUnix())
    {
      if (uPathSeps == nil)
	{
	  [placeholderLock lock];
	  if (uPathSeps == nil)
	    {
	      uPathSeps
		= [NSCharacterSet characterSetWithCharactersInString: @"/"];
	      IF_NO_GC(RETAIN(uPathSeps));
	    }
	  [placeholderLock unlock];
	}
      return uPathSeps;
    }
  if (GSPathHandlingWindows())
    {
      if (wPathSeps == nil)
	{
	  [placeholderLock lock];
	  if (wPathSeps == nil)
	    {
	      wPathSeps
		= [NSCharacterSet characterSetWithCharactersInString: @"\\"];
	      IF_NO_GC(RETAIN(wPathSeps));
	    }
	  [placeholderLock unlock];
	}
      return wPathSeps;
    }
  pathHandling = PH_DO_THE_RIGHT_THING;
  return pathSeps();
}

inline static BOOL
pathSepMember(unichar c)
{
  if (c == (unichar)'/')
    {
      if (GSPathHandlingWindows() == NO)
	{
	  return YES;
	}
    }
  else if (c == (unichar)'\\')
    {
      if (GSPathHandlingUnix() == NO)
	{
	  return YES;
	}
    }
  return NO;
}

/*
 * For cross-platform portability we always use slash as the separator
 * when building paths ... unless specific windows path handling is
 * required.
 */
inline static unichar
pathSepChar()
{
  if (GSPathHandlingWindows() == NO)
    {
      return '/';
    }
  return '\\';
}

/*
 * For cross-platform portability we always use slash as the separator
 * when building paths ... unless specific windows path handling is
 * required.
 */
inline static NSString*
pathSepString()
{
  if (GSPathHandlingWindows() == NO)
    {
      return @"/";
    }
  return @"\\";
}

/*
 * Find end of 'root' sequence in a string.  Characters before this
 * point in the string cannot be split into path components/extensions.
 * Possible roots are -
 *
 * '/'			absolute root on unix
 * ''			if entire path is empty string
 * 'C:/'		absolute root for a drive on windows
 * 'C:'			if entire path is 'C:' or 'C:relativepath'
 * '//host/share/'	absolute root for a host and share on windows
 * '//host/share'	if entire path is '//host/share'
 * '~/'			home directory for user
 * '~'			if entire path is '~'
 * '~username/'		home directory for user
 * '~username'		if entire path is '~username'
 *
 * Most roots are terminated in '/' (or '\') unless the root is the entire
 * path.  The exception is for windows drive-relative paths, where the root
 * may be a drive letter followed by a colon, but there may still be path
 * components after the root with no path separator.
 *
 * The presence of any non-empty root indicates an absolute path except -
 * 1. A windows drive-relative path is not absolute unless the root
 * ends with a path separator, since the path part on the drive is relative.
 * 2. On windows, a root consisting of a single path separator indicates
 * a drive-relative path with no drive ... so the path is relative.
 */
static unsigned rootOf(NSString *s, unsigned l)
{
  unsigned	root = 0;

  if (l > 0)
    {
      unichar	c = [s characterAtIndex: 0];

      if (c == '~')
	{
	  NSRange	range = NSMakeRange(1, l-1);

	  range = [s rangeOfCharacterFromSet: pathSeps()
				     options: NSLiteralSearch
				       range: range];
	  if (range.length == 0)
	    {
	      root = l;			// ~ or ~name
	    }
	  else
	    {
	      root = NSMaxRange(range);	// ~/... or ~name/...
	    }
	}
      else
	{
	  if (pathSepMember(c))
	    {
	      root++;
	    }
	  if (GSPathHandlingUnix() == NO)
	    {
	      if (root == 0 && l > 1
		&& ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'))
		&& [s characterAtIndex: 1] == ':')
		{
		  // Got a drive relative path ... see if it's absolute.
		  root = 2;
		  if (l > 2 && pathSepMember([s characterAtIndex: 2]))
		    {
		      root++;
		    }
		}
	      else if (root == 1
		&& l > 4 && pathSepMember([s characterAtIndex: 1]))
		{
		  NSRange	range = NSMakeRange(2, l-2);

		  range = [s rangeOfCharacterFromSet: pathSeps()
					     options: NSLiteralSearch
					       range: range];
		  if (range.length > 0 && range.location > 2)
		    {
		      unsigned pos = NSMaxRange(range);

		      // Found end of UNC host perhaps ... look for share
		      if (pos < l)
			{
			  range = NSMakeRange(pos, l - pos);
			  range = [s rangeOfCharacterFromSet: pathSeps()
						     options: NSLiteralSearch
						       range: range];
			  if (range.length > 0)
			    {
			      /*
			       * Found another slash ...  but if it comes
			       * immediately after the last one this can't
			       * be a UNC path as it's '//host//' rather
			       * than '//host/share'
			       */
			      if (range.location > pos)
				{
				  root = NSMaxRange(range);
				}
			    }
			  else
			    {
			      root = l;
			    }
			}
		    }
		}
	    }
	}
    }
  return root;
}


/* Convert a high-low surrogate pair into Unicode scalar code-point */
static inline uint32_t
surrogatePairValue(unichar high, unichar low)
{
  return ((high - (unichar)0xD800) * (unichar)400)
    + ((low - (unichar)0xDC00) + (unichar)10000);
}

@implementation NSString
//  NSString itself is an abstract class which provides factory
//  methods to generate objects of unspecified subclasses.

static NSStringEncoding _DefaultStringEncoding;
static BOOL		_ByteEncodingOk;
static const unichar byteOrderMark = 0xFEFF;
static const unichar byteOrderMarkSwapped = 0xFFFE;

#ifdef HAVE_REGISTER_PRINTF_FUNCTION
#include <stdio.h>
#include <printf.h>
#include <stdarg.h>

/* <sattler@volker.cs.Uni-Magdeburg.DE>, with libc-5.3.9 thinks this
   flag PRINTF_ATSIGN_VA_LIST should be 0, but for me, with libc-5.0.9,
   it crashes.  -mccallum

   Apparently GNU libc 2.xx needs this to be 0 also, along with Linux
   libc versions 5.2.xx and higher (including libc6, which is just GNU
   libc). -chung */
#define PRINTF_ATSIGN_VA_LIST			\
       (defined(_LINUX_C_LIB_VERSION_MINOR)	\
	&& _LINUX_C_LIB_VERSION_MAJOR <= 5	\
	&& _LINUX_C_LIB_VERSION_MINOR < 2)

#if ! PRINTF_ATSIGN_VA_LIST
static int
arginfo_func (const struct printf_info *info, size_t n, int *argtypes)
{
  *argtypes = PA_POINTER;
  return 1;
}
#endif /* !PRINTF_ATSIGN_VA_LIST */

static int
handle_printf_atsign (FILE *stream,
		      const struct printf_info *info,
#if PRINTF_ATSIGN_VA_LIST
		      va_list *ap_pointer)
#elif defined(_LINUX_C_LIB_VERSION_MAJOR)       \
     && _LINUX_C_LIB_VERSION_MAJOR < 6
                      const void **const args)
#else /* GNU libc needs the following. */
                      const void *const *args)
#endif
{
#if ! PRINTF_ATSIGN_VA_LIST
  const void *ptr = *args;
#endif
  id string_object;
  int len;

  /* xxx This implementation may not pay pay attention to as much
     of printf_info as it should. */

#if PRINTF_ATSIGN_VA_LIST
  string_object = va_arg (*ap_pointer, id);
#else
  string_object = *((id*) ptr);
#endif
  string_object = [string_object description];

#if HAVE_WIDE_PRINTF_FUNCTION
  if (info->wide)
    {
      if (sizeof(wchar_t) == 4)
        {
	  unsigned	length = [string_object length];
	  wchar_t	buf[length + 1];
	  unsigned	i;

	  for (i = 0; i < length; i++)
	    {
	      buf[i] = [string_object characterAtIndex: i];
	    }
	  buf[i] = 0;
          len = fwprintf(stream, L"%*ls",
	    (info->left ? - info->width : info->width), buf);
        }
      else
        {
          len = fwprintf(stream, L"%*ls",
	    (info->left ? - info->width : info->width),
	    [string_object cStringUsingEncoding: NSUnicodeStringEncoding]);
	}
    }
  else
#endif	/* HAVE_WIDE_PRINTF_FUNCTION */
    {
      len = fprintf(stream, "%*s",
	(info->left ? - info->width : info->width),
	[string_object lossyCString]);
    }
  return len;
}
#endif /* HAVE_REGISTER_PRINTF_FUNCTION */

+ (void) initialize
{
  /*
   * Flag required as we call this method explicitly from GSBuildStrings()
   * to ensure that NSString is initialised properly.
   */
  static BOOL	beenHere = NO;

  if (self == [NSString class] && beenHere == NO)
    {
      beenHere = YES;
      cMemberSel = @selector(characterIsMember:);
      caiSel = @selector(characterAtIndex:);
      gcrSel = @selector(getCharacters:range:);
      ranSel = @selector(rangeOfComposedCharacterSequenceAtIndex:);

      _DefaultStringEncoding = GSPrivateDefaultCStringEncoding();
      _ByteEncodingOk = GSPrivateIsByteEncoding(_DefaultStringEncoding);

      NSStringClass = self;
      [self setVersion: 1];
      NSMutableStringClass = [NSMutableString class];
      NSDataClass = [NSData class];
      GSPlaceholderStringClass = [GSPlaceholderString class];
      GSStringClass = [GSString class];
      GSMutableStringClass = [GSMutableString class];

      /*
       * Set up infrastructure for placeholder strings.
       */
      defaultPlaceholderString = (GSPlaceholderString*)
	NSAllocateObject(GSPlaceholderStringClass, 0, NSDefaultMallocZone());
      placeholderMap = NSCreateMapTable(NSNonOwnedPointerMapKeyCallBacks,
	NSNonRetainedObjectMapValueCallBacks, 0);
      placeholderLock = [NSLock new];

#ifdef HAVE_REGISTER_PRINTF_FUNCTION
      if (register_printf_function ('@',
				    handle_printf_atsign,
#if PRINTF_ATSIGN_VA_LIST
				    0))
#else
	                            arginfo_func))
#endif
	[NSException raise: NSGenericException
		     format: @"register printf handling of %%@ failed"];
#endif /* HAVE_REGISTER_PRINTF_FUNCTION */
    }
}

+ (id) allocWithZone: (NSZone*)z
{
  if (self == NSStringClass)
    {
      /*
       * For a constant string, we return a placeholder object that can
       * be converted to a real object when its initialisation method
       * is called.
       */
      if (z == NSDefaultMallocZone() || z == 0)
	{
	  /*
	   * As a special case, we can return a placeholder for a string
	   * in the default zone extremely efficiently.
	   */
	  return defaultPlaceholderString;
	}
      else
	{
	  id	obj;

	  /*
	   * For anything other than the default zone, we need to
	   * locate the correct placeholder in the (lock protected)
	   * table of placeholders.
	   */
	  [placeholderLock lock];
	  obj = (id)NSMapGet(placeholderMap, (void*)z);
	  if (obj == nil)
	    {
	      /*
	       * There is no placeholder object for this zone, so we
	       * create a new one and use that.
	       */
	      obj = (id)NSAllocateObject(GSPlaceholderStringClass, 0, z);
	      NSMapInsert(placeholderMap, (void*)z, (void*)obj);
	    }
	  [placeholderLock unlock];
	  return obj;
	}
    }
  else if (GSObjCIsKindOf(self, GSStringClass) == YES)
    {
      [NSException raise: NSInternalInconsistencyException
		  format: @"Called +allocWithZone: on private string class"];
      return nil;	/* NOT REACHED */
    }
  else
    {
      /*
       * For user provided strings, we simply allocate an object of
       * the given class.
       */
      return NSAllocateObject (self, 0, z);
    }
}

/**
 * Return the class used to store constant strings (those ascii strings
 * placed in the source code using the @"this is a string" syntax).<br />
 * Use this method to obtain the constant string class rather than
 * using the obsolete name <em>NXConstantString</em> in your code ...
 * with more recent compiler versions the name of this class is variable
 * (and will automatically be changed by GNUstep to avoid conflicts
 * with the default implementation in the Objective-C runtime library).
 */
+ (Class) constantStringClass
{
  return [NXConstantString class];
}

/**
 * Create an empty string.
 */
+ (id) string
{
  return AUTORELEASE([[self allocWithZone: NSDefaultMallocZone()] init]);
}

/**
 * Create a copy of aString.
 */
+ (id) stringWithString: (NSString*)aString
{
  NSString	*obj;

  obj = [self allocWithZone: NSDefaultMallocZone()];
  obj = [obj initWithString: aString];
  return AUTORELEASE(obj);
}

/**
 * Create a string of unicode characters.
 */
+ (id) stringWithCharacters: (const unichar*)chars
		     length: (unsigned int)length
{
  NSString	*obj;

  obj = [self allocWithZone: NSDefaultMallocZone()];
  obj = [obj initWithCharacters: chars length: length];
  return AUTORELEASE(obj);
}

/**
 * Create a string based on the given C (char[]) string, which should be
 * null-terminated and encoded in the default C string encoding.  (Characters
 * will be converted to unicode representation internally.)
 */
+ (id) stringWithCString: (const char*)byteString
{
  NSString	*obj;
  unsigned	length = byteString ? strlen(byteString) : 0;

  obj = [self allocWithZone: NSDefaultMallocZone()];
  obj = [obj initWithCString: byteString length: length];
  return AUTORELEASE(obj);
}

/**
 * Create a string based on the given C (char[]) string, which should be
 * null-terminated and encoded in the specified C string encoding.
 * Characters may be converted to unicode representation internally.
 */
+ (id) stringWithCString: (const char*)byteString
		encoding: (NSStringEncoding)encoding
{
  NSString	*obj;

  obj = [self allocWithZone: NSDefaultMallocZone()];
  obj = [obj initWithCString: byteString encoding: encoding];
  return AUTORELEASE(obj);
}

/**
 * Create a string based on the given C (char[]) string, which may contain
 * null bytes and should be encoded in the default C string encoding.
 * (Characters will be converted to unicode representation internally.)
 */
+ (id) stringWithCString: (const char*)byteString
		  length: (unsigned int)length
{
  NSString	*obj;

  obj = [self allocWithZone: NSDefaultMallocZone()];
  obj = [obj initWithCString: byteString length: length];
  return AUTORELEASE(obj);
}

/**
 * Create a string based on the given UTF-8 string, null-terminated.
 */
+ (id) stringWithUTF8String: (const char *)bytes
{
  NSString	*obj;

  obj = [self allocWithZone: NSDefaultMallocZone()];
  obj = [obj initWithUTF8String: bytes];
  return AUTORELEASE(obj);
}

/**
 * Load contents of file at path into a new string.  Will interpret file as
 * containing direct unicode if it begins with the unicode byte order mark,
 * else converts to unicode using default C string encoding.
 */
+ (id) stringWithContentsOfFile: (NSString *)path
{
  NSString	*obj;

  obj = [self allocWithZone: NSDefaultMallocZone()];
  obj = [obj initWithContentsOfFile: path];
  return AUTORELEASE(obj);
}

/**
 * Load contents of file at path into a new string using the
 * -initWithContentsOfFile:usedEncoding:error: method.
 */
+ (id) stringWithContentsOfFile: (NSString *)path
                   usedEncoding: (NSStringEncoding*)enc
                          error: (NSError**)error
{
  NSString	*obj;

  obj = [self allocWithZone: NSDefaultMallocZone()];
  obj = [obj initWithContentsOfFile: path usedEncoding: enc error: error];
  return AUTORELEASE(obj);
}

/**
 * Load contents of given URL into a new string.  Will interpret contents as
 * containing direct unicode if it begins with the unicode byte order mark,
 * else converts to unicode using default C string encoding.
 */
+ (id) stringWithContentsOfURL: (NSURL *)url
{
  NSString	*obj;

  obj = [self allocWithZone: NSDefaultMallocZone()];
  obj = [obj initWithContentsOfURL: url];
  return AUTORELEASE(obj);
}

/**
 * Creates a new string using C printf-style formatting.  First argument should
 * be a constant format string, like '<code>@"float val = %f"</code>', remaining
 * arguments should be the variables to print the values of, comma-separated.
 */
+ (id) stringWithFormat: (NSString*)format,...
{
  va_list ap;
  id ret;

  va_start(ap, format);
  if (format == nil)
    ret = nil;
  else
    ret = AUTORELEASE([[self allocWithZone: NSDefaultMallocZone()]
      initWithFormat: format arguments: ap]);
  va_end(ap);
  return ret;
}


/**
 * <p>In MacOS-X class clusters do not have designated initialisers,
 * and there is a general rule that -init is treated as the designated
 * initialiser of the class cluster, but that other intitialisers
 * may not work as expected and would need to be individually overridden
 * in any subclass.
 * </p>
 * <p>GNUstep tries to make it easier to subclass a class cluster,
 * by making class clusters follow the same convention as normal
 * classes, so the designated initialiser is the <em>richest</em>
 * initialiser.  This means that all other initialisers call the
 * documented designated initialiser (which calls -init only for
 * MacOS-X compatibility), and anyone writing a subclass only needs
 * to override that one initialiser in order to have all the other
 * ones work.
 * </p>
 * <p>For MacOS-X compatibility, you may also need to override various
 * other initialisers.  Exactly which ones, you will need to determine
 * by trial on a MacOS-X system ... and may vary between releases of
 * MacOS-X.  So to be safe, on MacOS-X you probably need to re-implement
 * <em>all</em> the class cluster initialisers you might use in conjunction
 * with your subclass.
 * </p>
 * <p>NB. The GNUstep designated initialiser for the NSString class cluster
 * has changed to -initWithBytesNoCopy:length:encoding:freeWhenDone:
 * from -initWithCharactersNoCopy:length:freeWhenDone: and older code
 * subclassing NSString will need to be updated.
 * </p>
 */
- (id) init
{
  self = [super init];
  return self;
}

/**
 * Initialises the receiver with a copy of the supplied length of bytes,
 * using the specified encoding.<br />
 * For NSUnicodeStringEncoding and NSUTF8String encoding, a Byte Order
 * Marker (if present at the start of the data) is removed automatically.<br />
 * If the data can not be interpreted using the encoding, the receiver
 * is released and nil is returned.
 */
- (id) initWithBytes: (const void*)bytes
	      length: (unsigned int)length
	    encoding: (NSStringEncoding)encoding
{
  if (length == 0)
    {
      return [self initWithBytesNoCopy: (void *)0
				length: 0
			      encoding: encoding
			  freeWhenDone: NO];
    }
  else
    {
      void	*buf = NSZoneMalloc(GSObjCZone(self), length);

      memcpy(buf, bytes, length);
      return [self initWithBytesNoCopy: buf
				length: length
			      encoding: encoding
			  freeWhenDone: YES];
    }
}

/** <init /> <override-subclass />
 * Initialises the receiver with the supplied length of bytes, using the
 * specified encoding.<br />
 * For NSUnicodeStringEncoding and NSUTF8String encoding, a Byte Order
 * Marker (if present at the start of the data) is removed automatically.<br />
 * If the data is not in a format which can be used internally unmodified,
 * it is copied, otherwise it is used as is.  If the data is not copied
 * the flag determines whether the string will free it when it is no longer
 * needed.<br />
 * If the data can not be interpreted using the encoding, the receiver
 * is released and nil is returned.
 * <p>Note, this is the most basic initialiser for strings.
 * In the GNUstep implementation, your subclasses may override
 * this initialiser in order to have all other functionality.</p>
 */
- (id) initWithBytesNoCopy: (void*)bytes
		    length: (unsigned int)length
		  encoding: (NSStringEncoding)encoding
	      freeWhenDone: (BOOL)flag
{
  self = [self init];
  return self;
}

/**
 * <p>Initialize with given unicode chars up to length, regardless of presence
 *  of null bytes.  Does not copy the string.  If flag, frees its storage when
 *  this instance is deallocated.</p>
 */
- (id) initWithCharactersNoCopy: (unichar*)chars
			 length: (unsigned int)length
		   freeWhenDone: (BOOL)flag
{
  return [self initWithBytesNoCopy: chars
			    length: length * sizeof(unichar)
			  encoding: NSUnicodeStringEncoding
		      freeWhenDone: flag];
}

/**
 * <p>Initialize with given unicode chars up to length, regardless of presence
 *  of null bytes.  Copies the string and frees copy when deallocated.</p>
 */
- (id) initWithCharacters: (const unichar*)chars
		   length: (unsigned int)length
{
  return [self initWithBytes: chars
		      length: length * sizeof(unichar)
		    encoding: NSUnicodeStringEncoding];
}

/**
 * <p>Initialize with given C string byteString up to length, regardless of
 *  presence of null bytes.  Characters converted to unicode based on the
 *  default C encoding.  Does not copy the string.  If flag, frees its storage
 *  when this instance is deallocated.</p>
 */
- (id) initWithCStringNoCopy: (char*)byteString
		      length: (unsigned int)length
		freeWhenDone: (BOOL)flag
{
  return [self initWithBytesNoCopy: byteString
			    length: length
			  encoding: _DefaultStringEncoding
		      freeWhenDone: flag];
}

/**
 * <p>Initialize with given C string byteString up to first nul byte.
 * Characters converted to unicode based on the specified C encoding.
 * Copies the string.</p>
 */
- (id) initWithCString: (const char*)byteString
	      encoding: (NSStringEncoding)encoding
{
  return [self initWithBytes: byteString
		      length: strlen(byteString)
		    encoding: encoding];
}

/**
 * <p>Initialize with given C string byteString up to length, regardless of
 *  presence of null bytes.  Characters converted to unicode based on the
 *  default C encoding.  Copies the string.</p>
 */
- (id) initWithCString: (const char*)byteString  length: (unsigned int)length
{
  return [self initWithBytes: byteString
		      length: length
		    encoding: _DefaultStringEncoding];
}

/**
 * <p>Initialize with given C string byteString, which should be
 * null-terminated.  Characters are converted to unicode based on the default
 * C encoding.  Copies the string.</p>
 */
- (id) initWithCString: (const char*)byteString
{
  return [self initWithBytes: byteString
		      length: (byteString ? strlen(byteString) : 0)
		    encoding: _DefaultStringEncoding];
}

/**
 * Initialize to be a copy of the given string.
 */
- (id) initWithString: (NSString*)string
{
  unsigned	length = [string length];

  if (length > 0)
    {
      unichar	*s = NSZoneMalloc(GSObjCZone(self), sizeof(unichar)*length);

      [string getCharacters: s range: ((NSRange){0, length})];
      self = [self initWithCharactersNoCopy: s
				     length: length
			       freeWhenDone: YES];
    }
  else
    {
      self = [self initWithCharactersNoCopy: (unichar*)0
				     length: 0
			       freeWhenDone: NO];
    }
  return self;
}

/**
 * Initialize based on given null-terminated UTF-8 string bytes.
 */
- (id) initWithUTF8String: (const char *)bytes
{
  return [self initWithBytes: bytes
		      length: (bytes ? strlen(bytes) : 0)
		    encoding: NSUTF8StringEncoding];
}

/**
 * Invokes -initWithFormat:locale:arguments: with a nil locale.
 */
- (id) initWithFormat: (NSString*)format,...
{
  va_list ap;
  va_start(ap, format);
  self = [self initWithFormat: format locale: nil arguments: ap];
  va_end(ap);
  return self;
}

/**
 * Invokes -initWithFormat:locale:arguments:
 */
- (id) initWithFormat: (NSString*)format
               locale: (NSDictionary*)locale, ...
{
  va_list ap;
  va_start(ap, locale);
  return [self initWithFormat: format locale: locale arguments: ap];
  va_end(ap);
  return self;
}

/**
 * Invokes -initWithFormat:locale:arguments: with a nil locale.
 */
- (id) initWithFormat: (NSString*)format
            arguments: (va_list)argList
{
  return [self initWithFormat: format locale: nil arguments: argList];
}

/**
 * Initialises the string using the specified format and locale
 * to format the following arguments.
 */
- (id) initWithFormat: (NSString*)format
               locale: (NSDictionary*)locale
            arguments: (va_list)argList
{
  unsigned char	buf[2048];
  GSStr_t	f;
  unichar	fbuf[1024];
  unichar	*fmt = fbuf;
  size_t	len;

  /*
   * First we provide an array of unichar characters containing the
   * format string.  For performance reasons we try to use an on-stack
   * buffer if the format string is small enough ... it almost always
   * will be.
   */
  len = [format length];
  if (len >= 1024)
    {
      fmt = objc_malloc((len+1)*sizeof(unichar));
    }
  [format getCharacters: fmt range: ((NSRange){0, len})];
  fmt[len] = '\0';

  /*
   * Now set up 'f' as a GSMutableString object whose initial buffer is
   * allocated on the stack.  The GSPrivateFormat function can write into it.
   */
  f.isa = GSMutableStringClass;
  f._zone = NSDefaultMallocZone();
  f._contents.c = buf;
  f._capacity = sizeof(buf);
  f._count = 0;
#if HAVE_WIDE_PRINTF_FUNCTION
  f._flags.wide = 0;
#endif	/* HAVE_WIDE_PRINTF_FUNCTION */
  f._flags.free = 0;
  GSPrivateFormat(&f, fmt, argList, locale);
  GSPrivateStrExternalize(&f);
  if (fmt != fbuf)
    {
      objc_free(fmt);
    }

  /*
   * Don't use noCopy because f._contents.u may be memory on the stack,
   * and even if it wasn't f._capacity may be greater than f._count so
   * we could be wasting quite a bit of space.  Better to accept a
   * performance hit due to copying data (and allocating/deallocating
   * the temporary buffer) for large strings.  For most strings, the
   * on-stack memory will have been used, so we will get better performance.
   */
#if HAVE_WIDE_PRINTF_FUNCTION
  if (f._flags.wide == 1)
    {
      self = [self initWithCharacters: f._contents.u length: f._count];
    }
  else
#endif	/* HAVE_WIDE_PRINTF_FUNCTION */
    {
      self = [self initWithCString: (char*)f._contents.c length: f._count];
    }

  /*
   * If the string had to grow beyond the initial buffer size, we must
   * release any allocated memory.
   */
  if (f._flags.free == 1)
    {
      NSZoneFree(f._zone, f._contents.c);
    }
  return self;
}

/**
 * Initialises the receiver with the supplied data, using the
 * specified encoding.<br />
 * For NSUnicodeStringEncoding and NSUTF8String encoding, a Byte Order
 * Marker (if present at the start of the data) is removed automatically.<br />
 * If the data can not be interpreted using the encoding, the receiver
 * is released and nil is returned.
 */
- (id) initWithData: (NSData*)data
	   encoding: (NSStringEncoding)encoding
{
  return [self initWithBytes: [data bytes]
		      length: [data length]
		    encoding: encoding];
}

/**
 * <p>Initialises the receiver with the contents of the file at path.
 * </p>
 * <p>Invokes [NSData-initWithContentsOfFile:] to read the file, then
 * examines the data to infer its encoding type, and converts the
 * data to a string using -initWithData:encoding:
 * </p>
 * <p>The encoding to use is determined as follows ... if the data begins
 * with the 16-bit unicode Byte Order Marker, then it is assumed to be
 * unicode data in the appropriate ordering and converted as such.<br />
 * If it begins with a UTF8 representation of the BOM, the UTF8 encoding
 * is used.<br />
 * Otherwise, the default C String encoding is used.
 * </p>
 * <p>Releases the receiver and returns nil if the file could not be read
 * and converted to a string.
 * </p>
 */
- (id) initWithContentsOfFile: (NSString*)path
{
  NSStringEncoding	enc = _DefaultStringEncoding;
  NSData		*d;
  unsigned int		len;
  const unsigned char	*data_bytes;

  d = [[NSDataClass alloc] initWithContentsOfFile: path];
  if (d == nil)
    {
      RELEASE(self);
      return nil;
    }
  len = [d length];
  if (len == 0)
    {
      RELEASE(d);
      RELEASE(self);
      return @"";
    }
  data_bytes = [d bytes];
  if ((data_bytes != NULL) && (len >= 2))
    {
      const unichar *data_ucs2chars = (const unichar *) data_bytes;
      if ((data_ucs2chars[0] == byteOrderMark)
	|| (data_ucs2chars[0] == byteOrderMarkSwapped))
	{
	  /* somebody set up us the BOM! */
	  enc = NSUnicodeStringEncoding;
	}
      else if (len >= 3
	&& data_bytes[0] == 0xEF
	&& data_bytes[1] == 0xBB
	&& data_bytes[2] == 0xBF)
	{
	  enc = NSUTF8StringEncoding;
	}
    }
  self = [self initWithData: d encoding: enc];
  RELEASE(d);
  if (self == nil)
    {
      NSWarnMLog(@"Contents of file '%@' are not string data", path);
    }
  return self;
}

/**
 * <p>Initialises the receiver with the contents of the file at path.
 * </p>
 * <p>Invokes [NSData-initWithContentsOfFile:] to read the file, then
 * examines the data to infer its encoding type, and converts the
 * data to a string using -initWithData:encoding:
 * </p>
 * <p>The encoding to use is determined as follows ... if the data begins
 * with the 16-bit unicode Byte Order Marker, then it is assumed to be
 * unicode data in the appropriate ordering and converted as such.<br />
 * If it begins with a UTF8 representation of the BOM, the UTF8 encoding
 * is used.<br />
 * Otherwise, the default C String encoding is used.
 * </p>
 * <p>Releases the receiver and returns nil if the file could not be read
 * and converted to a string.
 * </p>
 */
- (id) initWithContentsOfFile: (NSString*)path
                 usedEncoding: (NSStringEncoding*)enc
                        error: (NSError**)error
{
  NSData		*d;
  unsigned int		len;
  const unsigned char	*data_bytes;

  d = [[NSDataClass alloc] initWithContentsOfFile: path];
  if (d == nil)
    {
      RELEASE(self);
      return nil;
    }
  *enc = _DefaultStringEncoding;
  len = [d length];
  if (len == 0)
    {
      RELEASE(d);
      RELEASE(self);
      return @"";
    }
  data_bytes = [d bytes];
  if ((data_bytes != NULL) && (len >= 2))
    {
      const unichar *data_ucs2chars = (const unichar *) data_bytes;
      if ((data_ucs2chars[0] == byteOrderMark)
	|| (data_ucs2chars[0] == byteOrderMarkSwapped))
	{
	  /* somebody set up us the BOM! */
	  *enc = NSUnicodeStringEncoding;
	}
      else if (len >= 3
	&& data_bytes[0] == 0xEF
	&& data_bytes[1] == 0xBB
	&& data_bytes[2] == 0xBF)
	{
	  *enc = NSUTF8StringEncoding;
	}
    }
  self = [self initWithData: d encoding: *enc];
  RELEASE(d);
  if (self == nil)
    {
      if (error != 0)
        {
          *error = [NSError errorWithDomain: NSCocoaErrorDomain
                                       code: NSFileReadCorruptFileError
                                   userInfo: nil];
        }
    }
  return self;
}

/**
 * <p>Initialises the receiver with the contents of the given URL.
 * </p>
 * <p>Invokes [NSData+dataWithContentsOfURL:] to read the contents, then
 * examines the data to infer its encoding type, and converts the
 * data to a string using -initWithData:encoding:
 * </p>
 * <p>The encoding to use is determined as follows ... if the data begins
 * with the 16-bit unicode Byte Order Marker, then it is assumed to be
 * unicode data in the appropriate ordering and converted as such.<br />
 * If it begins with a UTF8 representation of the BOM, the UTF8 encoding
 * is used.<br />
 * Otherwise, the default C String encoding is used.
 * </p>
 * <p>Releases the receiver and returns nil if the URL contents could not be
 * read and converted to a string.
 * </p>
 */
- (id) initWithContentsOfURL: (NSURL*)url
{
  NSStringEncoding	enc = _DefaultStringEncoding;
  NSData		*d = [NSDataClass dataWithContentsOfURL: url];
  unsigned int		len = [d length];
  const unsigned char	*data_bytes;

  if (d == nil)
    {
      NSWarnMLog(@"Contents of URL '%@' are not readable", url);
      RELEASE(self);
      return nil;
    }
  if (len == 0)
    {
      RELEASE(self);
      return @"";
    }
  data_bytes = [d bytes];
  if ((data_bytes != NULL) && (len >= 2))
    {
      const unichar *data_ucs2chars = (const unichar *) data_bytes;
      if ((data_ucs2chars[0] == byteOrderMark)
	|| (data_ucs2chars[0] == byteOrderMarkSwapped))
	{
	  enc = NSUnicodeStringEncoding;
	}
      else if (len >= 3
	&& data_bytes[0] == 0xEF
	&& data_bytes[1] == 0xBB
	&& data_bytes[2] == 0xBF)
	{
	  enc = NSUTF8StringEncoding;
	}
    }
  self = [self initWithData: d encoding: enc];
  if (self == nil)
    {
      NSWarnMLog(@"Contents of URL '%@' are not string data", url);
    }
  return self;
}

/**
 * Returns the number of Unicode characters in this string, including the
 * individual characters of composed character sequences,
 */
- (unsigned int) length
{
  [self subclassResponsibility: _cmd];
  return 0;
}

// Accessing Characters

/**
 * Returns unicode character at index.  <code>unichar</code> is an unsigned
 * short.  Thus, a 16-bit character is returned.
 */
- (unichar) characterAtIndex: (unsigned int)index
{
  [self subclassResponsibility: _cmd];
  return (unichar)0;
}

/**
 * Returns this string as an array of 16-bit <code>unichar</code> (unsigned
 * short) values.  buffer must be preallocated and should be capable of
 * holding -length shorts.
 */
// Inefficient.  Should be overridden
- (void) getCharacters: (unichar*)buffer
{
  [self getCharacters: buffer range: ((NSRange){0, [self length]})];
  return;
}

/**
 * Returns aRange of string as an array of 16-bit <code>unichar</code>
 * (unsigned short) values.  buffer must be preallocated and should be capable
 * of holding a sufficient number of shorts.
 */
// Inefficient.  Should be overridden
- (void) getCharacters: (unichar*)buffer
		 range: (NSRange)aRange
{
  unsigned	l = [self length];
  unsigned	i;
  unichar	(*caiImp)(NSString*, SEL, unsigned int);

  GS_RANGE_CHECK(aRange, l);

  caiImp = (unichar (*)(NSString*,SEL,unsigned))
    [self methodForSelector: caiSel];

  for (i = 0; i < aRange.length; i++)
    {
      buffer[i] = (*caiImp)(self, caiSel, aRange.location + i);
    }
}

/**
 * Constructs a new ASCII string which is a representation of the receiver
 * in which characters are escaped where necessary in order to produce a
 * version of the string legal for inclusion within a URL.<br />
 * The original string is converted to bytes using the specified encoding
 * and then those bytes are escaped unless they correspond to 'legal'
 * ASCII characters.  The byte values escaped are any below 32 and any
 * above 126 as well as 32 (space), 34 ("), 35 (#), 37 (%), 60 (&lt;),
 * 62 (&gt;), 91 ([), 92 (\), 93 (]), 94 (^), 96 (~), 123 ({), 124 (|),
 * and 125 (}).<br />
 * Returns nil if the receiver cannot be represented using the specified
 * encoding.<br />
 * NB. This behavior is MacOS-X (4.2) compatible, and it should be noted
 * that it does <em>not</em> produce a string suitable for use as a field
 * value in a url-encoded form as it does <strong>not</strong> escape the
 * '+', '=' and '&amp;' characters used in such forms.  If you need to
 * add a string as a form field value (or name) you must add percent
 * escapes for those characters yourself.
 */
- (NSString*) stringByAddingPercentEscapesUsingEncoding: (NSStringEncoding)e
{
  NSData	*data = [self dataUsingEncoding: e];
  NSString	*s = nil;

  if (data != nil)
    {
      unsigned char	*src = (unsigned char*)[data bytes];
      unsigned int	slen = [data length];
      NSMutableData	*d = [[NSMutableData alloc] initWithLength: slen * 3];
      unsigned char	*dst = (unsigned char*)[d mutableBytes];
      unsigned int	spos = 0;
      unsigned int	dpos = 0;

      while (spos < slen)
	{
	  unsigned char	c = src[spos++];
	  unsigned int	hi;
	  unsigned int	lo;

	  if (c <= 32 || c > 126 || c == 34 || c == 35 || c == 37
	    || c == 60 || c == 62 || c == 91 || c == 92 || c == 93
	    || c == 94 || c == 96 || c == 123 || c == 124 || c == 125)
	    {
	      dst[dpos++] = '%';
	      hi = (c & 0xf0) >> 4;
	      dst[dpos++] = (hi > 9) ? 'A' + hi - 10 : '0' + hi;
	      lo = (c & 0x0f);
	      dst[dpos++] = (lo > 9) ? 'A' + lo - 10 : '0' + lo;
	    }
	  else
	    {
	      dst[dpos++] = c;
	    }
	}
      [d setLength: dpos];
      s = [[NSString alloc] initWithData: d encoding: NSASCIIStringEncoding];
      RELEASE(d);
      AUTORELEASE(s);
    }
  return s;
}

/**
 * Constructs a new string consisting of this instance followed by the string
 * specified by format.
 */
- (NSString*) stringByAppendingFormat: (NSString*)format,...
{
  va_list	ap;
  id		ret;

  va_start(ap, format);
  ret = [self stringByAppendingString:
    [NSString stringWithFormat: format arguments: ap]];
  va_end(ap);
  return ret;
}

/**
 * Constructs a new string consisting of this instance followed by the aString.
 */
- (NSString*) stringByAppendingString: (NSString*)aString
{
  unsigned	len = [self length];
  unsigned	otherLength = [aString length];
  NSZone	*z = GSObjCZone(self);
  unichar	*s = NSZoneMalloc(z, (len+otherLength)*sizeof(unichar));
  NSString	*tmp;

  [self getCharacters: s range: ((NSRange){0, len})];
  [aString getCharacters: s + len range: ((NSRange){0, otherLength})];
  tmp = [[NSStringClass allocWithZone: z] initWithCharactersNoCopy: s
    length: len + otherLength freeWhenDone: YES];
  return AUTORELEASE(tmp);
}

// Dividing Strings into Substrings

/**
 * <p>Returns an array of [NSString]s representing substrings of this string
 * that are separated by characters in the set (which must not be nil).
 * If there are no occurrences of separator, the whole string is
 * returned.  If string begins or ends with separator, empty strings will
 * be returned for those positions.</p>
 */
- (NSArray *) componentsSeparatedByCharactersInSet: (NSCharacterSet *)set
{
  NSRange	search;
  NSRange	complete;
  NSRange	found;
  NSMutableArray *array;

  if (set == nil)
    [NSException raise: NSInvalidArgumentException format: @"set is nil"];

  array = [NSMutableArray array];
  search = NSMakeRange (0, [self length]);
  complete = search;
  found = [self rangeOfCharacterFromSet: set];
  while (found.length != 0)
    {
      NSRange current;

      current = NSMakeRange (search.location,
	found.location - search.location);
      [array addObject: [self substringWithRange: current]];

      search = NSMakeRange (found.location + found.length,
	complete.length - found.location - found.length);
      found = [self rangeOfCharacterFromSet: set
                                    options: 0
                                      range: search];
    }
  // Add the last search string range
  [array addObject: [self substringWithRange: search]];

  // FIXME: Need to make mutable array into non-mutable array?
  return array;
}

/**
 * <p>Returns an array of [NSString]s representing substrings of this string
 * that are separated by separator (which itself is never returned in the
 * array).  If there are no occurrences of separator, the whole string is
 * returned.  If string begins or ends with separator, empty strings will
 * be returned for those positions.</p>
 * <p>Note, use an [NSScanner] if you need more sophisticated parsing.</p>
 */
- (NSArray*) componentsSeparatedByString: (NSString*)separator
{
  NSRange	search;
  NSRange	complete;
  NSRange	found;
  NSMutableArray *array = [NSMutableArray array];

  search = NSMakeRange (0, [self length]);
  complete = search;
  found = [self rangeOfString: separator];
  while (found.length != 0)
    {
      NSRange current;

      current = NSMakeRange (search.location,
	found.location - search.location);
      [array addObject: [self substringWithRange: current]];

      search = NSMakeRange (found.location + found.length,
	complete.length - found.location - found.length);
      found = [self rangeOfString: separator
			  options: 0
			    range: search];
    }
  // Add the last search string range
  [array addObject: [self substringWithRange: search]];

  // FIXME: Need to make mutable array into non-mutable array?
  return array;
}

/**
 * Returns a substring of the receiver from character at the specified
 * index to the end of the string.<br />
 * So, supplying an index of 3 would return a substring consisting of
 * the entire string apart from the first three character (those would
 * be at index 0, 1, and 2).<br />
 * If the supplied index is greater than or equal to the length of the
 * receiver an exception is raised.
 */
- (NSString*) substringFromIndex: (unsigned int)index
{
  return [self substringWithRange: ((NSRange){index, [self length]-index})];
}

/**
 * Returns a substring of the receiver from the start of the
 * string to (but not including) the specified index position.<br />
 * So, supplying an index of 3 would return a substring consisting of
 * the first three characters of the receiver.<br />
 * If the supplied index is greater than the length of the receiver
 * an exception is raised.
 */
- (NSString*) substringToIndex: (unsigned int)index
{
  return [self substringWithRange: ((NSRange){0,index})];;
}

/**
 * An obsolete name for -substringWithRange: ... deprecated.
 */
- (NSString*) substringFromRange: (NSRange)aRange
{
  return [self substringWithRange: aRange];
}

/**
 * Returns a substring of the receiver containing the characters
 * in aRange.<br />
 * If aRange specifies any character position not
 * present in the receiver, an exception is raised.<br />
 * If aRange has a length of zero, an empty string is returned.
 */
- (NSString*) substringWithRange: (NSRange)aRange
{
  unichar	*buf;
  id		ret;
  unsigned	len = [self length];

  GS_RANGE_CHECK(aRange, len);

  if (aRange.length == 0)
    return @"";
  buf = NSZoneMalloc(GSObjCZone(self), sizeof(unichar)*aRange.length);
  [self getCharacters: buf range: aRange];
  ret = [[NSStringClass allocWithZone: NSDefaultMallocZone()]
    initWithCharactersNoCopy: buf length: aRange.length freeWhenDone: YES];
  return AUTORELEASE(ret);
}

// Finding Ranges of Characters and Substrings

/**
 * Returns position of first character in this string that is in aSet.
 * Positions start at 0.  If the character is a composed character sequence,
 * the range returned will contain the whole sequence, else just the character
 * itself.
 */
- (NSRange) rangeOfCharacterFromSet: (NSCharacterSet*)aSet
{
  NSRange all = NSMakeRange(0, [self length]);

  return [self rangeOfCharacterFromSet: aSet
			       options: 0
				 range: all];
}

/**
 * Returns position of first character in this string that is in aSet.
 * Positions start at 0.  If the character is a composed character sequence,
 * the range returned will contain the whole sequence, else just the character
 * itself.  mask may contain <code>NSCaseInsensitiveSearch</code>,
 * <code>NSLiteralSearch</code> (don't consider alternate forms of composed
 * characters equal), or <code>NSBackwardsSearch</code> (search from end of
 * string).
 */
- (NSRange) rangeOfCharacterFromSet: (NSCharacterSet*)aSet
			    options: (unsigned int)mask
{
  NSRange all = NSMakeRange(0, [self length]);

  return [self rangeOfCharacterFromSet: aSet
			       options: mask
				 range: all];
}

/**
 * Returns position of first character in this string that is in aSet.
 * Positions start at 0.  If the character is a composed character sequence,
 * the range returned will contain the whole sequence, else just the character
 * itself.  mask may contain <code>NSCaseInsensitiveSearch</code>,
 * <code>NSLiteralSearch</code> (don't consider alternate forms of composed
 * characters equal), or <code>NSBackwardsSearch</code> (search from end of
 * string).  Search only carried out within aRange.
 */
- (NSRange) rangeOfCharacterFromSet: (NSCharacterSet*)aSet
			    options: (unsigned int)mask
			      range: (NSRange)aRange
{
  unsigned int	i;
  unsigned int	start;
  unsigned int	stop;
  int		step;
  NSRange	range;
  unichar	(*cImp)(id, SEL, unsigned int);
  BOOL		(*mImp)(id, SEL, unichar);

  i = [self length];
  GS_RANGE_CHECK(aRange, i);

  if ((mask & NSBackwardsSearch) == NSBackwardsSearch)
    {
      start = NSMaxRange(aRange)-1; stop = aRange.location-1; step = -1;
    }
  else
    {
      start = aRange.location; stop = NSMaxRange(aRange); step = 1;
    }
  range.location = NSNotFound;
  range.length = 0;

  cImp = (unichar(*)(id,SEL,unsigned int))
    [self methodForSelector: caiSel];
  mImp = (BOOL(*)(id,SEL,unichar))
    [aSet methodForSelector: cMemberSel];

  for (i = start; i != stop; i += step)
    {
      unichar letter = (unichar)(*cImp)(self, caiSel, i);

      if ((*mImp)(aSet, cMemberSel, letter))
	{
	  range = NSMakeRange(i, 1);
	  break;
	}
    }

  return range;
}

- (NSRange) rangeOfComposedCharacterSequencesForRange: (NSRange)range
{
  return NSMakeRange(0, 0);     // FIXME
}

/**
 * Invokes -rangeOfString:options: with no options.
 */
- (NSRange) rangeOfString: (NSString*)string
{
  NSRange	all = NSMakeRange(0, [self length]);

  return [self rangeOfString: string
		     options: 0
		       range: all];
}

/**
 * Invokes -rangeOfString:options:range: with the range set
 * set to the range of the whole of the receiver.
 */
- (NSRange) rangeOfString: (NSString*)string
		  options: (unsigned int)mask
{
  NSRange	all = NSMakeRange(0, [self length]);

  return [self rangeOfString: string
		     options: mask
		       range: all];
}

/**
 * Returns the range giving the location and length of the first
 * occurrence of aString within aRange.
 * <br/>
 * If aString does not exist in the receiver (an empty
 * string is never considered to exist in the receiver),
 * the length of the returned range is zero.
 * <br/>
 * If aString is nil, an exception is raised.
 * <br/>
 * If any part of aRange lies outside the range of the
 * receiver, an exception is raised.
 * <br/>
 * The options mask may contain the following options -
 * <list>
 *   <item><code>NSCaseInsensitiveSearch</code></item>
 *   <item><code>NSLiteralSearch</code></item>
 *   <item><code>NSBackwardsSearch</code></item>
 *   <item><code>NSAnchoredSearch</code></item>
 * </list>
 * The <code>NSAnchoredSearch</code> option means aString must occur at the
 * beginning (or end, if <code>NSBackwardsSearch</code> is also given) of the
 * string.  Options should be OR'd together using <code>'|'</code>.
 */
- (NSRange) rangeOfString: (NSString *)aString
		  options: (unsigned int)mask
		    range: (NSRange)aRange
{
  if (aString == nil)
    [NSException raise: NSInvalidArgumentException format: @"range of nil"];
  return strRangeNsNs(self, aString, mask, aRange);
}

- (NSRange) rangeOfString: (NSString *)aString
                  options: (NSStringCompareOptions)mask
                    range: (NSRange)searchRange
                   locale: (NSLocale *)locale
{
  return NSMakeRange(0, 0);     // FIXME
}

- (unsigned int) indexOfString: (NSString *)substring
{
  NSRange range = {0, [self length]};

  range = [self rangeOfString: substring options: 0 range: range];
  return range.length ? range.location : NSNotFound;
}

- (unsigned int) indexOfString: (NSString*)substring
		     fromIndex: (unsigned int)index
{
  NSRange range = {index, [self length] - index};

  range = [self rangeOfString: substring options: 0 range: range];
  return range.length ? range.location : NSNotFound;
}

// Determining Composed Character Sequences

/**
 * Unicode utility method.  If character at anIndex is part of a composed
 * character sequence anIndex (note indices start from 0), returns the full
 * range of this sequence.
 */
- (NSRange) rangeOfComposedCharacterSequenceAtIndex: (unsigned int)anIndex
{
  unsigned	start;
  unsigned	end;
  unsigned	length = [self length];
  unichar	ch;
  unichar	(*caiImp)(NSString*, SEL, unsigned int);
  NSCharacterSet *nbSet = [NSCharacterSet nonBaseCharacterSet];

  if (anIndex >= length)
    [NSException raise: NSRangeException format:@"Invalid location."];
  caiImp = (unichar (*)(NSString*,SEL,unsigned))
    [self methodForSelector: caiSel];

  for (start = anIndex; start > 0; start--)
    {
      ch = (*caiImp)(self, caiSel, start);
      if ([nbSet characterIsMember: ch] == NO)
        break;
    }
  for (end = start+1; end < length; end++)
    {
      ch = (*caiImp)(self, caiSel, end);
      if ([nbSet characterIsMember: ch] == NO)
        break;
    }

  return NSMakeRange(start, end-start);
}

// Identifying and Comparing Strings

/**
 * <p>Compares this instance with aString.  Returns
 * <code>NSOrderedAscending</code>, <code>NSOrderedDescending</code>, or
 * <code>NSOrderedSame</code>, depending on whether this instance occurs
 * before or after string in lexical order, or is equal to it.</p>
 */
- (NSComparisonResult) compare: (NSString*)aString
{
  return [self compare: aString options: 0];
}

/**
 * <p>Compares this instance with aString.  mask may be either
 * <code>NSCaseInsensitiveSearch</code> or <code>NSLiteralSearch</code>.  The
 * latter requests a literal byte-by-byte comparison, which is fastest but may
 * return inaccurate results in cases where two different composed character
 * sequences may be used to express the same character.</p>
 */
- (NSComparisonResult) compare: (NSString*)aString
		       options: (unsigned int)mask
{
  return [self compare: aString options: mask
		 range: ((NSRange){0, [self length]})];
}

/**
 * <p>Compares this instance with string.  mask may be either
 * <code>NSCaseInsensitiveSearch</code> or <code>NSLiteralSearch</code>.  The
 * latter requests a literal byte-by-byte comparison, which is fastest but may
 * return inaccurate results in cases where two different composed character
 * sequences may be used to express the same character.  aRange refers
 * to this instance, and should be set to 0..length to compare the whole
 * string.</p>
 */
// xxx Should implement full POSIX.2 collate
- (NSComparisonResult) compare: (NSString*)aString
		       options: (unsigned int)mask
			 range: (NSRange)aRange
{
  if (aString == nil)
    [NSException raise: NSInvalidArgumentException format: @"compare with nil"];
  return strCompNsNs(self, aString, mask, aRange);
}

/**
 *  Returns whether this string starts with aString.
 */
- (BOOL) hasPrefix: (NSString*)aString
{
  NSRange	range;

  range = [self rangeOfString: aString options: NSAnchoredSearch];
  return (range.length > 0) ? YES : NO;
}

/**
 *  Returns whether this string ends with aString.
 */
- (BOOL) hasSuffix: (NSString*)aString
{
  NSRange	range;

  range = [self rangeOfString: aString
                      options: NSAnchoredSearch | NSBackwardsSearch];
  return (range.length > 0) ? YES : NO;
}

/**
 *  Returns whether the receiver and an anObject are equals as strings.
 *  If anObject isn't an NSString, returns NO.
 */
- (BOOL) isEqual: (id)anObject
{
  if (anObject == self)
    {
      return YES;
    }
  if (anObject != nil && GSObjCIsInstance(anObject) == YES)
    {
      Class c = GSObjCClass(anObject);

      if (c != nil)
	{
	  if (GSObjCIsKindOf(c, NSStringClass))
	    {
	      return [self isEqualToString: anObject];
	    }
	}
    }
  return NO;
}

/**
 *  Returns whether this instance is equal as a string to aString.  See also
 *  -compare: and related methods.
 */
- (BOOL) isEqualToString: (NSString*)aString
{
  if ([self hash] != [aString hash])
    return NO;
  if (strCompNsNs(self, aString, 0, (NSRange){0, [self length]})
    == NSOrderedSame)
    return YES;
  return NO;
}

/**
 * Return 28-bit hash value (in 32-bit integer).  The top few bits are used
 * for other purposes in a bitfield in the concrete string subclasses, so we
 * must not use the full unsigned integer.
 */
- (unsigned int) hash
{
  unsigned	ret = 0;
  unsigned	len = [self length];

  if (len > 0)
    {
      unichar		buf[64];
      unichar		*ptr = (len <= 64) ? buf :
	NSZoneMalloc(NSDefaultMallocZone(), len * sizeof(unichar));
      unichar		*p;
      unsigned		char_count = 0;

      [self getCharacters: ptr range: NSMakeRange(0,len)];

      p = ptr;

      while (char_count++ < len)
	{
	  unichar	c = *p++;

	  // FIXME ... should normalize composed character sequences.
	  ret = (ret << 5) + ret + c;
	}

      if (ptr != buf)
	{
	  NSZoneFree(NSDefaultMallocZone(), ptr);
	}

      /*
       * The hash caching in our concrete string classes uses zero to denote
       * an empty cache value, so we MUST NOT return a hash of zero.
       */
      ret &= 0x0fffffff;
      if (ret == 0)
	{
	  ret = 0x0fffffff;
	}
      return ret;
    }
  else
    {
      return 0x0ffffffe;	/* Hash for an empty string.	*/
    }
}

// Getting a Shared Prefix

/**
 *  Returns the largest initial portion of this instance shared with aString.
 *  mask may be either <code>NSCaseInsensitiveSearch</code> or
 *  <code>NSLiteralSearch</code>.  The latter requests a literal byte-by-byte
 *  comparison, which is fastest but may return inaccurate results in cases
 *  where two different composed character sequences may be used to express
 *  the same character.
 */
- (NSString*) commonPrefixWithString: (NSString*)aString
			     options: (unsigned int)mask
{
  if (mask & NSLiteralSearch)
    {
      int prefix_len = 0;
      unsigned	length = [self length];
      unsigned	aLength = [aString length];
      unichar *u,*w;
      unichar a1[length+1];
      unichar *s1 = a1;
      unichar a2[aLength+1];
      unichar *s2 = a2;

      u = s1;
      [self getCharacters: s1 range: ((NSRange){0, length})];
      s1[length] = (unichar)0;
      [aString getCharacters: s2 range: ((NSRange){0, aLength})];
      s2[aLength] = (unichar)0;
      u = s1;
      w = s2;

      if (mask & NSCaseInsensitiveSearch)
	{
	  while (*s1 && *s2 && (uni_tolower(*s1) == uni_tolower(*s2)))
	    {
	      s1++;
	      s2++;
	      prefix_len++;
	    }
	}
      else
	{
	  while (*s1 && *s2 && (*s1 == *s2))
	    {
	      s1++;
	      s2++;
	      prefix_len++;
	    }
	}
      return [NSStringClass stringWithCharacters: u length: prefix_len];
    }
  else
    {
      unichar	(*scImp)(NSString*, SEL, unsigned int);
      unichar	(*ocImp)(NSString*, SEL, unsigned int);
      void	(*sgImp)(NSString*, SEL, unichar*, NSRange) = 0;
      void	(*ogImp)(NSString*, SEL, unichar*, NSRange) = 0;
      NSRange	(*srImp)(NSString*, SEL, unsigned int) = 0;
      NSRange	(*orImp)(NSString*, SEL, unsigned int) = 0;
      BOOL	gotRangeImps = NO;
      BOOL	gotFetchImps = NO;
      NSRange	sRange;
      NSRange	oRange;
      unsigned	sLength = [self length];
      unsigned	oLength = [aString length];
      unsigned	sIndex = 0;
      unsigned	oIndex = 0;

      if (!sLength)
	return IMMUTABLE(self);
      if (!oLength)
	return IMMUTABLE(aString);

      scImp = (unichar (*)(NSString*,SEL,unsigned))
	[self methodForSelector: caiSel];
      ocImp = (unichar (*)(NSString*,SEL,unsigned))
	[aString methodForSelector: caiSel];

      while ((sIndex < sLength) && (oIndex < oLength))
	{
	  unichar	sc = (*scImp)(self, caiSel, sIndex);
	  unichar	oc = (*ocImp)(aString, caiSel, oIndex);

	  if (sc == oc)
	    {
	      sIndex++;
	      oIndex++;
	    }
	  else if ((mask & NSCaseInsensitiveSearch)
	    && (uni_tolower(sc) == uni_tolower(oc)))
	    {
	      sIndex++;
	      oIndex++;
	    }
	  else
	    {
	      if (gotRangeImps == NO)
		{
		  gotRangeImps = YES;
		  srImp=(NSRange (*)())[self methodForSelector: ranSel];
		  orImp=(NSRange (*)())[aString methodForSelector: ranSel];
		}
	      sRange = (*srImp)(self, ranSel, sIndex);
	      oRange = (*orImp)(aString, ranSel, oIndex);

	      if ((sRange.length < 2) || (oRange.length < 2))
		return [self substringWithRange: NSMakeRange(0, sIndex)];
	      else
		{
		  GSEQ_MAKE(sBuf, sSeq, sRange.length);
		  GSEQ_MAKE(oBuf, oSeq, oRange.length);

		  if (gotFetchImps == NO)
		    {
		      gotFetchImps = YES;
		      sgImp=(void (*)())[self methodForSelector: gcrSel];
		      ogImp=(void (*)())[aString methodForSelector: gcrSel];
		    }
		  (*sgImp)(self, gcrSel, sBuf, sRange);
		  (*ogImp)(aString, gcrSel, oBuf, oRange);

		  if (GSeq_compare(&sSeq, &oSeq) == NSOrderedSame)
		    {
		      sIndex += sRange.length;
		      oIndex += oRange.length;
		    }
		  else if (mask & NSCaseInsensitiveSearch)
		    {
		      GSeq_lowercase(&sSeq);
		      GSeq_lowercase(&oSeq);
		      if (GSeq_compare(&sSeq, &oSeq) == NSOrderedSame)
			{
			  sIndex += sRange.length;
			  oIndex += oRange.length;
			}
		      else
			return [self substringWithRange: NSMakeRange(0,sIndex)];
		    }
		  else
		    return [self substringWithRange: NSMakeRange(0,sIndex)];
		}
	    }
	}
      return [self substringWithRange: NSMakeRange(0, sIndex)];
    }
}

/**
 * Determines the smallest range of lines containing aRange and returns
 * the information as a range.<br />
 * Calls -getLineStart:end:contentsEnd:forRange: to do the work.
 */
- (NSRange) lineRangeForRange: (NSRange)aRange
{
  unsigned startIndex;
  unsigned lineEndIndex;

  [self getLineStart: &startIndex
                 end: &lineEndIndex
         contentsEnd: NULL
            forRange: aRange];
  return NSMakeRange(startIndex, lineEndIndex - startIndex);
}

/**
 * Determines the smallest range of lines containing aRange and returns
 * the locations in that range.<br />
 * Lines are delimited by any of these character sequences, the longest
 * (CRLF) sequence preferred.
 * <list>
 *   <item>U+000A (linefeed)</item>
 *   <item>U+000D (carriage return)</item>
 *   <item>U+2028 (Unicode line separator)</item>
 *   <item>U+2029 (Unicode paragraph separator)</item>
 *   <item>U+000D U+000A (CRLF)</item>
 * </list>
 * The index of the first character of the line at or before aRange is
 * returned in startIndex.<br />
 * The index of the first character of the next line after the line terminator
 * is returned in endIndex.<br />
 * The index of the last character before the line terminator is returned
 * contentsEndIndex.<br />
 * Raises an NSRangeException if the range is invalid, but permits the index
 * arguments to be null pointers (in which case no value is returned in that
 * argument).
 */
- (void) getLineStart: (unsigned int *)startIndex
                  end: (unsigned int *)lineEndIndex
          contentsEnd: (unsigned int *)contentsEndIndex
	     forRange: (NSRange)aRange
{
  unichar	thischar;
  unsigned	start, end, len, termlen;
  unichar	(*caiImp)(NSString*, SEL, unsigned int);

  len = [self length];
  GS_RANGE_CHECK(aRange, len);

  caiImp = (unichar (*)())[self methodForSelector: caiSel];
  start = aRange.location;

  if (startIndex)
    {
      if (start == 0)
	{
	  *startIndex = 0;
	}
      else
	{
	  start--;
	  while (start > 0)
	    {
	      BOOL	done = NO;

	      thischar = (*caiImp)(self, caiSel, start);
	      switch (thischar)
		{
		  case (unichar)0x000A:
		  case (unichar)0x000D:
		  case (unichar)0x2028:
		  case (unichar)0x2029:
		    done = YES;
		    break;
		  default:
		    start--;
		    break;
		}
	      if (done)
		break;
	    }
	  if (start == 0)
	    {
	      thischar = (*caiImp)(self, caiSel, start);
	      switch (thischar)
		{
		  case (unichar)0x000A:
		  case (unichar)0x000D:
		  case (unichar)0x2028:
		  case (unichar)0x2029:
		    start++;
		    break;
		  default:
		    break;
		}
	    }
	  else
	    {
	      start++;
	    }
	  *startIndex = start;
	}
    }

  if (lineEndIndex || contentsEndIndex)
    {
      BOOL found = NO;
      end = aRange.location;
      if (aRange.length)
        {
          end += (aRange.length - 1);
        }
      while (end < len)
	{
	   thischar = (*caiImp)(self, caiSel, end);
	   switch (thischar)
	     {
	       case (unichar)0x000A:
	       case (unichar)0x000D:
	       case (unichar)0x2028:
	       case (unichar)0x2029:
		 found = YES;
		 break;
	       default:
		 break;
	     }
	   end++;
	   if (found)
	     break;
	}
      termlen = 1;
      if (lineEndIndex)
	{
	  if (end < len
	    && ((*caiImp)(self, caiSel, end-1) == (unichar)0x000D)
	    && ((*caiImp)(self, caiSel, end) == (unichar)0x000A))
	    {
	      *lineEndIndex = end+1;
	      termlen = 2;
	    }
	  else
	    {
	      *lineEndIndex = end;
	    }
	}
      if (contentsEndIndex)
	{
	  if (found)
	    {
	      *contentsEndIndex = end-termlen;
	    }
	  else
	    {
	      /* xxx OPENSTEP documentation does not say what to do if last
		 line is not terminated. Assume this */
	      *contentsEndIndex = end;
	    }
	}
    }
}

- (void) getParagraphStart: (NSUInteger *)startPtr 
                       end: (NSUInteger *)parEndPtr
               contentsEnd: (NSUInteger *)contentsEndPtr
                  forRange: (NSRange)range
{
  // FIXME
}

// Changing Case

/**
 * Returns version of string in which each whitespace-delimited <em>word</em>
 * is capitalized (not every letter).  Conversion to capitals is done in a
 * unicode-compliant manner but there may be exceptional cases where behavior
 * is not what is desired.
 */
// xxx There is more than this in word capitalization in Unicode,
// but this will work in most cases
- (NSString*) capitalizedString
{
  unichar	*s;
  unsigned	count = 0;
  BOOL		found = YES;
  unsigned	len = [self length];

  if (len == 0)
    return IMMUTABLE(self);
  if (whitespaceBitmapRep == NULL)
    setupWhitespace();

  s = NSZoneMalloc(GSObjCZone(self), sizeof(unichar)*len);
  [self getCharacters: s range: ((NSRange){0, len})];
  while (count < len)
    {
      if (GS_IS_WHITESPACE(s[count]))
	{
	  count++;
	  found = YES;
	  while (count < len
	    && GS_IS_WHITESPACE(s[count]))
	    {
	      count++;
	    }
	}
      if (count < len)
	{
	  if (found)
	    {
	      s[count] = uni_toupper(s[count]);
	      count++;
	    }
	  else
	    {
	      while (count < len
		&& !GS_IS_WHITESPACE(s[count]))
		{
		  s[count] = uni_tolower(s[count]);
		  count++;
		}
	    }
	}
      found = NO;
    }
  return AUTORELEASE([[NSString allocWithZone: NSDefaultMallocZone()]
    initWithCharactersNoCopy: s length: len freeWhenDone: YES]);
}

/**
 * Returns a copy of the receiver with all characters converted
 * to lowercase.
 */
- (NSString*) lowercaseString
{
  static NSCharacterSet	*uc = nil;
  unichar	*s;
  unsigned	count;
  NSRange	start;
  unsigned	len = [self length];

  if (len == 0)
    {
      return IMMUTABLE(self);
    }
  if (uc == nil)
    {
      uc = RETAIN([NSCharacterSet uppercaseLetterCharacterSet]);
    }
  start = [self rangeOfCharacterFromSet: uc
				options: NSLiteralSearch
				  range: ((NSRange){0, len})];
  if (start.length == 0)
    {
      return IMMUTABLE(self);
    }
  s = NSZoneMalloc(GSObjCZone(self), sizeof(unichar)*len);
  [self getCharacters: s range: ((NSRange){0, len})];
  for (count = start.location; count < len; count++)
    {
      s[count] = uni_tolower(s[count]);
    }
  return AUTORELEASE([[NSStringClass allocWithZone: NSDefaultMallocZone()]
    initWithCharactersNoCopy: s length: len freeWhenDone: YES]);
}

/**
 * Returns a copy of the receiver with all characters converted
 * to uppercase.
 */
- (NSString*) uppercaseString
{
  static NSCharacterSet	*lc = nil;
  unichar	*s;
  unsigned	count;
  NSRange	start;
  unsigned	len = [self length];

  if (len == 0)
    {
      return IMMUTABLE(self);
    }
  if (lc == nil)
    {
      lc = RETAIN([NSCharacterSet lowercaseLetterCharacterSet]);
    }
  start = [self rangeOfCharacterFromSet: lc
				options: NSLiteralSearch
				  range: ((NSRange){0, len})];
  if (start.length == 0)
    {
      return IMMUTABLE(self);
    }
  s = NSZoneMalloc(GSObjCZone(self), sizeof(unichar)*len);
  [self getCharacters: s range: ((NSRange){0, len})];
  for (count = start.location; count < len; count++)
    {
      s[count] = uni_toupper(s[count]);
    }
  return AUTORELEASE([[NSStringClass allocWithZone: NSDefaultMallocZone()]
    initWithCharactersNoCopy: s length: len freeWhenDone: YES]);
}

// Storing the String

/** Returns <code>self</code>. */
- (NSString*) description
{
  return self;
}


// Getting C Strings

/**
 * Returns a pointer to a null terminated string of 16-bit unichar
 * The memory pointed to is not owned by the caller, so the
 * caller must copy its contents to keep it.
 */
- (const unichar*) unicharString
{
  NSMutableData	*data;
  unichar	*uniStr;

  GSOnceMLog(@"deprecated ... use cStringUsingEncoding:");

  data = [NSMutableData dataWithLength: ([self length] + 1) * sizeof(unichar)];
  uniStr = (unichar*)[data mutableBytes];
  if (uniStr != 0)
    {
      [self getCharacters: uniStr];
    }
  return uniStr;
}

/**
 * Returns a pointer to a null terminated string of 8-bit characters in the
 * default encoding.  The memory pointed to is not owned by the caller, so the
 * caller must copy its contents to keep it.  Raises an
 * <code>NSCharacterConversionException</code> if loss of information would
 * occur during conversion.  (See -canBeConvertedToEncoding: .)
 */
- (const char*) cString
{
  NSData	*d;
  NSMutableData	*m;

  d = [self dataUsingEncoding: _DefaultStringEncoding
	 allowLossyConversion: NO];
  if (d == nil)
    {
      [NSException raise: NSCharacterConversionException
		  format: @"unable to convert to cString"];
    }
  m = [d mutableCopy];
  [m appendBytes: "" length: 1];
  AUTORELEASE(m);
  return (const char*)[m bytes];
}

/**
 * Returns a pointer to a null terminated string of characters in the
 * specified encoding.<br />
 * NB. under GNUstep you can used this to obtain a nul terminated utf-16
 * string (sixteen bit characters) as well as eight bit strings.<br />
 * The memory pointed to is not owned by the caller, so the
 * caller must copy its contents to keep it.<br />
 * Raises an <code>NSCharacterConversionException</code> if loss of
 * information would occur during conversion.
 */
- (const char*) cStringUsingEncoding: (NSStringEncoding)encoding
{
  NSData	*d;
  NSMutableData	*m;

  d = [self dataUsingEncoding: encoding allowLossyConversion: NO];
  if (d == nil)
    {
      [NSException raise: NSCharacterConversionException
		  format: @"unable to convert to cString"];
    }
  m = [d mutableCopy];
  if (encoding == NSUnicodeStringEncoding)
    {
      unichar c = 0;

      [m appendBytes: &c length: 2];
    }
  else
    {
      [m appendBytes: "" length: 1];
    }
  AUTORELEASE(m);
  return (const char*)[m bytes];
}

/**
 * Returns the number of bytes needed to encode the receiver in the
 * specified encoding (without adding a nul character terminator).<br />
 * Returns 0 if the conversion is not possible.
 */
- (unsigned) lengthOfBytesUsingEncoding: (NSStringEncoding)encoding
{
  NSData	*d;

  d = [self dataUsingEncoding: encoding allowLossyConversion: NO];
  return [d length];
}

/**
 * Returns a size guaranteed to be large enough to encode the receiver in the
 * specified encoding (without adding a nul character terminator).  This may
 * be larger than the actual number of bytes needed.
 */
- (unsigned) maximumLengthOfBytesUsingEncoding: (NSStringEncoding)encoding
{
  if (encoding == NSUnicodeStringEncoding)
    return [self length] * 2;
  if (encoding == NSUTF8StringEncoding)
    return [self length] * 6;
  if (encoding == NSUTF7StringEncoding)
    return [self length] * 8;
  return [self length];				// Assume single byte/char
}

/**
 * Returns a C string converted using the default C string encoding, which may
 * result in information loss.  The memory pointed to is not owned by the
 * caller, so the caller must copy its contents to keep it.
 */
- (const char*) lossyCString
{
  NSData	*d;
  NSMutableData	*m;

  d = [self dataUsingEncoding: _DefaultStringEncoding
         allowLossyConversion: YES];
  m = [d mutableCopy];
  [m appendBytes: "" length: 1];
  AUTORELEASE(m);
  return (const char*)[m bytes];
}

/**
 * Returns null-terminated UTF-8 version of this unicode string.  The char[]
 * memory comes from an autoreleased object, so it will eventually go out of
 * scope.
 */
- (const char *) UTF8String
{
  NSData	*d;
  NSMutableData	*m;

  d = [self dataUsingEncoding: NSUTF8StringEncoding
         allowLossyConversion: NO];
  m = [d mutableCopy];
  [m appendBytes: "" length: 1];
  AUTORELEASE(m);
  return (const char*)[m bytes];
}

/**
 *  Returns length of a version of this unicode string converted to bytes
 *  using the default C string encoding.  If the conversion would result in
 *  information loss, the results are unpredictable.  Check
 *  -canBeConvertedToEncoding: first.
 */
- (unsigned int) cStringLength
{
  NSData	*d;

  d = [self dataUsingEncoding: _DefaultStringEncoding
         allowLossyConversion: NO];
  return [d length];
}

/**
 * Deprecated ... do not use.<br />.
 * Use -getCString:maxLength:encoding: instead.
 */
- (void) getCString: (char*)buffer
{
  [self getCString: buffer maxLength: NSMaximumStringLength
	     range: ((NSRange){0, [self length]})
    remainingRange: NULL];
}

/**
 * Deprecated ... do not use.<br />.
 * Use -getCString:maxLength:encoding: instead.
 */
- (void) getCString: (char*)buffer
	  maxLength: (unsigned int)maxLength
{
  [self getCString: buffer maxLength: maxLength
	     range: ((NSRange){0, [self length]})
    remainingRange: NULL];
}

/**
 * Retrieve up to maxLength bytes from the receiver into the buffer.<br />
 * In GNUstep, this method implements the actual behavior of the MacOS-X
 * method rather than it's documented behavior ...<br />
 * The maxLength argument must be the size (in bytes) of the area of
 * memory pointed to by the buffer argument.<br />
 * Returns YES on success.<br />
 * Returns NO if maxLength is too small to hold the entire string
 * including a terminating nul character.<br />
 * If it returns NO, the terminating nul will <em>not</em> have been
 * written to the buffer.<br />
 * Raises an exception if the string can not be converted to the
 * specified encoding without loss of information.<br />
 * eg. If the receiver is @"hello" then the provided buffer must be
 * at least six bytes long and the value of maxLength must be at least
 * six if NSASCIIStringEncoding is requested, but they must be at least
 * twelve if NSUnicodeStringEncoding is requested. 
 */
- (BOOL) getCString: (char*)buffer
	  maxLength: (unsigned int)maxLength
	   encoding: (NSStringEncoding)encoding
{
  if (encoding == NSUnicodeStringEncoding)
    {
      unsigned	length = [self length];

      if (maxLength > length * sizeof(unichar))
	{
	  unichar	*ptr = (unichar*)buffer;

	  maxLength = (maxLength - 1) / sizeof(unichar);
	  [self getCharacters: ptr
			range: NSMakeRange(0, maxLength)];
	  ptr[maxLength] = 0;
	  return YES;
	}
      return NO;
    }
  else
    {
      NSData	*d = [self dataUsingEncoding: encoding];
      unsigned	length = [d length];
      BOOL	result = (length <= maxLength) ? YES : NO;

      if (d == nil)
        {
	  [NSException raise: NSCharacterConversionException
		      format: @"Can't convert to C string."];
	}
      if (length > maxLength)
        {
          length = maxLength;
	}
      memcpy(buffer, [d bytes], length);
      buffer[length] = '\0';
      return result;
    }
}

/**
 * Deprecated ... do not use.<br />.
 * Use -getCString:maxLength:encoding: instead.
 */
- (void) getCString: (char*)buffer
	  maxLength: (unsigned int)maxLength
	      range: (NSRange)aRange
     remainingRange: (NSRange*)leftoverRange
{
  NSString	*s;

  /* As this is a deprecated method, keep things simple (but inefficient)
   * by copying the receiver to a new instance of a base library built-in
   * class, and use the implementation provided by that class.
   * We need an autorelease to avoid a memory leak if there is an exception.
   */
  s = AUTORELEASE([(NSString*)defaultPlaceholderString initWithString: self]);
  [s getCString: buffer
      maxLength: maxLength
	  range: aRange
 remainingRange: leftoverRange];
}


// Getting Numeric Values

// xxx Should we use NSScanner here ?

/**
 * Returns YES when scanning the receiver's text from left to right finds a
 * digit in the range 1-9 or a letter in the set ('Y', 'y', 'T', 't').<br />
 * Any trailing characters are ignored.<br />
 * Any leading whitespace or zeros or signs are also ignored.<br />
 * Returns NO if the above conditions are not met.
 */
- (BOOL) boolValue
{
  static NSCharacterSet *yes = nil;

  if (yes == nil)
    {
      yes = RETAIN([NSCharacterSet characterSetWithCharactersInString:
      @"123456789yYtT"]);
    }
  if ([self rangeOfCharacterFromSet: yes].length > 0)
    {
      return YES;
    }
  return NO;
}

/**
 * Returns the string's content as a decimal.<br />
 * Undocumented feature of Aplle Foundation.
 */
- (NSDecimal) decimalValue
{
  NSDecimal     result;

  NSDecimalFromString(&result, self, nil);
  return result;
}

/**
 * Returns the string's content as a double.  Skips leading whitespace.<br />
 * Conversion is not localised (i.e. uses '.' as the decimal separator).<br />
 * Returns 0.0 on underflow or if the string does not contain a number.
 */
- (double) doubleValue
{
  unichar	buf[32];
  unsigned	len = [self length];
  double	d = 0.0;

  if (len > 32) len = 32;
  [self getCharacters: buf range: NSMakeRange(0, len)];
  GSScanDouble(buf, len, &d);
  return d;
}

/**
 * Returns the string's content as a float.  Skips leading whitespace.<br />
 * Conversion is not localised (i.e. uses '.' as the decimal separator).<br />
 * Returns 0.0 on underflow or if the string does not contain a number.
 */
- (float) floatValue
{
  unichar	buf[32];
  unsigned	len = [self length];
  double	d = 0.0;

  if (len > 32) len = 32;
  [self getCharacters: buf range: NSMakeRange(0, len)];
  GSScanDouble(buf, len, &d);
  return (float)d;
}

/**
 * <p>Returns the string's content as an int.<br/>
 * Current implementation uses C library <code>atoi()</code>, which does not
 * detect conversion errors -- use with care!</p>
 */
- (int) intValue
{
  return atoi([self lossyCString]);
}

- (NSInteger) integerValue
{
  return atol([self lossyCString]);
}

- (long long) longLongValue
{
  return atoll([self lossyCString]);
}

// Working With Encodings

/**
 * <p>
 *   Returns the encoding used for any method accepting a C string.
 *   This value is determined automatically from the program's
 *   environment and cannot be changed programmatically.
 * </p>
 * <p>
 *   You should <em>NOT</em> override this method in an attempt to
 *   change the encoding being used... it won't work.
 * </p>
 * <p>
 *   In GNUstep, this encoding is determined by the initial value
 *   of the <code>GNUSTEP_STRING_ENCODING</code> environment
 *   variable.  If this is not defined,
 *   <code>NSISOLatin1StringEncoding</code> is assumed.
 * </p>
 */
+ (NSStringEncoding) defaultCStringEncoding
{
  return _DefaultStringEncoding;
}

/**
 * Returns an array of all available string encodings,
 * terminated by a null value.
 */
+ (NSStringEncoding*) availableStringEncodings
{
  return GSPrivateAvailableEncodings();
}

/**
 * Returns the localized name of the encoding specified.
 */
+ (NSString*) localizedNameOfStringEncoding: (NSStringEncoding)encoding
{
  id ourbundle;
  id ourname;

/*
      Should be path to localizable.strings file.
      Until we have it, just make sure that bundle
      is initialized.
*/
  ourbundle = [NSBundle bundleForLibrary: @"gnustep-base"];

  ourname = GSPrivateEncodingName(encoding);
  return [ourbundle localizedStringForKey: ourname
				    value: ourname
				    table: nil];
}

/**
 *  Returns whether this string can be converted to the given string encoding
 *  without information loss.
 */
- (BOOL) canBeConvertedToEncoding: (NSStringEncoding)encoding
{
  id d = [self dataUsingEncoding: encoding allowLossyConversion: NO];

  return d != nil ? YES : NO;
}

/**
 *  Converts string to a byte array in the given encoding, returning nil if
 *  this would result in information loss.
 */
- (NSData*) dataUsingEncoding: (NSStringEncoding)encoding
{
  return [self dataUsingEncoding: encoding allowLossyConversion: NO];
}

/**
 *  Converts string to a byte array in the given encoding.  If flag is NO,
 *  nil would be returned if this would result in information loss.
 */
- (NSData*) dataUsingEncoding: (NSStringEncoding)encoding
	 allowLossyConversion: (BOOL)flag
{
  unsigned	len = [self length];
  NSData	*d;

  if (len == 0)
    {
      d = [NSDataClass data];
    }
  else if (encoding == NSUnicodeStringEncoding)
    {
      unichar	*u;
      unsigned	l;

      u = (unichar*)NSZoneMalloc(NSDefaultMallocZone(),
	(len + 1) * sizeof(unichar));
      *u = byteOrderMark;
      [self getCharacters: u + 1];
      l = GSUnicode(u, len, 0, 0);
      if (l == len || flag == YES)
	{
	  d = [NSDataClass dataWithBytesNoCopy: u
					length: (l + 1) * sizeof(unichar)];
	}
      else
	{
	  d = nil;
	  NSZoneFree(NSDefaultMallocZone(), u);
	}
    }
  else
    {
      unichar		buf[8192];
      unichar		*u = buf;
      unsigned int	options;
      unsigned char	*b = 0;
      unsigned int	l = 0;

      /* Build a fake object on the stack and copy unicode characters
       * into its buffer from the receiver.
       * We can then use our concrete subclass implementation to do the
       * work of converting to the desired encoding.
       */
      if (len >= 4096)
	{
	  u = objc_malloc(len * sizeof(unichar));
	}
      [self getCharacters: u];
      if (flag == NO)
        {
	  options = GSUniStrict;
	}
      else
        {
	  options = 0;
	}
      if (GSFromUnicode(&b, &l, u, len, encoding, NSDefaultMallocZone(),
	options) == YES)
	{
	  d = [NSDataClass dataWithBytesNoCopy: b length: l];
	}
      else
        {
	  d = nil;
	}
      if (u != buf)
	{
	  objc_free(u);
	}
    }
  return d;
}

/**
 * Returns the encoding with which this string can be converted without
 * information loss that would result in most efficient character access.
 */
- (NSStringEncoding) fastestEncoding
{
  return NSUnicodeStringEncoding;
}

/**
 * Returns the smallest encoding with which this string can be converted
 * without information loss.
 */
- (NSStringEncoding) smallestEncoding
{
  return NSUnicodeStringEncoding;
}

- (unsigned int) completePathIntoString: (NSString**)outputName
			  caseSensitive: (BOOL)flag
		       matchesIntoArray: (NSArray**)outputArray
			    filterTypes: (NSArray*)filterTypes
{
  NSString		*basePath = [self stringByDeletingLastPathComponent];
  NSString		*lastComp = [self lastPathComponent];
  NSString		*tmpPath;
  NSDirectoryEnumerator *e;
  NSMutableArray	*op = nil;
  unsigned		matchCount = 0;

  if (outputArray != 0)
    {
      op = (NSMutableArray*)[NSMutableArray array];
    }

  if (outputName != NULL)
    {
      *outputName = nil;
    }

  if ([basePath length] == 0)
    {
      basePath = @".";
    }

  e = [[NSFileManager defaultManager] enumeratorAtPath: basePath];
  while (tmpPath = [e nextObject], tmpPath)
    {
      /* Prefix matching */
      if (flag == YES)
	{ /* Case sensitive */
	  if ([tmpPath hasPrefix: lastComp] == NO)
	    {
	      continue;
	    }
	}
      else if ([[tmpPath uppercaseString]
	hasPrefix: [lastComp uppercaseString]] == NO)
	{
	  continue;
	}

      /* Extensions filtering */
      if (filterTypes
	&& ([filterTypes containsObject: [tmpPath pathExtension]] == NO))
	{
	  continue;
	}

      /* Found a completion */
      matchCount++;
      if (outputArray != NULL)
	{
	  [op addObject: tmpPath];
	}

      if ((outputName != NULL) &&
	((*outputName == nil) || (([*outputName length] < [tmpPath length]))))
	{
	  *outputName = tmpPath;
	}
    }
  if (outputArray != NULL)
    {
      *outputArray = AUTORELEASE([op copy]);
    }
  return matchCount;
}

static NSFileManager *fm = nil;

#if	defined(__MINGW32__)
- (const GSNativeChar*) fileSystemRepresentation
{
  if (fm == nil)
    {
      fm = RETAIN([NSFileManager defaultManager]);
    }
  return [fm fileSystemRepresentationWithPath: self];
}

- (BOOL) getFileSystemRepresentation: (GSNativeChar*)buffer
			   maxLength: (unsigned int)size
{
  const unichar	*ptr;
  unsigned	i;

  if (size == 0)
    {
      return NO;
    }
  if (buffer == 0)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"%@ given null pointer",
	NSStringFromSelector(_cmd)];
    }
  ptr = [self fileSystemRepresentation];
  for (i = 0; i < size; i++)
    {
      buffer[i] = ptr[i];
      if (ptr[i] == 0)
	{
	  break;
	}
    }
  if (i == size && ptr[i] != 0)
    {
      return NO;	// Not at end.
    }
  return YES;
}
#else
- (const GSNativeChar*) fileSystemRepresentation
{
  if (fm == nil)
    {
      fm = RETAIN([NSFileManager defaultManager]);
    }
  return [fm fileSystemRepresentationWithPath: self];
}

- (BOOL) getFileSystemRepresentation: (GSNativeChar*)buffer
			   maxLength: (unsigned int)size
{
  const char* ptr;

  if (size == 0)
    {
      return NO;
    }
  if (buffer == 0)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"%@ given null pointer",
	NSStringFromSelector(_cmd)];
    }
  ptr = [self fileSystemRepresentation];
  if (strlen(ptr) > size)
    {
      return NO;
    }
  strcpy(buffer, ptr);
  return YES;
}
#endif

- (NSString*) lastPathComponent
{
  unsigned int	l = [self length];
  NSRange	range;
  unsigned int	i;

  if (l == 0)
    {
      return @"";		// self is empty
    }

  // Skip back over any trailing path separators, but not in to root.
  i = rootOf(self, l);
  while (l > i && pathSepMember([self characterAtIndex: l-1]) == YES)
    {
      l--;
    }

  // If only the root is left, return it.
  if (i == l)
    {
      /*
       * NB. tilde escapes should not have trailing separator in the
       * path component as they are not trreated as true roots.
       */
      if ([self characterAtIndex: 0] == '~'
	&& pathSepMember([self characterAtIndex: i-1]) == YES)
	{
	  return [self substringToIndex: i-1];
	}
      return [self substringToIndex: i];
    }

  // Got more than root ... find last component.
  range = [self rangeOfCharacterFromSet: pathSeps()
				options: NSBackwardsSearch
				  range: ((NSRange){i, l-i})];
  if (range.length > 0)
    {
      // Found separator ... adjust to point to component.
      i = NSMaxRange(range);
    }
  return [self substringWithRange: ((NSRange){i, l-i})];
}

- (NSRange) paragraphRangeForRange: (NSRange)range
{
  return NSMakeRange(0, 0);     // FIXME
}

- (NSString*) pathExtension
{
  NSRange	range;
  unsigned int	l = [self length];
  unsigned int	root;

  if (l == 0)
    {
      return @"";
    }
  root = rootOf(self, l);

  /*
   * Step past trailing path separators.
   */
  while (l > root && pathSepMember([self characterAtIndex: l-1]) == YES)
    {
      l--;
    }
  range = NSMakeRange(root, l-root);

  /*
   * Look for a dot in the path ... if there isn't one, or if it is
   * immediately after the root or a path separator, there is no extension.
   */
  range = [self rangeOfString: @"." options: NSBackwardsSearch range: range];
  if (range.length > 0 && range.location > root
    && pathSepMember([self characterAtIndex: range.location-1]) == NO)
    {
      NSRange	sepRange;

      /*
       * Found a dot, so we determine the range of the (possible)
       * path extension, then check to see if we have a path
       * separator within it ... if we have a path separator then
       * the dot is inside the last path component and there is
       * therefore no extension.
       */
      range.location++;
      range.length = l - range.location;
      sepRange = [self rangeOfCharacterFromSet: pathSeps()
				       options: NSBackwardsSearch
				         range: range];
      if (sepRange.length == 0)
	{
	  return [self substringFromRange: range];
	}
    }

  return @"";
}

- (NSString*) stringByAppendingPathComponent: (NSString*)aString
{
  unsigned	originalLength = [self length];
  unsigned	length = originalLength;
  unsigned	aLength = [aString length];
  unsigned	root;
  unichar	buf[length+aLength+1];

  /* If the 'component' has a leading path separator (or drive spec
   * in windows) then we need to find its length so we can strip it.
   */
  root = rootOf(aString, aLength);
  if (root > 0)
    {
      unichar c = [aString characterAtIndex: 0];

      if (c == '~')
        {
	  root = 0;
	}
      else if (root > 1 && pathSepMember(c))
        {
	  int	i;

	  for (i = 1; i < root; i++)
	    {
	      c = [aString characterAtIndex: i];
	      if (!pathSepMember(c))
	        {
		  break;
		}
	    }
	  root = i;
	}
    }

  if (length == 0)
    {
      [aString getCharacters: buf range: ((NSRange){0, aLength})];
      length = aLength;
    }
  else
    {
      [self getCharacters: buf range: ((NSRange){0, length})];

      /* We strip back trailing path separators, and replace them with
       * a single one ... except in the case where we have a windows
       * drive specification, and the string being appended does not
       * have a path separator as a root. In that case we just want to
       * append to the drive specification directly, leaving a relative
       * path like c:foo
       */
      if (length != 2 || buf[1] != ':' || GSPathHandlingUnix() == YES
	|| buf[0] < 'A' || buf[0] > 'z' || (buf[0] > 'Z' && buf[0] < 'a')
	|| (root > 0 && pathSepMember([aString characterAtIndex: root-1])))
	{
	  while (length > 0 && pathSepMember(buf[length-1]) == YES)
	    {
	      length--;
	    }
	  buf[length++] = pathSepChar();
	}

      if ((aLength - root) > 0)
	{
	  // appending .. discard root from aString
	  [aString getCharacters: &buf[length]
			   range: ((NSRange){root, aLength-root})];
	  length += aLength-root;
	}
      // Find length of root part of new path.
      root = rootOf(self, originalLength);
    }

  // Trim trailing path separators
  while (length > 1 && pathSepMember(buf[length-1]) == YES)
    {
      length--;
    }

  /* Trim multi separator sequences outside root (root may contain an
   * initial // pair if it is a windows UNC path).
   */
  if (length > 0)
    {
      aLength = length - 1;
      while (aLength > root)
	{
	  if (pathSepMember(buf[aLength]) == YES)
	    {
	      buf[aLength] = pathSepChar();
	      if (pathSepMember(buf[aLength-1]) == YES)
		{
		  unsigned	pos;

		  buf[aLength-1] = pathSepChar();
		  for (pos = aLength+1; pos < length; pos++)
		    {
		      buf[pos-1] = buf[pos];
		    }
		  length--;
		}
	    }
	  aLength--;
	}
    }
  return [NSStringClass stringWithCharacters: buf length: length];
}

- (NSString*) stringByAppendingPathExtension: (NSString*)aString
{
  unsigned	l = [self length];
  unsigned 	originalLength = l;
  unsigned	root;

  if (l == 0)
    {
      NSLog(@"[%@-%@] cannot append extension '%@' to empty string",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd), aString);
      return @"";		// Must have a file name to append extension.
    }
  root = rootOf(self, l);
  /*
   * Step past trailing path separators.
   */
  while (l > root && pathSepMember([self characterAtIndex: l-1]) == YES)
    {
      l--;
    }
  if (root == l)
    {
      NSLog(@"[%@-%@] cannot append extension '%@' to path '%@'",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd),
	aString, self);
      return IMMUTABLE(self);	// Must have a file name to append extension.
    }

  /* MacOS-X prohibits an extension beginning with a path separator,
   * but this code extends that a little to prohibit any root except
   * one beginning with '~' from being used as an extension. 
   */ 
  root = rootOf(aString, [aString length]);
  if (root > 0 && [aString characterAtIndex: 0] != '~')
    {
      NSLog(@"[%@-%@] cannot append extension '%@' to path '%@'",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd),
	aString, self);
      return IMMUTABLE(self);	// Must have a file name to append extension.
    }

  if (originalLength != l)
    {
      NSRange	range = NSMakeRange(0, l);

      return [[self substringFromRange: range]
	stringByAppendingFormat: @".%@", aString];
    }
  return [self stringByAppendingFormat: @".%@", aString];
}

- (NSString*) stringByDeletingLastPathComponent
{
  NSRange	range;
  unsigned int	l = [self length];
  unsigned int	i;

  if (l == 0)
    {
      return @"";
    }
  i = rootOf(self, l);

  /*
   * Any root without a trailing path separator can be deleted
   * as it's either a relative path or a tilde expression.
   */
  if (i == l && pathSepMember([self characterAtIndex: i-1]) == NO)
    {
      return @"";	// Delete relative root
    }

  /*
   * Step past trailing path separators.
   */
  while (l > i && pathSepMember([self characterAtIndex: l-1]) == YES)
    {
      l--;
    }

  /*
   * If all we have left is the root, return that root, except for the
   * special case of a tilde expression ... which may be deleted even
   * when it is followed by a separator.
   */
  if (l == i)
    {
      if ([self characterAtIndex: 0] == '~')
	{
	  return @"";				// Tilde roots may be deleted.
	}
      return [self substringToIndex: i];	// Return root component.
    }

  /*
   * Locate path separator preceding last path component.
   */
  range = [self rangeOfCharacterFromSet: pathSeps()
				options: NSBackwardsSearch
				  range: ((NSRange){i, l-i})];
  if (range.length == 0)
    {
      return [self substringToIndex: i];
    }
  return [self substringToIndex: range.location];
}

- (NSString*) stringByDeletingPathExtension
{
  NSRange	range;
  NSRange	r0;
  NSRange	r1;
  NSString	*substring;
  unsigned	l = [self length];
  unsigned	root;

  if ((root = rootOf(self, l)) == l)
    {
      return IMMUTABLE(self);
    }

  /*
   * Skip past any trailing path separators... but not into root.
   */
  while (l > root && pathSepMember([self characterAtIndex: l-1]) == YES)
    {
      l--;
    }
  range = NSMakeRange(root, l-root);
  /*
   * Locate path extension.
   */
  r0 = [self rangeOfString: @"."
		   options: NSBackwardsSearch
		     range: range];
  /*
   * Locate a path separator.
   */
  r1 = [self rangeOfCharacterFromSet: pathSeps()
			     options: NSBackwardsSearch
			       range: range];
  /*
   * Assuming the extension separator was found in the last path
   * component, set the length of the substring we want.
   */
  if (r0.length > 0 && r0.location > root
    && (r1.length == 0 || r1.location < r0.location))
    {
      l = r0.location;
    }
  substring = [self substringToIndex: l];
  return substring;
}

- (NSString*) stringByExpandingTildeInPath
{
  NSString	*homedir;
  NSRange	firstSlashRange;
  unsigned	length;

  if ((length = [self length]) == 0)
    {
      return IMMUTABLE(self);
    }
  if ([self characterAtIndex: 0] != 0x007E)
    {
      return IMMUTABLE(self);
    }

  /* FIXME ... should remove in future
   * Anything beginning '~@' is assumed to be a windows path specification
   * which can't be expanded.
   */
  if (length > 1 && [self characterAtIndex: 1] == 0x0040)
    {
      return IMMUTABLE(self);
    }

  firstSlashRange = [self rangeOfCharacterFromSet: pathSeps()
					    options: NSLiteralSearch
					      range: ((NSRange){0, length})];
  if (firstSlashRange.length == 0)
    {
      firstSlashRange.location = length;
    }

  /* FIXME ... should remove in future
   * Anything beginning '~' followed by a single letter is assumed
   * to be a windows drive specification.
   */
  if (firstSlashRange.location == 2 && isalpha([self characterAtIndex: 1]))
    {
      return IMMUTABLE(self);
    }

  if (firstSlashRange.location != 1)
    {
      /* It is of the form `~username/blah/...' or '~username' */
      int	userNameLen;
      NSString	*uname;

      if (firstSlashRange.length != 0)
	{
	  userNameLen = firstSlashRange.location - 1;
	}
      else
	{
	  /* It is actually of the form `~username' */
	  userNameLen = [self length] - 1;
	  firstSlashRange.location = [self length];
	}
      uname = [self substringWithRange: ((NSRange){1, userNameLen})];
      homedir = NSHomeDirectoryForUser (uname);
    }
  else
    {
      /* It is of the form `~/blah/...' or is '~' */
      homedir = NSHomeDirectory ();
    }

  if (homedir != nil)
    {
      if (firstSlashRange.location < length)
	{
	  return [homedir stringByAppendingPathComponent:
	    [self substringFromIndex: firstSlashRange.location]];
	}
      else
	{
	  return IMMUTABLE(homedir);
	}
    }
  else
    {
      return IMMUTABLE(self);
    }
}

- (NSString*) stringByAbbreviatingWithTildeInPath
{
  NSString	*homedir = NSHomeDirectory ();

  if (![self hasPrefix: homedir])
    {
      return IMMUTABLE(self);
    }
  if ([self length] == [homedir length])
    {
      return @"~";
    }
  return [@"~" stringByAppendingPathComponent:
    [self substringFromIndex: [homedir length]]];
}

/**
 * Returns a string formed by extending or truncating the receiver to
 * newLength characters.  If the new string is larger, it is padded
 * by appending characters from padString (appending it as many times
 * as required).  The first character from padString to be appended
 * is specified by padIndex.<br />
 */
- (NSString*) stringByPaddingToLength: (unsigned int)newLength
			   withString: (NSString*)padString
		      startingAtIndex: (unsigned int)padIndex
{
  unsigned	length = [self length];
  unsigned	padLength;

  if (padString == nil || [padString isKindOfClass: [NSString class]] == NO)
    {
      [NSException raise: NSInvalidArgumentException
	format: @"%@ - Illegal pad string", NSStringFromSelector(_cmd)];
    }
  padLength = [padString length];
  if (padIndex >= padLength)
    {
      [NSException raise: NSRangeException
	format: @"%@ - pad index larger too big", NSStringFromSelector(_cmd)];
    }
  if (newLength == length)
    {
      return IMMUTABLE(self);
    }
  else if (newLength < length)
    {
      return [self substringToIndex: newLength];
    }
  else
    {
      length = newLength - length;	// What we want to add.
      if (length <= (padLength - padIndex))
	{
	  NSRange	r;

	  r = NSMakeRange(padIndex, length);
	  return [self stringByAppendingString:
	    [padString substringWithRange: r]];
	}
      else
	{
	  NSMutableString	*m = [self mutableCopy];

	  if (padIndex > 0)
	    {
	      NSRange	r;

	      r = NSMakeRange(padIndex, padLength - padIndex);
	      [m appendString: [padString substringWithRange: r]];
	      length -= r.length;
	    }
	  /*
	   * In case we have to append a small string lots of times,
	   * we cache the method impllementation to do it.
	   */
	  if (length >= padLength)
	    {
	      void	(*appImp)(NSMutableString*, SEL, NSString*);
	      SEL	appSel;

	      appSel = @selector(appendString:);
	      appImp = (void (*)(NSMutableString*, SEL, NSString*))
		[m methodForSelector: appSel];
	      while (length >= padLength)
		{
		  (*appImp)(m, appSel, padString);
		  length -= padLength;
		}
	    }
	  if (length > 0)
	    {
	      [m appendString:
		[padString substringWithRange: NSMakeRange(0, length)]];
	    }
	  return AUTORELEASE(m);
	}
    }
}

/**
 * Returns a string created by replacing percent escape sequences in the
 * receiver assuming that the resulting data represents characters in
 * the specified encoding.<br />
 * Returns nil if the result is not a string in the specified encoding.
 */
- (NSString*) stringByReplacingPercentEscapesUsingEncoding: (NSStringEncoding)e
{
  NSMutableData	*d;
  NSString	*s = nil;

  d = [[self dataUsingEncoding: NSASCIIStringEncoding] mutableCopy];
  if (d != nil)
    {
      unsigned char	*p = (unsigned char*)[d mutableBytes];
      unsigned		l = [d length];
      unsigned		i = 0;
      unsigned		j = 0;

      while (i < l)
	{
	  unsigned char	t;

	  if ((t = p[i++]) == '%')
	    {
	      unsigned char	c;

	      if (i >= l)
		{
		  DESTROY(d);
		  break;
		}
	      t = p[i++];

	      if (isxdigit(t))
		{
		  if (t <= '9')
		    {
		      c = t - '0';
		    }
		  else if (t <= 'A')
		    {
		      c = t - 'A' + 10;
		    }
		  else
		    {
		      c = t - 'a' + 10;
		    }
		}
	      else
		{
		  DESTROY(d);
		  break;
		}
	      c <<= 4;

	      if (i >= l)
		{
		  DESTROY(d);
		  break;
		}
	      t = p[i++];
	      if (isxdigit(t))
		{
		  if (t <= '9')
		    {
		      c |= t - '0';
		    }
		  else if (t <= 'A')
		    {
		      c |= t - 'A' + 10;
		    }
		  else
		    {
		      c |= t - 'a' + 10;
		    }
		}
	      else
		{
		  DESTROY(d);
		  break;
		}
	      p[j++] = c;
	    }
	  else
	    {
	      p[j++] = t;
	    }
	}
      [d setLength: j];
      s = AUTORELEASE([[NSString alloc] initWithData: d encoding: e]);
      RELEASE(d);
    }
  return s;
}

- (NSString*) stringByResolvingSymlinksInPath
{
#if defined(__MINGW32__)
  return IMMUTABLE(self);
#else
  #ifndef PATH_MAX
  #define PATH_MAX 1024
  /* Don't use realpath unless we know we have the correct path size limit */
  #ifdef        HAVE_REALPATH
  #undef        HAVE_REALPATH
  #endif
  #endif
  char		newBuf[PATH_MAX];
#ifdef HAVE_REALPATH

  if (realpath([self fileSystemRepresentation], newBuf) == 0)
    return IMMUTABLE(self);
#else
  char		extra[PATH_MAX];
  char		*dest;
  const char	*name = [self fileSystemRepresentation];
  const char	*start;
  const	char	*end;
  unsigned	num_links = 0;

  if (name[0] != '/')
    {
      if (!getcwd(newBuf, PATH_MAX))
	{
	  return IMMUTABLE(self);	/* Couldn't get directory.	*/
	}
      dest = strchr(newBuf, '\0');
    }
  else
    {
      newBuf[0] = '/';
      dest = &newBuf[1];
    }

  for (start = end = name; *start; start = end)
    {
      struct stat	st;
      int		n;
      int		len;

      /* Elide repeated path separators	*/
      while (*start == '/')
	{
	  start++;
	}
      /* Locate end of path component	*/
      end = start;
      while (*end && *end != '/')
	{
	  end++;
	}
      len = end - start;
      if (len == 0)
	{
	  break;	/* End of path.	*/
	}
      else if (len == 1 && *start == '.')
	{
          /* Elide '/./' sequence by ignoring it.	*/
	}
      else if (len == 2 && strncmp(start, "..", len) == 0)
	{
	  /*
	   * Backup - if we are not at the root, remove the last component.
	   */
	  if (dest > &newBuf[1])
	    {
	      do
		{
		  dest--;
		}
	      while (dest[-1] != '/');
	    }
	}
      else
        {
          if (dest[-1] != '/')
	    {
	      *dest++ = '/';
	    }
          if (&dest[len] >= &newBuf[PATH_MAX])
	    {
	      return IMMUTABLE(self);	/* Resolved name too long.	*/
	    }
          memcpy(dest, start, len);
          dest += len;
          *dest = '\0';

          if (lstat(newBuf, &st) < 0)
	    {
	      return IMMUTABLE(self);	/* Unable to stat file.		*/
	    }
          if (S_ISLNK(st.st_mode))
            {
              char buf[PATH_MAX];

              if (++num_links > MAXSYMLINKS)
		{
		  return IMMUTABLE(self);	/* Too many links.	*/
		}
              n = readlink(newBuf, buf, PATH_MAX);
              if (n < 0)
		{
		  return IMMUTABLE(self);	/* Couldn't resolve.	*/
		}
              buf[n] = '\0';

              if ((n + strlen(end)) >= PATH_MAX)
		{
		  return IMMUTABLE(self);	/* Path too long.	*/
		}
	      /*
	       * Concatenate the resolved name with the string still to
	       * be processed, and start using the result as input.
	       */
              strcat(buf, end);
              strcpy(extra, buf);
              name = end = extra;

              if (buf[0] == '/')
		{
		  /*
		   * For an absolute link, we start at root again.
		   */
		  dest = newBuf + 1;
		}
              else
		{
		  /*
		   * Backup - remove the last component.
		   */
		  if (dest > newBuf + 1)
		    {
		      do
			{
			  dest--;
			}
		      while (dest[-1] != '/');
		    }
		}
            }
          else
	    {
	      num_links = 0;
	    }
        }
    }
  if (dest > newBuf + 1 && dest[-1] == '/')
    {
      --dest;
    }
  *dest = '\0';
#endif
  if (strncmp(newBuf, "/private/", 9) == 0)
    {
      struct stat	st;

      if (lstat(&newBuf[8], &st) == 0)
	{
	  strcpy(newBuf, &newBuf[8]);
	}
    }
  return [[NSFileManager defaultManager]
   stringWithFileSystemRepresentation: newBuf length: strlen(newBuf)];
#endif  /* (__MINGW32__) */
}

- (NSString*) stringByStandardizingPath
{
  NSMutableString	*s;
  NSRange		r;
  unichar		(*caiImp)(NSString*, SEL, unsigned int);
  unsigned int		l = [self length];
  unichar		c;
  unsigned		root;

  if (l == 0)
    {
      return @"";
    }
  c = [self characterAtIndex: 0];
  if (c == '~')
    {
      s = AUTORELEASE([[self stringByExpandingTildeInPath] mutableCopy]);
    }
  else
    {
      s = AUTORELEASE([self mutableCopy]);
    }

  if (GSPathHandlingUnix() == YES)
    {
      [s replaceString: @"\\" withString: @"/"];
    }
  else if (GSPathHandlingWindows() == YES)
    {
      [s replaceString: @"/" withString: @"\\"];
    }

  l = [s length];
  root = rootOf(s, l);

  caiImp = (unichar (*)())[s methodForSelector: caiSel];

  // Condense multiple separator ('/') sequences.
  r = (NSRange){root, l-root};
  while ((r = [s rangeOfCharacterFromSet: pathSeps()
				 options: 0
				   range: r]).length == 1)
    {
      while (NSMaxRange(r) < l
	&& pathSepMember((*caiImp)(s, caiSel, NSMaxRange(r))) == YES)
	{
	  r.length++;
	}
      r.location++;
      r.length--;
      if (r.length > 0)
	{
	  [s deleteCharactersInRange: r];
	  l -= r.length;
	}
      r.length = l - r.location;
    }
  // Condense ('/./') sequences.
  r = (NSRange){root, l-root};
  while ((r = [s rangeOfString: @"." options: 0 range: r]).length == 1)
    {
      if (r.location > 0
	&& pathSepMember((*caiImp)(s, caiSel, r.location-1)) == YES
        && (NSMaxRange(r) == l
	  || pathSepMember((*caiImp)(s, caiSel, NSMaxRange(r))) == YES))
	{
	  r.length++;
	  [s deleteCharactersInRange: r];
	  l -= r.length;
	}
      else
	{
	  r.location++;
	}
      r.length = l - r.location;
    }

  // Strip trailing '/' if present.
  if (l > root && pathSepMember([s characterAtIndex: l - 1]) == YES)
    {
      r.length = 1;
      r.location = l - r.length;
      [s deleteCharactersInRange: r];
      l -= r.length;
    }

  if ([s isAbsolutePath] == NO)
    {
      return s;
    }

  // Remove leading `/private' if present.
  if ([s hasPrefix: @"/private"])
    {
      [s deleteCharactersInRange: ((NSRange){0,8})];
      l -= 8;
    }

  /*
   *	For absolute paths, we must resolve symbolic links or (on MINGW)
   *	remove '/../' sequences and their matching parent directories.
   */
#if defined(__MINGW32__)
  /* Condense `/../' */
  r = (NSRange){root, l-root};
  while ((r = [s rangeOfString: @".." options: 0 range: r]).length == 2)
    {
      if (r.location > 0
	&& pathSepMember((*caiImp)(s, caiSel, r.location-1)) == YES
        && (NSMaxRange(r) == l
	  || pathSepMember((*caiImp)(s, caiSel, NSMaxRange(r))) == YES))
	{
	  r.location--;
	  r.length++;
	  if (r.location > root)
	    {
	      NSRange r2 = {root, r.location-root};

	      r = [s rangeOfCharacterFromSet: pathSeps()
				     options: NSBackwardsSearch
				       range: r2];
	      if (r.length == 0)
		{
		  r = r2;
		}
	      else
		{
		  r.length = NSMaxRange(r2) - r.location;
		}
	      r.length += 3;		/* Add the `/..' */
	    }
	  [s deleteCharactersInRange: r];
	  l -= r.length;
	}
      else
	{
	  r.location++;
	}
      r.length = l - r.location;
    }

  return IMMUTABLE(s);
#else
  return [s stringByResolvingSymlinksInPath];
#endif
}

/**
 * Return a string formed by removing characters from the ends of the
 * receiver.  Characters are removed only if they are in aSet.<br />
 * If the string consists entirely of characters in aSet, an empty
 * string is returned.<br />
 * The aSet argument must not be nil.<br />
 */
- (NSString*) stringByTrimmingCharactersInSet: (NSCharacterSet*)aSet
{
  unsigned	length = [self length];
  unsigned	end = length;
  unsigned	start = 0;

  if (aSet == nil)
    {
      [NSException raise: NSInvalidArgumentException
	format: @"%@ - nil character set argument", NSStringFromSelector(_cmd)];
    }
  if (length > 0)
    {
      unichar	(*caiImp)(NSString*, SEL, unsigned int);
      BOOL	(*mImp)(id, SEL, unichar);
      unichar	letter;

      caiImp = (unichar (*)())[self methodForSelector: caiSel];
      mImp = (BOOL(*)(id,SEL,unichar)) [aSet methodForSelector: cMemberSel];

      while (end > 0)
	{
	  letter = (*caiImp)(self, caiSel, end-1);
	  if ((*mImp)(aSet, cMemberSel, letter) == NO)
	    {
	      break;
	    }
	  end--;
	}
      while (start < end)
	{
	  letter = (*caiImp)(self, caiSel, start);
	  if ((*mImp)(aSet, cMemberSel, letter) == NO)
	    {
	      break;
	    }
	  start++;
	}
    }
  if (start == 0 && end == length)
    {
      return IMMUTABLE(self);
    }
  if (start == end)
    {
      return @"";
    }
  return [self substringFromRange: NSMakeRange(start, end - start)];
}

// private methods for Unicode level 3 implementation
- (int) _baseLength
{
  int		blen = 0;
  unsigned	len = [self length];

  if (len > 0)
    {
      unsigned int	count = 0;
      unichar	(*caiImp)(NSString*, SEL, unsigned int);

      caiImp = (unichar (*)())[self methodForSelector: caiSel];
      while (count < len)
	{
	  if (!uni_isnonsp((*caiImp)(self, caiSel, count++)))
	    {
	      blen++;
	    }
	}
    }
  return blen;
}

+ (NSString*) pathWithComponents: (NSArray*)components
{
  NSString	*s;
  unsigned	c;
  unsigned	i;

  c = [components count];
  if (c == 0)
    {
      return @"";
    }
  s = [components objectAtIndex: 0];
  if ([s length] == 0)
    {
      s = pathSepString();
    }
  for (i = 1; i < c; i++)
    {
      s = [s stringByAppendingPathComponent: [components objectAtIndex: i]];
    }
  return s;
}

- (BOOL) isAbsolutePath
{
  unichar	c;
  unsigned	l = [self length];
  unsigned	root;

  if (l == 0)
    {
      return NO;		// Empty string ... relative
    }
  c = [self characterAtIndex: 0];
  if (c == (unichar)'~')
    {
      return YES;		// Begins with tilde ... absolute
    }

  /*
   * Any string beginning with '/' is absolute ... except in windows mode
   * or on windows and not in unix mode.
   */
  if (c == pathSepChar())
    {
#if defined(__MINGW32__)
      if (GSPathHandlingUnix() == YES)
	{
	  return YES;
	}
#else
      if (GSPathHandlingWindows() == NO)
	{
	  return YES;
	}
#endif
     }

  /*
   * Any root over two characters long must be a drive specification with a
   * slash (absolute) or a UNC path (always absolute).
   */
  root = rootOf(self, l);
  if (root > 2)
    {
      return YES;		// UNC or C:/ ... absolute
    }

  /*
   * What we have left are roots of the form 'C:' or '\' or a path
   * with no root, or a '/' (in windows mode only sence we already
   * handled a single slash in unix mode) ...
   * all these cases are relative paths.
   */
  return NO;
}

- (NSArray*) pathComponents
{
  NSMutableArray	*a;
  NSArray		*r;
  NSString		*s = self;
  unsigned int		l = [s length];
  unsigned int		root;
  unsigned int		i;
  NSRange		range;

  if (l == 0)
    {
      return [NSArray array];
    }
  root = rootOf(s, l);
  a = [[NSMutableArray alloc] initWithCapacity: 8];
  if (root > 0)
    {
      [a addObject: [s substringToIndex: root]];
    }
  i = root;

  while (i < l)
    {
      range = [s rangeOfCharacterFromSet: pathSeps()
				 options: NSLiteralSearch
				   range: ((NSRange){i, l - i})];
      if (range.length > 0)
	{
	  if (range.location > i)
	    {
	      [a addObject: [s substringWithRange:
		NSMakeRange(i, range.location - i)]];
	    }
	  i = NSMaxRange(range);
	}
      else
	{
	  [a addObject: [s substringFromIndex: i]];
	  i = l;
	}
    }

  /*
   * If the path ended with a path separator which was not already
   * added as part of the root, add it as final component.
   */
  if (l > root && pathSepMember([s characterAtIndex: l-1]))
    {
      [a addObject: pathSepString()];
    }

  r = [a copy];
  RELEASE(a);
  return AUTORELEASE(r);
}

- (NSArray*) stringsByAppendingPaths: (NSArray*)paths
{
  NSMutableArray	*a;
  NSArray		*r;
  unsigned		i, count = [paths count];

  a = [[NSMutableArray allocWithZone: NSDefaultMallocZone()]
	initWithCapacity: count];
  for (i = 0; i < count; i++)
    {
      NSString	*s = [paths objectAtIndex: i];

      s = [self stringByAppendingPathComponent: s];
      [a addObject: s];
    }
  r = [a copy];
  RELEASE(a);
  return AUTORELEASE(r);
}

/**
 * Returns an autoreleased string with given format using the default locale.
 */
+ (NSString*) localizedStringWithFormat: (NSString*) format, ...
{
  va_list ap;
  id ret;

  va_start(ap, format);
  if (format == nil)
    {
      ret = nil;
    }
  else
    {
      ret = AUTORELEASE([[self allocWithZone: NSDefaultMallocZone()]
        initWithFormat: format locale: GSPrivateDefaultLocale() arguments: ap]);
    }
  va_end(ap);
  return ret;
}

/**
 * Compares this string with aString ignoring case.  Convenience for
 * -compare:options:range: with the <code>NSCaseInsensitiveSearch</code>
 * option, in the default locale.
 */
- (NSComparisonResult) caseInsensitiveCompare: (NSString*)aString
{
  return [self compare: aString
	       options: NSCaseInsensitiveSearch
		 range: ((NSRange){0, [self length]})];
}

/**
 * <p>Compares this instance with string, using rules in locale given by dict.
 * mask may be either <code>NSCaseInsensitiveSearch</code> or
 * <code>NSLiteralSearch</code>.  The latter requests a literal byte-by-byte
 * comparison, which is fastest but may return inaccurate results in cases
 * where two different composed character sequences may be used to express
 * the same character.  compareRange refers to this instance, and should be
 * set to 0..length to compare the whole string.</p>
 *
 * <p>Returns <code>NSOrderedAscending</code>, <code>NSOrderedDescending</code>,
 * or <code>NSOrderedSame</code>, depending on whether this instance occurs
 * before or after string in lexical order, or is equal to it.</p>
 *
 * <p><em><strong>Warning:</strong> this implementation and others in NSString
 * IGNORE the locale.</em></p>
 */
- (NSComparisonResult) compare: (NSString *)string
		       options: (unsigned int)mask
			 range: (NSRange)compareRange
			locale: (NSDictionary *)dict
{
  // FIXME: This does only a normal compare, ignoring locale
  return [self compare: string
	       options: mask
		 range: compareRange];
}

/**
 * Compares this instance with string, using rules in the default locale.
 */
- (NSComparisonResult) localizedCompare: (NSString *)string
{
  return [self compare: string
               options: 0
                 range: ((NSRange){0, [self length]})
                locale: GSPrivateDefaultLocale()];
}

/**
 * Compares this instance with string, using rules in the default locale,
 * ignoring case.
 */
- (NSComparisonResult) localizedCaseInsensitiveCompare: (NSString *)string
{
  return [self compare: string
               options: NSCaseInsensitiveSearch
                 range: ((NSRange){0, [self length]})
                locale: GSPrivateDefaultLocale()];
}

/**
 * Writes contents out to file at filename, using the default C string encoding
 * unless this would result in information loss, otherwise straight unicode.
 * The '<code>atomically</code>' option if set will cause the contents to be
 * written to a temp file, which is then closed and renamed to filename.  Thus,
 * an incomplete file at filename should never result.
 */
- (BOOL) writeToFile: (NSString*)filename
	  atomically: (BOOL)useAuxiliaryFile
{
  id	d = [self dataUsingEncoding: _DefaultStringEncoding];

  if (d == nil)
    {
      d = [self dataUsingEncoding: NSUnicodeStringEncoding];
    }
  return [d writeToFile: filename atomically: useAuxiliaryFile];
}

/**
 * Writes contents out to anURL, using the default C string encoding
 * unless this would result in information loss, otherwise straight unicode.
 * See [NSURLHandle-writeData:] on which URL types are supported.
 * The '<code>atomically</code>' option is only heeded if the URL is a
 * <code>file://</code> URL; see -writeToFile:atomically: .
 */
- (BOOL) writeToURL: (NSURL*)anURL atomically: (BOOL)atomically
{
  id	d = [self dataUsingEncoding: _DefaultStringEncoding];

  if (d == nil)
    {
      d = [self dataUsingEncoding: NSUnicodeStringEncoding];
    }
  return [d writeToURL: anURL atomically: atomically];
}

/* NSCopying Protocol */

- (id) copyWithZone: (NSZone*)zone
{
  /*
   * Default implementation should not simply retain ... the string may
   * have been initialised with freeWhenDone==NO and not own its
   * characters ... so the code which created it may destroy the memory
   * when it has finished with the original string ... leaving the
   * copy with pointers to invalid data.  So, we always copy in full.
   */
  return [[NSStringClass allocWithZone: zone] initWithString: self];
}

- (id) mutableCopyWithZone: (NSZone*)zone
{
  return [[GSMutableStringClass allocWithZone: zone] initWithString: self];
}

/* NSCoding Protocol */

- (void) encodeWithCoder: (NSCoder*)aCoder
{
  if ([aCoder allowsKeyedCoding])
    {
      [(NSKeyedArchiver*)aCoder _encodePropertyList: self forKey: @"NS.string"];
    }
  else
    {
      unsigned	count = [self length];

      [aCoder encodeValueOfObjCType: @encode(unsigned int) at: &count];
      if (count > 0)
	{
	  NSStringEncoding	enc = NSUnicodeStringEncoding;
	  unichar		*chars;

	  [aCoder encodeValueOfObjCType: @encode(NSStringEncoding) at: &enc];

	  chars = NSZoneMalloc(NSDefaultMallocZone(), count*sizeof(unichar));
	  [self getCharacters: chars range: ((NSRange){0, count})];
	  [aCoder encodeArrayOfObjCType: @encode(unichar)
				  count: count
				     at: chars];
	  NSZoneFree(NSDefaultMallocZone(), chars);
	}
    }
}

- (id) initWithCoder: (NSCoder*)aCoder
{
  if ([aCoder allowsKeyedCoding])
    {
      NSString *string = (NSString*)[(NSKeyedUnarchiver*)aCoder
			     _decodePropertyListForKey: @"NS.string"];

      self = [self initWithString: string];
    }
  else
    {
      unsigned	count;
	
      [aCoder decodeValueOfObjCType: @encode(unsigned int) at: &count];

      if (count > 0)
        {
	  NSStringEncoding	enc;
	  NSZone		*zone;
	
	  [aCoder decodeValueOfObjCType: @encode(NSStringEncoding) at: &enc];
#if	GS_WITH_GC
	  zone = GSAtomicMallocZone();
#else
	  zone = GSObjCZone(self);
#endif
	
	  if (enc == NSUnicodeStringEncoding)
	    {
	      unichar	*chars;
	
	      chars = NSZoneMalloc(zone, count*sizeof(unichar));
	      [aCoder decodeArrayOfObjCType: @encode(unichar)
		                      count: count
		                         at: chars];
	      self = [self initWithCharactersNoCopy: chars
					     length: count
				       freeWhenDone: YES];
	    }
	  else
	    {
	      unsigned char	*chars;
	
	      chars = NSZoneMalloc(zone, count+1);
	      [aCoder decodeArrayOfObjCType: @encode(unsigned char)
		                      count: count
				         at: chars];
	      self = [self initWithBytesNoCopy: chars
					length: count
				      encoding: enc
				  freeWhenDone: YES];
	    }
	}
      else
        {
	  self = [self initWithBytesNoCopy: ""
				    length: 0
			          encoding: NSASCIIStringEncoding
			      freeWhenDone: NO];
	}
    }
  return self;
}

- (Class) classForCoder
{
  return NSStringClass;
}

- (id) replacementObjectForPortCoder: (NSPortCoder*)aCoder
{
  if ([aCoder isByref] == NO)
    return self;
  return [super replacementObjectForPortCoder: aCoder];
}

/**
 * <p>Attempts to interpret the receiver as a <em>property list</em>
 * and returns the result.  If the receiver does not contain a
 * string representation of a <em>property list</em> then the method
 * returns nil.
 * </p>
 * <p>Containers (arrays and dictionaries) are decoded as <em>mutable</em>
 * objects.
 * </p>
 * <p>There are three readable <em>property list</em> storage formats -
 * The binary format used by [NSSerializer] does not concern us here,
 * but there are two 'human readable' formats, the <em>traditional</em>
 * OpenStep format (which is extended in GNUstep) and the <em>XML</em> format.
 * </p>
 * <p>The [NSArray-descriptionWithLocale:indent:] and
 * [NSDictionary-descriptionWithLocale:indent:] methods
 * both generate strings containing traditional style <em>property lists</em>,
 * but [NSArray-writeToFile:atomically:] and
 * [NSDictionary-writeToFile:atomically:] generate either traditional or
 * XML style <em>property lists</em> depending on the value of the
 * GSMacOSXCompatible and NSWriteOldStylePropertyLists user defaults.<br />
 * If GSMacOSXCompatible is YES then XML <em>property lists</em> are
 * written unless NSWriteOldStylePropertyLists is also YES.<br />
 * By default GNUstep writes old style data and always supports reading of
 * either style.
 * </p>
 * <p>The traditional format is more compact and more easily readable by
 * people, but (without the GNUstep extensions) cannot represent date and
 * number objects (except as strings).  The XML format is more verbose and
 * less readable, but can be fed into modern XML tools and thus used to
 * pass data to non-OpenStep applications more readily.
 * </p>
 * <p>The traditional format is strictly ascii encoded, with any unicode
 * characters represented by escape sequences.  The XML format is encoded
 * as UTF8 data.
 * </p>
 * <p>Both the traditional format and the XML format permit comments to be
 * placed in <em>property list</em> documents.  In traditional format the
 * comment notations used in Objective-C programming are supported, while
 * in XML format, the standard SGML comment sequences are used.
 * </p>
 * <p>See the documentation for [NSPropertyListSerialization] for more
 * information on what a property list is.
 * </p>
 * <p>If the string cannot be parsed as a normal property list format,
 * this method also tries to parse it as 'strings file' format (see the
 * -propertyListFromStringsFileFormat method).
 * </p>
 */
- (id) propertyList
{
  NSData		*data;
  id			result = nil;
  NSPropertyListFormat	format;
  NSString		*error = nil;

  if ([self length] == 0)
    {
      return nil;
    }
  data = [self dataUsingEncoding: NSUTF8StringEncoding];
  NSAssert(data, @"Couldn't get utf8 data from string.");

  result = [NSPropertyListSerialization
    propertyListFromData: data
    mutabilityOption: NSPropertyListMutableContainers
    format: &format
    errorDescription: &error];

  if (result == nil)
    {
      extern id	GSPropertyListFromStringsFormat(NSString *string);

      NS_DURING
        {
          result = GSPropertyListFromStringsFormat(self);
        }
      NS_HANDLER
        {
          result = nil;
        }
      NS_ENDHANDLER
      if (result == nil)
        {
          [NSException raise: NSGenericException
                      format: @"Parse failed  - %@", error];
        }
    }
  return result;
}

/**
 * <p>Reads a <em>property list</em> (see -propertyList) from a simplified
 * file format.  This format is a traditional style property list file
 * containing a single dictionary, but with the leading '{' and trailing
 * '}' characters omitted.
 * </p>
 * <p>That is to say, the file contains only semicolon separated key/value
 * pairs (and optionally comments).  As a convenience, it is possible to
 * omit the equals sign and the value, so an entry consists of a key string
 * followed by a semicolon.  In this case, the value for that key is
 * assumed to be an empty string.
 * </p>
 * <example>
 *   // Strings file entries follow -
 *   key1 = " a string value";
 *   key2;	// This key has an empty string as a value.
 *   "Another key" = "a longer string value for th third key";
 * </example>
 */
- (NSDictionary*) propertyListFromStringsFileFormat
{
  extern id	GSPropertyListFromStringsFormat(NSString *string);

  return GSPropertyListFromStringsFormat(self);
}

@end

/**
 * This is the mutable form of the [NSString] class.
 */
@implementation NSMutableString

+ (id) allocWithZone: (NSZone*)z
{
  if (self == NSMutableStringClass)
    {
      return NSAllocateObject(GSMutableStringClass, 0, z);
    }
  else
    {
      return NSAllocateObject(self, 0, z);
    }
}

// Creating Temporary Strings

/**
 * Constructs an empty string.
 */
+ (id) string
{
  return AUTORELEASE([[GSMutableStringClass allocWithZone:
    NSDefaultMallocZone()] initWithCapacity: 0]);
}

/**
 * Constructs an empty string with initial buffer size of capacity.
 */
+ (NSMutableString*) stringWithCapacity: (unsigned int)capacity
{
  return AUTORELEASE([[GSMutableStringClass allocWithZone:
    NSDefaultMallocZone()] initWithCapacity: capacity]);
}

/**
 * Create a string of unicode characters.
 */
// Inefficient implementation.
+ (id) stringWithCharacters: (const unichar*)characters
		     length: (unsigned int)length
{
  return AUTORELEASE([[GSMutableStringClass allocWithZone:
    NSDefaultMallocZone()] initWithCharacters: characters length: length]);
}

/**
 * Load contents of file at path into a new string.  Will interpret file as
 * containing direct unicode if it begins with the unicode byte order mark,
 * else converts to unicode using default C string encoding.
 */
+ (id) stringWithContentsOfFile: (NSString *)path
{
  return AUTORELEASE([[GSMutableStringClass allocWithZone:
    NSDefaultMallocZone()] initWithContentsOfFile: path]);
}

/**
 * Create a string based on the given C (char[]) string, which should be
 * null-terminated and encoded in the default C string encoding.  (Characters
 * will be converted to unicode representation internally.)
 */
+ (id) stringWithCString: (const char*)byteString
{
  return AUTORELEASE([[GSMutableStringClass allocWithZone:
    NSDefaultMallocZone()] initWithCString: byteString]);
}

/**
 * Create a string based on the given C (char[]) string, which may contain
 * null bytes and should be encoded in the default C string encoding.
 * (Characters will be converted to unicode representation internally.)
 */
+ (id) stringWithCString: (const char*)byteString
		  length: (unsigned int)length
{
  return AUTORELEASE([[GSMutableStringClass allocWithZone:
    NSDefaultMallocZone()] initWithCString: byteString length: length]);
}

/**
 * Creates a new string using C printf-style formatting.  First argument should
 * be a constant format string, like '<code>@"float val = %f"</code>', remaining
 * arguments should be the variables to print the values of, comma-separated.
 */
+ (id) stringWithFormat: (NSString*)format, ...
{
  va_list ap;
  va_start(ap, format);
  self = [super stringWithFormat: format arguments: ap];
  va_end(ap);
  return self;
}

/** <init/> <override-subclass />
 * Constructs an empty string with initial buffer size of capacity.<br />
 * Calls -init (which does nothing but maintain MacOS-X compatibility),
 * and needs to be re-implemented in subclasses in order to have all
 * other initialisers work.
 */
- (id) initWithCapacity: (unsigned int)capacity
{
  self = [self init];
  return self;
}

- (id) initWithCharactersNoCopy: (unichar*)chars
			 length: (unsigned int)length
		   freeWhenDone: (BOOL)flag
{
  if ((self = [self initWithCapacity: length]) != nil && length > 0)
    {
      NSString	*tmp;

      tmp = [NSString allocWithZone: NSDefaultMallocZone()];
      tmp = [tmp initWithCharactersNoCopy: chars
				   length: length
			     freeWhenDone: flag];
      [self replaceCharactersInRange: NSMakeRange(0,0) withString: tmp];
      RELEASE(tmp);
    }
  return self;
}

- (id) initWithCStringNoCopy: (char*)chars
		      length: (unsigned int)length
		freeWhenDone: (BOOL)flag
{
  if ((self = [self initWithCapacity: length]) != nil && length > 0)
    {
      NSString	*tmp;

      tmp = [NSString allocWithZone: NSDefaultMallocZone()];
      tmp = [tmp initWithCStringNoCopy: chars
				length: length
			  freeWhenDone: flag];
      [self replaceCharactersInRange: NSMakeRange(0,0) withString: tmp];
      RELEASE(tmp);
    }
  return self;
}

// Modify A String

/**
 *  Modifies this string by appending aString.
 */
- (void) appendString: (NSString*)aString
{
  NSRange aRange;

  aRange.location = [self length];
  aRange.length = 0;
  [self replaceCharactersInRange: aRange withString: aString];
}

/**
 *  Modifies this string by appending string described by given format.
 */
// Inefficient implementation.
- (void) appendFormat: (NSString*)format, ...
{
  va_list	ap;
  id		tmp;

  va_start(ap, format);
  tmp = [[NSStringClass allocWithZone: NSDefaultMallocZone()]
    initWithFormat: format arguments: ap];
  va_end(ap);
  [self appendString: tmp];
  RELEASE(tmp);
}

- (Class) classForCoder
{
  return NSMutableStringClass;
}

/**
 * Modifies this instance by deleting specified range of characters.
 */
- (void) deleteCharactersInRange: (NSRange)range
{
  [self replaceCharactersInRange: range withString: nil];
}

/**
 * Modifies this instance by inserting aString at loc.
 */
- (void) insertString: (NSString*)aString atIndex: (unsigned int)loc
{
  NSRange range = {loc, 0};
  [self replaceCharactersInRange: range withString: aString];
}

/**
 * Modifies this instance by deleting characters in range and then inserting
 * aString at its beginning.
 */
- (void) replaceCharactersInRange: (NSRange)range
		       withString: (NSString*)aString
{
  [self subclassResponsibility: _cmd];
}

/**
 * Replaces all occurrences of the replace string with the by string,
 * for those cases where the entire replace string lies within the
 * specified searchRange value.<br />
 * The value of opts determines the direction of the search is and
 * whether only leading/trailing occurrences (anchored search) of
 * replace are substituted.<br />
 * Raises NSInvalidArgumentException if either string argument is nil.<br />
 * Raises NSRangeException if part of searchRange is beyond the end
 * of the receiver.
 */
- (unsigned int) replaceOccurrencesOfString: (NSString*)replace
				 withString: (NSString*)by
				    options: (unsigned int)opts
				      range: (NSRange)searchRange
{
  NSRange	range;
  unsigned int	count = 0;
  GSRSFunc	func;

  if ([replace isKindOfClass: NSStringClass] == NO)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"%@ bad search string", NSStringFromSelector(_cmd)];
    }
  if ([by isKindOfClass: NSStringClass] == NO)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"%@ bad replace string", NSStringFromSelector(_cmd)];
    }
  if (NSMaxRange(searchRange) > [self length])
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"%@ bad search range", NSStringFromSelector(_cmd)];
    }
  func = GSPrivateRangeOfString(self, replace);
  range = (*func)(self, replace, opts, searchRange);

  if (range.length > 0)
    {
      unsigned	byLen = [by length];
      SEL	sel;
      void	(*imp)(id, SEL, NSRange, NSString*);

      sel = @selector(replaceCharactersInRange:withString:);
      imp = (void(*)(id, SEL, NSRange, NSString*))[self methodForSelector: sel];
      do
	{
	  count++;
	  (*imp)(self, sel, range, by);
	  if ((opts & NSBackwardsSearch) == NSBackwardsSearch)
	    {
	      searchRange.length = range.location - searchRange.location;
	    }
	  else
	    {
	      unsigned int	newEnd;

	      newEnd = NSMaxRange(searchRange) + byLen - range.length;
	      searchRange.location = range.location + byLen;
	      searchRange.length = newEnd - searchRange.location;
	    }

	  range = (*func)(self, replace, opts, searchRange);
	}
      while (range.length > 0);
    }
  return count;
}

/**
 * Modifies this instance by replacing contents with those of aString.
 */
- (void) setString: (NSString*)aString
{
  NSRange range = {0, [self length]};
  [self replaceCharactersInRange: range withString: aString];
}

@end


/**
 * GNUstep specific (non-standard) additions to the NSMutableString class.
 * The methods in this category are not available in MacOS-X
 */
@implementation NSMutableString (GNUstep)

/**
 * Returns a proxy to the receiver which will allow access to the
 * receiver as an NSString, but which will not allow any of the
 * extra NSMutableString methods to be used.  You can use this method
 * to provide other code with read-only access to a mutable string
 * you own.
 */
- (NSString*) immutableProxy
{
  if ([self isKindOfClass: GSMutableStringClass])
    {
      return AUTORELEASE([[GSImmutableString alloc] initWithString: self]);
    }
  else
    {
      return AUTORELEASE([[NSImmutableString alloc] initWithString: self]);
    }
}

@end

