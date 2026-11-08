# 1937 iPad 云端构建包

本目录可直接作为 GitHub 仓库根目录上传，也可以将里面的文件加入你已有的
`efzb-wx/1937tezhongbing` 仓库。请保留 `.github` 隐藏目录。

## 当前状态

- 已编写 iPad 资源打包与沙盒解压、横屏界面和触控操作适配。
- 本地使用 Godot 4.7.2 验证十二关读取、资源完整性、第一关地形和角色加载、
  触控移图/框选以及按钮选人；原有 101 项输入检查通过。
- 尚未在 macOS 执行 Xcode 编译，也没有 iPad 真机验证。
- 本目录是构建输入，不是 IPA，不能直接安装到 iPad。

## 上传并构建

1. 将 `.github/`、`port/`、`scripts/` 和 IPAD-BUILD.md 上传至仓库根目录。
   不需要上传游戏资源 ZIP、Windows EXE 或 Godot 编辑器。
2. 使用 `main` 或 `ipad-build` 分支提交这些文件，工作流会自动触发。
   也可以在 GitHub 的 Actions 中打开 **Build iPad IPA (unsigned)**，点击
   **Run workflow**。Fork 仓库可能需要先在 Actions 页启用工作流。
3. 等待 macOS runner 下载原始源码、公开发行资源、Godot 和导出模板，导出
   Xcode 工程并编译 ARM64 应用。
4. 成功后下载 Artifacts 中的 `1937-iPad-unsigned`，解压得到
   `1937-iPad-unsigned.ipa` 和 SHA-256 文件。失败时查看 `ios-build-logs`。

工作流不会写回仓库或公开发布 Release，只上传构建产物，保留 14 天。
实际可运行性仍需要首次云端构建与真机测试确认。请以 Actions 的实际执行结果
为准；当前没有已经成功生成 IPA 的记录。

## 安装与操作

构建产物没有苹果签名，需要使用你自己的签名/侧载方式安装。它不是可以直接
点击安装的已签名应用。签名有效期由你使用的账户与安装方式决定。

目标为 ARM64 iPad、iPadOS 16 或更新版本、横屏。真实最低系统版本还受
所用 Godot 导出模板和 Xcode 支持范围限制。

顶部菜单切换：

- **点按**：按原游戏左键规则选人、移动或攻击。
- **移图**：在场景内拖动平移镜头。
- **框选**：在场景内拖动矩形选择队员。
- **+ / −**：调整镜头缩放。
- **更多**：队员 1—5、武器、物品、视线、掩埋和帮助。

首次启动需要把约 157 MiB 资源解压到应用沙盒，启动页会显示进度；之后直接
复用缓存。安装与首次运行需要为打包资源及解压缓存预留空间。
触控按钮目前沿用默认快捷键；修改键位后需同步适配。尚未验证所有设备安全区、
多点触控、完整十二关通关及后台恢复。

## 版本与构建路径

- 上游：`https://github.com/bigsinger/1937tezhongbing`
- 固定源码：`7ddb75fa4b3425d6f1f5327a11dff728e4fbf56c`
- 游戏资源发行版：`archive-2026.08.10 / 1937-Remake-portable.zip`
- Godot：`4.7.2-stable`，Standard / GDScript
- runner：`macos-15`
- Bundle ID：`org.community.m1937.ipad`

`port/` 只包含新增适配文件和集成脚本。构建时从固定上游拉取 Remake，
覆盖这些文件，再运行集成脚本与资源校验，不需要把整份源码重复上传。
