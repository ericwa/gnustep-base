/* Mutable array proxies for GNUstep's KeyValueCoding
   Copyright (C) 2007 Free Software Foundation, Inc.

   Written by:  Chris Farber <chris@chrisfarber.net>

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
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02111 USA.

   $Date: 2007-06-08 04: 04: 14 -0400 (Fri, 08 Jun 2007) $ $Revision: 25230 $
   */

#import "Foundation/NSInvocation.h"
#import "Foundation/NSIndexSet.h"
#import "Foundation/NSKeyValueObserving.h"

@interface NSKeyValueMutableArray : NSMutableArray
{
  @protected
  id object;
  NSString *key;
  NSMutableArray *array;
  BOOL otherChangeInProgress;
}

+ (NSKeyValueMutableArray *) arrayForKey: (NSString *)aKey ofObject: (id)anObject;
- (id) initWithKey: (NSString *)aKey ofObject: (id)anObject;

@end

@interface NSKeyValueFastMutableArray : NSKeyValueMutableArray 
{
  @private
  NSInvocation *insertObjectInvocation;
  NSInvocation *removeObjectInvocation;
  NSInvocation *replaceObjectInvocation;
}

+ (id) arrayForKey: (NSString *)aKey ofObject: (id)anObject
  withCapitalizedKey: (const char *)capitalized;

- (id) initWithKey: (NSString *)aKey ofObject: (id)anObject
  withCapitalizedKey: (const char *)capitalized;

@end

@interface NSKeyValueSlowMutableArray : NSKeyValueMutableArray
{
  @private
  NSInvocation *setArrayInvocation;
}

+ (id) arrayForKey: (NSString *)aKey ofObject: (id)anObject
  withCapitalizedKey: (const char *)capitalized;

- (id) initWithKey: (NSString *)aKey ofObject: (id)anObject
  withCapitalizedKey: (const char *)capitalized;

@end

@interface NSKeyValueIvarMutableArray : NSKeyValueMutableArray
{
  @private
}

+ (id) arrayForKey: (NSString *)aKey ofObject: (id)anObject;

- (id) initWithKey: (NSString *)aKey ofObject: (id)anObject;

@end


@implementation NSKeyValueMutableArray

+ (NSKeyValueMutableArray *) arrayForKey: (NSString *)aKey
                                ofObject: (id)anObject
{
  NSKeyValueMutableArray *proxy;
  unsigned size = [aKey maximumLengthOfBytesUsingEncoding: 
			  NSUTF8StringEncoding];
  char key[size + 1];
  [aKey getCString: key
         maxLength: size + 1
          encoding: NSUTF8StringEncoding];
  if (islower(*key))
    {
      *key = toupper(*key);
    }

  proxy = [NSKeyValueFastMutableArray arrayForKey: aKey 
				         ofObject: anObject
			       withCapitalizedKey: key];
  if (proxy == nil)
    {
      proxy = [NSKeyValueSlowMutableArray arrayForKey: aKey 
  					     ofObject: anObject
				   withCapitalizedKey: key];

      if (proxy == nil)
	{
	  proxy = [NSKeyValueIvarMutableArray arrayForKey: aKey 
					         ofObject: anObject];
	}
    }
  return proxy;
}

- (id) initWithKey: (NSString *)aKey ofObject: (id)anObject
{
  if ((self = [super init]) != nil)
    {
      object = anObject;
      key = [aKey copy];
      otherChangeInProgress = NO;
    }
  return self;
}

- (unsigned) count
{
  if (array == nil)
    {
      array = [object valueForKey: key];
    }
  return [array count];
}

- (id) objectAtIndex: (unsigned)index
{
  if (array == nil)
    {
      array = [object valueForKey: key];
    }
  return [array objectAtIndex: index];
}

- (void) addObject: (id)anObject
{
  [self insertObject: anObject  atIndex: [self count]];
}

- (void) removeLastObject
{
  [self removeObjectAtIndex: ([self count] - 1)];
}

@end

@implementation NSKeyValueFastMutableArray

+ (id) arrayForKey: (NSString *)aKey ofObject: (id)anObject
       withCapitalizedKey: (char *)capitalized
{
  return [[[self alloc] initWithKey: aKey ofObject: anObject
                 withCapitalizedKey: capitalized] autorelease];
}

- (id) initWithKey: (NSString *)aKey ofObject: (id)anObject
       withCapitalizedKey: (const char *)capitalized
{
  SEL insert;
  SEL remove;
  SEL replace;

  insert = NSSelectorFromString
    ([NSString stringWithFormat: @"insertObject:in%sAtIndex:", capitalized]);
  remove = NSSelectorFromString
    ([NSString stringWithFormat: @"removeObjectFrom%sAtIndex:", capitalized]);
  if (!([anObject respondsToSelector: insert]
    && [anObject respondsToSelector: remove]))
    {
      [self release];
      return nil;
    }
  replace = NSSelectorFromString
    ([NSString stringWithFormat: @"replaceObjectIn%sAtIndex:withObject:",
    capitalized]);

  if ((self = [super initWithKey: aKey ofObject: anObject]) != nil)
    {
      insertObjectInvocation = [[NSInvocation invocationWithMethodSignature: 
        [anObject methodSignatureForSelector: insert]] retain];
      [insertObjectInvocation setTarget: anObject];
      [insertObjectInvocation setSelector: insert];
      removeObjectInvocation = [[NSInvocation invocationWithMethodSignature: 
        [anObject methodSignatureForSelector: remove]] retain];
      [removeObjectInvocation setTarget: anObject];
      [removeObjectInvocation setSelector: remove];
      if ([anObject respondsToSelector: replace])
        {
          replaceObjectInvocation
            = [[NSInvocation invocationWithMethodSignature: 
            [anObject methodSignatureForSelector: replace]] retain];
          [replaceObjectInvocation setTarget: anObject];
          [replaceObjectInvocation setSelector: replace];
        }
    }
  return self;
}

- (void) dealloc
{
  [insertObjectInvocation release];
  [removeObjectInvocation release];
  [replaceObjectInvocation release];
  [super dealloc];
}

- (void) removeObjectAtIndex: (unsigned)index
{
  NSIndexSet *indexes;

  if (!otherChangeInProgress)
    {
      indexes = [NSIndexSet indexSetWithIndex: index];
      [object willChange: NSKeyValueChangeRemoval
        valuesAtIndexes: indexes
                  forKey: key];
    }
  [removeObjectInvocation setArgument: &index atIndex: 2];
  [removeObjectInvocation invoke];
  if (!otherChangeInProgress)
    {
      [object didChange: NSKeyValueChangeRemoval
        valuesAtIndexes: indexes
                  forKey: key];
    }
}

- (void) insertObject: (id)anObject atIndex: (unsigned)index
{
  NSIndexSet *indexes;

  if (!otherChangeInProgress)
    {
      indexes = [NSIndexSet indexSetWithIndex: index];
      [object willChange: NSKeyValueChangeInsertion
      valuesAtIndexes: indexes
                forKey: key];
    }
  [insertObjectInvocation setArgument: &anObject atIndex: 2];
  [insertObjectInvocation setArgument: &index atIndex: 3];
  [insertObjectInvocation invoke];
  if (!otherChangeInProgress)
    {
      [object didChange: NSKeyValueChangeInsertion
       valuesAtIndexes: indexes
                 forKey: key];
    }
}

- (void) replaceObjectAtIndex: (unsigned)index withObject: (id)anObject
{
  NSIndexSet *indexes;
  BOOL triggerNotifications = !otherChangeInProgress;

  if (triggerNotifications)
    {
      otherChangeInProgress = YES;
      indexes = [NSIndexSet indexSetWithIndex: index];
      [object willChange: NSKeyValueChangeReplacement
        valuesAtIndexes: indexes
                 forKey: key];
    }
  if (replaceObjectInvocation)
    {
      [replaceObjectInvocation setArgument: &index atIndex: 2];
      [replaceObjectInvocation setArgument: &anObject atIndex: 3];
      [replaceObjectInvocation invoke];
    }
  else
    {
      [self removeObjectAtIndex: index];
      [self insertObject: anObject atIndex: index];
    }
  if (triggerNotifications)
    {
      [object didChange: NSKeyValueChangeReplacement
       valuesAtIndexes: indexes
                 forKey: key];
      otherChangeInProgress = NO;
    }
}


@end

@implementation NSKeyValueSlowMutableArray

+ (id) arrayForKey: (NSString *)aKey ofObject: (id)anObject
       withCapitalizedKey: (const char *)capitalized
{
  return [[[self alloc] initWithKey: aKey ofObject: anObject
                withCapitalizedKey: capitalized] autorelease];
}

- (id) initWithKey: (NSString *)aKey ofObject: (id)anObject
       withCapitalizedKey: (const char *)capitalized;

{
  SEL set = NSSelectorFromString([NSString stringWithFormat: 
    @"set%s:", capitalized]);

  if (![anObject respondsToSelector: set])
    {
      [self release];
      return nil;
    }

  if ((self = [super initWithKey: aKey ofObject: anObject]) != nil)
    {
      setArrayInvocation = [[NSInvocation invocationWithMethodSignature: 
        [anObject methodSignatureForSelector: set]] retain];
      [setArrayInvocation setSelector: set];
      [setArrayInvocation setTarget: anObject];
   }
  return self;
}

- (void) removeObjectAtIndex: (unsigned)index
{
  NSIndexSet *indexes;
  NSMutableArray *temp;

  if (!otherChangeInProgress)
    {
      indexes = [NSIndexSet indexSetWithIndex: index];
      [object willChange: NSKeyValueChangeRemoval
        valuesAtIndexes: indexes
                  forKey: key];
    }
  
  temp = [NSMutableArray arrayWithArray: [object valueForKey: key]];
  [temp removeObjectAtIndex: index];

  [setArrayInvocation setArgument: &temp atIndex: 2];
  [setArrayInvocation invoke];

  if (!otherChangeInProgress)
    {
      [object didChange: NSKeyValueChangeRemoval
       valuesAtIndexes: indexes
                 forKey: key];
    }
}

- (void) insertObject: (id)anObject atIndex: (unsigned)index
{
  NSIndexSet *indexes;
  NSMutableArray *temp;

  if (!otherChangeInProgress)
    {
      indexes = [NSIndexSet indexSetWithIndex: index];
      [object willChange: NSKeyValueChangeInsertion
        valuesAtIndexes: indexes
                  forKey: key];
    }

  temp = [NSMutableArray arrayWithArray: [object valueForKey: key]];
  [temp insertObject: anObject atIndex: index];
  
  [setArrayInvocation setArgument: &temp atIndex: 2];
  [setArrayInvocation invoke];

  if (!otherChangeInProgress)
    {
      [object didChange: NSKeyValueChangeInsertion
       valuesAtIndexes: indexes
                 forKey: key];
    }
}

- (void) replaceObjectAtIndex: (unsigned)index withObject: (id)anObject
{
  NSIndexSet *indexes;
  NSMutableArray *temp;

  if (!otherChangeInProgress)
    {
      indexes = [NSIndexSet indexSetWithIndex: index];
      [object willChange: NSKeyValueChangeReplacement
        valuesAtIndexes: indexes
                  forKey: key];
    }
  
  temp = [NSMutableArray arrayWithArray: [object valueForKey: key]];
  [temp removeObjectAtIndex: index];
  [temp insertObject: anObject atIndex: index];

  [setArrayInvocation setArgument: &temp atIndex: 2];
  [setArrayInvocation invoke];

  if (!otherChangeInProgress)
    {
      [object didChange: NSKeyValueChangeReplacement
       valuesAtIndexes: indexes
                 forKey: key];
    }
}


@end


@implementation NSKeyValueIvarMutableArray

+ (id) arrayForKey: (NSString *)key ofObject: (id)anObject
{
  return [[[self alloc] initWithKey: key ofObject: anObject] autorelease];
}

- (id) initWithKey: (NSString *)aKey ofObject: (id)anObject
{
  if ((self = [super initWithKey: aKey  ofObject: anObject]) != nil)
    {
      unsigned size = [aKey maximumLengthOfBytesUsingEncoding:
        NSUTF8StringEncoding];
      char cKey[size + 2];
      char *cKeyPtr = &cKey[0];
      const char *type = 0;
      BOOL found;
      int offset;
      
      cKey[0] = '_';
      [aKey getCString: cKeyPtr + 1
             maxLength: size + 1
              encoding: NSUTF8StringEncoding];
      
      if (!GSObjCFindVariable (anObject, cKeyPtr, &type, &size, &offset))
        found = GSObjCFindVariable (anObject, ++cKeyPtr, &type, &size, &offset);
      if (found)
        {
          array = GSObjCGetVal (anObject, cKeyPtr, NULL, type, size, offset);
        }
      else
        {
          array = [object valueForKey: key];
        }
    }

  return self;
}

- (void) addObject: (id)anObject
{
  NSIndexSet *indexes = [NSIndexSet indexSetWithIndex: [array count]];

  [object willChange: NSKeyValueChangeInsertion
     valuesAtIndexes: indexes
              forKey: key];
  [array addObject: anObject];
  [object didChange: NSKeyValueChangeInsertion
    valuesAtIndexes: indexes
             forKey: key];
}

- (void) removeObjectAtIndex: (unsigned)index
{
  NSIndexSet *indexes = [NSIndexSet indexSetWithIndex: index];

  [object willChange: NSKeyValueChangeRemoval
     valuesAtIndexes: indexes
              forKey: key];
  [array removeObjectAtIndex: index];
  [object didChange: NSKeyValueChangeRemoval
    valuesAtIndexes: indexes
             forKey: key];
}

- (void) insertObject: (id)anObject atIndex: (unsigned)index
{
  NSIndexSet *indexes = [NSIndexSet indexSetWithIndex: index];

  [object willChange: NSKeyValueChangeInsertion
     valuesAtIndexes: indexes
              forKey: key];
  [array insertObject: anObject atIndex: index];
  [object didChange: NSKeyValueChangeInsertion
    valuesAtIndexes: indexes
             forKey: key];
}

- (void) removeLastObject
{
  NSIndexSet *indexes = [NSIndexSet indexSetWithIndex: [array count] - 1];

  [object willChange: NSKeyValueChangeRemoval
     valuesAtIndexes: indexes
              forKey: key];
  [array removeObjectAtIndex: [indexes firstIndex]];
  [object didChange: NSKeyValueChangeRemoval
    valuesAtIndexes: indexes
             forKey: key];
}

- (void) replaceObjectAtIndex: (unsigned)index withObject: (id)anObject
{
  NSIndexSet *indexes = [NSIndexSet indexSetWithIndex: index];

  [object willChange: NSKeyValueChangeReplacement
     valuesAtIndexes: indexes
              forKey: key];
  [array replaceObjectAtIndex: index withObject: anObject];
  [object didChange: NSKeyValueChangeReplacement
    valuesAtIndexes: indexes
             forKey: key];
}


@end
