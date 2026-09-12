# ClipForge iOS

ClipForge 的 iOS / iPadOS 客户端。把「图片生成、图生视频、语音合成与声音克隆、素材时间线拼接导出」整合进一个 App，复刻 macOS 版的核心能力，针对移动端重新组织交互。

> **仓库关系**：本仓库（`PlayChessClub/ClipForge-ios`）是 iOS 正式实现。
> 另有两条平行发布线：[videogenerator](https://github.com/PlayChessClub/videogenerator)（macOS 原生，主力）与
> [clipforge-web](https://github.com/PlayChessClub/clipforge-web)（Windows / Linux Web 版）。
> macOS 仓库内的 `ClipForgeAI/ios/` 是**早期 swiftc 版 iOS 尝试（历史遗留、不再维护）**，与本仓库无关，以本仓库为准。

## 功能

- **图片生成**：试试手气 / 试试手气 Pro 两阶段（向量选句 + qwen-plus 扩写）；多模型、1:1 / 16:9 / 9:16 尺寸、1/2/4 张可选；提交前弹出 Token 消耗确认。
- **视频生成**：wan 系列图生视频（i2v）与文生视频（t2v），**模型下拉可选（价格升序 + 一句话优势）**；首帧图支持相册 / 文件 / URL 三种来源；配音音频可选；720P / 1080P、5/10/15 秒、单 / 多镜头、智能扩写与音频轨开关；任务轮询 → 自动下载 → 内置播放器预览 + 分享。
- **语音合成**：CosyVoice 文本转语音，**模型下拉可选（cosyvoice-v3.5-flash / v3.5-plus 默认 / v3-plus / v2，价格升序）**；克隆模型与合成模型保持一致（音色与模型绑定）；Pro 旁白两阶段；「我的音色」云端列表（点选填充、长按删除）。
- **声音克隆**：录音（麦克风 16k wav）/ 本地音频 / 公网 URL → 上传 OSS → voice-enrollment → 轮询就绪，生成专属音色。
- **时间线**：素材库（生成结果自动收录，也可手动导入 mp4 / 音频 / 图片）；两种导出模式——拼接（保留原声）与配音（替换音轨），AVFoundation 原生导出 mp4。
- **账本**：每次生成记录模型 / Token / 费用，可在设置页 CSV 分享。

## 要求

- Xcode 26+（已在 26.6 验证）
- 运行目标：**iOS 16.1+ 真机**（iPhone 8 / iPhone10,1 实测）或 **iOS 26.5 模拟器**
- **DashScope API Key**：在「设置」页填写，存入 Keychain
- **Apple ID**：免费账号即可（自动签名）；App 有效期 7 天，重跑 ⌘R 续期

## 构建与运行

1. 用 Xcode 打开 `clipforgeios.xcodeproj`
2. 顶部选择运行目标（已连接真机或模拟器），按 **⌘R**
3. 真机首次运行：
   - **设置 > 隐私与安全性 > 开发者模式** → 打开，手机会重启
   - 重启后 **设置 > 通用 > VPN 与设备管理** → 信任你的开发者证书
4. 免费个人账号不支持「推送通知 / iCloud」能力，`clipforgeios.entitlements` 已清空，无需额外申请。
5. 启动后在「设置」页填入 DashScope API Key 即可使用全部功能。

## 目录结构

```
clipforgeios/                  SwiftUI 应用（5 个 Tab：图片 / 视频 / 语音 / 时间线 / 设置）
clipforgeios/ClipForgeCore/    共享逻辑：网络(DashScopeClient) / 模型 / Token 估算 / 价目 / 词库 / 导出引擎
VoiceSamples/                  内置样音（声音克隆演示用）
clipforgeios.xcodeproj         Xcode 26 工程（PBXFileSystemSynchronizedRootGroup，文件夹同步）
```

## 签名

仓库内的工程配置：

- `CODE_SIGN_STYLE = Automatic`
- `DEVELOPMENT_TEAM = YOUR_TEAM_ID`（**占位符**，入库即为占位符）
- `PRODUCT_BUNDLE_IDENTIFIER = videogenerator.clipforgeios`（Tests 为 `videogenerator.clipforgeiosTests`）

运行时按下面填自己的 Team（免费个人账号即可）：

1. Xcode 打开工程 → 选项目 → *Signing & Capabilities*；
2. **Team** 选你自己的账号（或填入你的 Team ID）；Bundle Identifier 改成全局唯一（例如 `com.<你的名字>.clipforgeios`）；
3. Xcode 会自动生成个人证书与描述文件。

> ⚠️ 本地填入真实 Team 后，`clipforgeios.xcodeproj/project.pbxproj` 会变成“已修改”状态——**请勿 `git add` / 提交该改动**，保持入库版本是占位符 `YOUR_TEAM_ID`，避免他人 clone 后签名冲突。
> 若已误改想还原：`git checkout -- clipforgeios.xcodeproj/project.pbxproj`（还原后需在 Xcode 重新选一次 Team）。

## 说明

- 本仓库为**源码仓库**，不发布预编译 IPA；需要 IPA 请按上面步骤在本地 archive + export（development 方式，含已注册设备）。
- 与 macOS 版的视觉差异：iOS 保留系统底部 TabBar，背景为系统默认外观（未启用 macOS 的 Aurora 彩色背景）。
- 数据源与 macOS 版一致：图片 / 视频走阿里云百炼 DashScope，语音走 CosyVoice。
