# zcoro 思路

- stackless
  - future
  - eventloop
  - threadpool
- stackful

## api design

fn main() {
  fn count(chan: Channel) {
    const res = 10;
    chan.return(res)
  }
  const async_count = xasync(counter)
  const res = await(async_count)
  print(res)
}

QueueScheduler
  - ThreadPool
  - Eventloop
  
- StackfulFrame -> Coroutine -> switch_context
  - StacklessFrame -> Future -> poll
  - Schedule enqueue  
- return value use channel like go style