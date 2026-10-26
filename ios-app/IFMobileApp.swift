import SwiftUI
import UniformTypeIdentifiers
import AirliftFFI

@main struct IFMobileApp: App {
    @StateObject private var model = CarrierModel()
    init() { _ = ALGetGrappaToken(0, 0, 0, nil, 0, nil, nil, 0) }
    var body: some Scene { WindowGroup { MainView().environmentObject(model) } }
}
@_silgen_name("ALGetGrappaToken")
func ALGetGrappaToken(_ version: UInt32, _ device: UInt32, _ protocolVersion: UInt32, _ buffer: UnsafeMutablePointer<UInt8>?, _ max: Int, _ size: UnsafeMutablePointer<Int>?, _ error: UnsafeMutablePointer<CChar>?, _ length: Int) -> Int32

struct CarrierRow: Decodable, Identifiable {
    var slot: String; var mcc: String; var mnc: String; var bundle: String; var version: String
    var id: String { slot }
    var title: String { mcc == "440" ? "日本 ifmobile" : mcc == "466" ? "台灣門號" : "門號 \(slot)" }
    var detail: String { bundle.replacingOccurrences(of: "com.apple.", with: "") + " · " + version }
}
struct CarrierReport: Decodable { var model: String; var ios: String; var build: String; var carriers: [CarrierRow]; var operation: String? }
@MainActor final class CarrierModel: ObservableObject {
    @Published var busy = false
    @Published var progress = "準備就緒"
    @Published var report: CarrierReport?
    @Published var checked: Date?
    @Published var error: String?
    @Published var logs: [String] = []
    @Published var paired = false
    @Published var importing = false
    @Published var showLogs = false
    @Published var action: String?
    let profileServer = ProfileServer()
    let fm = FileManager.default
    var dataRoot: URL {
        var root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CarrierBackups", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues(); values.isExcludedFromBackup = true; try? root.setResourceValues(values)
        return root
    }
    init() { refresh() }
    func refresh() {
        // USB provisioning is consumed into private Application Support on launch.
        let source = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("import_pairing.plist")
        if fm.fileExists(atPath: source.path) {
            _ = PairingController.syncCanonicalPairingFile(from: source.path)
            try? fm.removeItem(at: source)
        }
        paired = fm.fileExists(atPath: PairingController.pairingFilePath())
    }
    func importPair(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), !data.isEmpty, data.count < 1_000_000,
              (try? PropertyListSerialization.propertyList(from: data, format: nil)) != nil else { error = "無法讀取有效的配對檔"; return }
        _ = PairingController.syncCanonicalPairingFile(from: url.path); refresh()
    }
    func append(_ raw: String) {
        let line = raw.replacingOccurrences(of: #"\b\d{11,20}\b"#, with: "[識別碼]", options: .regularExpression)
        logs.append(line); if logs.count > 150 { logs.removeFirst(logs.count - 150) }
        let file = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("latest-operation.txt")
        try? logs.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        if !line.hasPrefix("airlift:") { progress = line }
    }
    func run(_ operation: String) {
        guard !busy else { return }; refresh()
        guard paired else { error = "請先完成配對或匯入配對檔"; return }
        busy = true; logs = []; progress = operation == "inspect" ? "正在讀取手機與雙卡設定…" : "正在準備備份與連線…"
        UIApplication.shared.isIdleTimerDisabled = true
        let pair = PairingController.pairingFilePath(); let root = dataRoot.path
        let trigger = Bundle.main.url(forResource: "AVEA_tr", withExtension: "ipcc")!.path
        let context = Unmanaged.passRetained(self).toOpaque()
        DispatchQueue.global(qos: .userInitiated).async {
            var output: UnsafeMutablePointer<CChar>?; var failure: UnsafeMutablePointer<CChar>?
            let result = pair.withCString { p in root.withCString { r in trigger.withCString { t in operation.withCString { a in
                im_carrier_run(p, r, t, a, { ctx, message in
                    guard let ctx, let message else { return }
                    let target = Unmanaged<CarrierModel>.fromOpaque(ctx).takeUnretainedValue()
                    let line = String(cString: message)
                    DispatchQueue.main.async { target.append(line) }
                }, context, &output, &failure)
            }}}}
            let json = output.map { String(cString: $0) }; let problem = failure.map { String(cString: $0) }
            if let output { al_string_free(output) }; if let failure { al_string_free(failure) }
            DispatchQueue.main.async {
                Unmanaged<CarrierModel>.fromOpaque(context).release()
                self.busy = false; UIApplication.shared.isIdleTimerDisabled = false
                if result == 0, let json, let data = json.data(using: .utf8), let value = try? JSONDecoder().decode(CarrierReport.self, from: data) {
                    self.report = value; self.checked = Date()
                    self.progress = operation == "inspect" ? "讀取完成" : operation == "recover" ? "中斷操作已復原" : "寫入、比對與重新載入完成"
                    let docs = self.fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    try? data.write(to: docs.appendingPathComponent("latest-status.json"), options: .atomic)
                } else { self.error = problem ?? "未取得有效結果，請查看紀錄"; self.progress = "操作未完成；備份已保留" }
                let docs = self.fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                try? self.logs.joined(separator: "\n").write(to: docs.appendingPathComponent("latest-operation.txt"), atomically: true, encoding: .utf8)
            }
        }
    }
    func installProfile() {
        guard !busy else { return }
        profileServer.start { [weak self] result in
            switch result { case .success(let url): UIApplication.shared.open(url)
            case .failure(let e): self?.error = e.localizedDescription }
        }
    }
}

struct MainView: View {
    @EnvironmentObject var model: CarrierModel
    @ObservedObject var pairing = PairingController.shared
    @Environment(\.scenePhase) var phase
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "simcard.2.fill").font(.largeTitle).foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ifmobile").font(.title.bold())
                            Text(model.progress).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 10)
                    if model.busy { ProgressView() }
                }
                Section("雙卡設定") {
                    if let report = model.report {
                        ForEach(report.carriers) { row in
                            HStack {
                                Text(row.title)
                                Spacer()
                                Text(row.bundle.contains("KDDI_BIGLOBE") ? "修復設定" : "原生設定")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else { Text("尚未讀取").foregroundStyle(.secondary) }
                    Button { model.run("inspect") } label: { Label("重新讀取", systemImage: "arrow.clockwise") }.disabled(model.busy)
                }
                Section("修復") {
                    Button { model.action = "apply" } label: { Label("套用語音修復", systemImage: "wrench.and.screwdriver") }.disabled(model.busy || !model.paired)
                    Button { model.installProfile() } label: { Label("安裝描述檔", systemImage: "arrow.down.doc") }.disabled(model.busy)
                    Button { model.action = "restore" } label: { Label("還原原生設定", systemImage: "arrow.uturn.backward") }.disabled(model.busy || !model.paired)
                }
                Section {
                    DisclosureGroup("配對") {
                        Label(model.paired ? "已配對" : "尚未配對", systemImage: model.paired ? "checkmark.shield" : "link")
                        Button("匯入配對檔") { model.importing = true }.disabled(model.busy || pairing.running)
                        Button(pairing.running ? "配對中…" : "建立配對") { pairing.start() }.disabled(model.busy || pairing.running)
                        if pairing.running {
                            Text(pairing.pairingStatus)
                            if let pin = pairing.pairingPIN { Text(pin).font(.largeTitle.monospaced().bold()) }
                            Text("到設定的開發者模式選擇與 ifmobile Helper 配對。")
                        }
                    }
                    DisclosureGroup("進階") {
                        Button("操作紀錄") { model.showLogs = true }
                        Button("復原中斷操作") { model.action = "recover" }.disabled(model.busy || !model.paired)
                    }
                }
            }
            .navigationTitle("ifmobile").navigationBarTitleDisplayMode(.inline)
            .onChange(of: phase) { _, phase in if phase == .active { model.refresh() } }
            .fileImporter(isPresented: $model.importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { r in if case .success(let urls) = r, let u = urls.first { model.importPair(u) } }
            .alert("操作結果", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(model.error ?? "") }
            .confirmationDialog(model.action == "restore" ? "還原日本卡" : model.action == "recover" ? "復原中斷操作" : "套用日本卡修復", isPresented: Binding(get: { model.action != nil }, set: { if !$0 { model.action = nil } }), titleVisibility: .visible) {
                let action = model.action ?? "inspect"
                Button("開始") { model.run(action); model.action = nil }
                Button("取消", role: .cancel) { model.action = nil }
            } message: { Text("請結束通話、保持 VPN 連線與 App 開啟。行動服務可能短暫中斷。") }
            .sheet(isPresented: $model.showLogs) { NavigationStack { ScrollView { Text(model.logs.joined(separator: "\n")).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }.navigationTitle("操作紀錄").toolbar { Button("完成") { model.showLogs = false } } } }
        }.tint(.blue)
    }
}
