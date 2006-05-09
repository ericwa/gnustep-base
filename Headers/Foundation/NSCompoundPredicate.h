/* Interface for NSCompoundPredicate for GNUStep
   Copyright (C) 2005 Free Software Foundation, Inc.

   Written by:  Dr. H. Nikolaus Schaller
   Created: 2005
   
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
   */ 

#ifndef __NSCompoundPredicate_h_GNUSTEP_BASE_INCLUDE
#define __NSCompoundPredicate_h_GNUSTEP_BASE_INCLUDE

#include <Foundation/NSPredicate.h>

typedef enum _NSCompoundPredicateType
{
  NSNotPredicateType = 0,
  NSAndPredicateType,
  NSOrPredicateType
} NSCompoundPredicateType;

@interface NSCompoundPredicate : NSPredicate

+ (NSPredicate *) andPredicateWithSubpredicates: (NSArray *)list;
+ (NSPredicate *) notPredicateWithSubpredicate: (NSPredicate *)predicate;
+ (NSPredicate *) orPredicateWithSubpredicates: (NSArray *)list;

- (NSCompoundPredicateType) compoundPredicateType;
- (id) initWithType: (NSCompoundPredicateType)type
      subpredicates: (NSArray *)list;
- (NSArray *) subpredicates;

@end
#endif

