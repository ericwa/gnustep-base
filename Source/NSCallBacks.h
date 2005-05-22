/* GNUStep callback functions prototypes.
 * Copyright(C) 1996  Free Software Foundation, Inc.
 * 
 * Author: Albin L. Jones <Albin.L.Jones@Dartmouth.EDU>
 * Created: Tue Feb 13 23:10:29 EST 1996
 * Updated: Tue Feb 13 23:10:29 EST 1996
 * Updated: Mon Feb  7 10:25:00 GMT 2000
 * Serial: 96.02.13.01
 * 
 * This file is part of the GNUstep Base Library.
 * 
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or(at your option) any later version.
 * 
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 * 
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the Free
 * Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02111 USA. */ 

#ifndef __NSCallBacks_h_OBJECTS_INCLUDE
#define __NSCallBacks_h_OBJECTS_INCLUDE 1

/**** Included Headers *******************************************************/

#include "Foundation/NSObject.h"
#include "Foundation/NSString.h"

/**** Type, Constant, and Macro Definitions **********************************/

/**** Function Prototypes ****************************************************/

/** For `int's **/

unsigned int _NS_int_hash(void *table, void* i);
BOOL _NS_int_is_equal(void *table, void* i, void* j);
void _NS_int_retain(void *table, void* i);
void _NS_int_release(void *table, void* i);
NSString *_NS_int_describe(void *table, void* i);

/** For owned `void *' **/

unsigned int _NS_owned_void_p_hash(void *table, void *p);
BOOL _NS_owned_void_p_is_equal(void *table, void *p, void *q);
void _NS_owned_void_p_retain(void *table, void *p);
void _NS_owned_void_p_release(void *table, void *p);
NSString *_NS_owned_void_p_describe(void *table, void *p);

/** For non-retained Objective-C objects **/
unsigned int _NS_non_retained_id_hash(void *table, id <NSObject> o);
BOOL _NS_non_retained_id_is_equal(void *table, id <NSObject> o, id <NSObject> p);
void _NS_non_retained_id_retain(void *table, id <NSObject> o);
void _NS_non_retained_id_release(void *table, id <NSObject> o);
NSString *_NS_non_retained_id_describe(void *table, id <NSObject> o);

/** For(retainable) objects **/
unsigned int _NS_id_hash(void *table, id <NSObject> o);
BOOL _NS_id_is_equal(void *table, id <NSObject> o, id <NSObject> p);
void _NS_id_retain(void *table, id <NSObject> o);
void _NS_id_release(void *table, id <NSObject> o);
NSString *_NS_id_describe(void *table, id <NSObject> o);

/** For(non-owned) `void *' **/
unsigned int _NS_non_owned_void_p_hash(void *table, void *p);
BOOL _NS_non_owned_void_p_is_equal(void *table, void *p, void *q);
void _NS_non_owned_void_p_retain(void *table, void *p);
void _NS_non_owned_void_p_release(void *table, void *p);
NSString *_NS_non_owned_void_p_describe(void *table, void *p);

/** For pointers to structures and `int *' **/
unsigned int _NS_int_p_hash(void *table, int *p);
BOOL _NS_int_p_is_equal(void *table, int *p, int *q);
void _NS_int_p_retain(void *table, int *p);
void _NS_int_p_release(void *table, int *p);
NSString *_NS_int_p_describe(void *table, int *p);

#endif /* __NSCallBacks_h_OBJECTS_INCLUDE **/

