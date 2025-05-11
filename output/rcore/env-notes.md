# ENV NOTES 开发环境搭建

## 将 assets/devcontainer-rcore 目录下的 devcontainer 配置文件放到工程的 .devcontainer 中

### Dockerfile 中 rust 版本不一致问题

在 Dockerfile 中将 RUST_VERSION=nightly-2024-05-02 修改为与 toolchain.toml 中的一致

### cargo install cargo-binutils 失败问题

```sh
cargo install cargo-binutils 这个命令现在会报错：
Caused by:
  rustc 1.80.0-nightly is not supported by the following package:
    backtrace@0.3.75 requires rustc 1.82.0
  Try re-running `cargo install` with `--locked
```

需要使用 cargo install cargo-binutils --locked 来解决，估计是 backtrace 设置了 rust 版本限制

## 将 .vscode settings.json 修改为如下配置

```json
{
    "rust-analyzer.cargo.target": "riscv64gc-unknown-none-elf",
    "rust-analyzer.checkOnSave": false
}
```

