# ifmobile-fixer

在 iPhone 上修復日本 ifmobile 門號於台灣漫遊時「有訊號、無法撥號」的問題。App 名稱為 **ifmobile Helper**，搭配 LocalDevVPN 使用，提供套用修復、安裝描述檔與還原功能。

## 支援版本

- **iOS 27.1（24A94425）／iPhone19,4**，目前寫入功能限定此組合。
- 日本 ifmobile（Docomo，MCC/MNC `44010`）＋台灣門號。

只在我自己的這臺設備上測試過，僅供參考；已測過雙卡、台灣卡行動上網／VoLTE／Wi-Fi 通話，以及重開機後日本卡撥號。這是個人專案，與電信業者無關。

## 使用

1. 從 [Releases](https://github.com/iceorange-dev/ifmobile-fixer/releases/latest) 下載 IPA，用 LCSign 或自己的簽名工具安裝；開啟並連線 [LocalDevVPN](https://apps.apple.com/app/id6755608044)。
2. App →「配對」→「建立配對」，到「設定 → 隱私權與安全性 → 開發者模式」完成配對，再回 App 按「重新讀取」。已有配對檔也可以直接匯入。
3. 按「套用語音修復」，等候完成。操作時保持 App 前景與 VPN 連線，先結束通話。
4. 先把行動數據選為日本卡，保持 Wi-Fi、關閉日本卡數據漫遊；按「安裝描述檔」，再到「設定 → 已下載描述檔」安裝 **ifmobile 漫遊語音設定**。完成後可把行動數據改回台灣卡。

一般不必重開機。還原時按「還原原生設定」，並在「設定 → 一般 → VPN 與裝置管理」移除語音描述檔。若操作中斷，保留 App，使用「進階 → 復原中斷操作」；不要刪除 App 內的備份。

此描述檔針對台灣漫遊語音，不是日本當地上網 APN。赴日前可先還原；在日本使用行動數據時，依 ifmobile 提供的 APN 設定。

## 建置

需要 macOS、Xcode、[XcodeGen](https://github.com/yonaskolb/XcodeGen)、Rust 與 Python 3。本次使用 Xcode 27.0、Rust 1.99.1。

```sh
brew install xcodegen
rustup target add aarch64-apple-ios
./scripts/build.sh
```

未簽名 IPA 與 SHA-256 放在 `dist/`。App 的最低編譯目標為 iOS 18.0；實際修復範圍仍以上面的支援版本為準。

## 原理與來源

透過 AirTraffic 將這張日本 SIM 對應至系統內建的 `KDDI_BIGLOBE_LTE_only_jp` 電信包，再重新載入設定；不修改 Apple 電信包簽章。操作前保存原始目錄，寫入後逐項比對，備份與配對資料只留在裝置上。

基於 [AirCard-iOS](https://github.com/Mak5er/AirCard-iOS)、[AirLift](https://github.com/0xjohnnydev/airlift)、[CarrierSIM](https://github.com/ios-bundles/CarrierSIM) 與 [idevice](https://github.com/jkcoxson/idevice)。授權與修改說明見 [THIRD_PARTY.md](THIRD_PARTY.md)。
