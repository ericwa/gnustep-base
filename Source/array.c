/* A (pretty good) implementation of a sparse array.
 * Copyright (C) 1994, 1995, 1996  Free Software Foundation, Inc.
 * 
 * Author: Albin L. Jones <Albin.L.Jones@Dartmouth.EDU>
 * Created: Thu Mar  2 02:28:50 EST 1994
 * Updated: Sat Feb 10 16:16:12 EST 1996
 * Serial: 96.02.10.02
 * 
 * This file is part of the GNU Objective C Class Library.
 * 
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 * 
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 * 
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the Free
 * Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 * 
 */ 

/**** Included Headers *******************************************************/

#include <objects/allocs.h>
#include <objects/callbacks.h>
#include <objects/abort.h>
#include <objects/array.h>
#include <objects/hash.h>

/**** Function Implementations ***********************************************/

/** Background functions **/

size_t
_objects_array_fold_index (size_t index, size_t slot_count)
{
  return (slot_count ? (index % slot_count) : 0);
}

size_t
_objects_array_internal_index (objects_array_t * array, size_t index)
{
  return _objects_array_fold_index (index, array->slot_count);
}

objects_array_slot_t *
_objects_array_slot_for_index (objects_array_t * array, size_t index)
{
  return (array->slots + _objects_array_internal_index (array, index));
}

objects_array_bucket_t *
_objects_array_bucket_for_index (objects_array_t * array, size_t index)
{
  objects_array_slot_t *slot;
  objects_array_bucket_t *bucket;

  /* First, we translate the index into a bucket index to find our
   * candidate for the bucket. */
  slot = _objects_array_slot_for_index (array, index);
  bucket = *slot;

  /* But we need to check to see whether this is really the bucket we
   * wanted. */
  if (bucket != NULL && bucket->index == index)
    /* Bucket `index' exists, and we've got it, so... */
    return bucket;
  else
    /* Either no bucket or some other bucket is where bucket `index'
     * would be, if it existed.  So... */
    return NULL;
}

objects_array_bucket_t *
_objects_array_new_bucket (objects_array_t * array, size_t index, const void *element)
{
  objects_array_bucket_t *bucket;

  bucket = (objects_array_bucket_t *) objects_malloc (objects_array_allocs (array),
					   sizeof (objects_array_bucket_t));
  if (bucket != NULL)
    {
      objects_retain (objects_array_element_callbacks (array), element, array);
      bucket->index = index;
      bucket->element = element;
    }
  return bucket;
}

void
_objects_array_free_bucket (objects_array_t * array, objects_array_bucket_t * bucket)
{
  if (bucket != NULL)
    {
      objects_release (objects_array_element_callbacks (array), 
		       (void*)bucket->element, 
		       array);
      objects_free (objects_array_allocs (array), bucket);
    }
  return;
}

objects_array_slot_t *
_objects_array_new_slots (objects_array_t * array, size_t slot_count)
{
  return (objects_array_slot_t *) objects_calloc (objects_array_allocs (array),
						  slot_count,
					     sizeof (objects_array_slot_t));
}

void
_objects_array_free_slots (objects_array_t * array, objects_array_slot_t * slots)
{
  if (slots != NULL)
    objects_free (objects_array_allocs (array), slots);
  return;
}

void
_objects_array_empty_slot (objects_array_t * array, objects_array_slot_t * slot)
{
  if (*slot != NULL)
    {
      /* Get rid of the bucket. */
      _objects_array_free_bucket (array, *slot);

      /* Mark the slot as empty. */
      *slot = NULL;

      /* Keep the element count accurate */
      --(array->element_count);
    }

  /* And return. */
  return;
}

void
_objects_array_insert_bucket (objects_array_t * array, objects_array_bucket_t * bucket)
{
  objects_array_slot_t *slot;

  slot = _objects_array_slot_for_index (array, bucket->index);

  /* We're adding a bucket, so the current set of sorted slots is now
   * invalidated. */
  if (array->sorted_slots != NULL)
    {
      _objects_array_free_slots (array, array->sorted_slots);
      array->sorted_slots = NULL;
    }

  if ((*slot) == NULL)
    {
      /* There's nothing there, so we can put `bucket' there. */
      *slot = bucket;

      /* Increment the array's bucket counter. */
      ++(array->element_count);
      return;
    }
  if ((*slot)->index == bucket->index)
    {
      /* There's a bucket there, and it has the same index as `bucket'.
       * So we get rid of the old one, and put the new one in its
       * place. */
      _objects_array_free_bucket (array, *slot);
      *slot = bucket;
      return;
    }
  else
    {
      /* Now we get to fiddle around with things to make the world a
       * better place... */

      size_t new_slot_count;
      objects_array_slot_t *new_slots;	/* This guy holds the buckets while we
					 * muck about with them. */
      size_t d;			/* Just a counter */

      /* FIXME: I *really* wish I had a way of generating
       * statistically better initial values for this variable.  So
       * I'll run a few tests and see...  And is there a better
       * algorithm, e.g., a better collection of sizes in the sense
       * that the likelyhood of fitting everything in earlier is
       * high?  Well, enough mumbling. */
      /* At any rate, we're guaranteed to need at least this many. */
      new_slot_count = array->element_count + 1;

      do
	{
	  /* First we make a new pile of slots for the buckets. */
	  new_slots = _objects_array_new_slots (array, new_slot_count);

	  if (new_slots == NULL)
	    objects_abort ();

	  /* Then we put the new bucket in the pile. */
	  new_slots[_objects_array_fold_index (bucket->index,
					       new_slot_count)] = bucket;

	  /* Now loop and try to place the others.  Upon collision
	   * with a previously inserted bucket, try again with more
	   * `new_slots'. */
	  for (d = 0; d < array->slot_count; ++d)
	    {
	      if (array->slots[d] != NULL)
		{
		  size_t i;

		  i = _objects_array_fold_index (array->slots[d]->index,
						 new_slot_count);

		  if (new_slots[i] == NULL)
		    {
		      new_slots[i] = array->slots[d];
		    }
		  else
		    {
		      /* A collision.  Clean up and try again. */

		      /* Free the current set of new buckets. */
		      _objects_array_free_slots (array, new_slots);

		      /* Bump up the number of new buckets. */
		      ++new_slot_count;

		      /* Break out of the `for' loop. */
		      break;
		    }
		}
	    }
	}
      while (d < array->slot_count);

      if (array->slots != NULL)
	_objects_array_free_slots (array, array->slots);

      array->slots = new_slots;
      array->slot_count = new_slot_count;
      ++(array->element_count);

      return;
    }
}

int
_objects_array_compare_slots (const objects_array_slot_t * slot1,
			      const objects_array_slot_t * slot2)
{
  if (slot1 == slot2)
    return 0;
  if (*slot1 == NULL)
    return 1;
  if (*slot2 == NULL)
    return -1;

  if ((*slot1)->index < (*slot2)->index)
    return -1;
  else if ((*slot1)->index > (*slot2)->index)
    return 1;
  else
    return 0;
}

typedef int (*qsort_compare_func_t) (const void *, const void *);

void
_objects_array_make_sorted_slots (objects_array_t * array)
{
  objects_array_slot_t *new_slots;

  /* If there're already some sorted slots, then they're valid, and
   * we're done. */
  if (array->sorted_slots != NULL)
    return;

  /* Make some new slots. */
  new_slots = _objects_array_new_slots (array, array->slot_count);

  /* Copy the pointers to buckets into the new slots. */
  memcpy (new_slots, array->slots, (array->slot_count
				    * sizeof (objects_array_slot_t)));

  /* Sort the new slots. */
  qsort (new_slots, array->slot_count, sizeof (objects_array_slot_t),
	 (qsort_compare_func_t) _objects_array_compare_slots);

  /* Put the newly sorted slots in the `sorted_slots' element of the
   * array structure. */
  array->sorted_slots = new_slots;

  return;
}

objects_array_bucket_t *
_objects_array_enumerator_next_bucket (objects_array_enumerator_t * enumerator)
{
  if (enumerator->is_sorted)
    {
      if (enumerator->is_ascending)
	{
	  if (enumerator->array->sorted_slots == NULL)
	    return NULL;

	  if (enumerator->index < enumerator->array->element_count)
	    {
	      objects_array_bucket_t *bucket;

	      bucket = enumerator->array->sorted_slots[enumerator->index];
	      ++(enumerator->index);
	      return bucket;
	    }
	  else
	    return NULL;
	}
      else
	{
	  if (enumerator->array->sorted_slots == NULL)
	    return NULL;

	  if (enumerator->index > 0)
	    {
	      objects_array_bucket_t *bucket;

	      --(enumerator->index);
	      bucket = enumerator->array->sorted_slots[enumerator->index];
	      return bucket;
	    }
	  else
	    return NULL;
	}
    }
  else
    {
      objects_array_bucket_t *bucket;

      if (enumerator->array->slots == NULL)
	return NULL;

      for (bucket = NULL;
	   (enumerator->index < enumerator->array->slot_count
	    && bucket == NULL);
	   ++(enumerator->index))
	{
	  bucket = enumerator->array->slots[enumerator->index];
	}

      return bucket;
    }
}

/** Statistics **/

size_t
objects_array_count (objects_array_t * array)
{
  return array->element_count;
}

size_t
objects_array_capacity (objects_array_t * array)
{
  return array->slot_count;
}

int
objects_array_check (objects_array_t * array)
{
  return 0;
}

int
objects_array_is_empty (objects_array_t * array)
{
  return objects_array_count (array) != 0;
}

/** Emptying **/

void
objects_array_empty (objects_array_t * array)
{
  size_t c;

  /* Just empty each slot out, one by one. */
  for (c = 0; c < array->slot_count; ++c)
    _objects_array_empty_slot (array, array->slots + c);

  return;
}

/** Creating **/

objects_array_t *
objects_array_alloc_with_allocs (objects_allocs_t allocs)
{
  objects_array_t *array;

  /* Get a new array. */
  array = _objects_array_alloc_with_allocs (allocs);

  return array;
}

objects_array_t *
objects_array_alloc (void)
{
  return objects_array_alloc_with_allocs (objects_allocs_standard ());
}

objects_array_t *
objects_array_with_allocs (objects_allocs_t allocs)
{
  return objects_array_init (objects_array_alloc_with_allocs (allocs));
}

objects_array_t *
objects_array_with_allocs_with_callbacks (objects_allocs_t allocs,
					  objects_callbacks_t callbacks)
{
  return objects_array_init_with_callbacks (objects_array_alloc_with_allocs (allocs),
					    callbacks);
}

objects_array_t *
objects_array_with_callbacks (objects_callbacks_t callbacks)
{
  return objects_array_init_with_callbacks (objects_array_alloc (), callbacks);
}

objects_array_t *
objects_array_of_char_p (void)
{
  return objects_array_with_callbacks (objects_callbacks_for_char_p);
}

objects_array_t *
objects_array_of_void_p (void)
{
  return objects_array_with_callbacks (objects_callbacks_for_void_p);
}

objects_array_t *
objects_array_of_owned_void_p (void)
{
  return objects_array_with_callbacks (objects_callbacks_for_owned_void_p);
}

objects_array_t *
objects_array_of_int (void)
{
  return objects_array_with_callbacks (objects_callbacks_for_int);
}

objects_array_t *
objects_array_of_id (void)
{
  return objects_array_with_callbacks (objects_callbacks_for_id);
}

/** Initializing **/

objects_array_t *
objects_array_init_with_callbacks (objects_array_t * array, objects_callbacks_t callbacks)
{
  if (array != NULL)
    {
      /* The default capacity is 15. */
      size_t capacity = 15;

      /* Record the element callbacks. */
      array->callbacks = objects_callbacks_standardize (callbacks);

      /* Initialize ARRAY's information. */
      array->element_count = 0;
      array->slot_count = capacity + 1;

      /* Make some new slots. */
      array->slots = _objects_array_new_slots (array, capacity + 1);

      /* Get the sorted slots ready for later use. */
      array->sorted_slots = NULL;
    }

  return array;
}

objects_array_t *
objects_array_init (objects_array_t * array)
{
  return objects_array_init_with_callbacks (array,
					    objects_callbacks_standard());
}

objects_array_t *
objects_array_init_from_array (objects_array_t * array, objects_array_t * old_array)
{
  objects_array_enumerator_t enumerator;
  size_t index;
  const void *element;

  /* Initialize ARRAY in the usual way. */
  objects_array_init_with_callbacks (array,
			       objects_array_element_callbacks (old_array));

  /* Get an enumerator for OLD_ARRAY. */
  enumerator = objects_array_enumerator (old_array);

  /* Step through OLD_ARRAY's elements, putting them at the proper
   * index in ARRAY. */
  while (objects_array_enumerator_next_index_and_element (&enumerator,
							  &index, &element))
    {
      objects_array_at_index_put_element (array, index, element);
    }

  return array;
}

/** Destroying **/

void
objects_array_dealloc (objects_array_t * array)
{
  if (array != NULL)
    {
      /* Empty out ARRAY. */
      objects_array_empty (array);

      /* Free up its slots. */
      _objects_array_free_slots (array, array->slots);

      /* FIXME: What about ARRAY's sorted slots? */

      /* Free up ARRAY itself. */
      _objects_array_dealloc (array);
    }

  return;
}

/** Searching **/

const void *
objects_array_element_at_index (objects_array_t * array, size_t index)
{
  objects_array_bucket_t *bucket = _objects_array_bucket_for_index (array, index);

  if (bucket != NULL)
    return bucket->element;
  else
    /* If `bucket' is NULL, then the requested index is unused. */
    /* There's no bucket, so... */
    return objects_array_not_an_element_marker (array);
}

size_t
objects_array_index_of_element (objects_array_t * array, const void *element)
{
  size_t i;

  for (i = 0; i < array->slot_count; ++i)
    {
      objects_array_bucket_t *bucket = array->slots[i];

      if (bucket != NULL)
	if (objects_is_equal (objects_array_element_callbacks (array),
			      bucket->element,
			      element,
			      array))
	  return bucket->index;
    }

  return i;
}

int
objects_array_contains_element (objects_array_t * array, const void *element)
{
  /* Note that this search is quite inefficient. */
  return objects_array_index_of_element (array, element) < (array->slot_count);
}

const void **
objects_array_all_elements (objects_array_t * array)
{
  objects_array_enumerator_t enumerator;
  const void **elements;
  size_t count, i;

  count = objects_array_count (array);

  /* Set aside space to hold the elements. */
  elements = (const void **) objects_calloc (objects_array_allocs (array),
				       count + 1,
				       sizeof (const void *));

  enumerator = objects_array_enumerator (array);

  for (i = 0; i < count; ++i)
    objects_array_enumerator_next_element (&enumerator, elements + i);

  elements[i] = objects_array_not_an_element_marker (array);

  /* We're done, so heave it back. */
  return elements;
}

const void **
objects_array_all_elements_ascending (objects_array_t * array)
{
  objects_array_enumerator_t enumerator;
  const void **elements;
  size_t count, i;

  count = objects_array_count (array);

  /* Set aside space to hold the elements. */
  elements = (const void **) objects_calloc (objects_array_allocs (array),
				       count + 1,
				       sizeof (const void *));

  enumerator = objects_array_ascending_enumerator (array);

  for (i = 0; i < count; ++i)
    objects_array_enumerator_next_element (&enumerator, elements + i);

  elements[i] = objects_array_not_an_element_marker (array);

  /* We're done, so heave it back. */
  return elements;
}

const void **
objects_array_all_elements_descending (objects_array_t * array)
{
  objects_array_enumerator_t enumerator;
  const void **elements;
  size_t count, i;

  count = objects_array_count (array);

  /* Set aside space to hold the elements. */
  elements = (const void **) objects_calloc (objects_array_allocs (array),
				       count + 1,
				       sizeof (const void *));

  enumerator = objects_array_descending_enumerator (array);

  for (i = 0; i < count; ++i)
    objects_array_enumerator_next_element (&enumerator, elements + i);

  elements[i] = objects_array_not_an_element_marker (array);

  /* We're done, so heave it back. */
  return elements;
}

/** Removing **/

void
objects_array_remove_element_at_index (objects_array_t * array, size_t index)
{
  objects_array_bucket_t *bucket;

  /* Get the bucket that might be there. */
  bucket = _objects_array_bucket_for_index (array, index);

  /* If there's a bucket at the index, then we empty its slot out. */
  if (bucket != NULL)
    _objects_array_empty_slot (array, _objects_array_slot_for_index (array, index));

  /* Finally, we return. */
  return;
}

void
objects_array_remove_element_known_present (objects_array_t * array,
					    const void *element)
{
  objects_array_remove_element_at_index (array,
				      objects_array_index_of_element (array,
								  element));
  return;
}

void
objects_array_remove_element (objects_array_t * array, const void *element)
{
  if (objects_array_contains_element (array, element))
    objects_array_remove_element_known_present (array, element);

  return;
}

/** Adding **/

const void *
objects_array_at_index_put_element (objects_array_t * array,
				    size_t index,
				    const void *element)
{
  objects_array_bucket_t *bucket;

  /* Clean out anything that's already there. */
  objects_array_remove_element_at_index (array, index);

  /* Make a bucket for our information. */
  bucket = _objects_array_new_bucket (array, index, element);

  /* Put our bucket in the array. */
  _objects_array_insert_bucket (array, bucket);

  return element;
}

/** Enumerating **/

objects_array_enumerator_t
objects_array_ascending_enumerator (objects_array_t * array)
{
  objects_array_enumerator_t enumerator;

  enumerator.array = array;
  enumerator.is_sorted = 1;
  enumerator.is_ascending = 1;
  enumerator.index = 0;

  _objects_array_make_sorted_slots (array);

  return enumerator;
}

objects_array_enumerator_t
objects_array_descending_enumerator (objects_array_t * array)
{
  objects_array_enumerator_t enumerator;

  enumerator.array = array;
  enumerator.is_sorted = 1;
  enumerator.is_ascending = 0;
  /* The `+ 1' is so that we have `0' as a known ending condition.
   * See `_objects_array_enumerator_next_bucket()'. */
  enumerator.index = array->element_count + 1;

  _objects_array_make_sorted_slots (array);

  return enumerator;
}

objects_array_enumerator_t
objects_array_enumerator (objects_array_t * array)
{
  objects_array_enumerator_t enumerator;

  enumerator.array = array;
  enumerator.is_sorted = 0;
  enumerator.is_ascending = 0;
  enumerator.index = 0;

  return enumerator;
}

int
objects_array_enumerator_next_index_and_element (objects_array_enumerator_t * enumerator,
						 size_t * index,
						 const void **element)
{
  objects_array_bucket_t *bucket;

  bucket = _objects_array_enumerator_next_bucket (enumerator);

  if (bucket != NULL)
    {
      if (element != NULL)
	*element = bucket->element;
      if (index != NULL)
	*index = bucket->index;
      return 1;
    }
  else
    {
      if (element != NULL)
	*element = objects_array_not_an_element_marker (enumerator->array);
      if (index != NULL)
	*index = 0;
      return 0;
    }
}

int
objects_array_enumerator_next_element (objects_array_enumerator_t * enumerator,
				       const void **element)
{
  return objects_array_enumerator_next_index_and_element (enumerator,
							  NULL,
							  element);
}

int
objects_array_enumerator_next_index (objects_array_enumerator_t * enumerator,
				     size_t * index)
{
  return objects_array_enumerator_next_index_and_element (enumerator,
							  index,
							  NULL);
}

/** Comparing **/

int
objects_array_is_equal_to_array (objects_array_t * array1, objects_array_t * array2)
{
  size_t a, b;
  const void *m, *n;
  objects_array_enumerator_t e, f;

  a = objects_array_count (array1);
  b = objects_array_count (array2);

  if (a < b)
    return (b - a);
  if (a > b)
    return (a - b);

  /* Get ascending enumerators for each of the two arrays. */
  e = objects_array_ascending_enumerator (array1);
  e = objects_array_ascending_enumerator (array1);

  while (objects_array_enumerator_next_index_and_element (&e, &a, &m)
	 && objects_array_enumerator_next_index_and_element (&f, &b, &n))
    {
      int c, d;

      if (a < b)
	return (b - a);
      if (a > b)
	return (a - b);

      c = objects_compare (objects_array_element_callbacks (array1), m, n, array1);
      if (c != 0)
	return c;

      d = objects_compare (objects_array_element_callbacks (array2), n, m, array2);
      if (d != 0)
	return d;
    }

  return 0;
}

/** Mapping **/

objects_array_t *
objects_array_map_elements (objects_array_t * array,
			    const void *(*fcn) (const void *, const void *),
			    const void *user_data)
{
  /* FIXME: Code this. */
  return array;
}

/** Miscellaneous **/

objects_hash_t *
objects_hash_init_from_array (objects_hash_t * hash, objects_array_t * array)
{
  objects_array_enumerator_t enumerator;
  const void *element;

  /* NOTE: If ARRAY contains multiple elements of the same equivalence
   * class, it is indeterminate which will end up in HASH.  This
   * shouldn't matter, though. */
  enumerator = objects_array_enumerator (array);

  /* Just walk through ARRAY's elements and add them to HASH. */
  while (objects_array_enumerator_next_element (&enumerator, &element))
    objects_hash_add_element (hash, element);

  return hash;
}

// objects_chash_t *
// objects_chash_init_from_array (objects_chash_t * chash, objects_array_t * array)
// {
//   objects_array_enumerator_t enumerator;
//   const void *element;
// 
//   /* NOTE: If ARRAY contains multiple elements of the same equivalence
//    * class, it is indeterminate which will end up in CHASH.  This
//    * shouldn't matter, though. */
//   enumerator = objects_array_enumerator (array);
// 
//   /* Just walk through ARRAY's elements and add them to CHASH. */
//   while (objects_array_enumerator_next_element (&enumerator, &element))
//     objects_chash_add_element (chash, element);
// 
//   return chash;
// }

