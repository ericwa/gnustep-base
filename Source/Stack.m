/* Implementation for Objective-C Stack object
   Copyright (C) 1993, 1994, 1996 Free Software Foundation, Inc.
   
   Written by:  Andrew Kachites McCallum <mccallum@gnu.ai.mit.edu>
   Created: May 1993
   
   This file is part of the Gnustep Base Library.
   
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

#include <gnustep/base/Stack.h>
#include <gnustep/base/ArrayPrivate.h>

@implementation Stack 
  
- (void) pushObject: newObject
{
  [self appendObject: newObject];
}

/* Overriding */
- (void) addObject: newObject
{
  [self pushObject: newObject];
}

- popObject
{
  id ret;
  ret = [[self lastObject] retain];
  [self removeLastObject];
  return [ret autorelease];
}

- topObject
{
  return [self lastObject];
}

/* xxx Yipes.  What copying semantics do we want here? */
- (void) duplicateTop
{
  [self pushObject: [self topObject]];
}

- (void) exchangeTop
{
  if (_count > 1)
    [self swapAtIndeces:_count-1 :_count-2];
}

@end
