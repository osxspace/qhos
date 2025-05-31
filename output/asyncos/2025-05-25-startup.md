# 第四阶段启动会

## 大致情况

- 从 2020 年开始
- 参与人数 - 发展空间
- 工程师比例逐年增加
- 通过率
- 归纳总结
- 实习的方向
- 共性小任务列表
  - deepwiki - 写文档
  - 代码改进
  - axprocess 小任务
- 学完第四阶段
  - 开源之夏
  - 全国大学生计算机系统能力大赛
  - 研究生操作系统开源创新大赛
- 完全、性能、开发、AI 支持是大方向

## 宏内核方向 - 郑友介 - 找 PPT

- arceos -> starry os -> 兼容 linux app
- starry 系统
  - 规范文档
  - 提供测例
  - 训练营工作规范化
- VDOS
- 网络协议栈的支持 - 这个需要看
- shadow process
  - 参考 osbinglab-2025s - nimbos
- 支持更多 linux 应用
- 扩展设备支持 - lwip

## hypervisor 方向

- github: hky1999
- AxVisor - Virtual Machine Manager
- 子方向
  - 设备树解析与修改 - DeviceTree
  - SeaBIOS
  - Type 1.5 AxVisor 启动 - rvm-rtos
    - type1 - bare metal 的 hypervisor
    - type1.5 - 部分硬件、部分 hypervisor - JailHouse
    - type2 - 运行在宿主操作系统之上的 - vmware
  - 虚拟中断控制器的开发 - 模拟中断控制器
  - axaddrspace 的 clone 和 COW 支持 - vm fork 的概念
    - vm fork 为一个新的 VM 实例
- discussion 小任务
- 每周六晚 8:30 腾讯在线会议

## 异步操作系统方向 - 向勇老师

- 各个模块都会有
- 宏观目标
  - 用户态中断 - 硬件支持了协程 - 软硬协同技术
    - risc-v
    - intel
- 方向
  - 变成组件
    - 杨德瑞 rCore-in-Single-workspace
    - arceos
  - 改善性能
    - fast-trap - 切换性能提升 - 杨德瑞
    - 吴一凡 - 优化
  - 调度器发力
    - tonado-os - 共享调度器的异步内核
    - 王文智 - UnifiedScheduler
    - 扬长可 - uCOS 做无人机飞控 - embassy_preempt - 性能对比
    - rCore-N
    - async-os
  - 开发调试工具
    - os-checker - 静态分析工具
    - code-debug