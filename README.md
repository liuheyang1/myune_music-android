# Myune Music for Android

Myune Music 的 Android 版源码。它是一个独立的 Flutter 工程，项目根目录就是本目录；`android/` 只是其中的原生平台部分。应用入口为 `lib/main.dart`，音频元数据功能还依赖 `rust/` 和 `rust_builder/`。

## 构建

准备 Flutter 3.47.2、Android SDK/NDK 28.2.13676358、JDK 17 和 Rust 工具链。在本目录运行：

```powershell
flutter pub get
flutter analyze
flutter test test
flutter build apk --debug --target-platform android-arm64
```

开发时可运行 `flutter run`。首次构建需要下载 Flutter/Dart、Gradle 和 Rust 依赖。GitHub Actions 对每次提交和拉取请求执行分析、备份测试和 Android/Rust 调试构建；调试 APK 不作为公开发行包。

## 歌单备份

设置 → 歌曲库提供“导出歌单备份”和“恢复歌单备份”。备份是带版本号的 JSON，只保存歌单结构、歌曲文件名和内容指纹，不包含音频，也不包含本机绝对路径。换机时先导入备份，再选择对应的音乐文件；应用按内容指纹匹配，显示已匹配与未找到的数量，确认后合并到现有歌单。未找到的歌曲不会写入歌单，可以稍后重新导入同一备份补齐。文件夹歌单在另一台设备上恢复为普通歌单，因为原文件夹路径无法移植。

Android 上新选入的歌曲会从文件选择器缓存复制到应用的持久目录；旧缓存路径在文件仍存在时也会在启动后迁移。由于歌曲文件存放在应用目录，卸载应用会删除这些副本。请自行保留原始音乐文件及导出的歌单备份。
这些音频副本已从 Android 自动备份中排除，避免大量音乐文件占用设备备份空间。

## 发布前

- GitHub 预览版使用 `com.myune.music.preview`，可以与原应用并存。第一次公开发布后，保持此包名和同一把签名密钥，才能覆盖安装后续版本。
- 由于 Android 对不同包名的数据隔离，预览版不会自动读取旧版 `com.myune.music` 的歌单；首次使用需重新导入音乐。此后可用预览版内的歌单备份功能迁移。
- 推荐把 PKCS12 密钥和 `key.properties` 都放在源码目录外，将 `MYUNE_SIGNING_PROPERTIES` 指向该配置文件；本机发布脚本也会查找同级的 `myune_music-android-signing/key.properties`。配置模板见 `android/key.properties.example`。真实密码、密钥和构建产物不要提交到 GitHub。
- 签名配置就绪后，在 Windows 运行 `& .\tool\build_release.ps1`；它会检查、构建签名 ARM64 APK，并打印 SHA-256。产物位于 `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`。发布到 GitHub Releases 时附上 APK、校验值、变更记录和已知限制。每次发行递增 `pubspec.yaml` 中 `+` 后面的构建号。

## 来源与许可

本项目从 [xiaobaimc/myune_music](https://github.com/xiaobaimc/myune_music) 的本地副本提取 Android 代码，并包含 Android 界面的后续修改。原项目及此提取版本保留 Apache License 2.0 许可，见 [LICENSE](LICENSE)。原项目的图标继续使用；新增听歌房插画的来源见 [ASSET_CREDITS.md](docs/ASSET_CREDITS.md)。`rust_builder/cargokit/` 包含第三方构建工具及其许可文件。发布时请保留原有版权与许可声明，并说明你对 Android 版所做的修改。

公开版没有打包音乐、专辑封面、从其他网站获取的场景插画或 MiSans 字体文件。用户从自己的设备选择音乐时，应用会读取该文件内嵌的封面；这些文件不进入仓库或发布安装包。

GitHub 仓库 [liuheyang1/myune_music-android](https://github.com/liuheyang1/myune_music-android) 是原项目的 Fork；当前主分支仅保留 Android 工程。原项目的 Windows/Linux 代码请到上游仓库查看。
