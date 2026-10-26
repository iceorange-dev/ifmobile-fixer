# Third-party code and resources

The project's own code is MIT licensed. Third-party code retains its original license; see `licenses/` and `licenses/Rust-dependencies.txt`. These notices are also bundled in the app.

| Component | Source | License / use |
| --- | --- | --- |
| AirCard-iOS | [Mak5er/AirCard-iOS](https://github.com/Mak5er/AirCard-iOS), base commit `40640c4d827aeab8d798285b57d24fcf6be070d0` | MIT; pairing UI, Grappa bridge, Rust tunnel and AirTraffic support |
| AirLift | [0xjohnnydev/airlift](https://github.com/0xjohnnydev/airlift) | MIT; underlying file-transfer technique |
| CarrierSIM | [ios-bundles/CarrierSIM](https://github.com/ios-bundles/CarrierSIM) | MIT; export / backup / place / readback transaction design |
| idevice / idevice-ffi | [jkcoxson/idevice](https://github.com/jkcoxson/idevice/tree/7bd551c16c6dd2e058740d85a2d9399a51a776e9) | MIT; device service and pairing protocols |

`rust-core/vendor/idevice` and `idevice-ffi` preserve the AirCard dependency snapshot, including its OPACK back-reference and on-device pairing adaptations. The AFC parser also accepts `LinkTarget` alongside `st_link_target`, as required by the target iOS build. The dependency versions are fixed by `Cargo.lock`.

The ifmobile-specific UI, profile download server, scoped SIM mapping, transactional backup checks, recovery, local ownership receipts and dedicated worker stack are maintained in this project. Existing App backups can establish ownership during an upgrade; no developer device or SIM identifiers are embedded in the source or IPA.

`Resources/AVEA_tr.ipcc` is an unmodified Apple-signed carrier package obtained from CarrierSIM's `assets.zip`. It is used only to request a carrier rescan; its SHA-256 is pinned in `rust-core/trigger.sha256`. Apple files are **not covered by this project's MIT license** and remain the property of their respective rights holders. The KDDI bundle itself is not redistributed: the app uses the copy already on iOS.

The mobileconfig's internal `com.iceorange.ifmobile.test-i` identifier is retained for replacement compatibility with earlier personal builds. Its displayed name is **ifmobile 漫遊語音設定**.
