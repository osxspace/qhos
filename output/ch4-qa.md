# CH4 QA

## Codes Diff

## 结构存储对照关系

- loader -> task -> memory_set -> page_table -> memory_area


SV39 定义

39 位虚拟页表转换为 56 位的物理页表，需要 64 位的三级页表项来存储映射关系 
- 这个概念从哪得出来的
  - ppt
  - book
  - deepseek
  - trae
    - 家里
    - 公司
  - cursor - no

38 位虚拟页表定义
56 位物理页表的定义
64 位页表项的定义

如何通过虚拟地址通过页表项找到物理地址

举例说明

- ![地址格式图](https://rcore-os.cn/rCore-Tutorial-Book-v3/_images/sv39-va-pa.png)

- ![satp组成](https://learningos.cn/os-lectures/lec5/figs/satp.png)

## 使用 satp 开启 SV39 的实现原理

### 概念

satp (Supervisor Address Translation and Protection) 的缩写，是 CSR (Control Status Register) 类型寄存器中的一种，它决定了是否启用虚拟内存以及使用哪种虚拟页表格式

satp 寄存器分为三段，如下图：

![satp组成](https://learningos.cn/os-lectures/lec5/figs/satp.png)

- MODE (4位)：开启分页并选择页表级数
    - 0 -> Bare 模式（无地址转换，物理地址=虚拟地址）
    - 8 -> Sv39 模式（39位虚拟地址空间）
    - 9 -> Sv48 模式（48位虚拟地址空间）
- ASID (16位)：地址空间标识符，用于TLB隔离不同进程 - 可选的，用来降低上下文切换的开销 (目前暂时无用)
- PPN (44位)：根页表的物理页号（Page Table Number）

### 代码实现思路剖析

```rs
// main.rs

pub fn rust_main() -> ! {
    ...
    mm::init(); // memory init
    ...
}
```

```rs
// mm/mod.rs

pub fn init() {
    heap_allocator::init_heap();
    frame_allocator::init_frame_allocator();
    KERNEL_SPACE.exclusive_access().activate(); // 激活 SV39 多级页表虚拟内存管理机制
}
```

```rs
// memory_set.rs
pub fn activate(&self) {
    let satp = self.page_table.token(); // 获取了用于设置 satp 寄存器的值
    unsafe {
        satp::write(satp); // 调用 rsic-v 库设置 satp 寄存器的值
        asm!("sfence.vma"); // sfence.vma 是RISC-V的一条指令，用于刷新TLB(Translation Lookaside Buffer)缓存。当页表发生变化时，需要执行这条指令以确保CPU不会使用过时的地址转换信息。
    }
}
```

```rs
// page_table.rs

/// get the token from the page table
pub fn token(&self) -> usize {
    // 8usize << 60 代表开启 SV39 分页模式 MODE 设置为 8
    // 8usize << 60 设置了最高的4位（60-63位）
    // self.root_ppn.0 设置了低44位（0-43位）
    // 按位或操作可以在不影响对方的情况下将这两个值合并到一个64位整数中
    8usize << 60 | self.root_ppn.0 
}
```

```rs
// page_table.rs

/// Create a new page table
pub fn new() -> Self {
    let frame = frame_alloc().unwrap();
    PageTable {
        root_ppn: frame.ppn, // root_ppn 是在这里通过 frame (FrameTracker) 获取到的
        frames: vec![frame],
    }
}
```

```rs
// frame_allocator.rs

/// Allocate a physical page frame in FrameTracker style
pub fn frame_alloc() -> Option<FrameTracker> { // 通过这个函数获取 frame (FrameTracker)
    FRAME_ALLOCATOR
        .exclusive_access()
        .alloc() // 这里的这个 alloc 调用很关键，
        .map(FrameTracker::new)
}

/// Allocate a physical page frame in FrameTracker style
fn alloc(&mut self) -> Option<PhysPageNum> { // 这里就可以看到实际上物理页号是按照什么规则创建和维护的
    if let Some(ppn) = self.recycled.pop() {
        Some(ppn.into())
    } else if self.current == self.end {
        None
    } else {
        self.current += 1;
        Some((self.current - 1).into())
    }
}

impl FrameTracker {
    /// Create a new FrameTracker
    pub fn new(ppn: PhysPageNum) -> Self {
        // page cleaning
        let bytes_array = ppn.get_bytes_array(); // 在这里将物理页的内存清零
        for i in bytes_array {
            *i = 0;
        }
        Self { ppn }
    }
}

pub fn init_frame_allocator() { // 这个函数设置了物理帧分配器的范围，从内核结束地址 ekernel 到内存结束地址 MEMORY_END
    extern "C" {
        fn ekernel();
    }
    FRAME_ALLOCATOR.exclusive_access().init(
        PhysAddr::from(ekernel as usize).ceil(),
        PhysAddr::from(MEMORY_END).floor(),
    );
}
```

```rs
// address.rs

/// Get the reference of page(array of bytes)
pub fn get_bytes_array(&self) -> &'static mut [u8] {
    let pa: PhysAddr = (*self).into(); // 根据物理页号获取物理地址起始
    unsafe { core::slice::from_raw_parts_mut(pa.0 as *mut u8, 4096) } // 获取到 4k 的物理页字节数组
}
```

### 获取 token 后填充 satp 寄存器的计算过程

假设我们有以下情况：

- 根页表的物理页号 self.root_ppn.0 是 0x12345
- 我们要使用 SV39 模式，对应的模式值是 8

计算过程如下：

- 8usize << 60 = 8 * 2^60 = 0x8000000000000000
- self.root_ppn.0 = 0x12345
- 8usize << 60 | self.root_ppn.0 = 0x8000000000000000 | 0x12345 = 0x8000000000012345

最终写入 satp 寄存器的值是 0x8000000000012345 ，这个值包含了：

- MODE = 8（SV39模式）
- ASID = 0（未使用地址空间标识符）
- PPN = 0x12345（根页表的物理页号）

```
0x8000000000012345 = 1000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0001 0010 0011 0100 0101
```

我们可以按照 satp 寄存器的结构来分解这个二进制值：

- MODE （4位 60-63）： 1000 = 8，表示SV39分页模式
- ASID （16位 44-59）： 0000 0000 0000 0000 = 0，未使用地址空间标识符
- PPN （44位 0-43）： 0000 0000 0000 0000 0000 0000 0000 0001 0010 0011 0100 0101 = 0x12345，根页表的物理页号

## SV39 虚拟地址空间结构

## 如何构建页表结构的

## 4k 页表大小是如何跟页表项填充的

## 跳板思路以及为什么要用跳板

## 各种上下文的理解

### TrapContext

### TaskContext

### 桥

## PageFault 如何检测的

- memarea 记录了虚拟地址空间的范围

## 常用的 CSR 寄存器有哪些，都有什么作用，参考书在哪里

## need todo

- 4096 介绍

- 地址空间多少位概念理解 - 阅读书
- 整理 deepseek AI 聊天 - 并整理到位部分

- 继续往下解答 QA 到 跳板之前

- 回答第一个问题
- 单独跑一个测试用例