/* Implementation of extension methods to standard classes

   Copyright (C) 2003 Free Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <rfm@gnu.org>

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

*/
#include "config.h"
#include <string.h>
#include <Foundation/Foundation.h>
#include "GNUstepBase/GSCategories.h"
#include "GNUstepBase/GSLock.h"

/**
 * Extension methods for the NSCalendarDate class
 */
@implementation NSCalendarDate (GSCategories)

/**
 * The ISO standard week of the year is based on the first week of the
 * year being that week (starting on monday) for which the thursday
 * is on or after the first of january.<br />
 * This has the effect that, if january first is a friday, saturday or
 * sunday, the days of that week (up to and including the sunday) are
 * considered to be in week 53 of the preceeding year. Similarly if the
 * last day of the year is a monday tuesday or wednesday, these days are
 * part of week 1 of the next year.
 */
- (int) weekOfYear
{
  int	dayOfWeek = [self dayOfWeek];
  int	dayOfYear;

  /*
   * Whether a week is considered to be in a year or not depends on its
   * thursday ... so find thursday for the receivers week.
   * NB. this may result in a date which is not in the same year as the
   * receiver.
   */
  if (dayOfWeek != 4)
    {
      CREATE_AUTORELEASE_POOL(arp);
      NSCalendarDate	*thursday;

      /*
       * A week starts on monday ... so adjust from 0 to 7 so that a
       * sunday is counted as the last day of the week.
       */
      if (dayOfWeek == 0)
	{
	  dayOfWeek = 7;
	}
      thursday = [self dateByAddingYears: 0
				  months: 0
				    days: 4 - dayOfWeek
				   hours: 0
				 minutes: 0
				 seconds: 0];
      dayOfYear = [thursday dayOfYear];
      RELEASE(arp);
    }
  else
    {
      dayOfYear = [self dayOfYear];
    }
  
  /*
   * Round up to a week boundary, so that when we divide by seven we
   * get a result in the range 1 to 53 as mandated by the ISO standard.
   */
  dayOfYear += (7 - dayOfYear % 7);
  return dayOfYear / 7;
}

@end



/**
 * Extension methods for the NSData class
 */
@implementation NSData (GSCategories)

/**
 * Returns an NSString object containing an ASCII hexadecimal representation
 * of the receiver.  This means that the returned object will contain
 * exactly twice as many characters as there are bytes as the receiver,
 * as each byte in the receiver is represented by two hexadecimal digits.<br />
 * The high order four bits of each byte is encoded before the low
 * order four bits.  Capital letters 'A' to 'F' are used to represent
 * values from 10 to 15.<br />
 * If you need the hexadecimal representation as raw byte data, use code
 * like -
 * <example>
 *   hexData = [[sourceData hexadecimalRepresentation]
 *     dataUsingEncoding: NSASCIIStringEncoding];
 * </example>
 */
- (NSString*) hexadecimalRepresentation
{
  static const char	*hexChars = "0123456789ABCDEF";
  unsigned		slen = [self length];
  unsigned		dlen = slen * 2;
  const unsigned char	*src = (const unsigned char *)[self bytes];
  char			*dst = (char*)NSZoneMalloc(NSDefaultMallocZone(), dlen);
  unsigned		spos = 0;
  unsigned		dpos = 0;
  NSData		*data;
  NSString		*string;

  while (spos < slen)
    {
      unsigned char	c = src[spos++];

      dst[dpos++] = hexChars[(c >> 4) & 0x0f];
      dst[dpos++] = hexChars[c & 0x0f];
    }
  data = [NSData allocWithZone: NSDefaultMallocZone()];
  data = [data initWithBytesNoCopy: dst length: dlen freeWhenDone: YES];
  string = [[NSString alloc] initWithData: data
				 encoding: NSASCIIStringEncoding];
  RELEASE(data);
  return AUTORELEASE(string);
}

/**
 * Initialises the receiver with the supplied string data which contains
 * a hexadecimal coding of the bytes.  The parsing of the string is
 * fairly tolerant, ignoring whitespace and permitting both upper and
 * lower case hexadecimal digits (the -hexadecimalRepresentation method
 * produces a string using only uppercase digits with no white spaqce).<br />
 * If the string does not contain one or more pairs of hexadecimal digits
 * then an exception is raised. 
 */
- (id) initWithHexadecimalRepresentation: (NSString*)string
{
  CREATE_AUTORELEASE_POOL(arp);
  NSData	*d;
  const char	*src;
  const char	*end;
  unsigned char	*dst;
  unsigned int	pos = 0;
  unsigned char	byte = 0;
  BOOL		high = NO;

  d = [string dataUsingEncoding: NSASCIIStringEncoding
	   allowLossyConversion: YES];
  src = (const char*)[d bytes];
  end = src + [d length];
  dst = NSZoneMalloc(NSDefaultMallocZone(), [d length]/2 + 1);

  while (src < end)
    {
      char		c = *src++;
      unsigned char	v;

      if (isspace(c))
	{
	  continue;
	}
      if (c >= '0' && c <= '9')
	{
	  v = c - '0';
	}
      else if (c >= 'A' && c <= 'F')
	{
	  v = c - 'A' + 10;
	}
      else if (c >= 'a' && c <= 'f')
	{
	  v = c - 'a' + 10;
	}
      else
	{
	  pos = 0;
	  break;
	}
      if (high == NO)
	{
	  byte = v << 4;
	  high = YES;
	}
      else
	{
	  byte |= v;
	  high = NO;
	  dst[pos++] = byte;
	}
    }
  if (pos > 0 && high == NO)
    {
      self = [self initWithBytes: dst length: pos];
    }
  else
    {
      DESTROY(self);
    }
  NSZoneFree(NSDefaultMallocZone(), dst);
  RELEASE(arp);
  if (self == nil)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"%@: invalid hexadeciaml string data",
	NSStringFromSelector(_cmd)];
    }
  return self;
}

struct MD5Context
{
  unsigned long buf[4];
  unsigned long bits[2];
  unsigned char in[64];
};
static void MD5Init (struct MD5Context *context);
static void MD5Update (struct MD5Context *context, unsigned char const *buf,
unsigned len);
static void MD5Final (unsigned char digest[16], struct MD5Context *context);
static void MD5Transform (unsigned long buf[4], unsigned long const in[16]);

/*
 * This code implements the MD5 message-digest algorithm.
 * The algorithm is due to Ron Rivest.  This code was
 * written by Colin Plumb in 1993, no copyright is claimed.
 * This code is in the public domain; do with it what you wish.
 *
 * Equivalent code is available from RSA Data Security, Inc.
 * This code has been tested against that, and is equivalent,
 * except that you don't need to include two pages of legalese
 * with every copy.
 *
 * To compute the message digest of a chunk of bytes, declare an
 * MD5Context structure, pass it to MD5Init, call MD5Update as
 * needed on buffers full of bytes, and then call MD5Final, which
 * will fill a supplied 16-byte array with the digest.
 */

/*
 * Ensure data is little-endian
 */
static void littleEndian (void *buf, unsigned longs)
{
  unsigned long	*ptr = (unsigned long*)buf;
  do
    {
      *ptr = NSSwapHostLongToLittle(*ptr);
      ptr++;
    }
  while (--longs);
}

/*
 * Start MD5 accumulation.  Set bit count to 0 and buffer to mysterious
 * initialization constants.
 */
static void MD5Init (struct MD5Context *ctx)
{
  ctx->buf[0] = 0x67452301;
  ctx->buf[1] = 0xefcdab89;
  ctx->buf[2] = 0x98badcfe;
  ctx->buf[3] = 0x10325476;

  ctx->bits[0] = 0;
  ctx->bits[1] = 0;
}

/*
 * Update context to reflect the concatenation of another buffer full
 * of bytes.
 */
static void MD5Update (struct MD5Context *ctx, unsigned char const *buf,
  unsigned len)
{
  unsigned long t;

  /* Update bitcount */

  t = ctx->bits[0];
  if ((ctx->bits[0] = t + ((unsigned long) len << 3)) < t)
    ctx->bits[1]++;		/* Carry from low to high */
  ctx->bits[1] += len >> 29;

  t = (t >> 3) & 0x3f;	/* Bytes already in shsInfo->data */

  /* Handle any leading odd-sized chunks */

  if (t)
    {
      unsigned char *p = (unsigned char *) ctx->in + t;

      t = 64 - t;
      if (len < t)
	{
	  memcpy (p, buf, len);
	  return;
	}
      memcpy (p, buf, t);
      littleEndian (ctx->in, 16);
      MD5Transform (ctx->buf, (unsigned long *) ctx->in);
      buf += t;
      len -= t;
    }
  /* Process data in 64-byte chunks */

  while (len >= 64)
    {
      memcpy (ctx->in, buf, 64);
      littleEndian (ctx->in, 16);
      MD5Transform (ctx->buf, (unsigned long *) ctx->in);
      buf += 64;
      len -= 64;
    }

  /* Handle any remaining bytes of data. */

  memcpy (ctx->in, buf, len);
}

/*
 * Final wrapup - pad to 64-byte boundary with the bit pattern 
 * 1 0* (64-bit count of bits processed, MSB-first)
 */
static void MD5Final (unsigned char digest[16], struct MD5Context *ctx)
{
  unsigned count;
  unsigned char *p;

  /* Compute number of bytes mod 64 */
  count = (ctx->bits[0] >> 3) & 0x3F;

  /* Set the first char of padding to 0x80.  This is safe since there is
     always at least one byte free */
  p = ctx->in + count;
  *p++ = 0x80;

  /* Bytes of padding needed to make 64 bytes */
  count = 64 - 1 - count;

  /* Pad out to 56 mod 64 */
  if (count < 8)
    {
      /* Two lots of padding:  Pad the first block to 64 bytes */
      memset (p, 0, count);
      littleEndian (ctx->in, 16);
      MD5Transform (ctx->buf, (unsigned long *) ctx->in);

      /* Now fill the next block with 56 bytes */
      memset (ctx->in, 0, 56);
    }
  else
    {
      /* Pad block to 56 bytes */
      memset (p, 0, count - 8);
    }
  littleEndian (ctx->in, 14);

  /* Append length in bits and transform */
  ((unsigned long *) ctx->in)[14] = ctx->bits[0];
  ((unsigned long *) ctx->in)[15] = ctx->bits[1];

  MD5Transform (ctx->buf, (unsigned long *) ctx->in);
  littleEndian ((unsigned char *) ctx->buf, 4);
  memcpy (digest, ctx->buf, 16);
  memset (ctx, 0, sizeof (ctx));	/* In case it's sensitive */
}

/* The four core functions - F1 is optimized somewhat */

/* #define F1(x, y, z) (x & y | ~x & z) */
#define F1(x, y, z) (z ^ (x & (y ^ z)))
#define F2(x, y, z) F1(z, x, y)
#define F3(x, y, z) (x ^ y ^ z)
#define F4(x, y, z) (y ^ (x | ~z))

/* This is the central step in the MD5 algorithm. */
#define MD5STEP(f, w, x, y, z, data, s) \
  ( w += f(x, y, z) + data,  w = w<<s | w>>(32-s),  w += x )

/*
 * The core of the MD5 algorithm, this alters an existing MD5 hash to
 * reflect the addition of 16 longwords of new data.  MD5Update blocks
 * the data and converts bytes into longwords for this routine.
 */
static void MD5Transform (unsigned long buf[4], unsigned long const in[16])
{
  register unsigned long a, b, c, d;

  a = buf[0];
  b = buf[1];
  c = buf[2];
  d = buf[3];

  MD5STEP (F1, a, b, c, d, in[0] + 0xd76aa478, 7);
  MD5STEP (F1, d, a, b, c, in[1] + 0xe8c7b756, 12);
  MD5STEP (F1, c, d, a, b, in[2] + 0x242070db, 17);
  MD5STEP (F1, b, c, d, a, in[3] + 0xc1bdceee, 22);
  MD5STEP (F1, a, b, c, d, in[4] + 0xf57c0faf, 7);
  MD5STEP (F1, d, a, b, c, in[5] + 0x4787c62a, 12);
  MD5STEP (F1, c, d, a, b, in[6] + 0xa8304613, 17);
  MD5STEP (F1, b, c, d, a, in[7] + 0xfd469501, 22);
  MD5STEP (F1, a, b, c, d, in[8] + 0x698098d8, 7);
  MD5STEP (F1, d, a, b, c, in[9] + 0x8b44f7af, 12);
  MD5STEP (F1, c, d, a, b, in[10] + 0xffff5bb1, 17);
  MD5STEP (F1, b, c, d, a, in[11] + 0x895cd7be, 22);
  MD5STEP (F1, a, b, c, d, in[12] + 0x6b901122, 7);
  MD5STEP (F1, d, a, b, c, in[13] + 0xfd987193, 12);
  MD5STEP (F1, c, d, a, b, in[14] + 0xa679438e, 17);
  MD5STEP (F1, b, c, d, a, in[15] + 0x49b40821, 22);

  MD5STEP (F2, a, b, c, d, in[1] + 0xf61e2562, 5);
  MD5STEP (F2, d, a, b, c, in[6] + 0xc040b340, 9);
  MD5STEP (F2, c, d, a, b, in[11] + 0x265e5a51, 14);
  MD5STEP (F2, b, c, d, a, in[0] + 0xe9b6c7aa, 20);
  MD5STEP (F2, a, b, c, d, in[5] + 0xd62f105d, 5);
  MD5STEP (F2, d, a, b, c, in[10] + 0x02441453, 9);
  MD5STEP (F2, c, d, a, b, in[15] + 0xd8a1e681, 14);
  MD5STEP (F2, b, c, d, a, in[4] + 0xe7d3fbc8, 20);
  MD5STEP (F2, a, b, c, d, in[9] + 0x21e1cde6, 5);
  MD5STEP (F2, d, a, b, c, in[14] + 0xc33707d6, 9);
  MD5STEP (F2, c, d, a, b, in[3] + 0xf4d50d87, 14);
  MD5STEP (F2, b, c, d, a, in[8] + 0x455a14ed, 20);
  MD5STEP (F2, a, b, c, d, in[13] + 0xa9e3e905, 5);
  MD5STEP (F2, d, a, b, c, in[2] + 0xfcefa3f8, 9);
  MD5STEP (F2, c, d, a, b, in[7] + 0x676f02d9, 14);
  MD5STEP (F2, b, c, d, a, in[12] + 0x8d2a4c8a, 20);

  MD5STEP (F3, a, b, c, d, in[5] + 0xfffa3942, 4);
  MD5STEP (F3, d, a, b, c, in[8] + 0x8771f681, 11);
  MD5STEP (F3, c, d, a, b, in[11] + 0x6d9d6122, 16);
  MD5STEP (F3, b, c, d, a, in[14] + 0xfde5380c, 23);
  MD5STEP (F3, a, b, c, d, in[1] + 0xa4beea44, 4);
  MD5STEP (F3, d, a, b, c, in[4] + 0x4bdecfa9, 11);
  MD5STEP (F3, c, d, a, b, in[7] + 0xf6bb4b60, 16);
  MD5STEP (F3, b, c, d, a, in[10] + 0xbebfbc70, 23);
  MD5STEP (F3, a, b, c, d, in[13] + 0x289b7ec6, 4);
  MD5STEP (F3, d, a, b, c, in[0] + 0xeaa127fa, 11);
  MD5STEP (F3, c, d, a, b, in[3] + 0xd4ef3085, 16);
  MD5STEP (F3, b, c, d, a, in[6] + 0x04881d05, 23);
  MD5STEP (F3, a, b, c, d, in[9] + 0xd9d4d039, 4);
  MD5STEP (F3, d, a, b, c, in[12] + 0xe6db99e5, 11);
  MD5STEP (F3, c, d, a, b, in[15] + 0x1fa27cf8, 16);
  MD5STEP (F3, b, c, d, a, in[2] + 0xc4ac5665, 23);

  MD5STEP (F4, a, b, c, d, in[0] + 0xf4292244, 6);
  MD5STEP (F4, d, a, b, c, in[7] + 0x432aff97, 10);
  MD5STEP (F4, c, d, a, b, in[14] + 0xab9423a7, 15);
  MD5STEP (F4, b, c, d, a, in[5] + 0xfc93a039, 21);
  MD5STEP (F4, a, b, c, d, in[12] + 0x655b59c3, 6);
  MD5STEP (F4, d, a, b, c, in[3] + 0x8f0ccc92, 10);
  MD5STEP (F4, c, d, a, b, in[10] + 0xffeff47d, 15);
  MD5STEP (F4, b, c, d, a, in[1] + 0x85845dd1, 21);
  MD5STEP (F4, a, b, c, d, in[8] + 0x6fa87e4f, 6);
  MD5STEP (F4, d, a, b, c, in[15] + 0xfe2ce6e0, 10);
  MD5STEP (F4, c, d, a, b, in[6] + 0xa3014314, 15);
  MD5STEP (F4, b, c, d, a, in[13] + 0x4e0811a1, 21);
  MD5STEP (F4, a, b, c, d, in[4] + 0xf7537e82, 6);
  MD5STEP (F4, d, a, b, c, in[11] + 0xbd3af235, 10);
  MD5STEP (F4, c, d, a, b, in[2] + 0x2ad7d2bb, 15);
  MD5STEP (F4, b, c, d, a, in[9] + 0xeb86d391, 21);

  buf[0] += a;
  buf[1] += b;
  buf[2] += c;
  buf[3] += d;
}

/**
 * Creates an MD5 digest of the information stored in the receiver and
 * returns it as an autoreleased 16 byte NSData object.<br />
 * If you need to produce a digest of string information, you need to
 * decide what character encoding is to be used and convert your string
 * to a data object of that encoding type first using the
 * [NSString-dataUsingEncoding:] method -
 * <example>
 *   myDigest = [[myString dataUsingEncoding: NSUTF8StringEncoding] md5Digest];
 * </example>
 * If you need to use the digest in a human readable form, you will
 * probably want it to be seen as 32 hexadecimal digits, and can do that
 * using the -hexadecimalRepresentation method.
 */
- (NSData*) md5Digest
{
  struct MD5Context	ctx;
  unsigned char		digest[16];

  MD5Init(&ctx);
  MD5Update(&ctx, [self bytes], [self length]);
  MD5Final(digest, &ctx);
  return [NSData dataWithBytes: digest length: 16];
}

@end

/**
 * GNUstep specific (non-standard) additions to the NSNumber class.
 */
@implementation NSNumber(GSCategories)

+ (NSValue*) valueFromString: (NSString*)string
{
  /* FIXME: implement this better */
  const char *str;

  str = [string cString];
  if (strchr(str, '.') >= 0 || strchr(str, 'e') >= 0 
      || strchr(str, 'E') >= 0)
    return [NSNumber numberWithDouble: atof(str)];
  else if (strchr(str, '-') >= 0)
    return [NSNumber numberWithInt: atoi(str)];
  else
    return [NSNumber numberWithUnsignedInt: atoi(str)];
  return [NSNumber numberWithInt: 0];
}

@end



/** 
 * Extension methods for the NSObject class
 */
@implementation NSObject (GSCategories)

- (id) notImplemented: (SEL)aSel
{
  [NSException
    raise: NSGenericException
    format: @"method %s not implemented in %s(%s)",
    aSel ? GSNameFromSelector(aSel) : "(null)", 
    GSClassNameFromObject(self),
    GSObjCIsInstance(self) ? "instance" : "class"];
  return nil;
}

- (id) shouldNotImplement: (SEL)aSel
{
  [NSException
    raise: NSGenericException
    format: @"%s(%s) should not implement %s", 
    GSClassNameFromObject(self), 
    GSObjCIsInstance(self) ? "instance" : "class",
    aSel ? GSNameFromSelector(aSel) : "(null)"];
  return nil;
}

- (id) subclassResponsibility: (SEL)aSel
{
  [NSException raise: NSGenericException
    format: @"subclass %s(%s) should override %s", 
	       GSClassNameFromObject(self),
	       GSObjCIsInstance(self) ? "instance" : "class",
	       aSel ? GSNameFromSelector(aSel) : "(null)"];
  return nil;
}

/**
 * WARNING: The -compare: method for NSObject is deprecated
 *          due to subclasses declaring the same selector with
 *          conflicting signatures.
 *          Comparision of arbitrary objects is not just meaningless
 *          but also dangerous as most concrete implementations
 *          expect comparable objects as arguments often accessing
 *          instance variables directly.
 *          This method will be removed in a future release.
 */
- (NSComparisonResult) compare: (id)anObject
{
  NSLog(@"WARNING: The -compare: method for NSObject is deprecated.");

  if (anObject == self)
    {
      return NSOrderedSame;
    }
  if (anObject == nil)
    {
      [NSException raise: NSInvalidArgumentException
		   format: @"nil argument for compare:"];
    }
  if ([self isEqual: anObject])
    {
      return NSOrderedSame;
    }
  /*
   * Ordering objects by their address is pretty useless,
   * so subclasses should override this is some useful way.
   */
  if (self > anObject)
    {
      return NSOrderedDescending;
    }
  else
    {
      return NSOrderedAscending;
    }
}

@end

/**
 * GNUstep specific (non-standard) additions to the NSString class.
 */
@implementation NSString (GSCategories)

/**
 * Returns a string formed by removing the prefix string from the
 * receiver.  Raises an exception if the prefix is not present.
 */
- (NSString*) stringByDeletingPrefix: (NSString*)prefix
{
  NSCAssert2([self hasPrefix: prefix],
    @"'%@' does not have the prefix '%@'", self, prefix);
  return [self substringFromIndex: [prefix length]];
}

/**
 * Returns a string formed by removing the suffix string from the
 * receiver.  Raises an exception if the suffix is not present.
 */
- (NSString*) stringByDeletingSuffix: (NSString*)suffix
{
  NSCAssert2([self hasSuffix: suffix],
    @"'%@' does not have the suffix '%@'", self, suffix);
  return [self substringToIndex: ([self length] - [suffix length])];
}

/**
 * Returns a string formed by removing leading white space from the
 * receiver.
 */
- (NSString*) stringByTrimmingLeadSpaces
{
  unsigned	length = [self length];

  if (length > 0)
    {
      unsigned	start = 0;
      unichar	(*caiImp)(NSString*, SEL, unsigned int);
      SEL caiSel = @selector(characterAtIndex:);

      caiImp = (unichar (*)())[self methodForSelector: caiSel];
      while (start < length && isspace((*caiImp)(self, caiSel, start)))
	{
	  start++;
	}
      if (start > 0)
	{
	  return [self substringFromIndex: start];
	}
    }
  return self;
}

/**
 * Returns a string formed by removing trailing white space from the
 * receiver.
 */
- (NSString*) stringByTrimmingTailSpaces
{
  unsigned	length = [self length];

  if (length > 0)
    {
      unsigned	end = length;
      unichar	(*caiImp)(NSString*, SEL, unsigned int);
      SEL caiSel = @selector(characterAtIndex:);

      caiImp = (unichar (*)())[self methodForSelector: caiSel];
      while (end > 0)
	{
	  if (!isspace((*caiImp)(self, caiSel, end - 1)))
	    {
	      break;
	    }
	  end--;
	}
      if (end < length)
	{
	  return [self substringToIndex: end];
	}
    }
  return self;
}

/**
 * Returns a string formed by removing both leading and trailing
 * white space from the receiver.
 */
- (NSString*) stringByTrimmingSpaces
{
  unsigned	length = [self length];

  if (length > 0)
    {
      unsigned	start = 0;
      unsigned	end = length;
      unichar	(*caiImp)(NSString*, SEL, unsigned int);
      SEL caiSel = @selector(characterAtIndex:);

      caiImp = (unichar (*)())[self methodForSelector: caiSel];
      while (start < length && isspace((*caiImp)(self, caiSel, start)))
	{
	  start++;
	}
      while (end > start)
	{
	  if (!isspace((*caiImp)(self, caiSel, end - 1)))
	    {
	      break;
	    }
	  end--;
	}
      if (start > 0 || end < length)
	{
          if (start < end)
	    {
	      return [self substringFromRange:
		NSMakeRange(start, end - start)];
	    }
          else
	    {
	      return [NSString string];
	    }
	}
    }
  return self;
}

/**
 * Returns a string in which any (and all) occurrances of
 * replace in the receiver have been replaced with by.
 * Returns the receiver if replace
 * does not occur within the receiver.  NB. an empty string is
 * not considered to exist within the receiver.
 */
- (NSString*) stringByReplacingString: (NSString*)replace
			   withString: (NSString*)by
{
  NSRange range = [self rangeOfString: replace];

  if (range.length > 0)
    {
      NSMutableString	*tmp = [self mutableCopy];
      NSString		*str;

      [tmp replaceString: replace withString: by];
      str = AUTORELEASE([tmp copy]);
      RELEASE(tmp);
      return str;
    }
  else
    return self;
}

@end

/**
 * GNUstep specific (non-standard) additions to the NSMutableString class.
 */
@implementation NSMutableString (GSCategories)

/**
 * Removes the specified suffix from the string.  Raises an exception
 * if the suffix is not present.
 */
- (void) deleteSuffix: (NSString*)suffix
{
  NSCAssert2([self hasSuffix: suffix],
    @"'%@' does not have the suffix '%@'", self, suffix);
  [self deleteCharactersInRange:
    NSMakeRange([self length] - [suffix length], [suffix length])];
}

/**
 * Removes the specified prefix from the string.  Raises an exception
 * if the prefix is not present.
 */
- (void) deletePrefix: (NSString*)prefix
{
  NSCAssert2([self hasPrefix: prefix],
    @"'%@' does not have the prefix '%@'", self, prefix);
  [self deleteCharactersInRange: NSMakeRange(0, [prefix length])];
}

/**
 * Replaces all occurrances of the string replace with the string by
 * in the receiver.<br />
 * Has no effect if replace does not occur within the
 * receiver.  NB. an empty string is not considered to exist within
 * the receiver.<br />
 * Calls - replaceOccurrencesOfString:withString:options:range: passing
 * zero for the options and a range from 0 with the length of the receiver.
 */
- (void) replaceString: (NSString*)replace
	    withString: (NSString*)by
{
  [self replaceOccurrencesOfString: replace
			withString: by
			   options: 0
			     range: NSMakeRange(0, [self length])];
}

/**
 * Removes all leading white space from the receiver.
 */
- (void) trimLeadSpaces
{
  unsigned	length = [self length];

  if (length > 0)
    {
      unsigned	start = 0;
      unichar	(*caiImp)(NSString*, SEL, unsigned int);
      SEL caiSel = @selector(characterAtIndex:);

      caiImp = (unichar (*)())[self methodForSelector: caiSel];
      while (start < length && isspace((*caiImp)(self, caiSel, start)))
	{
	  start++;
	}
      if (start > 0)
	{
	  [self deleteCharactersInRange: NSMakeRange(0, start)];
	}
    }
}

/**
 * Removes all trailing white space from the receiver.
 */
- (void) trimTailSpaces
{
  unsigned	length = [self length];

  if (length > 0)
    {
      unsigned	end = length;
      unichar	(*caiImp)(NSString*, SEL, unsigned int);
      SEL caiSel = @selector(characterAtIndex:);

      caiImp = (unichar (*)())[self methodForSelector: caiSel];
      while (end > 0 && isspace((*caiImp)(self, caiSel, end - 1)))
	{
	  end--;
	}
      if (end < length)
	{
	  [self deleteCharactersInRange: NSMakeRange(end, length - end)];
	}
    }
}

/**
 * Removes all leading or trailing white space from the receiver.
 */
- (void) trimSpaces
{
  [self trimTailSpaces];
  [self trimLeadSpaces];
}

@end

/**
 * GNUstep specific (non-standard) additions to the NSLock class.
 */

static NSRecursiveLock *local_lock = nil;

/* 
   This class only exists to provide 
   a thread safe mechanism to initialize local_lock
   as +initialize is called under a lock in ObjC runtimes.
   User code should resort to GS_INITIALIZED_LOCK(),
   which uses the +newLockAt: extension.
*/

@interface _GSLockInitializer : NSObject
@end
@implementation _GSLockInitializer
+ (void) initialize
{
  if (local_lock == nil)
    {
      local_lock = [GSLazyRecursiveLock new];
    }
}
@end

GS_STATIC_INLINE id
newLockAt(Class self, SEL _cmd, id *location)
{
  if (location == 0)
    {
      [NSException raise: NSInvalidArgumentException
                   format: @"'%@' called with nil location",
		   NSStringFromSelector(_cmd)];
    }

  if (*location == nil)
    {
      if (local_lock == nil)
	{
	  [_GSLockInitializer class];
	}

      [local_lock lock];

      if (*location == nil)
	{
	  *location = [[self alloc] init];
	}

      [local_lock unlock];
    }

  return *location;
}


@implementation NSLock (GSCategories)
/**
 * Initializes the id pointed to by location
 * with a new instance of the receiver's class
 * in a thread safe manner, unless
 * it has been previously initialized.
 * Returns the contents pointed to by location.  
 * The location is considered unintialized if it contains nil.
 * <br/>
 * This method is used in the GS_INITIALIZED_LOCK macro
 * to initialize lock variables when it cannot be insured
 * that they can be initialized in a thread safe environment.
 * <example>
 * NSLock *my_lock = nil;
 *
 * void function (void)
 * {
 *   [GS_INITIALIZED_LOCK(my_lock, NSLock) lock];
 *   do_work ();
 *   [my_lock unlock];
 * }
 * 
 * </example>
 */
+ (id) newLockAt: (id *)location
{
  return newLockAt(self, _cmd, location);
}
@end

@implementation NSRecursiveLock (GSCategories)
/**
 * Initializes the id pointed to by location
 * with a new instance of the receiver's class
 * in a thread safe manner, unless
 * it has been previously initialized.
 * Returns the contents pointed to by location.  
 * The location is considered unintialized if it contains nil.
 * <br/>
 * This method is used in the GS_INITIALIZED_LOCK macro
 * to initialize lock variables when it cannot be insured
 * that they can be initialized in a thread safe environment.
 * <example>
 * NSLock *my_lock = nil;
 *
 * void function (void)
 * {
 *   [GS_INITIALIZED_LOCK(my_lock, NSRecursiveLock) lock];
 *   do_work ();
 *   [my_lock unlock];
 * }
 * 
 * </example>
 */
+ (id) newLockAt: (id *)location
{
  return newLockAt(self, _cmd, location);
}
@end
