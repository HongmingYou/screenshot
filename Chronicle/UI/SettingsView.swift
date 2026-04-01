import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var isKeyVisible = false

    var body: some View {
        Form {
            Section {
                HStack {
                    if isKeyVisible {
                        TextField("sk-or-...", text: $settings.openRouterAPIKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("sk-or-...", text: $settings.openRouterAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        isKeyVisible.toggle()
                    } label: {
                        Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Text("在 openrouter.ai 获取 API Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("OpenRouter API Key")
            }

            Section {
                Picker("模型", selection: $settings.openRouterModel) {
                    ForEach(AppSettings.availableModels, id: \.id) { model in
                        Text(model.label).tag(model.id)
                    }
                    Divider()
                    if !AppSettings.availableModels.contains(where: { $0.id == settings.openRouterModel }) {
                        Text(settings.openRouterModel).tag(settings.openRouterModel)
                    }
                }

                TextField("或输入自定义 Model ID", text: $settings.openRouterModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("AI 模型")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 280)
    }
}
