# ARCEOS QA

## arceos 基本框架组成

- 应用程序(app) -> axstd -> arceos_api |->  (axruntime | kerenel) -> axhal
- arceruntime 从源码看起到承上启下的作用，辅助 axhal 引导程序启动，也就是从 rusty_entry -> rust_main -> fn main
- hal - hardware abstract layer (硬件抽象层，这里是与 opensbi 交互的)

## axhal 是如何引导 arceos 的应用程序启动的

- axhal/src/platform/riscv64_qemu_virt/boot.rs
- axhal/src/platform/riscv64_qemu_virt/mod.rs (rust_entry)

## 从 arceos 打印日志看是走的 api 调用，但是 rcore 是走的 syscall，真是操作系统如何选择？

- 是否是交给上层的 std 自己来决策