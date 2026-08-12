# 開發備忘

iOS 的工具鏈、模擬器與實機側載流程請見 [`docs/IOS_DEVELOPMENT.md`](docs/IOS_DEVELOPMENT.md)。

## 模擬器：用 `Pixel_9_std`，不要用 `Pixel_9`

- `Pixel_9`：用的是 Google 較新的「16k page size」實驗性系統映像，這台的 SurfaceView 同步機制有 bug，畫面會整個黑屏
- `Pixel_9_std`：另外建的標準 Android 15 (API 35) 映像，正常。

如果模擬器莫名其妙黑屏/當機，先檢查是不是又用到 `Pixel_9`。另外這台模擬器如果被強制關閉太多次，AVD 的 quick-boot 快照可能會壞掉（app 明明是 topResumedActivity、螢幕也是 Awake，畫面卻整個黑掉，logcat 也沒有 crash），這時候把 `~/.android/avd/Pixel_9_std.avd/*.qcow2` 刪掉重開機（等於強制 cold boot）通常能解決。這個狀況目前已經復發過不只一次，是這台模擬器最常見的故障模式，遇到黑屏優先懷疑這個。

```bash
adb emu kill
rm ~/.android/avd/Pixel_9_std.avd/*.qcow2
flutter emulators --launch Pixel_9_std   # 這次會強制 cold boot
```

## 常用指令

```bash
# 啟動模擬器
flutter emulators --launch Pixel_9_std

# 等開機完成
adb wait-for-device
adb shell getprop sys.boot_completed   # 要回傳 1

# 建置＋安裝＋跑起來（在專案目錄下）
flutter run -d <device-id> --debug
```

`<device-id>` 用 `flutter devices` 或 `adb devices -l` 查，通常長得像 `emulator-5554`。
