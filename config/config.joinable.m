/* Test whether Objective-C runtime uses pthreads and doesn't detach
 * them properly. If the join attempt succeeds, the thread was created
 * joinable (which it shouldn't be) and this program returns 0.
 */

#include <objc/thr.h>
#include <objc/Object.h>
#include <pthread.h>

int
main()
{
  id            o = [Object new];
  pthread_t     tid;
  void          *value_ptr;

  tid = (pthread_t)objc_thread_detach (@selector(hash), o, nil);
  return pthread_join (tid, &value_ptr);
}

