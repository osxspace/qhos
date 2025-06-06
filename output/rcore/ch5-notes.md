# CH5 Notes

让开发者能够控制程序的运行 - 原本只能通过操作系统内核来控制

## 理论

### 目标

抽象进程的概念，并实现以下功能：

- 创建
- 销毁
- 等待
- 信息
- 其他

### 状态

- 就绪态
- 运行态
- 等待态

### 操作

- 创建
- 阻塞
- 终止

### 系统调用

- fork
- exec
- wait
- exit

### 改动思路

- 但把任务抽象进化成了进程抽象
- 其主要改动集中在进程管理的功能上，即通过提供新的系统调用服务
  - sys_fork(创建子进程)、
  - sys_waitpid(等待子进程结束并回收子进程资源)、
  - sys_exec（用新的应用内容覆盖当前进程，即达到执行新应用的目的）
- 为了让用户能够输入命令或执行程序的名字，ProcessOS还增加了一个 read 系统调用服务，这样用户通过操作系统的命令行接口 – 新添加的 shell 应用程序发出命令，来动态地执行各种新的应用

### 进程，线程和协程 - 很重要

进程，线程和协程是操作系统中经常出现的名词，它们都是操作系统中的抽象概念，有联系和共同的地方，但也有区别。计算机的核心是 CPU，它承担了基本上所有的计算任务；而操作系统是计算机的管理者，它可以以进程，线程和协程为基本的管理和调度单位来使用 CPU 执行具体的程序逻辑。

从历史角度上看，它们依次出现的顺序是进程、线程和协程。在还没有进程抽象的早期操作系统中，计算机科学家把程序在计算机上的一次执行过程称为一个任务（Task）或一个工作（Job），其特点是任务和工作在其整个的执行过程中，不会被切换。这样其他任务必须等待一个任务结束后，才能执行，这样系统的效率会比较低。

在引入面向 CPU 的分时切换机制和面向内存的虚拟内存机制后，进程的概念就被提出了，进程成为 CPU（也称处理器）调度（Scheduling）和分派（Switch）的对象，各个进程间以时间片为单位轮流使用 CPU，且每个进程有各自独立的一块内存，使得各个进程之间内存地址相互隔离。这时，操作系统通过进程这个抽象来完成对应用程序在 CPU 和内存使用上的管理。

随着计算机的发展，对计算机系统性能的要求越来越高，而进程之间的切换开销相对较大，于是计算机科学家就提出了线程。线程是程序执行中一个单一的顺序控制流程，线程是进程的一部分，一个进程可以包含一个或多个线程。各个线程之间共享进程的地址空间，但线程要有自己独立的栈（用于函数访问，局部变量等）和独立的控制流。且线程是处理器调度和分派的基本单位。对于线程的调度和管理，可以在操作系统层面完成，也可以在用户态的线程库中完成。用户态线程也称为绿色线程（GreenThread）。如果是在用户态的线程库中完成，操作系统是“看不到”这样的线程的，也就谈不上对这样线程的管理了。

协程（Coroutines，也称纤程（Fiber）），也是程序执行中一个单一的顺序控制流程，建立在线程之上（即一个线程上可以有多个协程），但又是比线程更加轻量级的处理器调度对象。协程一般是由用户态的协程管理库来进行管理和调度，这样操作系统是看不到协程的。而且多个协程共享同一线程的栈，这样协程在时间和空间的管理开销上，相对于线程又有很大的改善。在具体实现上，协程可以在用户态运行时库这一层面通过函数调用来实现；也可在语言级支持协程，比如 Rust 借鉴自其他语言的的 async 、 await 关键字等，通过编译器和运行时库二者配合来简化程序员编程的负担并提高整体的性能。

- 进程是操作系统进行资源调度的基本对象
- 线程共享进程的地址空间，拥有自己独立的栈 - 函数栈
- 协程共享同一个线程的栈 - 函数栈

### 各种调度机制的实现

- 单处理器调度
  - 调度时机
  - 调度策略
    - 机器资源使用模式
  - 找出衡量指标
    - cpu 使用率
    - 吞吐量已延迟 - 高带宽低延迟
    - 响应时间
  - 常见调度算法 - 调度算法的演进
    - FCFS - 先来先服务
    - SJF - 短作业有限
    - SRT - 最短剩余时间
    - HRRN - 最高响应比
    - RR - round robin - 时间片轮转算法
    - 多级队列调度算法 - MQ
    - 多级反馈
    - 公平共享调度苏凡
- 实时调度
- 多核处理器的调度

## 实践

### 代码修改

- 基于应用名加载应用
  - load_app
  - get_app_data
- 创建进程标识符
  - PidHandler
  - PidAllocator
- 内核栈创建代码抽取
- 进程控制块调整 (TCB)
  - 基本结构调整
  - 系统调用实现
    - fork
      - 地址空间创建
    - exec
    - exit
      - 进程资源回收机制 - 进程资源回收挂载初始进程
    - waitpid - 初始进程等待子进程结束
- TaskManager 调整
  - TaskManager - 负责管理所有进程(任务)
  - Processor - 负责调度
- 任务调度循环实现 
  - 协作式调度
  - 抢占式调度
  - 进程调度机制详细实现
- 创建初始进程
- 根据字符输入运行进程