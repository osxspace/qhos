# xasync

- fiber - stackfull coroutine -> green thread
- runtime - stackless coroutine -> future

## how to run

```sh
# use zig 0.14.1
cd ./
zig run xasync.zig
zig test fut_rt.zig
```