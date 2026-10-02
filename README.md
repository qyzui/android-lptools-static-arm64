# android-lptools-static-arm64

Android ARM64 静态构建的动态分区工具：

- lpmake
- lpdump
- lpflash
- lpadd
- lpunpack

## 构建

GitHub Actions 使用 Android NDK 构建 AArch64/ARM64 ELF，并在构建完成后检查动态依赖。

验证要求：

- ARM64 / AArch64
- 静态 ELF
- 不包含 DT_NEEDED 动态依赖

## 下载

构建完成后，从 GitHub Actions 的 Artifacts 下载构建产物。
