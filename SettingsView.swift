import SwiftUI
import SwiftData


struct AppAccent: Identifiable {
    let id: String
    let name: String
    let color: Color
}

enum AppTheme {
    static let palette: [AppAccent] = [
        AppAccent(id: "green", name: "Зелёный", color: .green),
        AppAccent(id: "blue", name: "Синий", color: .blue),
        AppAccent(id: "pink", name: "Розовый", color: .pink),
        AppAccent(id: "purple", name: "Фиолетовый", color: .purple),
        AppAccent(id: "orange", name: "Оранжевый", color: .orange),
        AppAccent(id: "red", name: "Красный", color: .red),
        AppAccent(id: "teal", name: "Бирюзовый", color: .teal),
        AppAccent(id: "indigo", name: "Индиго", color: .indigo)
    ]

    static func color(_ key: String) -> Color {
        palette.first { $0.id == key }?.color ?? .green
    }
}

struct AppBackground: View {
    var grouped = true
    @AppStorage("bgStyle") private var bgStyle = "system"
    @AppStorage("accentColor") private var accentKey = "green"

    var body: some View {
        ZStack {
            switch bgStyle {
            case "gradient":
                LinearGradient(
                    colors: [AppTheme.color(accentKey).opacity(0.40), Color(.systemBackground)],
                    startPoint: .top, endPoint: .bottom
                )
            case "tinted":
                Color(.systemBackground).overlay(AppTheme.color(accentKey).opacity(0.12))
            case "amoled":
                Color.black
            default:
                grouped ? Color(.systemGroupedBackground) : Color(.systemBackground)
            }
        }
        .ignoresSafeArea()
    }
}

struct AppBackgroundModifier: ViewModifier {
    @AppStorage("bgStyle") private var bgStyle = "system"

    func body(content: Content) -> some View {
        if bgStyle == "system" {
            content
        } else {
            content
                .scrollContentBackground(.hidden)
                .background(AppBackground())
        }
    }
}


struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var tracks: [Track]

    @AppStorage("accentColor") private var accentKey = "green"
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("bgStyle") private var bgStyle = "system"
    @AppStorage("autoDownload") private var autoDownload = true

    @State private var confirmClear = false
    private let downloads = DownloadService.shared

    private var downloaded: [Track] {
        tracks.filter { $0.hasRemoteSource && $0.isDownloaded }
    }

    private var downloadedSize: String {
        let bytes = downloaded.reduce(Int64(0)) { $0 + FileStore.size(of: $1.fileName) }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var isBusy: Bool { !downloads.active.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Оформление") {
                    Picker("Тема", selection: $appearance) {
                        Text("Как в системе").tag("system")
                        Text("Светлая").tag("light")
                        Text("Тёмная").tag("dark")
                    }
                    Picker("Фон", selection: $bgStyle) {
                        Text("Обычный").tag("system")
                        Text("Градиент цвета").tag("gradient")
                        Text("Лёгкий оттенок").tag("tinted")
                        Text("Чёрный (AMOLED)").tag("amoled")
                    }
                }

                Section("Цвет акцента") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                        ForEach(AppTheme.palette) { item in
                            Circle()
                                .fill(item.color)
                                .frame(width: 38, height: 38)
                                .overlay {
                                    if accentKey == item.id {
                                        Image(systemName: "checkmark")
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { accentKey = item.id }
                                .accessibilityLabel(item.name)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    Toggle("Скачивать при сохранении", isOn: $autoDownload)

                    LabeledContent("Скачано", value: "\(downloaded.count) · \(downloadedSize)")

                    Button {
                        Task { await downloads.downloadAll(tracks) }
                    } label: {
                        HStack {
                            Text("Скачать всю медиатеку")
                            if isBusy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isBusy)

                    Button("Удалить загрузки", role: .destructive) { confirmClear = true }
                        .disabled(downloaded.isEmpty)
                } header: {
                    Text("Офлайн")
                } footer: {
                    Text("Скачанные треки играют без интернета и сразу, без ожидания.")
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .confirmationDialog("Удалить скачанные треки?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    for track in downloaded { downloads.removeDownload(track) }
                }
            } message: {
                Text("Треки останутся в медиатеке, но без интернета играть не будут.")
            }
        }
    }
}
