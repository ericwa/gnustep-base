/* Interface for NSPredicate for GNUStep
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

#ifndef __NSPredicate_h_GNUSTEP_BASE_INCLUDE
#define __NSPredicate_h_GNUSTEP_BASE_INCLUDE

#include	<Foundation/NSObject.h>
#include	<Foundation/NSArray.h>

@interface NSPredicate : NSObject <NSCoding, NSCopying>

+ (NSPredicate *) predicateWithFormat: (NSString *)format, ...;
+ (NSPredicate *) predicateWithFormat: (NSString *)format
			argumentArray: (NSArray *)args;
+ (NSPredicate *) predicateWithFormat: (NSString *)format
			    arguments: (va_list)args;
+ (NSPredicate *) predicateWithValue: (BOOL)value;

- (BOOL) evaluateWithObject: (id)object;
- (NSString *) predicateFormat;
- (NSPredicate *) predicateWithSubstitutionVariables: (NSDictionary *)variables;

@end

@interface NSArray (NSPredicate)
- (NSArray *) filteredArrayUsingPredicate: (NSPredicate *)predicate;
@end

#endif /* __NSPredicate_h_GNUSTEP_BASE_INCLUDE */
