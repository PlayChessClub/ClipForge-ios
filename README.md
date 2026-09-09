# ClipForge iOS

ClipForge 的 iOS / iPadOS 客户端。把「图片生成、图生视频、语音合成与声音克隆、素材时间线拼接导出」整合进一个 App，复刻 macOS 版的核心能力，针对移动端重新组织交互。

## 功能

- **图片生成**：试试手气 / 试试手气 Pro 两阶段（向量选句 + qwen-plus 扩写）；多模型、1:1 / 16:9 / 9:16 尺寸、1/2/4 张可选；提交前弹出 Token 消耗确认。
- **视频生成**：wan 系列图生视频（i2v）与文生视频（t2v）；首帧图支持相册 / 文件 / URL 三种来源；配音音频可选；720P / 1080P、5/10/15 秒、单 / 多镜头、智能扩写与音频轨开关；任务轮询 → 自动下载 → 内置播放器预览 + 分享。
- **语音合成**：CosyVoice 文本转语音；Pro 旁白两阶段；「我的音色」云端列表（点选填充、长按删除）。
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

`project.pbxproj` 已写入 `DEVELOPMENT_TEAM = YOUR_TEAM_ID`、`CODE_SIGN_STYLE = Automatic`。
换成自己的账号：把 pbxproj 里的 `DEVELOPMENT_TEAM` 改成你的 Team ID，Xcode 会自动用你的证书与描述文件。

## 说明

- 本仓库为**源码仓库**，不发布预编译 IPA；需要 IPA 请按上面步骤在本地 archive + export（development 方式，含已注册设备）。
- 与 macOS 版的视觉差异：iOS 保留系统底部 TabBar，背景为系统默认外观（未启用 macOS 的 Aurora 彩色背景）。
- 数据源与 macOS 版一致：图片 / 视频走阿里云百炼 DashScope，语音走 CosyVoice。
