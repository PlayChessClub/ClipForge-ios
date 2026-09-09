import SwiftUI
import UniformTypeIdentifiers

// MARK: - 设置页（API Key / 保存位置 / 音色素材夹 / 价目表）
//
// API Key 存 Keychain（iOS 适配：afterFirstUnlock + synchronizable=false，见 Core.Models.Keychain）
// 保存位置：iOS 沙盒 Documents/ClipForge，不可改根（与 macOS「整根目录」不同，沙盒仅能写自己容器内）
// 音色素材夹：默认 Documents/VoiceSamples，可在本页改；改的只是「将来写入位置」，不搬旧文件

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var keyDraft: String = ""
    @State private var showFolderPicker = false
    @State private var showSaved = false
    @State private var savedMsg = ""

    var body: some View {
        NavigationStack {
            Form {
                // MARK: DashScope
                Section {
                    HStack {
                        Text("API Key 状态")
                        Spacer()
                        Text(settings.hasKey ? "已填写" : "未填写")
                            .foregroundStyle(settings.hasKey ? .green : .secondary)
                    }
                    SecureField("粘贴 DashScope API Key", text: $keyDraft)
                        .textContentType(.password)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Button(action: saveKey) {
                        Label("保存到钥匙串", systemImage: "key.fill")
                    }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("DashScope 凭证")
                } footer: {
                    Text("Key 仅存于本机钥匙串，不上传、不落日志。")
                        .font(.footnote)
                }

                // MARK: 保存位置
                Section {
                    HStack {
                        Text("图片/音频保存位置")
                        Spacer()
                        Text("Documents/ClipForge")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("生成结果保存位置")
                } footer: {
                    Text("iOS 沙盒限制：结果只能写入本 App 容器内（文件 App 可访问「我的 iPhone → ClipForge」）。")
                        .font(.footnote)
                }

                // MARK: 音色素材夹
                voiceMaterialSection

                // MARK: 账本入口
                Section {
                    NavigationLink {
                        BillingView()
                    } label: {
                        Label("生成账单（明细与 CSV 导出）", systemImage: "receipt")
                    }
                }

                // MARK: 价目表
                priceSection
            }
            .navigationTitle("设置")
            .onAppear { keyDraft = settings.apiKey }
            .alert("已保存", isPresented: $showSaved) {
                Button("好", role: .cancel) {}
            } message: { Text(savedMsg) }
            .fileImporter(
                isPresented: $showFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    VoiceSampleKit.setMaterialRoot(url)
                    savedMsg = "音色素材夹已改为：\(VoiceSampleKit.materialRootDisplay())"
                    showSaved = true
                }
            }
        }
    }

    private var voiceMaterialSection: some View {
        Section {
            HStack {
                Text("当前素材夹")
                Spacer()
                Text(VoiceSampleKit.materialRootDisplay())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            Button(action: { showFolderPicker = true }) {
                Label("选择素材夹…", systemImage: "folder")
            }
            if !VoiceSampleKit.isMaterialRootDefault {
                Button(role: .destructive, action: {
                    VoiceSampleKit.resetMaterialRoot()
                    savedMsg = "已重置为默认：Documents/VoiceSamples"
                    showSaved = true
                }) {
                    Label("重置为默认", systemImage: "arrow.uturn.backward")
                }
            }
        } header: {
            Text("音色素材夹（Voice Samples）")
        } footer: {
            Text("内置样音（随包）只读可试听/克隆；手动放入的 wav/mp3/m4a 作为用户素材列出。")
                .font(.footnote)
        }
    }

    private var priceSection: some View {
        Section {
            ForEach([("视频", PriceList.video),
                     ("图片", PriceList.image),
                     ("语音", PriceList.audio),
                     ("向量/文本", PriceList.vector)], id: \.0) { group in
                DisclosureGroup(group.0) {
                    ForEach(group.1) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name).font(.subheadline)
                            Text("\(row.model) · \(row.unit) · \(row.price)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("价目表（华北2·北京按量，仅供参考）")
        } footer: {
            Text("实际以阿里云官方账单为准。")
                .font(.footnote)
        }
    }

    private func saveKey() {
        settings.apiKey = keyDraft
        settings.save()
        savedMsg = settings.hasKey ? "API Key 已写入钥匙串" : "Key 为空，已清空"
        showSaved = true
    }
}
