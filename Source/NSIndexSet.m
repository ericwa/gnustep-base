/** Implementation for NSIndexSet, NSMutableIndexSet for GNUStep
   Copyright (C) 2004 Free Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <rfm@gnu.org>
   Created: Feb 2004

   This file is part of the GNUstep Base Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 3 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02111 USA.

   */

#include        "Foundation/NSCoder.h"
#include        "Foundation/NSData.h"
#include	"Foundation/NSIndexSet.h"
#include	"Foundation/NSException.h"
#include	"Foundation/NSZone.h"

#define	GSI_ARRAY_TYPE	NSRange
#define GSI_ARRAY_TYPES	GSI_ARRAY_EXTRA

#define	GSI_ARRAY_NO_RELEASE	1
#define	GSI_ARRAY_NO_RETAIN	1

#include "GNUstepBase/GSIArray.h"

#define	_array	((GSIArray)(self->_data))
#define	_other	((GSIArray)(aSet->_data))

#ifdef	SANITY_CHECKS
static void sanity(GSIArray array)
{
  if (array != 0)
    {
      unsigned	c = GSIArrayCount(array);
      unsigned	i;
      unsigned	last = 0;

      for (i = 0; i < c; i++)
	{
	  NSRange	r = GSIArrayItemAtIndex(array, i).ext;

	  NSCAssert(r.location >= last, @"Overlap ranges");
	  NSCAssert(NSMaxRange(r) > r.location, @"Bad range length");
	  last = NSMaxRange(r);
	}
    }
}
#define	SANITY()	sanity(_array)
#else
#define	SANITY()	
#endif

/*
 * Returns the position in the array at which the index should be inserted.
 * This may be the position of a range containing the index if it is already
 * present, otherwise it is the position of the first range containing an
 * index greater than the argument (or a position beyond the end of the
 * array).
 */
static unsigned posForIndex(GSIArray array, unsigned index)
{
  unsigned int	upper = GSIArrayCount(array);
  unsigned int	lower = 0;
  unsigned int	pos;

  /*
   *	Binary search for an item equal to the one to be inserted.
   */
  for (pos = upper/2; upper != lower; pos = (upper+lower)/2)
    {
      NSRange	r = GSIArrayItemAtIndex(array, pos).ext;

      if (index < r.location)
        {
          upper = pos;
        }
      else if (index > NSMaxRange(r))
        {
          lower = pos + 1;
        }
      else
        {
          break;
        }
    }
  /*
   * Now skip past any item containing no values as high as the index.
   */
  while (pos < GSIArrayCount(array)
    && index >= NSMaxRange(GSIArrayItemAtIndex(array, pos).ext))
    {
      pos++;
    }
  return pos;
}

@implementation	NSIndexSet
+ (id) indexSet
{
  id	o = [self allocWithZone: NSDefaultMallocZone()];

  o = [o init];
  return AUTORELEASE(o);
}

+ (id) indexSetWithIndex: (unsigned int)anIndex
{
  id	o = [self allocWithZone: NSDefaultMallocZone()];

  o = [o initWithIndex: anIndex];
  return AUTORELEASE(o);
}

+ (id) indexSetWithIndexesInRange: (NSRange)aRange
{
  id	o = [self allocWithZone: NSDefaultMallocZone()];

  o = [o initWithIndexesInRange: aRange];
  return AUTORELEASE(o);
}

- (BOOL) containsIndex: (unsigned int)anIndex
{
  unsigned	pos;
  NSRange	r;

  if (_array == 0 || GSIArrayCount(_array) == 0
    || (pos = posForIndex(_array, anIndex)) >= GSIArrayCount(_array))
    {
      return NO;
    }
  r = GSIArrayItemAtIndex(_array, pos).ext;
  return NSLocationInRange(anIndex, r);
}

- (BOOL) containsIndexes: (NSIndexSet*)aSet
{
  unsigned	count = _other ? GSIArrayCount(_other) : 0;

  if (count > 0)
    {
      unsigned	i;

      for (i = 0; i < count; i++)
	{
	  NSRange	r = GSIArrayItemAtIndex(_other, i).ext;

	  if ([self containsIndexesInRange: r] == NO)
	    {
	      return NO;
	    }
	}
    }
  return YES;
}

- (BOOL) containsIndexesInRange: (NSRange)aRange
{
  unsigned	pos;
  NSRange	r;

  if (NSNotFound - aRange.length < aRange.location)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"[%@-%@]: Bad range",
        NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  if (_array == 0 || GSIArrayCount(_array) == 0
    || (pos = posForIndex(_array, aRange.location)) >= GSIArrayCount(_array))
    {
      return NO;	// Empty ... contains no indexes.
    }
  if (aRange.length == 0)
    {
      return YES;	// No indexes needed.
    }
  r = GSIArrayItemAtIndex(_array, pos).ext;
  if (NSLocationInRange(aRange.location, r)
    && NSLocationInRange(NSMaxRange(aRange)-1, r))
    {
      return YES;
    }
  return NO;
}

- (id) copyWithZone: (NSZone*)aZone
{
  if (NSShouldRetainWithZone(self, aZone))
    {
      return RETAIN(self);
    }
  else
    {
      NSIndexSet	*c = [NSIndexSet allocWithZone: aZone];

      return [c initWithIndexSet: self];
    }
}

- (unsigned int) count
{
  if (_array == 0 || GSIArrayCount(_array) == 0)
    {
      return 0;
    }
  else
    {
      unsigned	count = GSIArrayCount(_array);
      unsigned	total = 0;
      unsigned	i = 0;

      while (i < count)
	{
	  total += GSIArrayItemAtIndex(_array, i).ext.length;
	  i++;
	}
      return total;
    }
}

- (void) dealloc
{
  if (_array != 0)
    {
      GSIArrayClear(_array);
      NSZoneFree([self zone], _array);
      _data = 0;
    }
  [super dealloc];
}

- (NSString*) description
{
  NSMutableString	*m;
  unsigned		c = (_array == 0) ? 0 : GSIArrayCount(_array);
  unsigned		i;

  if (c == 0)
    {
      return [NSString stringWithFormat: @"%@(no indexes)",
        [super description]];
    }
  m = [NSMutableString stringWithFormat:
    @"%@[number of indexes: %u (in %u ranges), indexes:",
    [super description], [self count], c];
  for (i = 0; i < c; i++)
    {
      NSRange	r = GSIArrayItemAtIndex(_array, i).ext;

      if (r.length > 1)
        {
          [m appendFormat: @" (%u-%u)", r.location, NSMaxRange(r) - 1];
	}
      else
        {
          [m appendFormat: @" %u", r.location];
	}
    }
  [m appendString: @"]"];
  return m;
}

- (void) encodeWithCoder: (NSCoder*)aCoder
{
  int rangeCount = 0;

  if (_array != 0)
    {
      rangeCount = GSIArrayCount(_array);
    }

  [aCoder encodeInt: rangeCount forKey: @"NSRangeCount"];
  
  if (rangeCount == 0)
    {
      // Do nothing
    }
  else if (rangeCount == 1)
    {
      NSRange	r;
      
      r = GSIArrayItemAtIndex(_array, 0).ext;
      [aCoder encodeInt: r.location forKey: @"NSLocation"];
      [aCoder encodeInt: r.length forKey: @"NSLength"];
    }
  else
    {
      NSMutableData     *m = [NSMutableData dataWithCapacity: rangeCount*2];
      unsigned          i;

      for (i = 0; i < rangeCount; i++)
        {
          NSRange	r;
          unsigned      v;
          uint8_t       b;
      
          r = GSIArrayItemAtIndex(_array, i).ext;
          v = r.location;
          do
            {
              if (v > 0x7f)
                {
                  b = (v & 0x7f) | 0x80; 
                }
              else
                {
                  b = v;
                }
              v >>= 7;
              [m appendBytes: &b length: 1];
            }
          while (v > 0);
          v = r.length;
          do
            {
              if (v > 0x7f)
                {
                  b = (v & 0x7f) | 0x80; 
                }
              else
                {
                  b = v;
                }
              v >>= 7;
              [m appendBytes: &b length: 1];
            }
          while (v > 0);
        }
      [aCoder encodeObject: m forKey: @"NSRangeData"];
    }
}

- (unsigned int) firstIndex
{
  if (_array == 0 || GSIArrayCount(_array) == 0)
    {
      return NSNotFound;
    }
  return GSIArrayItemAtIndex(_array, 0).ext.location;
}

- (unsigned int) getIndexes: (unsigned int*)aBuffer
		   maxCount: (unsigned int)aCount
	       inIndexRange: (NSRangePointer)aRange
{
  unsigned	pos;
  unsigned	i = 0;
  NSRange	r;
  NSRange	fullRange;

  if (aBuffer == 0)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"[%@-%@]: nul pointer argument",
        NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  if (aRange == 0)
    {
      fullRange = (NSRange){0, NSNotFound};
      aRange = &fullRange;
    }
  else if (NSNotFound - aRange->length < aRange->location)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"[%@-%@]: Bad range",
        NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  if (_array == 0 || GSIArrayCount(_array) == 0
    || (pos = posForIndex(_array, aRange->location)) >= GSIArrayCount(_array))
    {
      *aRange = NSMakeRange(NSMaxRange(*aRange), 0);
      return 0;
    }

  while (aRange->length > 0 && i < aCount && pos < GSIArrayCount(_array))
    {
      r = GSIArrayItemAtIndex(_array, pos).ext;
      if (aRange->location < r.location)
	{
	  unsigned	skip = r.location - aRange->location;

	  if (skip > aRange->length)
	    {
	      skip = aRange->length;
	    }
	  aRange->location += skip;
	  aRange->length -= skip;
	}
      if (NSLocationInRange(aRange->location, r))
	{
	  while (aRange->length > 0 && i < aCount
	    && aRange->location < NSMaxRange(r))
	    {
	      aBuffer[i++] = aRange->location++;
	      aRange->length--;
	    }
	}
      else
	{
	}
      pos++;
    }
  return i;
}

- (unsigned int) hash
{
  return [self count];
}

- (unsigned int) indexGreaterThanIndex: (unsigned int)anIndex
{
  unsigned	pos;
  NSRange	r;

  if (anIndex++ == NSNotFound)
    {
      return NSNotFound;
    }
  if (_array == 0 || GSIArrayCount(_array) == 0
    || (pos = posForIndex(_array, anIndex)) >= GSIArrayCount(_array))
    {
      return NSNotFound;
    }
  r = GSIArrayItemAtIndex(_array, pos).ext;
  if (NSLocationInRange(anIndex, r))
    {
      return anIndex;
    }
  return r.location;
}

- (unsigned int) indexGreaterThanOrEqualToIndex: (unsigned int)anIndex
{
  unsigned	pos;
  NSRange	r;

  if (anIndex == NSNotFound)
    {
      return NSNotFound;
    }
  if (_array == 0 || GSIArrayCount(_array) == 0
    || (pos = posForIndex(_array, anIndex)) >= GSIArrayCount(_array))
    {
      return NSNotFound;
    }
  r = GSIArrayItemAtIndex(_array, pos).ext;
  if (NSLocationInRange(anIndex, r))
    {
      return anIndex;
    }
  return r.location;
}

- (unsigned int) indexLessThanIndex: (unsigned int)anIndex
{
  unsigned	pos;
  NSRange	r;

  if (anIndex-- == 0)
    {
      return NSNotFound;
    }
  if (_array == 0 || GSIArrayCount(_array) == 0
    || (pos = posForIndex(_array, anIndex)) >= GSIArrayCount(_array))
    {
      return NSNotFound;
    }
  r = GSIArrayItemAtIndex(_array, pos).ext;
  if (NSLocationInRange(anIndex, r))
    {
      return anIndex;
    }
  if (pos-- == 0)
    {
      return NSNotFound;
    }
  r = GSIArrayItemAtIndex(_array, pos).ext;
  return NSMaxRange(r) - 1;
}

- (unsigned int) indexLessThanOrEqualToIndex: (unsigned int)anIndex
{
  unsigned	pos;
  NSRange	r;

  if (_array == 0 || GSIArrayCount(_array) == 0
    || (pos = posForIndex(_array, anIndex)) >= GSIArrayCount(_array))
    {
      return NSNotFound;
    }
  r = GSIArrayItemAtIndex(_array, pos).ext;
  if (NSLocationInRange(anIndex, r))
    {
      return anIndex;
    }
  if (pos-- == 0)
    {
      return NSNotFound;
    }
  r = GSIArrayItemAtIndex(_array, pos).ext;
  return NSMaxRange(r) - 1;
}

- (id) init
{
  return self;
}

- (id) initWithCoder: (NSCoder*)aCoder
{
  int rangeCount = 0;

  if ([aCoder containsValueForKey: @"NSRangeCount"])
    {
      rangeCount = [aCoder decodeIntForKey: @"NSRangeCount"];
    }

  if (rangeCount == 0)
    {
      // Do nothing
    }
  else if (rangeCount == 1)
    {
      unsigned len = 0;
      unsigned loc = 0;
      
      if ([aCoder containsValueForKey: @"NSLocation"])
        {
          loc = [aCoder decodeIntForKey: @"NSLocation"];
        }
      if ([aCoder containsValueForKey: @"NSLength"])
        {
          len = [aCoder decodeIntForKey: @"NSLength"];
        }
      self = [self initWithIndexesInRange: NSMakeRange(loc, len)];
    }
  else
    {
      NSMutableIndexSet *other = [NSMutableIndexSet new];
      NSData            *data = nil;
      const uint8_t     *bytes;
      unsigned          length;
      unsigned          index = 0;

      if ([aCoder containsValueForKey: @"NSRangeData"])
        {
          data = [aCoder decodeObjectForKey: @"NSRangeData"];
        }
      bytes = (const uint8_t*)[data bytes];
      length = [data length];
      while (index < length)
        {
          NSRange       range;
          unsigned      offset;
          unsigned      value;
          unsigned      next;

          for (offset = 0; index + offset < length; offset++)
            {
              if (bytes[index + offset] < 0x80)
                {
                  break;
                }
            }
          NSAssert(index + offset < length && bytes[index + offset] < 0x80,
            NSInternalInconsistencyException);
          next = index + offset + 1;
          value = bytes[index + offset];
          while (offset-- > 0)
            {
              value <<= 7;
              value += (bytes[index + offset] & 0x7f);
            }
          range.location = value;
          index  = next;
          for (offset = 0; index + offset < length; offset++)
            {
              if (bytes[index + offset] < 0x80)
                {
                  break;
                }
            }
          NSAssert(index + offset < length && bytes[index + offset] < 0x80,
            NSInternalInconsistencyException);
          next = index + offset + 1;
          value = bytes[index + offset];
          while (offset-- > 0)
            {
              value <<= 7;
              value += (bytes[index + offset] & 0x7f);
            }
          range.length = value;
          index = next;
          [other addIndexesInRange: range];
        }
      self = [self initWithIndexSet: other];
      RELEASE(other);
      /*
        FIXME:
        NSLog(@"Decoded count %d, data %@", rangeCount, data);
        This is a very strange format:

        5 + 6 + 9 gives <05020901>
        5 + 6 + 23 gives <05021701>
        155 + 156 + 223 gives <9b0102df 0101>
       */
    }

  return self;
}

- (id) initWithIndex: (unsigned int)anIndex
{
  if (anIndex == NSNotFound)
    {
      DESTROY(self);	// NSNotFound is not legal
    }
  else
    {
      self = [self initWithIndexesInRange: NSMakeRange(anIndex, 1)];
    }
  return self;
}

- (id) initWithIndexesInRange: (NSRange)aRange
{
  if (aRange.length > 0)
    {
      if (NSMaxRange(aRange) == NSNotFound)
	{
	  DESTROY(self);	// NSNotFound is not legal
	}
      else
	{
	  _data = (GSIArray)NSZoneMalloc([self zone], sizeof(GSIArray_t));
	  GSIArrayInitWithZoneAndCapacity(_array, [self zone], 1);
	  GSIArrayAddItem(_array, (GSIArrayItem)aRange);
	}
    }
  return self;
}

- (id) initWithIndexSet: (NSIndexSet*)aSet
{
  if (aSet == nil || [aSet isKindOfClass: [NSIndexSet class]] == NO)
    {
      DESTROY(self);
    }
  else
    {
      unsigned count = _other ? GSIArrayCount(_other) : 0;

      if (count > 0)
	{
	  unsigned	i;

	  _data = (GSIArray)NSZoneMalloc([self zone], sizeof(GSIArray_t));
	  GSIArrayInitWithZoneAndCapacity(_array, [self zone], count);
	  for (i = 0; i < count; i++)
	    {
	      GSIArrayAddItem(_array, GSIArrayItemAtIndex(_other, i));
	    }
	}
    }
  return self;
}

- (BOOL) intersectsIndexesInRange: (NSRange)aRange
{
  unsigned	p1;
  unsigned	p2;

  if (NSNotFound - aRange.length < aRange.location)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"[%@-%@]: Bad range",
        NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  if (aRange.length == 0 || _array == 0 || GSIArrayCount(_array) == 0)
    {
      return NO;	// Empty
    }
  p1 = posForIndex(_array, aRange.location);
  p2 = posForIndex(_array, NSMaxRange(aRange) - 1);
  if (p1 != p2)
    {
      return YES;
    }
  if (p1 >= GSIArrayCount(_array))
    {
      return NO;
    }
  if (NSLocationInRange(aRange.location, GSIArrayItemAtIndex(_array, p1).ext))
    {
      return YES;
    }
  if (NSLocationInRange(NSMaxRange(aRange)-1,
      GSIArrayItemAtIndex(_array, p1).ext))
    {
      return YES;
    }
  return NO;
}

- (BOOL) isEqual: (id)aSet
{
  if ([aSet isKindOfClass: [NSIndexSet class]] == YES)
    {
      return [self isEqualToIndexSet: aSet];
    }
  return NO;
}

- (BOOL) isEqualToIndexSet: (NSIndexSet*)aSet
{
  unsigned	count = _other ? GSIArrayCount(_other) : 0;

  if (count != (_array ? GSIArrayCount(_array) : 0))
    {
      return NO;
    }
  if (count > 0)
    {
      unsigned	i;

      for (i = 0; i < count; i++)
	{
	  NSRange	rself = GSIArrayItemAtIndex(_array, i).ext;
	  NSRange	rother = GSIArrayItemAtIndex(_other, i).ext;

	  if (NSEqualRanges(rself, rother) == NO)
	    {
	      return NO;
	    }
	}
    }
  return YES;
}

- (unsigned int) lastIndex
{
  if (_array == 0 || GSIArrayCount(_array) == 0)
    {
      return NSNotFound;
    }
  return NSMaxRange(GSIArrayItemAtIndex(_array, GSIArrayCount(_array)-1).ext)-1;
}

- (id) mutableCopyWithZone: (NSZone*)aZone
{
  NSMutableIndexSet	*c = [NSMutableIndexSet allocWithZone: aZone];

  return [c initWithIndexSet: self];
}

@end


@implementation	NSMutableIndexSet

#undef	_other
#define	_other	((GSIArray)(((NSMutableIndexSet*)aSet)->_data))

- (void) addIndex: (unsigned int)anIndex
{
  [self addIndexesInRange: NSMakeRange(anIndex, 1)];
}

- (void) addIndexes: (NSIndexSet*)aSet
{
  unsigned	count = _other ? GSIArrayCount(_other) : 0;

  if (count > 0)
    {
      unsigned	i;

      for (i = 0; i < count; i++)
	{
	  NSRange	r = GSIArrayItemAtIndex(_other, i).ext;

	  [self addIndexesInRange: r];
	}
    }
}

- (void) addIndexesInRange: (NSRange)aRange
{
  unsigned	pos;

  if (NSNotFound - aRange.length < aRange.location)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"[%@-%@]: Bad range",
        NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  if (aRange.length == 0)
    {
      return;
    }
  if (_array == 0)
    {
      _data = (GSIArray)NSZoneMalloc([self zone], sizeof(GSIArray_t));
      GSIArrayInitWithZoneAndCapacity(_array, [self zone], 1);
    }

  pos = posForIndex(_array, aRange.location);
  if (pos >= GSIArrayCount(_array))
    {
      /*
       * The start of the range to add lies beyond the existing
       * ranges, so we can simply append it.
       */
      GSIArrayAddItem(_array, (GSIArrayItem)aRange);
    }
  else
    {
      NSRange	r = GSIArrayItemAtIndex(_array, pos).ext;

      if (NSLocationInRange(aRange.location, r))
	{
	  pos++;
	}
      GSIArrayInsertItem(_array, (GSIArrayItem)aRange, pos);
    }

  /*
   * Combine with the preceding ranges if possible.
   */
  while (pos > 0)
    {
      NSRange	r = GSIArrayItemAtIndex(_array, pos-1).ext;

      if (NSMaxRange(r) < aRange.location)
	{
	  break;
	}
      if (NSMaxRange(r) >= NSMaxRange(aRange))
        {
          GSIArrayRemoveItemAtIndex(_array, pos--);
	}
      else
        {
          r.length += (NSMaxRange(aRange) - NSMaxRange(r));
          GSIArrayRemoveItemAtIndex(_array, pos--);
          GSIArraySetItemAtIndex(_array, (GSIArrayItem)r, pos);
	}
    }

  /*
   * Combine with any following ranges where possible.
   */
  while (pos + 1 < GSIArrayCount(_array))
    {
      NSRange	r = GSIArrayItemAtIndex(_array, pos+1).ext;

      if (NSMaxRange(aRange) < r.location)
	{
	  break;
	}
      GSIArrayRemoveItemAtIndex(_array, pos + 1);
      if (NSMaxRange(r) > NSMaxRange(aRange))
	{
	  int	offset = NSMaxRange(r) - NSMaxRange(aRange);

	  r = GSIArrayItemAtIndex(_array, pos).ext;
	  r.length += offset;
	  GSIArraySetItemAtIndex(_array, (GSIArrayItem)r, pos);
	}
    }
  SANITY();
}

- (id) copyWithZone: (NSZone*)aZone
{
  NSIndexSet	*c = [NSIndexSet allocWithZone: aZone];

  return [c initWithIndexSet: self];
}

- (void) removeAllIndexes
{
  if (_array != 0)
    {
      GSIArrayRemoveAllItems(_array);
    }
}

- (void) removeIndex: (unsigned int)anIndex
{
  [self removeIndexesInRange: NSMakeRange(anIndex, 1)];
}

- (void) removeIndexes: (NSIndexSet*)aSet
{
  unsigned	count = _other ? GSIArrayCount(_other) : 0;

  if (count > 0)
    {
      unsigned	i;

      for (i = 0; i < count; i++)
	{
	  NSRange	r = GSIArrayItemAtIndex(_other, i).ext;

	  [self removeIndexesInRange: r];
	}
    }
}

- (void) removeIndexesInRange: (NSRange)aRange
{
  unsigned	pos;
  NSRange	r;

  if (NSNotFound - aRange.length < aRange.location)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"[%@-%@]: Bad range",
        NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  if (aRange.length == 0 || _array == 0
    || (pos = posForIndex(_array, aRange.location)) >= GSIArrayCount(_array))
    {
      return;	// Already empty
    }

  r = GSIArrayItemAtIndex(_array, pos).ext;
  if (r.location <= aRange.location)
    {
      if (r.location == aRange.location)
        {
   	  if (NSMaxRange(r) <= NSMaxRange(aRange))
	    {
	      /*
	       * Found range is entirely within range to remove,
	       * leaving next range to check at current position.
	       */
	      GSIArrayRemoveItemAtIndex(_array, pos);
	    }
	  else
	    {
	      /*
	       * Range to remove is entirely within found range and
	       * overlaps the start of the found range ... shrink it
	       * and then we are finished.
	       */
	      r.location += aRange.length;
	      r.length -= aRange.length;
	      GSIArraySetItemAtIndex(_array, (GSIArrayItem)r, pos);
	      pos++;
	    }
	}
      else
	{
   	  if (NSMaxRange(r) <= NSMaxRange(aRange))
	    {
	      /*
	       * Range to remove overlaps the end of the found range.
	       * May also overlap next range ... so shorten found
	       * range and move on.
	       */
	      r.length = aRange.location - r.location;
	      GSIArraySetItemAtIndex(_array, (GSIArrayItem)r, pos);
	      pos++;
	    }
	  else
	    {
	      NSRange	next = r;

	      /*
	       * Range to remove is entirely within found range and
	       * overlaps the middle of the found range ... split it.
	       * Then we are finished.
	       */
	      next.location = NSMaxRange(aRange);
	      next.length = NSMaxRange(r) - next.location;
	      r.length = aRange.location - r.location;
	      GSIArraySetItemAtIndex(_array, (GSIArrayItem)r, pos);
	      pos++;
	      GSIArrayInsertItem(_array, (GSIArrayItem)next, pos);
	      pos++;
	    }
	}
    }

  /*
   * At this point we are guaranteed that, if there is a range at pos,
   * it does not start before aRange.location
   */
  while (pos < GSIArrayCount(_array))
    {
      NSRange	r = GSIArrayItemAtIndex(_array, pos).ext;

      if (NSMaxRange(r) <= NSMaxRange(aRange))
	{
	  /*
	   * Found range is entirely within range to remove ...
	   * delete it.
	   */
	  GSIArrayRemoveItemAtIndex(_array, pos);
	}
      else
	{
	  if (r.location < NSMaxRange(aRange))
	    {
	      /*
	       * Range to remove overlaps start of found range ...
	       * shorten it.
	       */
	      r.length = NSMaxRange(r) - NSMaxRange(aRange);
	      r.location = NSMaxRange(aRange);
	      GSIArraySetItemAtIndex(_array, (GSIArrayItem)r, pos);
	    }
	  /*
	   * Found range extends beyond range to remove ... finished.
	   */
	  break;
	}
    }
  SANITY();
}

- (void) shiftIndexesStartingAtIndex: (unsigned int)anIndex by: (int)amount
{
  if (amount != 0 && _array != 0 && GSIArrayCount(_array) > 0)
    {
      unsigned	c;
      unsigned	pos;

      if (amount > 0)
	{
	  c = GSIArrayCount(_array);
	  pos = posForIndex(_array, anIndex);

	  if (pos < c)
	    {
	      NSRange	r = GSIArrayItemAtIndex(_array, pos).ext;

	      /*
	       * If anIndex is within an existing range, we split
	       * that range so we have one starting at anIndex.
	       */
	      if (r.location < anIndex)
		{
		  NSRange	t;

		  /*
		   * Split the range.
		   */
		  t = NSMakeRange(r.location, anIndex - r.location);
		  GSIArrayInsertItem(_array, (GSIArrayItem)t, pos);
		  c++;
		  r.length = NSMaxRange(r) - anIndex;
		  r.location = anIndex;
		  GSIArraySetItemAtIndex(_array, (GSIArrayItem)r, ++pos);
		}

	      /*
	       * Shift all higher ranges to the right.
	       */
	      while (c > pos)
		{
		  NSRange	r = GSIArrayItemAtIndex(_array, --c).ext;

		  if (NSNotFound - amount <= r.location)
		    {
		      GSIArrayRemoveItemAtIndex(_array, c);
		    }
		  else if (NSNotFound - amount < NSMaxRange(r))
		    {
		      r.location += amount;
		      r.length = NSNotFound - r.location;
		      GSIArraySetItemAtIndex(_array, (GSIArrayItem)r, c);
		    }
		  else
		    {
		      r.location += amount;
		      GSIArraySetItemAtIndex(_array, (GSIArrayItem)r, c);
		    }
		}
	    }
	}
      else
	{
	  amount = -amount;

	  /*
	   * Delete range which will be overwritten.
	   */
	  if (amount >= anIndex)
	    {
	      [self removeIndexesInRange: NSMakeRange(0, anIndex)];
	    }
	  else
	    {
	      [self removeIndexesInRange:
		NSMakeRange(anIndex - amount, amount)];
	    }
	  pos = posForIndex(_array, anIndex);

	  /*
	   * Now shift everything left into the hole we made.
	   */
	  c = GSIArrayCount(_array);
	  while (c > pos)
	    {
	      NSRange	r = GSIArrayItemAtIndex(_array, --c).ext;

	      if (NSMaxRange(r) <= amount)
		{
		  GSIArrayRemoveItemAtIndex(_array, c);
		}
	      else if (r.location <= amount)
		{
		  r.length += (r.location - amount);
		  r.location = 0;
		  GSIArraySetItemAtIndex(_array, (GSIArrayItem)r, c);
		}
	      else
		{
		  r.location -= amount;
		  GSIArraySetItemAtIndex(_array, (GSIArrayItem)r, c);
		}
	    }
	}
    }
  SANITY();
}

@end

@implementation	NSIndexSet (NSCharacterSet)
/* Extra method to let NSCharacterSet play with index sets more efficiently.
 */
- (unsigned int) _gapGreaterThanIndex: (unsigned int)anIndex
{
  unsigned	pos;
  NSRange	r;

  if (anIndex++ == NSNotFound)
    {
      return NSNotFound;
    }
  if (_array == 0 || GSIArrayCount(_array) == 0)
    {
      return NSNotFound;
    }

  if ((pos = posForIndex(_array, anIndex)) >= GSIArrayCount(_array))
    {
      r = GSIArrayItemAtIndex(_array, pos-1).ext;
      if (anIndex > NSMaxRange(r))
        {
          return NSNotFound;
	}
      return anIndex;	// anIndex is the gap after the last index.
    }
  r = GSIArrayItemAtIndex(_array, pos).ext;
  if (r.location > anIndex)
    {
      return anIndex;	// anIndex is in a gap between index ranges.
    }
  return NSMaxRange(r);	// Return start of gap after the index range.
}

@end

/* A subclass used to access a pre-generated table of information on the
 * stack or in other non-heap allocated memory.
 */
@interface	_GSStaticIndexSet : NSIndexSet
@end

@implementation	_GSStaticIndexSet
- (void) dealloc
{
  if (_array != 0)
    {
      /* Free the array without freeing its static content.
       */
      NSZoneFree([self zone], _array);
      _data = 0;
    }
  [super dealloc];
}

- (id) _initWithBytes: (const void*)bytes length: (unsigned)length
{
  NSAssert(length % sizeof(NSRange) == 0, NSInvalidArgumentException);
  length /= sizeof(NSRange);
  _data = NSZoneMalloc([self zone], sizeof(GSIArray_t));
  _array->ptr = (GSIArrayItem*)bytes;
  _array->count = length;
  _array->cap = length;
  _array->old = length;
  _array->zone = 0;
  return self;
}

- (id) init
{
  return [self _initWithBytes: 0 length: 0];
}
@end

