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
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Library General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.

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

#include "config.h"
#include <stdio.h>
#include <string.h>
#include "GNUstepBase/preface.h"
#include "Foundation/NSAutoreleasePool.h"
#include "Foundation/NSString.h"
#include "Foundation/NSCalendarDate.h"
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
#include "Foundation/NSUserDefaults.h"
#include "Foundation/NSDebug.h"
// For private method _decodePropertyListForKey:
#include "Foundation/NSKeyedArchiver.h"
#include "GNUstepBase/GSMime.h"
#include "GSFormat.h"
#include <limits.h>
#include <sys/stat.h>
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#include <sys/types.h>
#include <fcntl.h>
#include <stdio.h>

#include "GNUstepBase/Unicode.h"

#include "GSPrivate.h"

extern BOOL GSScanDouble(unichar*, unsigned, double*);

@class	GSString;
@class	GSMutableString;
@class	GSPlaceholderString;
@class	GSMutableArray;
@class	GSMutableDictionary;


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

static Class	plArray;
static id	(*plAdd)(id, SEL, id) = 0;

static Class	plDictionary;
static id	(*plSet)(id, SEL, id, id) = 0;

static id	(*plAlloc)(Class, SEL, NSZone*) = 0;
static id	(*plInit)(id, SEL, unichar*, unsigned int) = 0;

static SEL	plSel;
static SEL	cMemberSel = 0;


#define IS_BIT_SET(a,i) ((((a) & (1<<(i)))) > 0)

static unsigned const char *hexdigitsBitmapRep = NULL;
#define GS_IS_HEXDIGIT(X) IS_BIT_SET(hexdigitsBitmapRep[(X)/8], (X) % 8)

static void setupHexdigits(void)
{
  if (hexdigitsBitmapRep == NULL)
    {
      NSCharacterSet *hexdigits;
      NSData *bitmap;

      hexdigits = [NSCharacterSet characterSetWithCharactersInString:
	@"0123456789abcdefABCDEF"];
      bitmap = RETAIN([hexdigits bitmapRepresentation]);
      hexdigitsBitmapRep = [bitmap bytes];
    }
}

static NSCharacterSet *quotables = nil;
static NSCharacterSet *oldQuotables = nil;
static unsigned const char *quotablesBitmapRep = NULL;
#define GS_IS_QUOTABLE(X) IS_BIT_SET(quotablesBitmapRep[(X)/8], (X) % 8)

static void setupQuotables(void)
{
  if (quotablesBitmapRep == NULL)
    {
      NSMutableCharacterSet	*s;
      NSData			*bitmap;

      s = [[NSCharacterSet characterSetWithCharactersInString:
	@"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	@"abcdefghijklmnopqrstuvwxyz!#$%&*+-./:?@|~_^"]
	mutableCopy];
      [s invert];
      quotables = [s copy];
      RELEASE(s);
      bitmap = RETAIN([quotables bitmapRepresentation]);
      quotablesBitmapRep = [bitmap bytes];
      s = [[NSCharacterSet characterSetWithCharactersInString:
	@"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	@"abcdefghijklmnopqrstuvwxyz$./_"]
	mutableCopy];
      [s invert];
      oldQuotables = [s copy];
      RELEASE(s);
    }
}

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


static id	GSPropertyList(NSString *string);
static id	GSPropertyListFromStringsFormat(NSString *string);

static NSCharacterSet	*myPathSeps = nil;
/*
 * The pathSeps character set is used for parsing paths ... it *must*
 * contain the '/' character, which is the internal path separator,
 * and *may* contain additiona system specific separators.
 *
 * We can't have a 'pathSeps' variable initialized in the +initialize
 * method 'cos that would cause recursion.
 */
static NSCharacterSet*
pathSeps(void)
{
  if (myPathSeps == nil)
    {
#if defined(__MINGW__)
      myPathSeps = [NSCharacterSet characterSetWithCharactersInString: @"/\\"];
#else
      myPathSeps = [NSCharacterSet characterSetWithCharactersInString: @"/"];
#endif
      IF_NO_GC(RETAIN(myPathSeps));
    }
  return myPathSeps;
}

inline static BOOL
pathSepMember(unichar c)
{

#if defined(__MINGW__)
  if (c == (unichar)'\\' || c == (unichar)'/')
#else
  if (c == (unichar)'/')
#endif
    {
      return YES;
    }
  else
    {
      return NO;
    }
}



/* Convert a high-low surrogate pair into Unicode scalar code-point */
static inline gsu32
surrogatePairValue(unichar high, unichar low)
{
  return ((high - (unichar)0xD800) * (unichar)400)
    + ((low - (unichar)0xDC00) + (unichar)10000);
}


/**
 * <p>
 *   NSString objects represent an immutable string of characters.
 *   NSString itself is an abstract class which provides factory
 *   methods to generate objects of unspecified subclasses.
 * </p>
 * <p>
 *   A constant NSString can be created using the following syntax:
 *   <code>@"..."</code>, where the contents of the quotes are the
 *   string, using only ASCII characters.
 * </p>
 * <p>
 *   To create a concrete subclass of NSString, you must have your
 *   class inherit from NSString and override at least the two
 *   primitive methods - length and characterAtIndex:
 * </p>
 * <p>
 *   In general the rule is that your subclass must override any
 *   initialiser that you want to use with it.  The GNUstep
 *   implementation relaxes that to say that, you may override
 *   only the <em>designated initialiser</em> and the other
 *   initialisation methods should work.
 * </p>
 */
@implementation NSString

static NSStringEncoding _DefaultStringEncoding;
static BOOL		_ByteEncodingOk;
static const unichar byteOrderMark = 0xFEFF;
static const unichar byteOrderMarkSwapped = 0xFFFE;

/* UTF-16 Surrogate Ranges */
static NSRange  highSurrogateRange = {0xD800, 1024};
static NSRange  lowSurrogateRange = {0xDC00, 1024};


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
  len = fprintf(stream, "%*s",
		(info->left ? - info->width : info->width),
		[[string_object description] lossyCString]);
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
      plSel = @selector(initWithCharacters:length:);
      cMemberSel = @selector(characterIsMember:);
      caiSel = @selector(characterAtIndex:);
      gcrSel = @selector(getCharacters:range:);
      ranSel = @selector(rangeOfComposedCharacterSequenceAtIndex:);

      _DefaultStringEncoding = GetDefEncoding();
      _ByteEncodingOk = GSIsByteEncoding(_DefaultStringEncoding);

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
	   * in the default malloc zone extremely efficiently.
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

// Creating Temporary Strings

+ (id) string
{
  return AUTORELEASE([[self allocWithZone: NSDefaultMallocZone()] init]);
}

+ (id) stringWithString: (NSString*)aString
{
  NSString	*obj;

  obj = [self allocWithZone: NSDefaultMallocZone()];
  obj = [obj initWithString: aString];
  return AUTORELEASE(obj);
}

+ (id) stringWithCharacters: (const unichar*)chars
		     length: (unsigned int)length
{
  NSString	*obj;

  obj = [self allocWithZone: NSDefaultMallocZone()];
  obj = [obj initWithCharacters: chars length: length];
  return AUTORELEASE(obj);
}

+ (id) stringWithCString: (const char*) byteString
{
  NSString	*obj;
  unsigned	length = byteString ? strlen(byteString) : 0;

  obj = [self allocWithZone: NSDefaultMallocZone()];
  obj = [obj initWithCString: byteString length: length];
  return AUTORELEASE(obj);
}

+ (id) stringWithCString: (const char*)byteString
		  length: (unsigned int)length
{
  NSString	*obj;

  obj = [self allocWithZone: NSDefaultMallocZone()];
  obj = [obj initWithCString: byteString length: length];
  return AUTORELEASE(obj);
}

+ (id) stringWithUTF8String: (const char *)bytes
{
  NSString	*obj;

  obj = [self allocWithZone: NSDefaultMallocZone()];
  obj = [obj initWithUTF8String: bytes];
  return AUTORELEASE(obj);
}

+ (id) stringWithContentsOfFile: (NSString *)path
{
  NSString	*obj;

  obj = [self allocWithZone: NSDefaultMallocZone()];
  obj = [obj initWithContentsOfFile: path];
  return AUTORELEASE(obj);
}

+ (id) stringWithContentsOfURL: (NSURL *)url
{
  NSString	*obj;

  obj = [self allocWithZone: NSDefaultMallocZone()];
  obj = [obj initWithContentsOfURL: url];
  return AUTORELEASE(obj);
}

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

// Initializing Newly Allocated Strings

/**
 * Initialises the receiver with a copy of the supplied length of bytes,
 * using the specified encoding.<br />
 * For NSUnicodeStringEncoding and NSUTF8String encoding, a Byte Order
 * Marker (if present at the start of the data) is removed automatically.<br />
 * If the data can not be interpreted using the encoding, the receiver
 * is released and nil is returned.
 */
- (id) initWithBytes: (const void*)bytes
	      length: (unsigned)length
	    encoding: (NSStringEncoding)encoding
{
  if (length == 0)
    {
      self = [self initWithCharactersNoCopy: (unichar*)0
				     length: 0
			       freeWhenDone: NO];
    }
  else if (_ByteEncodingOk == YES
    && (encoding==_DefaultStringEncoding || encoding==NSASCIIStringEncoding))
    {
      self = [self initWithCString: bytes
			    length: length];
    }
  else if (encoding == NSUTF8StringEncoding)
    {
      unsigned char	*b = (unsigned char*)bytes;
      unsigned		i = 0;

      /*
       * If the data begins with the UTF8 Byte Order Marker (as a
       * signature for UTF8 data) we must remove it.
       */
      if (length > 2 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF)
	{
	  length -= 3;
	  bytes += 3;
	}

      if (_ByteEncodingOk)
	{
	  /*
	   * If it's ok to store ascii strings as internal C strings,
	   * check to see if we have in fact got an ascii string.
	   */
	  while (i < length)
	    {
	      if (b[i] > 127)
		{
		  break;
		}
	      i++;
	    }
	}

      if (i == length)
	{
	  self = [self initWithCString: bytes length: length];
	}
      else
	{
	  unichar	*u = 0;
	  unsigned int	l = 0;

	  if (GSToUnicode(&u, &l, bytes, length, NSUTF8StringEncoding,
	    GSObjCZone(self), 0) == NO)
	    {
	      DESTROY(self);
	    }
	  else
	    {
	      self = [self initWithCharactersNoCopy: u
					     length: l
				       freeWhenDone: YES];
	    }
	}
    }
  else if (encoding == NSUnicodeStringEncoding)
    {
      if (length%2 != 0)
	{
	  DESTROY(self);	// Not valid unicode data.
	}
      else
	{
	  BOOL		swapped = NO;
	  unsigned char	*b;
	  unichar	*uptr;

	  b = (unsigned char*)bytes;
	  uptr = (unichar*)b;
	  if (*uptr == byteOrderMark)
	    {
	      b = (unsigned char*)++uptr;
	      length -= sizeof(unichar);
	    }
	  else if (*uptr == byteOrderMarkSwapped)
	    {
	      b = (unsigned char*)++uptr;
	      length -= sizeof(unichar);
	      swapped = YES;
	    }
	  if (length == 0)
	    {
	      self = [self initWithCharactersNoCopy: (unichar*)0
					     length: 0
				       freeWhenDone: NO];
	    }
	  else
	    {
	      unsigned char	*u;

	      u = (unsigned char*)NSZoneMalloc(GSObjCZone(self), length);
	      if (swapped == YES)
		{
		  unsigned	i;

		  for (i = 0; i < length; i += 2)
		    {
		      u[i] = b[i + 1];
		      u[i + 1] = b[i];
		    }
		}
	      else
		{
		  memcpy(u, b, length);
		}
	      self = [self initWithCharactersNoCopy: (unichar*)u
					     length: length/2
				       freeWhenDone: YES];
	    }
	}
    }
  else
    {
      unsigned char	*b;
      unichar		*u = 0;
      unsigned		l = 0;

      b = (unsigned char*)bytes;
      if (GSToUnicode(&u, &l, b, length, encoding, GSObjCZone(self), 0) == NO)
	{
	  DESTROY(self);
	}
      else
	{
	  self = [self initWithCharactersNoCopy: u
					 length: l
				   freeWhenDone: YES];
	}
    }
  return self;
}

/**
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
 */
- (id) initWithBytesNoCopy: (const void*)bytes
		    length: (unsigned)length
		  encoding: (NSStringEncoding)encoding
	      freeWhenDone: (BOOL)flag
{
  BOOL	bytesNeeded = NO;

  if (flag == NO)
    {
      bytesNeeded = YES;
    }

  if (length == 0)
    {
      self = [self initWithCharactersNoCopy: (unichar*)0
				     length: 0
			       freeWhenDone: NO];
    }
  else if (_ByteEncodingOk == YES
    && (encoding==_DefaultStringEncoding || encoding==NSASCIIStringEncoding))
    {
      self = [self initWithCStringNoCopy: (void*)bytes
				  length: length
			    freeWhenDone: YES];
      bytesNeeded = YES;
    }
  else if (encoding == NSUTF8StringEncoding)
    {
      unsigned char	*b =(unsigned char*)bytes;
      unsigned		i = 0;

      /*
       * If the data begins with the UTF8 Byte Order Marker (as a
       * signature for UTF8 data) we must remove it.
       */
      if (length > 2 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF)
	{
	  length -= 3;
	  bytes += 3;
	}

      if (_ByteEncodingOk)
	{
	  /*
	   * If it's ok to store ascii strings as internal C strings,
	   * check to see if we have in fact got an ascii string.
	   */
	  while (i < length)
	    {
	      if (b[i] > 127)
		{
		  break;
		}
	      i++;
	    }
	}

      if (i == length)
	{
	  self = [self initWithCString: bytes length: length];
	}
      else
	{
	  unichar	*u = 0;
	  unsigned int	l = 0;

	  if (GSToUnicode(&u, &l, bytes, length, NSUTF8StringEncoding,
	    GSObjCZone(self), 0) == NO)
	    {
	      DESTROY(self);
	    }
	  else
	    {
	      self = [self initWithCharactersNoCopy: u
					     length: l
				       freeWhenDone: YES];
	    }
	}
    }
  else if (encoding == NSUnicodeStringEncoding)
    {
      if (length%2 != 0)
	{
	  DESTROY(self);	// Not valid unicode data.
	}
      else
	{
	  BOOL		swapped = NO;
	  BOOL		copy = NO;
	  unsigned char	*b;
	  unichar	*uptr;

	  b = (unsigned char*)bytes;
	  uptr = (unichar*)b;
	  if (*uptr == byteOrderMark)
	    {
	      b = (unsigned char*)++uptr;
	      length -= sizeof(unichar);
	      copy = YES;
	      flag = YES;
	    }
	  else if (*uptr == byteOrderMarkSwapped)
	    {
	      b = (unsigned char*)++uptr;
	      length -= sizeof(unichar);
	      swapped = YES;
	      copy = YES;
	      flag = YES;
	    }
	  if (length == 0)
	    {
	      self = [self initWithCharactersNoCopy: (unichar*)0
					     length: 0
				       freeWhenDone: NO];
	    }
	  else
	    {
	      unsigned char	*u;

	      if (copy == YES)
		{
		  u = (unsigned char*)NSZoneMalloc(GSObjCZone(self), length);
		  if (swapped == YES)
		    {
		      unsigned	i;

		      for (i = 0; i < length; i += 2)
			{
			  u[i] = b[i + 1];
			  u[i + 1] = b[i];
			}
		    }
		  else
		    {
		      memcpy(u, b, length);
		    }
		}
	      else
		{
		  u = (unsigned char *)bytes;
		  bytesNeeded = YES;
		}
	      self = [self initWithCharactersNoCopy: (unichar*)u
					     length: length/2
				       freeWhenDone: flag];
	    }
	}
    }
  else
    {
      unsigned char	*b;
      unichar		*u = 0;
      unsigned		l = 0;

      b = (unsigned char*)bytes;
      if (GSToUnicode(&u, &l, b, length, encoding, GSObjCZone(self), 0) == NO)
	{
	  DESTROY(self);
	}
      else
	{
	  self = [self initWithCharactersNoCopy: u
					 length: l
				   freeWhenDone: YES];
	}
    }
  if (bytesNeeded == NO && bytes != 0)
    {
      NSZoneFree(NSZoneFromPointer((void*)bytes), (void*)bytes);
    }
  return self;
}

/** <init />
 * This is the most basic initialiser for unicode strings.
 * In the GNUstep implementation, your subclasses may override
 * this initialiser in order to have all others function.
 */
- (id) initWithCharactersNoCopy: (unichar*)chars
			 length: (unsigned int)length
		   freeWhenDone: (BOOL)flag
{
  [self subclassResponsibility: _cmd];
  return self;
}

- (id) initWithCharacters: (const unichar*)chars
		   length: (unsigned int)length
{
  if (length > 0)
    {
      unsigned int	i;
      BOOL		isAscii = YES;

      if (chars == 0)
	{
	  [NSException raise: NSInvalidArgumentException
		      format: @"null pointer but non-zero length"];
	}
      for (i = 0; i < length; i++)
	{
	  if (chars[i] >= 128)
	    {
	      isAscii = NO;
	      break;
	    }
	}
      if (isAscii == YES)
	{
	  char	*s;

	  s = NSZoneMalloc(GSObjCZone(self), length);

	  for (i = 0; i < length; i++)
	    {
	      s[i] = (unsigned char)chars[i];
	    }
	  self = [self initWithCStringNoCopy: s
				      length: length
				freeWhenDone: YES];
	}
      else
	{
	  unichar	*s;

	  s = NSZoneMalloc(GSObjCZone(self), sizeof(unichar)*length);

	  memcpy(s, chars, sizeof(unichar)*length);
	  self = [self initWithCharactersNoCopy: s
					 length: length
				   freeWhenDone: YES];
	}
    }
  else
    {
      self = [self initWithCharactersNoCopy: (unichar*)0
				     length: 0
			       freeWhenDone: NO];
    }

  return self;
}

- (id) initWithCStringNoCopy: (char*)byteString
		      length: (unsigned int)length
		freeWhenDone: (BOOL)flag
{
  unichar	*buf = 0;
  unsigned int	l = 0;

  if (GSToUnicode(&buf, &l, byteString, length, _DefaultStringEncoding,
    [self zone], 0) == NO)
    {
      DESTROY(self);
    }
  else
    {
      if (flag == YES && byteString != 0)
	{
	  NSZoneFree(NSZoneFromPointer(byteString), byteString);
	}
      self = [self initWithCharactersNoCopy: buf length: l freeWhenDone: YES];
    }
  return self;
}

- (id) initWithCString: (const char*)byteString  length: (unsigned int)length
{
  if (length > 0)
    {
      char	*s = NSZoneMalloc(GSObjCZone(self), length);

      if (byteString != 0)
	{
	  memcpy(s, byteString, length);
	}
      self = [self initWithCStringNoCopy: s length: length freeWhenDone: YES];
    }
  else
    {
      self = [self initWithCStringNoCopy: 0 length: 0 freeWhenDone: NO];
    }

  return self;
}

- (id) initWithCString: (const char*)byteString
{
  return [self initWithCString: byteString
    length: (byteString ? strlen(byteString) : 0)];
}

- (id) initWithString: (NSString*)string
{
  unsigned	length = [string length];

  if (length > 0)
    {
      unichar	*s = NSZoneMalloc(GSObjCZone(self), sizeof(unichar)*length);

      [string getCharacters: s];
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

- (id) initWithUTF8String: (const char *)bytes
{
  unsigned	length = 0;

  if (bytes == NULL)
    {
      NSDebugMLog(@"bytes is NULL");
    }
  else
    {
      length = strlen(bytes);
    }

  if (length > 0)
    {
      unsigned		i = 0;

      if (_ByteEncodingOk)
	{
	  /*
	   * If it's ok to store ascii strings as internal C strings,
	   * check to see if we have in fact got an ascii string.
	   */
	  while (i < length)
	    {
	      if (((unsigned char*)bytes)[i] > 127)
		{
		  break;
		}
	      i++;
	    }
	}

      if (i == length)
	{
	  self = [self initWithCString: bytes length: length];
	}
      else
	{
	  unichar	*u = 0;
	  unsigned int	l = 0;

	  if (GSToUnicode(&u, &l, bytes, length, NSUTF8StringEncoding,
	    GSObjCZone(self), 0) == NO)
	    {
	      DESTROY(self);
	    }
	  else
	    {
	      self = [self initWithCharactersNoCopy: u
					     length: l
				       freeWhenDone: YES];
	    }
	}
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
  FormatBuf_t	f;
  unichar	*fmt;
  size_t	len;

  len = [format length];
  fmt = objc_malloc((len+1)*sizeof(unichar));
  [format getCharacters: fmt];
  fmt[len] = '\0';
  f.z = NSDefaultMallocZone();
  f.buf = NSZoneMalloc(f.z, 100*sizeof(unichar));
  f.len = 0;
  f.size = 100;
  GSFormat(&f, fmt, argList, locale);
  objc_free(fmt);
  // don't use noCopy because f.size > f.len!
  self = [self initWithCharacters: f.buf length: f.len];
  NSZoneFree(f.z, f.buf);
  return self;
}

#if 0
/* xxx Change this when we have non-CString classes */
- (id) initWithFormat: (NSString*)format
               locale: (NSDictionary*)locale
            arguments: (va_list)argList
{
#if defined(HAVE_VSPRINTF) || defined(HAVE_VASPRINTF)
  const char *format_cp = [format lossyCString];
  int format_len = strlen (format_cp);
#ifdef HAVE_VASPRINTF
  char *buf;
  int printed_len = 0;
  NSString *ret;

#ifndef HAVE_REGISTER_PRINTF_FUNCTION
  NSZone *z = GSObjCZone(self);

  /* If the available libc doesn't have `register_printf_function()', then
     the `%@' printf directive isn't available with printf() and friends.
     Here we make a feable attempt to handle it. */
  {
    /* We need a local copy since we change it.  (Changing and undoing
       the change doesn't work because some format strings are constant
       strings, placed in a non-writable section of the executable, and
       writing to them will cause a segfault.) */
    char format_cp_copy[format_len+1];
    char *atsign_pos;	     /* points to a location inside format_cp_copy */
    char *format_to_go = format_cp_copy;
    char *buf_l;
#define _PRINTF_BUF_LEN 256
    int printed_local_len, avail_len = _PRINTF_BUF_LEN;
    int cstring_len;

    buf = NSZoneMalloc(z, _PRINTF_BUF_LEN);
    strcpy (format_cp_copy, format_cp);
    /* Loop once for each `%@' in the format string. */
    while ((atsign_pos = strstr (format_to_go, "%@")))
      {
        const char *cstring;
        char *formatter_pos; // Position for formatter.

        /* If there is a "%%@", then do the right thing: print it literally. */
        if ((*(atsign_pos-1) == '%')
            && atsign_pos != format_cp_copy)
          continue;
        /* Temporarily terminate the string before the `%@'. */
        *atsign_pos = '\0';
        /* Print the part before the '%@' */
        printed_local_len = VASPRINTF_LENGTH (vasprintf (&buf_l,
	  format_to_go, argList));
        if(buf_l)
          {
            if(avail_len < printed_local_len+1)
              {
                NS_DURING
                  {
                    buf = NSZoneRealloc(z, buf,
		      printed_len+printed_local_len+_PRINTF_BUF_LEN);
                    avail_len += _PRINTF_BUF_LEN;
                  }
                NS_HANDLER
                  {
                    free(buf_l);
                    [localException raise];
                  }
                NS_ENDHANDLER
              }
            memcpy(&buf[printed_len], buf_l, printed_local_len+1);
            avail_len -= printed_local_len;
            printed_len += printed_local_len;
            free(buf_l);
          }
        else
          {
            [NSException raise: NSMallocException
                        format: @"No available memory"];
          }
        /* Skip arguments used in last vsprintf(). */
        while ((formatter_pos = strchr(format_to_go, '%')))
          {
            char *spec_pos; // Position of conversion specifier.

            if (*(formatter_pos+1) == '%')
              {
                format_to_go = formatter_pos+2;
                continue;
              }
            spec_pos = strpbrk(formatter_pos+1, "dioxXucsfeEgGpn\0");
            switch (*spec_pos)
              {
#ifndef powerpc
	      /* FIXME: vsprintf on powerpc apparently advances the arg list
             so this doesn't need to be done. Make a more general check
             for this */
              case 'd': case 'i': case 'o':
              case 'x': case 'X': case 'u': case 'c':
                va_arg(argList, int);
                break;
              case 's':
                if (*(spec_pos - 1) == '*')
                  va_arg(argList, int*);
                va_arg(argList, char*);
                break;
              case 'f': case 'e': case 'E': case 'g': case 'G':
                va_arg(argList, double);
                break;
              case 'p':
                va_arg(argList, void*);
                break;
              case 'n':
                va_arg(argList, int*);
                break;
#endif /* NOT powerpc */
              case '\0':
                spec_pos--;
                break;
              }
            format_to_go = spec_pos+1;
          }
        /* Get a C-string (char*) from the String object, and print it. */
        cstring = [[(id) va_arg (argList, id) description] lossyCString];
        if (!cstring)
          cstring = "<null string>";
        cstring_len = strlen(cstring);

        if(cstring_len)
          {
            if(avail_len < cstring_len+1)
              {
                buf = NSZoneRealloc(z, buf,
                                    printed_len+cstring_len+_PRINTF_BUF_LEN);
                avail_len += _PRINTF_BUF_LEN;
              }
            memcpy(&buf[printed_len], cstring, cstring_len+1);
            avail_len -= cstring_len;
            printed_len += cstring_len;
          }
        /* Skip over this `%@', and look for another one. */
        format_to_go = atsign_pos + 2;
      }
    /* Print the rest of the string after the last `%@'. */
    printed_local_len = VASPRINTF_LENGTH (vasprintf (&buf_l,
      format_to_go, argList));
    if(buf_l)
      {
        if(avail_len < printed_local_len+1)
          {
            NS_DURING
              {
                buf = NSZoneRealloc(z, buf,
		  printed_len+printed_local_len+_PRINTF_BUF_LEN);
                avail_len += _PRINTF_BUF_LEN;
              }
            NS_HANDLER
              {
                free(buf_l);
                [localException raise];
              }
            NS_ENDHANDLER
          }
        memcpy(&buf[printed_len], buf_l, printed_local_len+1);
        avail_len -= printed_local_len;
        printed_len += printed_local_len;
        free(buf_l);
      }
    else
      {
        [NSException raise: NSMallocException
                     format: @"No available memory"];
      }
  }
#else /* HAVE_VSPRINTF */
  /* The available libc has `register_printf_function()', so the `%@'
     printf directive is handled by printf and friends. */
  printed_len = VASPRINTF_LENGTH (vasprintf (&buf, format_cp, argList));

  if(!buf)
    {
      [NSException raise: NSMallocException
                   format: @"No available memory"];
    }
#endif /* !HAVE_REGISTER_PRINTF_FUNCTION */

  ret = [self initWithCString: buf];
#ifndef HAVE_REGISTER_PRINTF_FUNCTION
  NSZoneFree(z, buf);
#else
  free(buf);
#endif
  return ret;
#else
  /* xxx horrible disgusting BUFFER_EXTRA arbitrary limit; fix this! */
  #define BUFFER_EXTRA 1024*500
  char buf[format_len + BUFFER_EXTRA];
  int printed_len = 0;

#ifndef HAVE_REGISTER_PRINTF_FUNCTION
  /* If the available libc doesn't have `register_printf_function()', then
     the `%@' printf directive isn't available with printf() and friends.
     Here we make a feable attempt to handle it. */
  {
    /* We need a local copy since we change it.  (Changing and undoing
       the change doesn't work because some format strings are constant
       strings, placed in a non-writable section of the executable, and
       writing to them will cause a segfault.) */
    char format_cp_copy[format_len+1];
    char *atsign_pos;	     /* points to a location inside format_cp_copy */
    char *format_to_go = format_cp_copy;
    strcpy (format_cp_copy, format_cp);
    /* Loop once for each `%@' in the format string. */
    while ((atsign_pos = strstr (format_to_go, "%@")))
      {
	const char *cstring;
	char *formatter_pos; // Position for formatter.

	/* If there is a "%%@", then do the right thing: print it literally. */
	if ((*(atsign_pos-1) == '%')
	    && atsign_pos != format_cp_copy)
	  continue;
	/* Temporarily terminate the string before the `%@'. */
	*atsign_pos = '\0';
	/* Print the part before the '%@' */
	printed_len += VSPRINTF_LENGTH (vsprintf (buf+printed_len,
						  format_to_go, argList));
	/* Skip arguments used in last vsprintf(). */
	while ((formatter_pos = strchr(format_to_go, '%')))
	  {
	    char *spec_pos; // Position of conversion specifier.

	    if (*(formatter_pos+1) == '%')
	      {
		format_to_go = formatter_pos+2;
		continue;
	      }
	    spec_pos = strpbrk(formatter_pos+1, "dioxXucsfeEgGpn\0");
	    switch (*spec_pos)
	      {
#ifndef powerpc
	      /* FIXME: vsprintf on powerpc apparently advances the arg list
	      so this doesn't need to be done. Make a more general check
	      for this */
	      case 'd': case 'i': case 'o':
	      case 'x': case 'X': case 'u': case 'c':
		(void)va_arg(argList, int);
		break;
	      case 's':
		if (*(spec_pos - 1) == '*')
		  (void)va_arg(argList, int*);
		(void)va_arg(argList, char*);
		break;
	      case 'f': case 'e': case 'E': case 'g': case 'G':
		(void)va_arg(argList, double);
		break;
	      case 'p':
		(void)va_arg(argList, void*);
		break;
	      case 'n':
		(void)va_arg(argList, int*);
		break;
#endif /* NOT powerpc */
	      case '\0':
		spec_pos--;
		break;
	      }
	    format_to_go = spec_pos+1;
	  }
	/* Get a C-string (char*) from the String object, and print it. */
	cstring = [[(id) va_arg (argList, id) description] lossyCString];
	if (!cstring)
	  cstring = "<null string>";
	strcat (buf+printed_len, cstring);
	printed_len += strlen (cstring);
	/* Skip over this `%@', and look for another one. */
	format_to_go = atsign_pos + 2;
      }
    /* Print the rest of the string after the last `%@'. */
    printed_len += VSPRINTF_LENGTH (vsprintf (buf+printed_len,
					      format_to_go, argList));
  }
#else
  /* The available libc has `register_printf_function()', so the `%@'
     printf directive is handled by printf and friends. */
  printed_len = VSPRINTF_LENGTH (vsprintf (buf, format_cp, argList));
#endif /* !HAVE_REGISTER_PRINTF_FUNCTION */

  /* Raise an exception if we overran our buffer. */
  NSParameterAssert (printed_len < format_len + BUFFER_EXTRA - 1);
  return [self initWithCString: buf];
#endif /* HAVE_VASPRINTF */
#else /* HAVE_VSPRINTF || HAVE_VASPRINTF */
  [self notImplemented: _cmd];
  return self;
#endif
}
#endif

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
  unsigned	len = [data length];

  if (len == 0)
    {
      self = [self initWithCharactersNoCopy: (unichar*)0
				     length: 0
			       freeWhenDone: NO];
    }
  else if (_ByteEncodingOk == YES
    && (encoding==_DefaultStringEncoding || encoding==NSASCIIStringEncoding))
    {
      char	*s;

      /*
       * We can only create an internal C string if the default C string
       * encoding is Ok, and the specified encoding matches it.
       */
      s = NSZoneMalloc(GSObjCZone(self), len);
      [data getBytes: s];
      self = [self initWithCStringNoCopy: s length: len freeWhenDone: YES];
    }
  else if (encoding == NSUTF8StringEncoding)
    {
      const unsigned char	*bytes = [data bytes];
      unsigned			i = 0;

      /*
       * If the data begins with the UTF8 Byte Order Marker (as a
       * signature for UTF8 data) we must remove it.
       */
      if (len > 2 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
	{
	  len -= 3;
	  bytes += 3;
	}

      if (_ByteEncodingOk)
	{
	  /*
	   * If it's ok to store ascii strings as internal C strings,
	   * check to see if we have in fact got an ascii string.
	   */
	  while (i < len)
	    {
	      if ((bytes)[i] > 127)
		{
		  break;
		}
	      i++;
	    }
	}

      if (i == len)
	{
	  self = [self initWithCString: bytes length: len];
	}
      else
	{
	  unichar	*u = 0;
	  unsigned int	l = 0;

	  if (GSToUnicode(&u, &l, bytes, len, NSUTF8StringEncoding,
	    GSObjCZone(self), 0) == NO)
	    {
	      DESTROY(self);
	    }
	  else
	    {
	      self = [self initWithCharactersNoCopy: u
					     length: l
				       freeWhenDone: YES];
	    }
	}
    }
  else if (encoding == NSUnicodeStringEncoding)
    {
      if (len%2 != 0)
	{
	  DESTROY(self);	// Not valid unicode data.
	}
      else
	{
	  BOOL		swapped = NO;
	  unsigned char	*b;
	  unichar	*uptr;

	  b = (unsigned char*)[data bytes];
	  uptr = (unichar*)b;
	  if (*uptr == byteOrderMark)
	    {
	      b = (unsigned char*)++uptr;
	      len -= sizeof(unichar);
	    }
	  else if (*uptr == byteOrderMarkSwapped)
	    {
	      b = (unsigned char*)++uptr;
	      len -= sizeof(unichar);
	      swapped = YES;
	    }
	  if (len == 0)
	    {
	      self = [self initWithCharactersNoCopy: (unichar*)0
					     length: 0
				       freeWhenDone: NO];
	    }
	  else
	    {
	      unsigned char	*u;

	      u = (unsigned char*)NSZoneMalloc(GSObjCZone(self), len);
	      if (swapped == YES)
		{
		  unsigned	i;

		  for (i = 0; i < len; i += 2)
		    {
		      u[i] = b[i + 1];
		      u[i + 1] = b[i];
		    }
		}
	      else
		{
		  memcpy(u, b, len);
		}
	      self = [self initWithCharactersNoCopy: (unichar*)u
					     length: len/2
				       freeWhenDone: YES];
	    }
	}
    }
  else
    {
      unsigned char	*b;
      unichar		*u = 0;
      unsigned		l = 0;

      b = (unsigned char*)[data bytes];
      if (GSToUnicode(&u, &l, b, len, encoding, GSObjCZone(self), 0) == NO)
	{
	  DESTROY(self);
	}
      else
	{
	  self = [self initWithCharactersNoCopy: u
					 length: l
				   freeWhenDone: YES];
	}
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

- (id) init
{
  self = [self initWithCharactersNoCopy: (unichar*)0
				 length: 0
			   freeWhenDone: 0];
  return self;
}

// Getting a String's Length

- (unsigned int) length
{
  [self subclassResponsibility: _cmd];
  return 0;
}

// Accessing Characters

- (unichar) characterAtIndex: (unsigned int)index
{
  [self subclassResponsibility: _cmd];
  return (unichar)0;
}

/* Inefficient.  Should be overridden */
- (void) getCharacters: (unichar*)buffer
{
  [self getCharacters: buffer range: ((NSRange){0, [self length]})];
  return;
}

/* Inefficient.  Should be overridden */
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

// Combining Strings

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

- (NSString*) stringByAppendingString: (NSString*)aString
{
  unsigned	len = [self length];
  unsigned	otherLength = [aString length];
  NSZone	*z = GSObjCZone(self);
  unichar	*s = NSZoneMalloc(z, (len+otherLength)*sizeof(unichar));
  NSString	*tmp;

  [self getCharacters: s];
  [aString getCharacters: s + len];
  tmp = [[NSStringClass allocWithZone: z] initWithCharactersNoCopy: s
    length: len + otherLength freeWhenDone: YES];
  return AUTORELEASE(tmp);
}

// Dividing Strings into Substrings

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

- (NSRange) rangeOfCharacterFromSet: (NSCharacterSet*)aSet
{
  NSRange all = NSMakeRange(0, [self length]);

  return [self rangeOfCharacterFromSet: aSet
			       options: 0
				 range: all];
}

- (NSRange) rangeOfCharacterFromSet: (NSCharacterSet*)aSet
			    options: (unsigned int)mask
{
  NSRange all = NSMakeRange(0, [self length]);

  return [self rangeOfCharacterFromSet: aSet
			       options: mask
				 range: all];
}

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

/**
 * Invokes -rangeOfString:options: with the options mask
 * set to zero.
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
 * set to the range of the whole of the reciever.
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
 *   <item>NSCaseInsensitiveSearch</item>
 *   <item>NSLiteralSearch</item>
 *   <item>NSBackwardsSearch</item>
 *   <item>NSAnchoredSearch</item>
 * </list>
 */
- (NSRange) rangeOfString: (NSString *)aString
		  options: (unsigned int)mask
		    range: (NSRange)aRange
{
  if (aString == nil)
    [NSException raise: NSInvalidArgumentException format: @"range of nil"];
  return strRangeNsNs(self, aString, mask, aRange);
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

- (NSComparisonResult) compare: (NSString*)aString
{
  return [self compare: aString options: 0];
}

- (NSComparisonResult) compare: (NSString*)aString
		       options: (unsigned int)mask
{
  return [self compare: aString options: mask
		 range: ((NSRange){0, [self length]})];
}

// xxx Should implement full POSIX.2 collate
- (NSComparisonResult) compare: (NSString*)aString
		       options: (unsigned int)mask
			 range: (NSRange)aRange
{
  if (aString == nil)
    [NSException raise: NSInvalidArgumentException format: @"compare with nil"];
  return strCompNsNs(self, aString, mask, aRange);
}

- (BOOL) hasPrefix: (NSString*)aString
{
  NSRange	range;

  range = [self rangeOfString: aString options: NSAnchoredSearch];
  return (range.length > 0) ? YES : NO;
}

- (BOOL) hasSuffix: (NSString*)aString
{
  NSRange	range;

  range = [self rangeOfString: aString
                      options: NSAnchoredSearch | NSBackwardsSearch];
  return (range.length > 0) ? YES : NO;
}

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
  unsigned ret = 0;

  int len = [self length];

  if (len > NSHashStringLength)
    {
      len = NSHashStringLength;
    }
  if (len > 0)
    {
      unichar		buf[len * MAXDEC + 1];
      GSeqStruct	s = { buf, len, len * MAXDEC, 0 };
      unichar		*p;
      unsigned		char_count = 0;

      [self getCharacters: buf range: NSMakeRange(0,len)];
      GSeq_normalize(&s);

      p = buf;

      while (*p && char_count++ < NSHashStringLength)
	{
	  ret = (ret << 5) + ret + *p++;
	}

      /*
       * The hash caching in our concrete string classes uses zero to denote
       * an empty cache value, so we MUST NOT return a hash of zero.
       */
      if (ret == 0)
	ret = 0x0fffffff;
      else
	ret &= 0x0fffffff;
      return ret;
    }
  else
    return 0x0ffffffe;	/* Hash for an empty string.	*/
}

// Getting a Shared Prefix

- (NSString*) commonPrefixWithString: (NSString*)aString
			     options: (unsigned int)mask
{
  if (mask & NSLiteralSearch)
    {
      int prefix_len = 0;
      unichar *u,*w;
      unichar a1[[self length]+1];
      unichar *s1 = a1;
      unichar a2[[aString length]+1];
      unichar *s2 = a2;

      u = s1;
      [self getCharacters: s1];
      s1[[self length]] = (unichar)0;
      [aString getCharacters: s2];
      s2[[aString length]] = (unichar)0;
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
	return self;
      if (!oLength)
	return aString;

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
      if(aRange.length)
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

// Changing Case

// xxx There is more than this in word capitalization in Unicode,
// but this will work in most cases
- (NSString*) capitalizedString
{
  unichar	*s;
  unsigned	count = 0;
  BOOL		found = YES;
  unsigned	len = [self length];

  if (len == 0)
    return self;
  if (whitespaceBitmapRep == NULL)
    setupWhitespace();

  s = NSZoneMalloc(GSObjCZone(self), sizeof(unichar)*len);
  [self getCharacters: s];
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
  unichar	*s;
  unsigned	count;
  unsigned	len = [self length];
  unichar	(*caiImp)(NSString*, SEL, unsigned int);

  if (len == 0)
    {
      return self;
    }

  s = NSZoneMalloc(GSObjCZone(self), sizeof(unichar)*len);
  caiImp = (unichar (*)())[self methodForSelector: caiSel];
  for (count = 0; count < len; count++)
    {
      s[count] = uni_tolower((*caiImp)(self, caiSel, count));
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
  unichar	*s;
  unsigned	count;
  unsigned	len = [self length];
  unichar	(*caiImp)(NSString*, SEL, unsigned int);

  if (len == 0)
    {
      return self;
    }
  s = NSZoneMalloc(GSObjCZone(self), sizeof(unichar)*len);
  caiImp = (unichar (*)())[self methodForSelector: caiSel];
  for (count = 0; count < len; count++)
    {
      s[count] = uni_toupper((*caiImp)(self, caiSel, count));
    }
  return AUTORELEASE([[NSStringClass allocWithZone: NSDefaultMallocZone()]
    initWithCharactersNoCopy: s length: len freeWhenDone: YES]);
}

// Storing the String

- (NSString*) description
{
  return self;
}


// Getting C Strings

/**
 * Returns a pointer to a null terminated string of 8-bit
 * characters in the default encoding.  The memory pointed
 * to is not owned by the caller, so the caller must copy
 * its contents to keep it.
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

- (unsigned int) cStringLength
{
  NSData	*d;

  d = [self dataUsingEncoding: _DefaultStringEncoding
         allowLossyConversion: NO];
  return [d length];
}

/**
 * Retrieve the contents of the receiver into the buffer.<br />
 * The buffer must be large enought to contain the CString representation
 * of the characters in the receiver, plus a null terminator which this
 * method adds.
 */
- (void) getCString: (char*)buffer
{
  [self getCString: buffer maxLength: NSMaximumStringLength
	     range: ((NSRange){0, [self length]})
    remainingRange: NULL];
}

/**
 * Retrieve up to maxLength characters from the receiver into the buffer.<br />
 * The buffer must be at least maxLength characters long, so that it has
 * room for the null terminator that this method adds.
 */
- (void) getCString: (char*)buffer
	  maxLength: (unsigned int)maxLength
{
  [self getCString: buffer maxLength: maxLength
	     range: ((NSRange){0, [self length]})
    remainingRange: NULL];
}

- (void) getCString: (char*)buffer
	  maxLength: (unsigned int)maxLength
	      range: (NSRange)aRange
     remainingRange: (NSRange*)leftoverRange
{
  unsigned	len;
  unsigned	count;
  unichar	(*caiImp)(NSString*, SEL, unsigned int);

  len = [self cStringLength];
  GS_RANGE_CHECK(aRange, len);

  caiImp = (unichar (*)())[self methodForSelector: caiSel];

  if (maxLength < aRange.length)
    {
      len = maxLength;
      if (leftoverRange)
	{
	  leftoverRange->location = 0;
	  leftoverRange->length = 0;
	}
    }
  else
    {
      len = aRange.length;
      if (leftoverRange)
	{
	  leftoverRange->location = aRange.location + maxLength;
	  leftoverRange->length = aRange.length - maxLength;
	}
    }
  count = 0;
  while (count < len)
    {
      buffer[count] = encode_unitochar(
	(*caiImp)(self, caiSel, aRange.location + count),
	_DefaultStringEncoding);
      if (buffer[count] == 0)
	{
	  [NSException raise: NSCharacterConversionException
		      format: @"unable to convert to cString"];
	}
      count++;
    }
  buffer[len] = '\0';
}


// Getting Numeric Values

// xxx Sould we use NSScanner here ?

/**
 * If the string consists of the words 'true' or 'yes' (case insensitive)
 * or begins with a non-zero numeric value, return YES, otherwise return
 * NO.
 */
- (BOOL) boolValue
{
  if ([self caseInsensitiveCompare: @"YES"] == NSOrderedSame)
    {
      return YES;
    }
  if ([self caseInsensitiveCompare: @"true"] == NSOrderedSame)
    {
      return YES;
    }
  return [self intValue] != 0 ? YES : NO;
}

/**
 * Returns the strings content as a double.  Skips leading whitespace.<br />
 * Conversion is not localised (ie uses '.' as the decimal separator).<br />
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
 * Returns the strings content as a double.  Skips leading whitespace.<br />
 * Conversion is not localised (ie uses '.' as the decimal separator).<br />
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

- (int) intValue
{
  return atoi([self lossyCString]);
}

// Working With Encodings

/**
 * <p>
 *   Returns the encoding used for any method accepting a C string.
 *   This value is determined automatically from the programs
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
  return GetAvailableEncodings();
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

  ourname = GetEncodingName(encoding);
  return [ourbundle localizedStringForKey: ourname
				    value: ourname
				    table: nil];
}

- (BOOL) canBeConvertedToEncoding: (NSStringEncoding)encoding
{
  id d = [self dataUsingEncoding: encoding allowLossyConversion: NO];

  return d != nil ? YES : NO;
}

- (NSData*) dataUsingEncoding: (NSStringEncoding)encoding
{
  return [self dataUsingEncoding: encoding allowLossyConversion: NO];
}

- (NSData*) dataUsingEncoding: (NSStringEncoding)encoding
	 allowLossyConversion: (BOOL)flag
{
  unsigned int	count = 0;
  unsigned int	len = [self length];
  unichar	(*caiImp)(NSString*, SEL, unsigned int);

  if (len == 0)
    {
      return [NSDataClass data];
    }

  caiImp = (unichar (*)())[self methodForSelector: caiSel];
  if ((encoding == NSASCIIStringEncoding)
    || (encoding == NSISOLatin1StringEncoding)
    || (encoding == NSISOLatin2StringEncoding)
    || (encoding == NSNEXTSTEPStringEncoding)
    || (encoding == NSNonLossyASCIIStringEncoding)
    || (encoding == NSSymbolStringEncoding)
    || (encoding == NSISOCyrillicStringEncoding)
    || (encoding == NSISOThaiStringEncoding))
    {
      char		t;
      unsigned char	*buff;

      buff = (unsigned char*)NSZoneMalloc(NSDefaultMallocZone(), len+1);
      if (!flag)
	{
	  for (count = 0; count < len; count++)
	    {
	      t = encode_unitochar((*caiImp)(self, caiSel, count), encoding);
	      if (t)
		{
		  buff[count] = t;
		}
	      else
		{
		  NSZoneFree(NSDefaultMallocZone(), buff);
		  return nil;
		}
	    }
	}
      else /* lossy */
	{
	  for (count = 0; count < len; count++)
	    {
	      t = encode_unitochar((*caiImp)(self, caiSel, count), encoding);
	      if (t)
		{
		  buff[count] = t;
		}
	      else
		{
		  /* xxx should handle decomposed characters */
		  /* OpenStep documentation is unclear on what to do
		   * if there is no simple replacement for character
		   */
		  buff[count] = '*';
		}
	    }
	}
      buff[count] = '\0';
      return [NSDataClass dataWithBytesNoCopy: buff length: count];
    }
  else if (encoding == NSUTF8StringEncoding)
    {
      unsigned char	*buff;
      unsigned		i, j;
      unichar		ch, ch2;
      gsu32		cp;

      buff = (unsigned char *)NSZoneMalloc(NSDefaultMallocZone(), len*3);

      /*
       * Each UTF-16 character maps to at most 3 bytes of UTF-8, so we simply
       * allocate three times as many bytes as UTF-16 characters, then use
       * NSZoneRealloc() later to trim the excess.  Most Unix virtual memory
       * implementations allocate address space, and actual memory pages are
       * not actually allocated until used, so this method shouldn't cause
       * memory problems on most Unix systems.  On other systems, it may prove
       * advantageous to scan the UTF-16 string to determine the UTF-8 string
       * length before allocating memory.
       */
      for (i = j = 0; i < len; i++)
        {
          ch = (*caiImp)(self, caiSel, i);
          if (NSLocationInRange(ch, highSurrogateRange) && ((i+1) < len))
            {
              ch2 = (*caiImp)(self, caiSel, i+1);
              if (NSLocationInRange(ch2, lowSurrogateRange))
                {
                  cp = surrogatePairValue(ch, ch2);
                  i++;
                }
              else
                cp = (gsu32)ch;
            }
          else
            cp = (gsu32)ch;

          if (cp < 0x80)
            {
              buff[j++] = cp;
            }
          else if (cp < 0x800)
            {
              buff[j++] = 0xC0 | ch>>6;
              buff[j++] = 0x80 | (ch & 0x3F);
            }
          else if (cp < 0x10000)
            {
              buff[j++] = 0xE0 | ch>>12;
              buff[j++] = 0x80 | (ch>>6 & 0x3F);
              buff[j++] = 0x80 | (ch & 0x3F);
            }
          else if (cp < 0x200000)
            {
              buff[j++] = 0xF0 | ch>>18;
              buff[j++] = 0x80 | (ch>>12 & 0x3F);
              buff[j++] = 0x80 | (ch>>6 & 0x3F);
              buff[j++] = 0x80 | (ch & 0x3F);
            }
        }

      NSZoneRealloc(NSDefaultMallocZone(), buff, j);

      return [NSDataClass dataWithBytesNoCopy: buff
                                       length: j];
    }
  else if (encoding == NSUnicodeStringEncoding)
    {
      unichar	*buff;

      buff = (unichar*)NSZoneMalloc(NSDefaultMallocZone(),
	sizeof(unichar)*(len+1));
      buff[0] = byteOrderMark;
      [self getCharacters: &buff[1]];
      return [NSDataClass dataWithBytesNoCopy: buff
					length: sizeof(unichar)*(len+1)];
    }
  else
    {
      unsigned char	*b = 0;
      int		l = 0;
      unichar		*u;

      u = (unichar*)NSZoneMalloc(NSDefaultMallocZone(), len*sizeof(unichar));
      [self getCharacters: u];
      if (GSFromUnicode(&b, &l, u, len, encoding, NSDefaultMallocZone(),
	(flag == NO) ? GSUniStrict : 0)
	== NO)
	{
	  NSZoneFree(NSDefaultMallocZone(), u);
	  return nil;
	}
      NSZoneFree(NSDefaultMallocZone(), u);
      return [NSDataClass dataWithBytesNoCopy: b length: l];
    }
  return nil;
}

- (NSStringEncoding) fastestEncoding
{
  return NSUnicodeStringEncoding;
}

- (NSStringEncoding) smallestEncoding
{
  return NSUnicodeStringEncoding;
}


// Manipulating File System Paths

- (unsigned int) completePathIntoString: (NSString**)outputName
			  caseSensitive: (BOOL)flag
		       matchesIntoArray: (NSArray**)outputArray
			    filterTypes: (NSArray*)filterTypes
{
  NSString		*base_path = [self stringByDeletingLastPathComponent];
  NSString		*last_compo = [self lastPathComponent];
  NSString		*tmp_path;
  NSDirectoryEnumerator *e;
  NSMutableArray	*op = nil;
  unsigned		match_count = 0;

  if (outputArray != 0)
    {
      op = (NSMutableArray*)[NSMutableArray array];
    }

  if (outputName != NULL)
    {
      *outputName = nil;
    }

  if ([base_path length] == 0)
    {
      base_path = @".";
    }

  e = [[NSFileManager defaultManager] enumeratorAtPath: base_path];
  while (tmp_path = [e nextObject], tmp_path)
    {
      /* Prefix matching */
      if (flag == YES)
	{ /* Case sensitive */
	  if ([tmp_path hasPrefix: last_compo] == NO)
	    {
	      continue;
	    }
	}
      else if ([[tmp_path uppercaseString]
	hasPrefix: [last_compo uppercaseString]] == NO)
	{
	  continue;
	}

      /* Extensions filtering */
      if (filterTypes
	&& ([filterTypes containsObject: [tmp_path pathExtension]] == NO))
	{
	  continue;
	}

      /* Found a completion */
      match_count++;
      if (outputArray != NULL)
	{
	  [op addObject: tmp_path];
	}

      if ((outputName != NULL) &&
	((*outputName == nil) || (([*outputName length] < [tmp_path length]))))
	{
	  *outputName = tmp_path;
	}
    }
  if (outputArray != NULL)
    {
      *outputArray = AUTORELEASE([op copy]);
    }
  return match_count;
}

/* Return a string for passing to OS calls to handle file system objects. */
- (const char*) fileSystemRepresentation
{
  static NSFileManager *fm = nil;

  if (fm == nil)
    {
      fm = RETAIN([NSFileManager defaultManager]);
    }

  return [fm fileSystemRepresentationWithPath: self];
}

- (BOOL) getFileSystemRepresentation: (char*)buffer
			   maxLength: (unsigned int)size
{
  const char* ptr = [self fileSystemRepresentation];
  if (strlen(ptr) > size)
    return NO;
  strcpy(buffer, ptr);
  return YES;
}

/**
 * Returns a string containing the last path component of the receiver.<br />
 * The path component is the last non-empty substring delimited by the ends
 * of the string or by path * separator ('/') characters.<br />
 * If the receiver is an empty string, it is simply returned.<br />
 * If there are no non-empty substrings, the root string is returned.
 */
- (NSString*) lastPathComponent
{
  NSString	*substring;
  unsigned int	l = [self length];

  if (l == 0)
    {
      substring = self;		// self is empty
    }
  else
    {
      NSRange	range;

      range = [self rangeOfCharacterFromSet: pathSeps()
				    options: NSBackwardsSearch];
      if (range.length == 0)
	{
	  substring = self;		// No '/' in self
	}
      else if (range.location == (l - 1))
	{
	  if (range.location == 0)
	    {
	      substring = self;		// Just '/'
	    }
	  else
	    {
	      l = range.location;
	      while (l > 0 && [self characterAtIndex: l - 1] == '/')
		{
		  l--;
		}
	      if (l > 0)
		{
		  substring = [[self substringToIndex: l] lastPathComponent];
		}
	      else
		{
		  substring = @"/";	// Multiple '/' characters.
		}
	    }
	}
      else
	{
	  substring = [self substringFromIndex: range.location + 1];
	}
    }

  return substring;
}

/**
 * Returns a new string containing the path extension of the receiver.<br />
 * The path extension is a suffix on the last path component which starts
 * with the extension separator (a '.') (for example .tiff is the
 * pathExtension for /foo/bar.tiff).<br />
 * Returns an empty string if no such extension exists.
 */
- (NSString*) pathExtension
{
  NSRange	range;
  NSString	*substring = @"";
  unsigned int	length = [self length];

  /*
   * Step past trailing path separators.
   */
  while (length > 1 && pathSepMember([self characterAtIndex: length-1]) == YES)
    {
      length--;
    }
  range = NSMakeRange(0, length);

  /*
   * Look for a dot in the path ... if there isn't one, there is no extension.
   */
  range = [self rangeOfString: @"." options: NSBackwardsSearch range: range];
  if (range.length > 0)
    {
      NSRange	sepRange;

      /*
       * Found a dot, so we determine the range of the (possible)
       * path extension, then cvheck to see if we have a path
       * separator within it ... if we have a path separator then
       * the dot is inside the last path component and there is
       * thereofore no extension.
       */
      range.location++;
      range.length = length - range.location;
      sepRange = [self rangeOfCharacterFromSet: pathSeps()
				       options: NSBackwardsSearch
				         range: range];
      if (sepRange.length == 0)
	{
	  substring = [self substringFromRange: range];
	}
    }

  return substring;
}

/**
 * Returns a new string with the path component given in aString
 * appended to the receiver.
 * Removes trailing separators and multiple separators.
 */
- (NSString*) stringByAppendingPathComponent: (NSString*)aString
{
  unsigned	length = [self length];
  unsigned	aLength = [aString length];
  unichar	buf[length+aLength+1];

  [self getCharacters: buf];
  while (length > 1 && pathSepMember(buf[length-1]) == YES)
    {
      length--;
    }
  if (aLength > 0)
    {
      if (length > 0 && pathSepMember(buf[length-1]) == NO)
	{
	  buf[length++] = '/';
	}
      [aString getCharacters: &buf[length]];
    }
  length += aLength;
  while (length > 1 && pathSepMember(buf[length-1]) == YES)
    {
      length--;
    }
  if (length > 0)
    {
      aLength = length - 1;
      while (aLength > 0)
	{
	  if (pathSepMember(buf[aLength]) == YES)
	    {
	      if (pathSepMember(buf[aLength-1]) == YES)
		{
		  unsigned	pos;

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

/**
 * Returns a new string with the path extension given in aString
 * appended to the receiver after the extensionSeparator ('.').<br />
 * If the receiver has trailing '/' characters which are not part of the
 * root directory, those '/' characters are stripped before the extension
 * separator is added.
 */
- (NSString*) stringByAppendingPathExtension: (NSString*)aString
{
  if ([aString length] == 0)
    {
      return [self stringByAppendingString: @"."];
    }
  else
    {
      unsigned	length = [self length];
      unsigned	len = length;
      NSString	*base = self;

      /*
       * Step past trailing path separators.
       */
      while (len > 1 && pathSepMember([self characterAtIndex: len-1]) == YES)
	{
	  len--;
	}
      if (length != len)
	{
	  NSRange	range = NSMakeRange(0, len);

	  base = [base substringFromRange: range];
	}
      return [base stringByAppendingFormat: @".%@", aString];
    }
}

/**
 * Returns a new string with the last path component (including any final
 * path separators) removed from the receiver.<br />
 * A string without a path component other than the root is returned
 * without alteration.<br />
 * See -lastPathComponent for a definition of a path component.
 */
- (NSString*) stringByDeletingLastPathComponent
{
  NSRange	range;
  NSString	*substring;
  unsigned int	length = [self length];

  /*
   * Step past trailing path separators.
   */
  while (length > 1 && pathSepMember([self characterAtIndex: length-1]) == YES)
    {
      length--;
    }
  range = NSMakeRange(0, length);

  /*
   * Locate path separator preceeding last path component.
   */
  range = [self rangeOfCharacterFromSet: pathSeps()
				options: NSBackwardsSearch
				  range: range];
  if (range.length == 0)
    {
      substring = @"";
    }
  else if (range.location == 0)
    {
      substring = @"/";
    }
  else
    {
      substring = [self substringToIndex: range.location];
    }
  return substring;
}

/**
 * Returns a new string with the path extension removed from the receiver.<br />
 * Strips any trailing path separators before checking for the extension
 * separator.<br />
 * Does not consider a string starting with the extension separator ('.') to
 * be a path extension.
 */
- (NSString*) stringByDeletingPathExtension
{
  NSRange	range;
  NSRange	r0;
  NSRange	r1;
  NSString	*substring;
  unsigned	length = [self length];

  /*
   * Skip past any trailing path separators... but not a leading one.
   */
  while (length > 1 && pathSepMember([self characterAtIndex: length-1]) == YES)
    {
      length--;
    }
  range = NSMakeRange(0, length);
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
  if (r0.length > 0 && (r1.length == 0 || r1.location < r0.location))
    {
      length = r0.location;
    }
  substring = [self substringToIndex: length];
  return substring;
}

/**
 * Returns a string created by expanding the initial tilde ('~') and any
 * following username to be the home directory of the current user or the
 * named user.<br />
 * Returns the receiver if it was not possible to expand it.
 */
- (NSString*) stringByExpandingTildeInPath
{
  NSString	*homedir;
  NSRange	first_slash_range;
  unsigned	length;

  if ((length = [self length]) == 0)
    {
      return self;
    }
  if ([self characterAtIndex: 0] != 0x007E)
    {
      return self;
    }

  /*
   * Anything beginning '~@' is assumed to be a windows path specification
   * which can't be expanded.
   */
  if (length > 1 && [self characterAtIndex: 1] == 0x0040)
    {
      return self;
    }

  first_slash_range = [self rangeOfCharacterFromSet: pathSeps()];

  if (first_slash_range.location != 1)
    {
      /* It is of the form `~username/blah/...' */
      int	uname_len;
      NSString	*uname;

      if (first_slash_range.length != 0)
	{
	  uname_len = first_slash_range.location - 1;
	}
      else
	{
	  /* It is actually of the form `~username' */
	  uname_len = [self length] - 1;
	  first_slash_range.location = [self length];
	}
      uname = [self substringWithRange: ((NSRange){1, uname_len})];
      homedir = NSHomeDirectoryForUser (uname);
    }
  else
    {
      /* It is of the form `~/blah/...' */
      homedir = NSHomeDirectory ();
    }
  if (homedir != nil)
    {
      return [homedir stringByAppendingPathComponent:
	[self substringFromIndex: first_slash_range.location]];
    }
  else
    {
      return self;
    }
}

/**
 * Returns a string where a prefix of the current user's home directory is
 * abbreviated by '~', or returns the receiver if it was not found to have
 * the home directory as a prefix.
 */
- (NSString*) stringByAbbreviatingWithTildeInPath
{
  NSString	*homedir = NSHomeDirectory ();

  if (![self hasPrefix: homedir])
    {
      return self;
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
      return self;
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

- (NSString*) stringByResolvingSymlinksInPath
{
#if defined(__MINGW__)
  return self;
#else
  #ifndef MAX_PATH
  #define MAX_PATH 1024
  #endif
  char		new_buf[MAX_PATH];
#ifdef HAVE_REALPATH

  if (realpath([self cString], new_buf) == 0)
    return self;
#else
  char		extra[MAX_PATH];
  char		*dest;
  const char	*name = [self cString];
  const char	*start;
  const	char	*end;
  unsigned	num_links = 0;


  if (name[0] != '/')
    {
      if (!getcwd(new_buf, MAX_PATH))
        return self;			/* Couldn't get directory.	*/
      dest = strchr(new_buf, '\0');
    }
  else
    {
      new_buf[0] = '/';
      dest = &new_buf[1];
    }

  for (start = end = name; *start; start = end)
    {
      struct stat	st;
      int		n;
      int		len;

      /* Elide repeated path separators	*/
      while (*start == '/')
	start++;

      /* Locate end of path component	*/
      end = start;
      while (*end && *end != '/')
	end++;

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
	  if (dest > &new_buf[1])
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
            *dest++ = '/';

          if (&dest[len] >= &new_buf[MAX_PATH])
	    return self;	/* Resolved name would be too long.	*/

          memcpy(dest, start, len);
          dest += len;
          *dest = '\0';

          if (lstat(new_buf, &st) < 0)
            return self;	/* Unable to stat file.		*/

          if (S_ISLNK(st.st_mode))
            {
              char buf[MAX_PATH];

              if (++num_links > MAXSYMLINKS)
		return self;	/* Too many symbolic links.	*/

              n = readlink(new_buf, buf, MAX_PATH);
              if (n < 0)
		return self;	/* Couldn't resolve links.	*/

              buf[n] = '\0';

              if ((n + strlen(end)) >= MAX_PATH)
		return self;	/* Path would be too long.	*/

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
		  dest = new_buf + 1;
		}
              else
		{
		  /*
		   * Backup - remove the last component.
		   */
		  if (dest > new_buf + 1)
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
  if (dest > new_buf + 1 && dest[-1] == '/')
    --dest;
  *dest = '\0';
#endif
  if (strncmp(new_buf, "/private/", 9) == 0)
    {
      struct stat	st;

      if (lstat(&new_buf[8], &st) == 0)
	strcpy(new_buf, &new_buf[8]);
    }
  return [NSStringClass stringWithCString: new_buf];
#endif  /* (__MINGW__) */
}

/**
 * Returns a standardised form of the receiver, with unnecessary parts
 * removed, tilde characters expanded, and symbolic links resolved
 * where possible.<br />
 * If the string is an invalid path, the unmodified receiver is returned.<br />
 * <p>
 *   Uses -stringByExpandingTildeInPath to expand tilde expressions.<br />
 *   Simplifies '//' and '/./' sequences.<br />
 *   Removes any '/private' prefix.
 * </p>
 * <p>
 *  For absolute paths, uses -stringByResolvingSymlinksInPath to resolve
 *  any links, then gets rid of '/../' sequences.
 * </p>
 */
- (NSString*) stringByStandardizingPath
{
  NSMutableString	*s;
  NSRange		r;
  unichar		(*caiImp)(NSString*, SEL, unsigned int);

  /* Expand `~' in the path */
  s = AUTORELEASE([[self stringByExpandingTildeInPath] mutableCopy]);
  caiImp = (unichar (*)())[s methodForSelector: caiSel];

  /* Condense `//' and '/./' */
  r = NSMakeRange(0, [s length]);
  while ((r = [s rangeOfCharacterFromSet: pathSeps()
				 options: 0
				   range: r]).length)
    {
      unsigned	length = [s length];

      if (r.location + r.length + 1 <= length
	&& pathSepMember((*caiImp)(s, caiSel, r.location + 1)) == YES)
	{
	  [s deleteCharactersInRange: r];
	}
      else if (r.location + r.length + 2 <= length
	&& (*caiImp)(s, caiSel, r.location + 1) == (unichar)'.'
	&& pathSepMember((*caiImp)(s, caiSel, r.location + 2)) == YES)
	{
	  r.length++;
	  [s deleteCharactersInRange: r];
	}
      else
	{
	  r.location++;
	}
      if ((r.length = [s length]) > r.location)
	{
	  r.length -= r.location;
	}
      else
	{
	  break;
	}
    }

  if ([s isAbsolutePath] == NO)
    {
      return s;
    }

  /* Remove `/private' */
  if ([s hasPrefix: @"/private"])
    {
      [s deleteCharactersInRange: ((NSRange){0,7})];
    }

  /*
   *	For absolute paths, we must resolve symbolic links or (on MINGW)
   *	remove '/../' sequences and their matching parent directories.
   */
#if defined(__MINGW__)
  /* Condense `/../' */
  r = NSMakeRange(0, [s length]);
  while ((r = [s rangeOfCharacterFromSet: pathSeps()
				 options: 0
				   range: r]).length)
    {
      if (r.location + r.length + 3 <= [s length]
	&& (*caiImp)(s, caiSel, r.location + 1) == (unichar)'.'
	&& (*caiImp)(s, caiSel, r.location + 2) == (unichar)'.'
	&& pathSepMember((*caiImp)(s, caiSel, r.location + 3)) == YES)
	{
	  if (r.location > 0)
	    {
	      NSRange r2 = {0, r.location};
	      r = [s rangeOfCharacterFromSet: pathSeps()
				     options: NSBackwardsSearch
				       range: r2];
	      if (r.length == 0)
		{
		  r = r2;
		}
	      else
		{
		  r.length = r2.length - r.location - 1;
		}
	      r.length += 4;		/* Add the `/../' */
	    }
	  [s deleteCharactersInRange: r];
	}
      else
	{
	  r.location++;
	}

      if ((r.length = [s length]) > r.location)
	{
	  r.length -= r.location;
	}
      else
	{
	  break;
	}
    }

  return s;
#else
  return [s stringByResolvingSymlinksInPath];
#endif
}

/**
 * Return a string formed by removing characters from the ends of the
 * receiver.  Characters are removed only if they are in aSet.<br />
 * If the string consists entirely of characters in aSet, an empty
 * string is returned.<br />
 * The aSet argument nust not be nil.<br />
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
      return self;
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

/**
 * Concatenates the strings in the components array placing a path
 * separator between each one and returns the result.
 */
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
      s = @"/";
    }
  for (i = 1; i < c; i++)
    {
      s = [s stringByAppendingPathComponent: [components objectAtIndex: i]];
    }
  return s;
}

/*
 * Returs YES if the receiver represents an absolute path ... ie if it begins
 * with a '/' or a '~'<br />
 * Returns NO otherwise.
 */
- (BOOL) isAbsolutePath
{
  unichar	c;

  if ([self length] == 0)
    {
      return NO;
    }
  c = [self characterAtIndex: 0];
#if defined(__MINGW__)
  if (isalpha(c) && [self indexOfString: @":"] == 1)
    {
      return YES;
    }
#endif
  if (c == (unichar)'/' || c == (unichar)'~')
    {
      return YES;
    }
  return NO;
}

/**
 * Returns the path components of the reciever separated into an array.<br />
 * If the receiver begins with a '/' character then that is used as the
 * first element in the array.<br />
 * Empty components are removed.
 */
- (NSArray*) pathComponents
{
  NSMutableArray	*a;
  NSArray		*r;

  if ([self length] == 0)
    {
      return [NSArray array];
    }
  a = [[self componentsSeparatedByString: @"/"] mutableCopy];
  if ([a count] > 0)
    {
      int	i;

      /*
       * If the path began with a '/' then the first path component must
       * be a '/' rather than an empty string so that our output could be
       * fed into [+pathWithComponents: ]
       */
      if ([[a objectAtIndex: 0] length] == 0)
	{
	  [a replaceObjectAtIndex: 0 withObject: @"/"];
	}
      /*
       * Similarly if the path ended with a path separator (other than the
       * leading one).
       */
      if ([[a objectAtIndex: [a count]-1] length] == 0)
	{
	  if ([self length] > 1)
	    {
	      [a replaceObjectAtIndex: [a count]-1 withObject: @"/"];
	    }
	}
      /* Any empty path components  must be removed. */
      for (i = [a count] - 1; i > 0; i--)
	{
	  if ([[a objectAtIndex: i] length] == 0)
	    {
	      [a removeObjectAtIndex: i];
	    }
	}
    }
  r = [a copy];
  RELEASE(a);
  return AUTORELEASE(r);
}

/**
 * Returns an array of strings made by appending the values in paths
 * to the receiver.
 */
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

+ (NSString*) localizedStringWithFormat: (NSString*) format, ...
{
  va_list ap;
  id ret;
  NSDictionary *dict;

  va_start(ap, format);
  if (format == nil)
    {
      ret = nil;
    }
  else
    {
      dict = GSUserDefaultsDictionaryRepresentation();
      ret = AUTORELEASE([[self allocWithZone: NSDefaultMallocZone()]
        initWithFormat: format locale: dict arguments: ap]);
    }
  va_end(ap);
  return ret;
}

- (NSComparisonResult) caseInsensitiveCompare: (NSString*)aString
{
  return [self compare: aString
	       options: NSCaseInsensitiveSearch
		 range: ((NSRange){0, [self length]})];
}

- (NSComparisonResult) compare: (NSString *)string
		       options: (unsigned int)mask
			 range: (NSRange)compareRange
			locale: (NSDictionary *)dict
{
  // FIXME: This does only a normal compare
  return [self compare: string
	       options: mask
		 range: compareRange];
}

- (NSComparisonResult) localizedCompare: (NSString *)string
{
  NSDictionary *dict = GSUserDefaultsDictionaryRepresentation();

  return [self compare: string
               options: 0
                 range: ((NSRange){0, [self length]})
                locale: dict];
}

- (NSComparisonResult) localizedCaseInsensitiveCompare: (NSString *)string
{
  NSDictionary *dict = GSUserDefaultsDictionaryRepresentation();

  return [self compare: string
               options: NSCaseInsensitiveSearch
                 range: ((NSRange){0, [self length]})
                locale: dict];
}

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
	  [self getCharacters: chars];
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
	  else if (enc == NSASCIIStringEncoding
	    || enc == _DefaultStringEncoding)
	    {
	      unsigned char	*chars;
	      
	      chars = NSZoneMalloc(zone, count+1);
	      [aCoder decodeArrayOfObjCType: @encode(unsigned char)
		                      count: count
				         at: chars];
	      self = [self initWithCStringNoCopy: chars
				          length: count
				    freeWhenDone: YES];
	    }
	  else if (enc == NSUTF8StringEncoding)
	    {
	      unsigned char	*chars;

	      chars = NSZoneMalloc(zone, count+1);
	      [aCoder decodeArrayOfObjCType: @encode(unsigned char)
		                      count: count
				         at: chars];
	      chars[count] = '\0';
	      self = [self initWithUTF8String: chars];
	      NSZoneFree(zone, chars);
	    }
	  else
	    {
	      unsigned char	*chars;
	      NSData	*data;
	      
	      chars = NSZoneMalloc(zone, count);
	      [aCoder decodeArrayOfObjCType: @encode(unsigned char)
			              count: count
				         at: chars];
	      data = [NSDataClass allocWithZone: zone];
	      data = [data initWithBytesNoCopy: chars length: count];
	      self = [self initWithData: data encoding: enc];
	      RELEASE(data);
	    }
	}
      else
        {
	  self = [self initWithCStringNoCopy: "" length: 0 freeWhenDone: NO];
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
 * comment notations used in ObjectiveC programming are supported, while
 * in XML format, the standard SGML comment sequences are used.
 * </p>
 * A <em>property list</em> may only be one of the following classes - 
 * <deflist>
 *   <term>[NSArray]</term>
 *   <desc>
 *     An array which is either empty or contains only <em>property list</em>
 *     objects.<br />
 *     An array is delimited by round brackets and its contents are comma
 *     <em>separated</em> (there is no comma after the last array element).
 *     <example>
 *       ( "one", "two", "three" )
 *     </example>
 *     In XML format, an array is an element whose name is <code>array</code>
 *     and whose content is the array content.
 *     <example>
 *       &lt;array&gt;&lt;string&gt;one&lt;/string&gt;&lt;string&gt;two&lt;/string&gt;&lt;string&gt;three&lt;/string&gt;&lt;/array&gt;
 *     </example>
 *   </desc>
 *   <term>[NSData]</term>
 *   <desc>
 *     An array is represented as a series of pairs of hexadecimal characters
 *     (each pair representing a byte of data) enclosed in angle brackets.
 *     Spaces are ignored).
 *     <example>
 *       &lt; 54637374 696D67 &gt;
 *     </example>
 *     In XML format, a data object is an element whose name is
 *     <code>data</code> and whose content is a stream of base64 encoded bytes.
 *   </desc>
 *   <term>[NSDate]</term>
 *   <desc>
 *     Date objects were not traditionally allowed in <em>property lists</em>
 *     but were added when the XML format was intoroduced.  GNUstep provides
 *     an extension to the traditional <em>property list</em> format to
 *     support date objects, but older code will not read
 *     <em>property lists</em> containing this extension.<br />
 *     This format consists of an asterisk follwed by the letter 'D' then a
 *     date/time in YYYY-MM-DD HH:MM:SS +/-ZZZZ format, all enclosed within
 *     angle brackets.
 *     <example>
 *       &lt;*D2002-03-22 11:30:00 +0100&gt;
 *     </example>
 *     In XML format, a date object is an element whose name is
 *     <code>date</code> and whose content is a date in the above format.
 *     <example>
 *       &lt;date&gt;2002-03-22 11:30:00 +0100&lt;/date&gt;
 *     </example>
 *   </desc>
 *   <term>[NSDictionary]</term>
 *   <desc>
 *     A dictionary which is either empty or contains only <em>string</em>
 *     keys and <em>property list</em> objects.<br />
 *     A dictionary is delimited by curly brackets and its contents are
 *     semicolon <em>terminated</em> (there is a semicolon after each value).
 *     Each item in the dictionary is a key/value pair with an equals sign
 *     after the key and before the value.
 *     <example>
 *       {
 *         "key1" = "value1";
 *       }
 *     </example>
 *     In XML format, a dictionary is an element whose name is
 *     <code>dictionary</code> and whose content consists of pairs of
 *     strings and other <em>property list</em> objects.
 *     <example>
 *       &lt;dictionary&gt;
 *         &lt;string&gt;key1&lt;/string&gt;
 *         &lt;string&gt;value1&lt;/string&gt;
 *       &lt;/dictionary&gt;
 *     </example>
 *   </desc>
 *   <term>[NSNumber]</term>
 *   <desc>
 *     Number objects were not traditionally allowed in <em>property lists</em>
 *     but were added when the XML format was intoroduced.  GNUstep provides
 *     an extension to the traditional <em>property list</em> format to
 *     support number objects, but older code will not read
 *     <em>property lists</em> containing this extension.<br />
 *     Numbers are stored in a variety of formats depending on their values.
 *     <list>
 *       <item>boolean ... either <code>&lt;*BY&gt;</code> for YES or
 *         <code>&lt;*BN&gt;</code> for NO.<br />
 *         In XML format this is either <code>&lt;true /&gt;</code> or
 *         <code>&lt;false /&gt;</code>
 *       </item>
 *       <item>integer ... <code>&lt;*INNN&gt;</code> where NNN is an
 *         integer.<br />
 *         In XML format this is <code>&lt;integer&gt;NNN&lt;integer&gt;</code>
 *       </item>
 *       <item>real ... <code>&lt;*RNNN&gt;</code> where NNN is a real
 *         number.<br />
 *         In XML format this is <code>&lt;real&gt;NNN&lt;real&gt;</code>
 *       </item>
 *     </list>
 *   </desc>
 *   <term>[NSString]</term>
 *   <desc>
 *     A string is either stored literally (if it contains no spaces or special
 *     characters), or is stored as a quoted string with special characters
 *     escaped where necessary.<br />
 *     Escape conventions are similar to those normally used in ObjectiveC
 *     programming, using a backslash followed by -
 *     <list>
 *      <item><strong>\</strong> a backslash character</item>
 *      <item><strong>"</strong> a quote character</item>
 *      <item><strong>b</strong> a backspace character</item>
 *      <item><strong>n</strong> a newline character</item>
 *      <item><strong>r</strong> a carriage return character</item>
 *      <item><strong>t</strong> a tab character</item>
 *      <item><strong>OOO</strong> (three octal digits)
 *	  an arbitrary ascii character</item>
 *      <item><strong>UXXXX</strong> (where X is a hexadecimal digit)
 *	  a an arbitrary unicode character</item>
 *     </list>
 *     <example>
 *       "hello world &amp; others"
 *     </example>
 *     In XML format, the string is simply stored in UTF8 format as the
 *     content of a <code>string</code> element, and the only character
 *     escapes  required are those used by XML such as the
 *     '&amp;lt;' markup representing a '&lt;' character.
 *     <example>
 *       &lt;string&gt;hello world &amp;amp; others&lt;/string&gt;"
 *     </example>
 *   </desc>
 * </deflist>
 */
- (id) propertyList
{
  return GSPropertyList(self);
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
  return GSPropertyListFromStringsFormat(self);
}

@end

/**
 * This is the mutable form of the NSString class.
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

+ (NSMutableString*) string
{
  return AUTORELEASE([[GSMutableStringClass allocWithZone:
    NSDefaultMallocZone()] initWithCapacity: 0]);
}

+ (NSMutableString*) stringWithCapacity: (unsigned int)capacity
{
  return AUTORELEASE([[GSMutableStringClass allocWithZone:
    NSDefaultMallocZone()] initWithCapacity: capacity]);
}

/* Inefficient. */
+ (NSString*) stringWithCharacters: (const unichar*)characters
			    length: (unsigned int)length
{
  return AUTORELEASE([[GSMutableStringClass allocWithZone:
    NSDefaultMallocZone()] initWithCharacters: characters length: length]);
}

+ (id) stringWithContentsOfFile: (NSString *)path
{
  return AUTORELEASE([[GSMutableStringClass allocWithZone:
    NSDefaultMallocZone()] initWithContentsOfFile: path]);
}

+ (NSString*) stringWithCString: (const char*)byteString
{
  return AUTORELEASE([[GSMutableStringClass allocWithZone:
    NSDefaultMallocZone()] initWithCString: byteString]);
}

+ (NSString*) stringWithCString: (const char*)byteString
			 length: (unsigned int)length
{
  return AUTORELEASE([[GSMutableStringClass allocWithZone:
    NSDefaultMallocZone()] initWithCString: byteString length: length]);
}

+ (NSString*) stringWithFormat: (NSString*)format, ...
{
  va_list ap;
  va_start(ap, format);
  self = [super stringWithFormat: format arguments: ap];
  va_end(ap);
  return self;
}

// Designated initialiser
- (id) initWithCapacity: (unsigned int)capacity
{
  [self subclassResponsibility: _cmd];
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

- (void) appendString: (NSString*)aString
{
  NSRange aRange;

  aRange.location = [self length];
  aRange.length = 0;
  [self replaceCharactersInRange: aRange withString: aString];
}

/* Inefficient. */
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

- (void) deleteCharactersInRange: (NSRange)range
{
  [self replaceCharactersInRange: range withString: nil];
}

- (void) insertString: (NSString*)aString atIndex: (unsigned int)loc
{
  NSRange range = {loc, 0};
  [self replaceCharactersInRange: range withString: aString];
}

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
 * whether only leading/trailing occurrances (anchored search) of
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

  if (replace == nil)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"%@ nil search string", NSStringFromSelector(_cmd)];
    }
  if (by == nil)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"%@ nil replace string", NSStringFromSelector(_cmd)];
    }
  range = [self rangeOfString: replace options: opts range: searchRange];

  if (range.length > 0)
    {
      unsigned	byLen = [by length];

      do
	{
	  count++;
	  [self replaceCharactersInRange: range
			      withString: by];
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

	  range = [self rangeOfString: replace
			      options: opts
				range: searchRange];
	}
      while (range.length > 0);
    }
  return count;
}

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
@class	NSImmutableString;
@class	GSImmutableString;

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



#ifdef	HAVE_LIBXML
#include	"GNUstepBase/GSXML.h"
static int      XML_ELEMENT_NODE;
#endif

#define inrange(ch,min,max) ((ch)>=(min) && (ch)<=(max))
#define char2num(ch) \
inrange(ch,'0','9') \
? ((ch)-0x30) \
: (inrange(ch,'a','f') \
? ((ch)-0x57) : ((ch)-0x37))

typedef	struct	{
  const unichar	*ptr;
  unsigned	end;
  unsigned	pos;
  unsigned	lin;
  NSString	*err;
} pldata;

/*
 *	Property list parsing - skip whitespace keeping count of lines and
 *	regarding objective-c style comments as whitespace.
 *	Returns YES if there is any non-whitespace text remaining.
 */
static BOOL skipSpace(pldata *pld)
{
  unichar	c;

  while (pld->pos < pld->end)
    {
      c = pld->ptr[pld->pos];

      if (GS_IS_WHITESPACE(c) == NO)
	{
	  if (c == '/' && pld->pos < pld->end - 1)
	    {
	      /*
	       * Check for comments beginning '/' followed by '/' or '*'
	       */
	      if (pld->ptr[pld->pos + 1] == '/')
		{
		  pld->pos += 2;
		  while (pld->pos < pld->end)
		    {
		      c = pld->ptr[pld->pos];
		      if (c == '\n')
			{
			  break;
			}
		      pld->pos++;
		    }
		  if (pld->pos >= pld->end)
		    {
		      pld->err = @"reached end of string in comment";
		      return NO;
		    }
		}
	      else if (pld->ptr[pld->pos + 1] == '*')
		{
		  pld->pos += 2;
		  while (pld->pos < pld->end)
		    {
		      c = pld->ptr[pld->pos];
		      if (c == '\n')
			{
			  pld->lin++;
			}
		      else if (c == '*' && pld->pos < pld->end - 1
			&& pld->ptr[pld->pos+1] == '/')
			{
			  pld->pos++; /* Skip past '*'	*/
			  break;
			}
		      pld->pos++;
		    }
		  if (pld->pos >= pld->end)
		    {
		      pld->err = @"reached end of string in comment";
		      return NO;
		    }
		}
	      else
		{
		  return YES;
		}
	    }
	  else
	    {
	      return YES;
	    }
	}
      if (c == '\n')
	{
	  pld->lin++;
	}
      pld->pos++;
    }
  pld->err = @"reached end of string";
  return NO;
}

static inline id parseQuotedString(pldata* pld)
{
  unsigned	start = ++pld->pos;
  unsigned	escaped = 0;
  unsigned	shrink = 0;
  BOOL		hex = NO;
  NSString	*obj;

  while (pld->pos < pld->end)
    {
      unichar	c = pld->ptr[pld->pos];

      if (escaped)
	{
	  if (escaped == 1 && c >= '0' && c <= '7')
	    {
	      escaped = 2;
	      hex = NO;
	    }
	  else if (escaped == 1 && (c == 'u' || c == 'U'))
	    {
	      escaped = 2;
	      hex = YES;
	    }
	  else if (escaped > 1)
	    {
	      if (hex && GS_IS_HEXDIGIT(c))
		{
		  shrink++;
		  escaped++;
		  if (escaped == 6)
		    {
		      escaped = 0;
		    }
		}
	      else if (c >= '0' && c <= '7')
		{
		  shrink++;
		  escaped++;
		  if (escaped == 4)
		    {
		      escaped = 0;
		    }
		}
	      else
		{
		  pld->pos--;
		  escaped = 0;
		}
	    }
	  else
	    {
	      escaped = 0;
	    }
	}
      else
	{
	  if (c == '\\')
	    {
	      escaped = 1;
	      shrink++;
	    }
	  else if (c == '"')
	    {
	      break;
	    }
	}
      if (c == '\n')
	pld->lin++;
      pld->pos++;
    }
  if (pld->pos >= pld->end)
    {
      pld->err = @"reached end of string while parsing quoted string";
      return nil;
    }
  if (pld->pos - start - shrink == 0)
    {
      obj = @"";
    }
  else
    {
      unichar	chars[pld->pos - start - shrink];
      unsigned	j;
      unsigned	k;

      escaped = 0;
      hex = NO;
      for (j = start, k = 0; j < pld->pos; j++)
	{
	  unichar	c = pld->ptr[j];

	  if (escaped)
	    {
	      if (escaped == 1 && c >= '0' && c <= '7')
		{
		  chars[k] = c - '0';
		  hex = NO;
		  escaped++;
		}
	      else if (escaped == 1 && (c == 'u' || c == 'U'))
		{
		  chars[k] = 0;
		  hex = YES;
		  escaped++;
		}
	      else if (escaped > 1)
		{
		  if (hex && GS_IS_HEXDIGIT(c))
		    {
		      chars[k] <<= 4;
		      chars[k] |= char2num(c);
		      escaped++;
		      if (escaped == 6)
			{
			  escaped = 0;
			  k++;
			}
		    }
		  else if (c >= '0' && c <= '7')
		    {
		      chars[k] <<= 3;
		      chars[k] |= (c - '0');
		      escaped++;
		      if (escaped == 4)
			{
			  escaped = 0;
			  k++;
			}
		    }
		  else
		    {
		      escaped = 0;
		      j--;
		      k++;
		    }
		}
	      else
		{
		  escaped = 0;
		  switch (c)
		    {
		      case 'a' : chars[k] = '\a'; break;
		      case 'b' : chars[k] = '\b'; break;
		      case 't' : chars[k] = '\t'; break;
		      case 'r' : chars[k] = '\r'; break;
		      case 'n' : chars[k] = '\n'; break;
		      case 'v' : chars[k] = '\v'; break;
		      case 'f' : chars[k] = '\f'; break;
		      default  : chars[k] = c; break;
		    }
		  k++;
		}
	    }
	  else
	    {
	      chars[k] = c;
	      if (c == '\\')
		{
		  escaped = 1;
		}
	      else
		{
		  k++;
		}
	    }
	}
      obj = (*plAlloc)(NSStringClass, @selector(allocWithZone:),
	NSDefaultMallocZone());
      obj = (*plInit)(obj, plSel, (void*)chars, pld->pos - start - shrink);
    }
  pld->pos++;
  return obj;
}

static inline id parseUnquotedString(pldata *pld)
{
  unsigned	start = pld->pos;
  id		obj;

  while (pld->pos < pld->end)
    {
      if (GS_IS_QUOTABLE(pld->ptr[pld->pos]) == YES)
	break;
      pld->pos++;
    }
  obj = (*plAlloc)(NSStringClass, @selector(allocWithZone:),
    NSDefaultMallocZone());
  obj = (*plInit)(obj, plSel, (void*)&pld->ptr[start], pld->pos-start);
  return obj;
}

static id parsePlItem(pldata* pld)
{
  id	result = nil;
  BOOL	start = (pld->pos == 1 ? YES : NO);

  if (skipSpace(pld) == NO)
    {
      return nil;
    }
  switch (pld->ptr[pld->pos])
    {
      case '{':
	{
	  NSMutableDictionary	*dict;

	  dict = [[plDictionary allocWithZone: NSDefaultMallocZone()]
	    initWithCapacity: 0];
	  pld->pos++;
	  while (skipSpace(pld) == YES && pld->ptr[pld->pos] != '}')
	    {
	      id	key;
	      id	val;

	      key = parsePlItem(pld);
	      if (key == nil)
		{
		  return nil;
		}
	      if (skipSpace(pld) == NO)
		{
		  RELEASE(key);
		  RELEASE(dict);
		  return nil;
		}
	      if (pld->ptr[pld->pos] != '=')
		{
		  pld->err = @"unexpected character (wanted '=')";
		  RELEASE(key);
		  RELEASE(dict);
		  return nil;
		}
	      pld->pos++;
	      val = parsePlItem(pld);
	      if (val == nil)
		{
		  RELEASE(key);
		  RELEASE(dict);
		  return nil;
		}
	      if (skipSpace(pld) == NO)
		{
		  RELEASE(key);
		  RELEASE(val);
		  RELEASE(dict);
		  return nil;
		}
	      if (pld->ptr[pld->pos] == ';')
		{
		  pld->pos++;
		}
	      else if (pld->ptr[pld->pos] != '}')
		{
		  pld->err = @"unexpected character (wanted ';' or '}')";
		  RELEASE(key);
		  RELEASE(val);
		  RELEASE(dict);
		  return nil;
		}
	      (*plSet)(dict, @selector(setObject:forKey:), val, key);
	      RELEASE(key);
	      RELEASE(val);
	    }
	  if (pld->pos >= pld->end)
	    {
	      pld->err = @"unexpected end of string when parsing dictionary";
	      RELEASE(dict);
	      return nil;
	    }
	  pld->pos++;
	  result = dict;
	}
	break;

      case '(':
	{
	  NSMutableArray	*array;

	  array = [[plArray allocWithZone: NSDefaultMallocZone()]
	    initWithCapacity: 0];
	  pld->pos++;
	  while (skipSpace(pld) == YES && pld->ptr[pld->pos] != ')')
	    {
	      id	val;

	      val = parsePlItem(pld);
	      if (val == nil)
		{
		  RELEASE(array);
		  return nil;
		}
	      if (skipSpace(pld) == NO)
		{
		  RELEASE(val);
		  RELEASE(array);
		  return nil;
		}
	      if (pld->ptr[pld->pos] == ',')
		{
		  pld->pos++;
		}
	      else if (pld->ptr[pld->pos] != ')')
		{
		  pld->err = @"unexpected character (wanted ',' or ')')";
		  RELEASE(val);
		  RELEASE(array);
		  return nil;
		}
	      (*plAdd)(array, @selector(addObject:), val);
	      RELEASE(val);
	    }
	  if (pld->pos >= pld->end)
	    {
	      pld->err = @"unexpected end of string when parsing array";
	      RELEASE(array);
	      return nil;
	    }
	  pld->pos++;
	  result = array;
	}
	break;

      case '<':
	pld->pos++;
	if (pld->pos < pld->end && pld->ptr[pld->pos] == '*')
	  {
	    const unichar	*ptr;
	    unsigned		min;
	    unsigned		len = 0;
	    unsigned		i;

	    pld->pos++;
	    min = pld->pos;
	    ptr = &(pld->ptr[min]);
	    while (pld->pos < pld->end && pld->ptr[pld->pos] != '>')
	      {
		pld->pos++;
	      }
	    len = pld->pos - min;
	    if (len > 1)
	      {
		unichar	type = *ptr++;

		len--;
		if (type == 'I')
		  {
		    char	buf[len+1];

		    for (i = 0; i < len; i++) buf[i] = (char)ptr[i];
		    buf[len] = '\0';
		    result = [[NSNumber alloc] initWithLong: atol(buf)];
		  }
		else if (type == 'B')
		  {
		    if (ptr[0] == 'Y')
		      {
			result = [[NSNumber alloc] initWithBool: YES];
		      }
		    else if (ptr[0] == 'N')
		      {
			result = [[NSNumber alloc] initWithBool: NO];
		      }
		    else
		      {
			pld->err = @"bad value for bool";
			return nil;
		      }
		  }
		else if (type == 'D')
		  {
		    NSString	*str;

		    str = [[NSString alloc] initWithCharacters: ptr
							length: len];
		    result = [[NSCalendarDate alloc] initWithString: str
		      calendarFormat: @"%Y-%m-%d %H:%M:%S %z"];
		    RELEASE(str);
		  }
		else if (type == 'R')
		  {
		    unichar	buf[len];
		    double	d = 0.0;

		    for (i = 0; i < len; i++) buf[i] = (char)ptr[i];
		    GSScanDouble(buf, len, &d);
		    result = [[NSNumber alloc] initWithDouble: d];
		  }
		else
		  {
		    pld->err = @"unrecognized type code after '<*'";
		    return nil;
		  }
	      }
	    else
	      {
		pld->err = @"missing type code after '<*'";
		return nil;
	      }
	    if (pld->pos >= pld->end)
	      {
		pld->err = @"unexpected end of string when parsing data";
		return nil;
	      }
	    if (pld->ptr[pld->pos] != '>')
	      {
		pld->err = @"unexpected character in string";
		return nil;
	      }
	    pld->pos++;
	  }
	else
	  {
	    NSMutableData	*data;
	    unsigned	max = pld->end - 1;
	    unsigned	char	buf[BUFSIZ];
	    unsigned	len = 0;

	    data = [[NSMutableData alloc] initWithCapacity: 0];
	    skipSpace(pld);
	    while (pld->pos < max
	      && GS_IS_HEXDIGIT(pld->ptr[pld->pos])
	      && GS_IS_HEXDIGIT(pld->ptr[pld->pos+1]))
	      {
		unsigned char	byte;

		byte = (char2num(pld->ptr[pld->pos])) << 4;
		pld->pos++;
		byte |= char2num(pld->ptr[pld->pos]);
		pld->pos++;
		buf[len++] = byte;
		if (len == sizeof(buf))
		  {
		    [data appendBytes: buf length: len];
		    len = 0;
		  }
		skipSpace(pld);
	      }
	    if (pld->pos >= pld->end)
	      {
		pld->err = @"unexpected end of string when parsing data";
		RELEASE(data);
		return nil;
	      }
	    if (pld->ptr[pld->pos] != '>')
	      {
		pld->err = @"unexpected character in string";
		RELEASE(data);
		return nil;
	      }
	    if (len > 0)
	      {
		[data appendBytes: buf length: len];
	      }
	    pld->pos++;
	    result = data;
	  }
	break;

      case '"':
	result = parseQuotedString(pld);
	break;

      default:
	result = parseUnquotedString(pld);
	break;
    }
  if (start == YES && result != nil)
    {
      if (skipSpace(pld) == YES)
	{
	  pld->err = @"extra data after parsed string";
	  result = nil;		// Not at end of string.
	}
    }
  return result;
}

#ifdef	HAVE_LIBXML
static GSXMLNode*
elementNode(GSXMLNode* node)
{
  while (node != nil)
    {
      if ([node type] == XML_ELEMENT_NODE)
        {
          break;
        }
      node = [node next];
    }
  return node;
}

static id
nodeToObject(GSXMLNode* node)
{
  CREATE_AUTORELEASE_POOL(arp);
  id		result = nil;

  node = elementNode(node);
  if (node != nil)
    {
      NSString	*name;
      NSString	*content;
      GSXMLNode	*children;

      name = [node name];
      children = [node firstChild];
      content = [children content];
      children = elementNode(children);

      if ([name isEqualToString: @"string"]
	|| [name isEqualToString: @"key"])
	{
	  if (content == nil)
	    {
	      content = @"";
	    }
	  else
	    {
	      NSRange	r;

	      r = [content rangeOfString: @"\\"];
	      if (r.length == 1)
		{
		  unsigned	len = [content length];
		  unichar	buf[len];
		  unsigned	pos = r.location;

		  [content getCharacters: buf];
		  while (pos < len)
		    {
		      if (++pos < len)
			{
			  if ((buf[pos] == 'u' || buf[pos] == 'U')
			    && (len >= pos + 4))
			    {
			      unichar	val = 0;
			      unsigned	i;
			      BOOL		ok = YES;

			      for (i = 1; i < 5; i++)
				{
				  unichar	c = buf[pos + i];

				  if (c >= '0' && c <= '9')
				    {
				      val = (val << 4) + c - '0';
				    }
				  else if (c >= 'A' && c <= 'F')
				    {
				      val = (val << 4) + c - 'A' + 10;
				    }
				  else if (c >= 'a' && c <= 'f')
				    {
				      val = (val << 4) + c - 'a' + 10;
				    }
				  else
				    {
				      ok = NO;
				    }
				}
			      if (ok == YES)
				{
				  len -= 5;
				  memcpy(&buf[pos], &buf[pos+5],
				    (len - pos) * sizeof(unichar));
				  buf[pos - 1] = val;
				}
			    }
			  while (pos < len && buf[pos] != '\\')
			    {
			      pos++;
			    }
			}
		    }
		  content = [NSString stringWithCharacters: buf length: len];
		}
	    }
	  result = content;
	}
      else if ([name isEqualToString: @"true"])
	{
	  result = [NSNumber numberWithBool: YES];
	}
      else if ([name isEqualToString: @"false"])
	{
	  result = [NSNumber numberWithBool: NO];
	}
      else if ([name isEqualToString: @"integer"])
	{
	  if (content == nil)
	    {
	      content = @"0";
	    }
	  result = [NSNumber numberWithInt: [content intValue]];
	}
      else if ([name isEqualToString: @"real"])
	{
	  if (content == nil)
	    {
	      content = @"0.0";
	    }
	  result = [NSNumber numberWithDouble: [content doubleValue]];
	}
      else if ([name isEqualToString: @"date"])
	{
	  if (content == nil)
	    {
	      content = @"";
	    }
	  result = [NSCalendarDate dateWithString: content
				 calendarFormat: @"%Y-%m-%d %H:%M:%S %z"];
	}
      else if ([name isEqualToString: @"data"])
	{
	  result = [GSMimeDocument decodeBase64String: content];
	}
      // container class
      else if ([name isEqualToString: @"array"])
	{
	  NSMutableArray	*container = [NSMutableArray array];

	  while (children != nil)
	    {
	      id	val;

	      val = nodeToObject(children);
	      [container addObject: val];
	      children = [children nextElement];
	    }
	  result = container;
	}
      else if ([name isEqualToString: @"dict"])
	{
	  NSMutableDictionary	*container = [NSMutableDictionary dictionary];

	  while (children != nil)
	    {
	      NSString	*key;
	      id	val;

	      key = nodeToObject(children);
	      children = [children nextElement];
	      val = nodeToObject(children);
	      children = [children nextElement];
	      [container setObject: val forKey: key];
	    }
	  result = container;
	}
    }
  RETAIN(result);
  RELEASE(arp);
  return AUTORELEASE(result);
}
#endif

static void
setupPl()
{
#ifdef	HAVE_LIBXML
  /*
   * Cache XML node information.
   */
  XML_ELEMENT_NODE = [GSXMLNode typeFromDescription: @"XML_ELEMENT_NODE"];
#endif
  plAlloc = (id (*)(id, SEL, NSZone*))
    [NSStringClass methodForSelector: @selector(allocWithZone:)];
  plInit = (id (*)(id, SEL, unichar*, unsigned int))
    [NSStringClass instanceMethodForSelector: plSel];

  plArray = [GSMutableArray class];
  plAdd = (id (*)(id, SEL, id))
    [plArray instanceMethodForSelector: @selector(addObject:)];

  plDictionary = [GSMutableDictionary class];
  plSet = (id (*)(id, SEL, id, id))
    [plDictionary instanceMethodForSelector: @selector(setObject:forKey:)];

  setupHexdigits();
  setupQuotables();
  setupWhitespace();
}

static id
GSPropertyList(NSString *string)
{
  pldata	_pld;
  pldata	*pld = &_pld;
  unsigned	length = [string length];
  NSData	*d;
  id		pl;
#ifdef	HAVE_LIBXML
  unsigned	index = 0;
#endif

  /*
   * An empty string is a nil property list.
   */
  if (length == 0)
    {
      return nil;
    }

  if (plAlloc == 0)
    {
      setupPl();
    }

#ifdef	HAVE_LIBXML
  if (whitespaceBitmapRep == NULL)
    {
      setupWhitespace();
    }
  while (index < length)
    {
      unsigned	c = [string characterAtIndex: index];

      if (GS_IS_WHITESPACE(c) == NO)
	{
	  break;
	}
      index++;
    }
  /*
   * A string beginning with a '<?' must be an XML file
   */
  if (index + 1 < length && [string characterAtIndex: index] == '<'
    && [string characterAtIndex: index+1] == '?')
    {
      NSData		*data;
      GSXMLParser	*parser;

      data = [string dataUsingEncoding: NSUTF8StringEncoding];
      parser = [GSXMLParser parser];
      [parser substituteEntities: YES];
      [parser doValidityChecking: YES];
      if ([parser parse: data] == NO || [parser parse: nil] == NO)
	{
	  [NSException raise: NSGenericException
		      format: @"not a property list - failed to parse as XML"];
	  return nil;
	}
      if (![[[[parser document] root] name] isEqualToString: @"plist"])
	{
	  [NSException raise: NSGenericException
		      format: @"not a property list - because name node is %@",
	    [[[parser document] root] name]];
	  return nil;
	}
      pl = RETAIN(nodeToObject([[[parser document] root] firstChild]));
      return AUTORELEASE(pl);
    }
#endif
  d = [string dataUsingEncoding: NSUnicodeStringEncoding];
  _pld.ptr = (unichar*)[d bytes];
  _pld.pos = 1;
  _pld.end = length + 1;
  _pld.err = nil;
  _pld.lin = 1;
  pl = AUTORELEASE(parsePlItem(pld));
  if (pl == nil && _pld.err != nil)
    {
      [NSException raise: NSGenericException
		  format: @"Parse failed at line %d (char %d) - %@",
	_pld.lin, _pld.pos, _pld.err];
    }
  return pl;
}

static id
GSPropertyListFromStringsFormat(NSString *string)
{
  NSMutableDictionary	*dict;
  pldata		_pld;
  pldata		*pld = &_pld;
  unsigned		length = [string length];
  NSData		*d;

  /*
   * An empty string is a nil property list.
   */
  if (length == 0)
    {
      return nil;
    }

  d = [string dataUsingEncoding: NSUnicodeStringEncoding];
  _pld.ptr = (unichar*)[d bytes];
  _pld.pos = 1;
  _pld.end = length + 1;
  _pld.err = nil;
  _pld.lin = 1;
  if (plAlloc == 0)
    {
      setupPl();
    }

  dict = [[plDictionary allocWithZone: NSDefaultMallocZone()]
    initWithCapacity: 0];
  while (skipSpace(pld) == YES)
    {
      id	key;
      id	val;

      if (pld->ptr[pld->pos] == '"')
	{
	  key = parseQuotedString(pld);
	}
      else
	{
	  key = parseUnquotedString(pld);
	}
      if (key == nil)
	{
	  DESTROY(dict);
	  break;
	}
      if (skipSpace(pld) == NO)
	{
	  pld->err = @"incomplete final entry (no semicolon?)";
	  RELEASE(key);
	  DESTROY(dict);
	  break;
	}
      if (pld->ptr[pld->pos] == ';')
	{
	  pld->pos++;
	  (*plSet)(dict, @selector(setObject:forKey:), @"", key);
	  RELEASE(key);
	}
      else if (pld->ptr[pld->pos] == '=')
	{
	  pld->pos++;
	  if (skipSpace(pld) == NO)
	    {
	      RELEASE(key);
	      DESTROY(dict);
	      break;
	    }
	  if (pld->ptr[pld->pos] == '"')
	    {
	      val = parseQuotedString(pld);
	    }
	  else
	    {
	      val = parseUnquotedString(pld);
	    }
	  if (val == nil)
	    {
	      RELEASE(key);
	      DESTROY(dict);
	      break;
	    }
	  if (skipSpace(pld) == NO)
	    {
	      pld->err = @"missing final semicolon";
	      RELEASE(key);
	      RELEASE(val);
	      DESTROY(dict);
	      break;
	    }
	  (*plSet)(dict, @selector(setObject:forKey:), val, key);
	  RELEASE(key);
	  RELEASE(val);
	  if (pld->ptr[pld->pos] == ';')
	    {
	      pld->pos++;
	    }
	  else
	    {
	      pld->err = @"unexpected character (wanted ';')";
	      DESTROY(dict);
	      break;
	    }
	}
      else
	{
	  pld->err = @"unexpected character (wanted '=' or ';')";
	  RELEASE(key);
	  DESTROY(dict);
	  break;
	}
    }
  if (dict == nil && _pld.err != nil)
    {
      RELEASE(dict);
      [NSException raise: NSGenericException
		  format: @"Parse failed at line %d (char %d) - %@",
	_pld.lin, _pld.pos, _pld.err];
    }
  return AUTORELEASE(dict);
}

