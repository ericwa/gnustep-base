# line 1 "NSConcreteNumber.m"	/* So gdb knows which file we are in */
/* NSConcreteNumber - Object encapsulation of numbers

   Copyright (C) 1993, 1994, 1996, 2000 Free Software Foundation, Inc.

   Written by:  Adam Fedor <fedor@boulder.colorado.edu>
   Date: Mar 1995
   Rewrite: Richard Frith-Macdonald <rfm@gnu.org>
   Date: Mar 2000

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

#include "config.h"
#include "GNUstepBase/preface.h"
#include "GSConfig.h"
#include "Foundation/NSObjCRuntime.h"
#include "Foundation/NSString.h"
#include "Foundation/NSException.h"
#include "Foundation/NSCoder.h"
#include "Foundation/NSPortCoder.h"
#include "Foundation/NSCoder.h"
#include "NSConcreteNumber.h"

/* This file should be run through a preprocessor with the macro TYPE_ORDER
   defined to a number from 0 to 12 corresponding to each number type */
#if TYPE_ORDER == 0
#  define NumberTemplate	NSBoolNumber
#  define TYPE_TYPE	BOOL
#elif TYPE_ORDER == 1
#  define NumberTemplate	NSCharNumber
#  define TYPE_TYPE	signed char
#elif TYPE_ORDER == 2
#  define NumberTemplate	NSUCharNumber
#  define TYPE_TYPE	unsigned char
#elif TYPE_ORDER == 3
#  define NumberTemplate	NSShortNumber
#  define TYPE_TYPE	signed short
#elif TYPE_ORDER == 4
#  define NumberTemplate	NSUShortNumber
#  define TYPE_TYPE	unsigned short
#elif TYPE_ORDER == 5
#  define NumberTemplate	NSIntNumber
#  define TYPE_TYPE	signed int
#elif TYPE_ORDER == 6
#  define NumberTemplate	NSUIntNumber
#  define TYPE_TYPE	unsigned int
#elif TYPE_ORDER == 7
#  define NumberTemplate	NSLongNumber
#  define TYPE_TYPE	signed long
#elif TYPE_ORDER == 8
#  define NumberTemplate	NSULongNumber
#  define TYPE_TYPE	unsigned long
#elif TYPE_ORDER == 9
#  define NumberTemplate	NSLongLongNumber
#  define TYPE_TYPE	signed long long
#elif TYPE_ORDER == 10
#  define NumberTemplate	NSULongLongNumber
#  define TYPE_TYPE	unsigned long long
#elif TYPE_ORDER == 11
#  define NumberTemplate	NSFloatNumber
#  define TYPE_TYPE	float
#elif TYPE_ORDER == 12
#  define NumberTemplate	NSDoubleNumber
#  define TYPE_TYPE	double
#endif

@implementation NumberTemplate

- (id) initWithBytes: (const void*)value objCType: (const char*)type
{
  typedef __typeof__(data) _dt;
  data = *(const _dt*)value;
  return self;
}

/*
 * Because of the rule that two numbers which are the same according to
 * [-isEqual: ] must generate the same hash, we must generate the hash
 * from the most general representation of the number.
 * NB. Don't change this without changing the matching function in
 * NSNumber.m
 */
- (unsigned) hash
{
  union {
    double d;
    unsigned char c[sizeof(double)];
  } val;
  unsigned	hash = 0;
  unsigned	i;

/*
 * If possible use a cached hash value for small integers.
 */
#if	TYPE_ORDER < 11
#if	(TYPE_ORDER & 1)
  if (data <= GS_SMALL && data >= -GS_SMALL)
#else
  if (data <= GS_SMALL)
#endif
    {
      return GSSmallHash((int)data);
    }
#endif

  val.d = [self doubleValue];
  for (i = 0; i < sizeof(double); i++)
    {
      hash = (hash << 5) + hash + val.c[i];
    }
  return hash;
}

- (BOOL) boolValue
{
  return (BOOL)data;
}

- (signed char) charValue
{
  return (signed char)data;
}

- (double) doubleValue
{
  return (double)data;
}

- (float) floatValue
{
  return (float)data;
}

- (signed int) intValue
{
  return (signed int)data;
}

- (signed long long) longLongValue
{
  return (signed long long)data;
}

- (signed long) longValue
{
  return (signed long)data;
}

- (signed short) shortValue
{
  return (signed short)data;
}

- (unsigned char) unsignedCharValue
{
  return (unsigned char)data;
}

- (unsigned int) unsignedIntValue
{
  return (unsigned int)data;
}

- (unsigned long long) unsignedLongLongValue
{
  return (unsigned long long)data;
}

- (unsigned long) unsignedLongValue
{
  return (unsigned long)data;
}

- (unsigned short) unsignedShortValue
{
  return (unsigned short)data;
}

- (NSComparisonResult) compare: (NSNumber*)other
{
  if (other == self)
    {
      return NSOrderedSame;
    }
  else if (other == nil)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"nil argument for compare:"];
    }
  else
    {
      GSNumberInfo	*info = GSNumberInfoFromObject(other);

      switch (info->typeLevel)
	{
	  case 0:
	    {
	      BOOL	oData;

	      (*(info->getValue))(other, @selector(getValue:), (void*)&oData);
#undef PT
#if	(TYPE_ORDER & 1) == 1
#if GS_SIZEOF_CHAR < GS_SIZEOF_SHORT && TYPE_ORDER < 3
#define	PT (short)
#elif GS_SIZEOF_CHAR < GS_SIZEOF_INT && TYPE_ORDER < 5
#define	PT (int)
#elif GS_SIZEOF_CHAR < GS_SIZEOF_LONG && TYPE_ORDER < 7
#define	PT (long)
#elif GS_SIZEOF_CHAR < GS_SIZEOF_LONG_LONG && TYPE_ORDER < 9
#define	PT (long long)
#else
#define	PT (double)
#endif
#else
#define	PT
#endif
	      if (PT data == PT oData)
		return NSOrderedSame;
	      else if (PT data < PT oData)
		return NSOrderedAscending;
	      else
		return NSOrderedDescending;
	    }
	  case 1:
	    {
	      signed char	oData;

	      (*(info->getValue))(other, @selector(getValue:), (void*)&oData);
#undef PT
#if	(TYPE_ORDER & 1) == 0
#if GS_SIZEOF_CHAR < GS_SIZEOF_SHORT && TYPE_ORDER < 3
#define	PT (short)
#elif GS_SIZEOF_CHAR < GS_SIZEOF_INT && TYPE_ORDER < 5
#define	PT (int)
#elif GS_SIZEOF_CHAR < GS_SIZEOF_LONG && TYPE_ORDER < 7
#define	PT (long)
#elif GS_SIZEOF_CHAR < GS_SIZEOF_LONG_LONG && TYPE_ORDER < 9
#define	PT (long long)
#else
#define	PT (double)
#endif
#else
#define	PT
#endif
	      if (PT data == PT oData)
		return NSOrderedSame;
	      else if (PT data < PT oData)
		return NSOrderedAscending;
	      else
		return NSOrderedDescending;
	    }
	  case 2:
	    {
	      unsigned char	oData;

	      (*(info->getValue))(other, @selector(getValue:), (void*)&oData);
#undef PT
#if	(TYPE_ORDER & 1) == 1
#if GS_SIZEOF_CHAR < GS_SIZEOF_SHORT && TYPE_ORDER < 3
#define	PT (short)
#elif GS_SIZEOF_CHAR < GS_SIZEOF_INT && TYPE_ORDER < 5
#define	PT (int)
#elif GS_SIZEOF_CHAR < GS_SIZEOF_LONG && TYPE_ORDER < 7
#define	PT (long)
#elif GS_SIZEOF_CHAR < GS_SIZEOF_LONG_LONG && TYPE_ORDER < 9
#define	PT (long long)
#else
#define	PT (double)
#endif
#else
#define	PT
#endif
	      if (PT data == PT oData)
		return NSOrderedSame;
	      else if (PT data < PT oData)
		return NSOrderedAscending;
	      else
		return NSOrderedDescending;
	    }
	  case 3:
	    {
	      signed short	oData;

	      (*(info->getValue))(other, @selector(getValue:), (void*)&oData);
#undef PT
#if	(TYPE_ORDER & 1) == 0
#if GS_SIZEOF_SHORT < GS_SIZEOF_INT && TYPE_ORDER < 5
#define	PT (int)
#elif GS_SIZEOF_SHORT < GS_SIZEOF_LONG && TYPE_ORDER < 7
#define	PT (long)
#elif GS_SIZEOF_SHORT < GS_SIZEOF_LONG_LONG && TYPE_ORDER < 9
#define	PT (long long)
#else
#define	PT (double)
#endif
#else
#define	PT
#endif
	      if (PT data == PT oData)
		return NSOrderedSame;
	      else if (PT data < PT oData)
		return NSOrderedAscending;
	      else
		return NSOrderedDescending;
	    }
	  case 4:
	    {
	      unsigned short	oData;

	      (*(info->getValue))(other, @selector(getValue:), (void*)&oData);
#undef PT
#if	(TYPE_ORDER & 1) == 1
#if GS_SIZEOF_SHORT < GS_SIZEOF_INT && TYPE_ORDER < 5
#define	PT (int)
#elif GS_SIZEOF_SHORT < GS_SIZEOF_LONG && TYPE_ORDER < 7
#define	PT (long)
#elif GS_SIZEOF_SHORT < GS_SIZEOF_LONG_LONG && TYPE_ORDER < 9
#define	PT (long long)
#else
#define	PT (double)
#endif
#else
#define	PT
#endif
	      if (PT data == PT oData)
		return NSOrderedSame;
	      else if (PT data < PT oData)
		return NSOrderedAscending;
	      else
		return NSOrderedDescending;
	    }
	  case 5:
	    {
	      signed int	oData;

	      (*(info->getValue))(other, @selector(getValue:), (void*)&oData);
#undef PT
#if	(TYPE_ORDER & 1) == 0
#if GS_SIZEOF_INT < GS_SIZEOF_LONG && TYPE_ORDER < 7
#define	PT (long)
#elif GS_SIZEOF_INT < GS_SIZEOF_LONG_LONG && TYPE_ORDER < 9
#define	PT (long long)
#else
#define	PT (double)
#endif
#else
#define	PT
#endif
	      if (PT data == PT oData)
		return NSOrderedSame;
	      else if (PT data < PT oData)
		return NSOrderedAscending;
	      else
		return NSOrderedDescending;
	    }
	  case 6:
	    {
	      unsigned int	oData;

	      (*(info->getValue))(other, @selector(getValue:), (void*)&oData);
#undef PT
#if	(TYPE_ORDER & 1) == 1
#if GS_SIZEOF_INT < GS_SIZEOF_LONG && TYPE_ORDER < 7
#define	PT (long)
#elif GS_SIZEOF_INT < GS_SIZEOF_LONG_LONG && TYPE_ORDER < 9
#define	PT (long long)
#else
#define	PT (double)
#endif
#else
#define	PT
#endif
	      if (PT data == PT oData)
		return NSOrderedSame;
	      else if (PT data < PT oData)
		return NSOrderedAscending;
	      else
		return NSOrderedDescending;
	    }
	  case 7:
	    {
	      signed long	oData;

	      (*(info->getValue))(other, @selector(getValue:), (void*)&oData);
#undef PT
#if	(TYPE_ORDER & 1) == 0
#if GS_SIZEOF_LONG < GS_SIZEOF_LONG_LONG && TYPE_ORDER < 9
#define	PT (long long)
#else
#define	PT (double)
#endif
#else
#define	PT
#endif
	      if (PT data == PT oData)
		return NSOrderedSame;
	      else if (PT data < PT oData)
		return NSOrderedAscending;
	      else
		return NSOrderedDescending;
	    }
	  case 8:
	    {
	      unsigned long	oData;

	      (*(info->getValue))(other, @selector(getValue:), (void*)&oData);
#undef PT
#if	(TYPE_ORDER & 1) == 1
#if GS_SIZEOF_LONG < GS_SIZEOF_LONG_LONG && TYPE_ORDER < 9
#define	PT (long long)
#else
#define	PT (double)
#endif
#else
#define	PT
#endif
	      if (PT data == PT oData)
		return NSOrderedSame;
	      else if (PT data < PT oData)
		return NSOrderedAscending;
	      else
		return NSOrderedDescending;
	    }
	  case 9:
	    {
	      signed long long	oData;

	      (*(info->getValue))(other, @selector(getValue:), (void*)&oData);
#undef PT
#if	(TYPE_ORDER & 1) == 0
#define	PT (double)
#else
#define	PT
#endif
	      if (PT data == PT oData)
		return NSOrderedSame;
	      else if (PT data < PT oData)
		return NSOrderedAscending;
	      else
		return NSOrderedDescending;
	    }
	  case 10:
	    {
	      unsigned long long	oData;

	      (*(info->getValue))(other, @selector(getValue:), (void*)&oData);
#undef PT
#if	(TYPE_ORDER & 1) == 1
#define	PT (double)
#else
#define	PT
#endif
	      if (PT data == PT oData)
		return NSOrderedSame;
	      else if (PT data < PT oData)
		return NSOrderedAscending;
	      else
		return NSOrderedDescending;
	    }
	  case 11:
	    {
	      float	oData;

	      (*(info->getValue))(other, @selector(getValue:), (void*)&oData);
#undef PT
#if TYPE_ORDER != 11
#define	PT (double)
#else
#define	PT
#endif
	      if (PT data == PT oData)
		return NSOrderedSame;
	      else if (PT data < PT oData)
		return NSOrderedAscending;
	      else
		return NSOrderedDescending;
	    }
	  case 12:
	    {
	      double	oData;

	      (*(info->getValue))(other, @selector(getValue:), (void*)&oData);
#undef PT
#define	PT (double)
	      if (PT data == PT oData)
		return NSOrderedSame;
	      else if (PT data < PT oData)
		return NSOrderedAscending;
	      else
		return NSOrderedDescending;
	    }
	  default:
	    [NSException raise: NSInvalidArgumentException
			format: @"number type value for comparison"];
	    return NSOrderedSame;
	}
    }
  return 0; /* Quiet warnings */
}

- (NSString*) descriptionWithLocale: (NSDictionary*)locale
{
#if TYPE_ORDER == 0
  return (data) ? @"YES" : @"NO";
#else
  NSString	*result = [NSString alloc];

#if TYPE_ORDER == 1
  result = [result initWithFormat: @"%i" locale: locale, (int)data];
#elif TYPE_ORDER == 2
  result = [result initWithFormat: @"%u" locale: locale, (unsigned int)data];
#elif TYPE_ORDER == 3
  result = [result initWithFormat: @"%hi" locale: locale, data];
#elif TYPE_ORDER == 4
  result = [result initWithFormat: @"%hu" locale: locale, data];
#elif TYPE_ORDER == 5
  result = [result initWithFormat: @"%i" locale: locale, data];
#elif TYPE_ORDER == 6
  result = [result initWithFormat: @"%u" locale: locale, data];
#elif TYPE_ORDER == 7
  result = [result initWithFormat: @"%li" locale: locale, data];
#elif TYPE_ORDER == 8
  result = [result initWithFormat: @"%lu" locale: locale, data];
#elif TYPE_ORDER == 9
  result = [result initWithFormat: @"%lli" locale: locale, data];
#elif TYPE_ORDER == 10
  result = [result initWithFormat: @"%llu" locale: locale, data];
#elif TYPE_ORDER == 11
  result = [result initWithFormat: @"%0.7g" locale: locale, (double)data];
#elif TYPE_ORDER == 12
  result = [result initWithFormat: @"%0.16g" locale: locale, data];
#endif
  return AUTORELEASE(result);
#endif
}

- (id) copy
{
  if (NSShouldRetainWithZone(self, NSDefaultMallocZone()))
    return RETAIN(self);
  else
    return NSCopyObject(self, 0, NSDefaultMallocZone());
}

- (id) copyWithZone: (NSZone*)zone
{
  if (NSShouldRetainWithZone(self, zone))
    return RETAIN(self);
  else
    return NSCopyObject(self, 0, zone);
}

// Override these from NSValue
- (void) getValue: (void*)value
{
  if (value == 0)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"Cannot copy value into NULL pointer"];
      /* NOT REACHED */
    }
  memcpy(value, &data, objc_sizeof_type(@encode(TYPE_TYPE)));
}

- (const char*) objCType
{
  return @encode(TYPE_TYPE);
}

- (id) nonretainedObjectValue
{
  return (id)(void*)&data;
}

- (void*) pointerValue
{
  return (void*)&data;
}

// NSCoding

/*
 * Exact mirror of NSNumber abstract class coding method.
 */
- (void) encodeWithCoder: (NSCoder*)coder
{
  const char	*t = @encode(TYPE_TYPE);

  [coder encodeValueOfObjCType: @encode(signed char) at: t];
  [coder encodeValueOfObjCType: t at: &data];
}

/*
 * NSNumber objects should have been encoded with their class set to the
 * abstract class.  If they haven't then we must be encoding from an old
 * archive, so we must implement the old initWithCoder: method.
 */
- (id) initWithCoder: (NSCoder*)coder
{
  [coder decodeValueOfObjCType: @encode(TYPE_TYPE) at: &data];
  return self;
}

@end

