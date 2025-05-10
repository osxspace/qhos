# ARCEOS QA

## arceos 基本框架组成

- 应用程序(app) -> axstd -> api |->  (axruntime | kerenel) -> axhal
- hal - hardware abstract layer (硬件抽象层，这里是与 opensbi 交互的)
- arceruntime 从源码看起到承上启下的作用，没有实际重要的代码

## 从 arceos 打印日志看是走的 api 调用，但是 rcore 是走的 syscall，真是操作系统如何选择？

- 是否是交给上层的 std 自己来决策