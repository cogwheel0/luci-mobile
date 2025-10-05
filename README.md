# LuCI Mobile

<div align="center">
  <a href="https://play.google.com/store/apps/details?id=com.cogwheel.LuCIMobile">
    <img src="store-badges/google.webp" alt="Get it on Google Play" style="height:56px;"/>
  </a>
  <a href="https://apps.apple.com/app/luci-mobile/id6749455847">
    <img src="store-badges/apple.webp" alt="Download on the App Store" style="height:56px;"/>
  </a>
  <a href="https://apt.izzysoft.de/fdroid/index/apk/com.cogwheel.LuCIMobile">
    <img src="store-badges/izzyondroid.webp" alt="Get it on IzzyOnDroid" style="height:56px;"/>
  </a>
  <br><br>

![Latest Release](https://shields.rbtlog.dev/simple/com.cogwheel.LuCIMobile)
![GitHub all downloads](https://img.shields.io/github/downloads/cogwheel0/luci-mobile/total?style=flat-square&label=Downloads&logo=github&color=0A84FF)

<img src="fastlane/metadata/android/en-US/images/phoneScreenshots/flutter_01.png" width="300"/>
</div>

<br>

**LuCI Mobile** is a modern Flutter app for managing and monitoring multiple OpenWrt/LuCI routers. It features a beautiful Material 3 UI, secure authentication, real-time stats, and seamless multi-router support.

---

## Features

- **Multiple Router Management:** Add, switch, and manage any number of OpenWrt routers. Each router’s data is kept separate and secure.
- **Secure Login:** HTTP/HTTPS support, self-signed certificate handling, and secure credential storage.
- **Dashboard Overview:** Real-time system stats, interface status, connected clients, and interactive charts.
- **Network Interface Management:** View and monitor all wired and wireless interfaces, bandwidth, IPs, and DNS.
- **Client Management:** See all connected devices, connection type, MAC/IP, vendor, DHCP lease, and more.
- **System Control:** Remote reboot, settings, and theme customization (light/dark mode).
- **Modern UI/UX:** Material Design 3, responsive layout, and intuitive navigation.
- **Open Source:** GPLv3 licensed and available on [Google Play](https://play.google.com/store/apps/details?id=com.cogwheel.LuCIMobile) and [IzzyOnDroid](https://apt.izzysoft.de/fdroid/index/apk/com.cogwheel.LuCIMobile).

---

## Multiple Router Functionality

- **Add Unlimited Routers:** Each with its own credentials and settings.
- **Quick Switch:** Instantly switch routers from the dashboard dropdown or "Manage Routers" screen.
- **Isolated Data:** Each router’s dashboard, clients, and settings are kept separate.
- **Edit & Remove:** Update credentials, rename, or remove routers at any time.
- **Auto-Connect:** Remembers your last selected router and auto-connects on launch.
- **Secure Storage:** All credentials are stored securely on your device.

---

## Screenshots

| Login | Dashboard | Clients | Interfaces |
|-------|-----------|---------|------------|
| <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/flutter_02.png" width="200"/> | <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/flutter_01.png" width="200"/> | <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/flutter_03.png" width="200"/> | <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/flutter_05.png" width="200"/> |

---

## Installation

**Get it on [Google Play](https://play.google.com/store/apps/details?id=com.cogwheel.LuCIMobile)**, **[Apple App Store](https://apps.apple.com/app/luci-mobile/id6749455847)**, or **[IzzyOnDroid](https://apt.izzysoft.de/fdroid/index/apk/com.cogwheel.LuCIMobile)**, or build from source:

```bash
git clone https://github.com/cogwheel0/luci-mobile.git
cd luci-mobile
flutter pub get
flutter run
```

- Requires Flutter 3.32.5+ and Dart 3.8+
- Android: `flutter build apk`  
- iOS: `flutter build ios`

---

## Project Structure

```
lib/
├── config/                 # App configuration
├── models/                 # Data models (client, interface, router)
├── screens/                # UI screens (dashboard, clients, interfaces, login, more, etc.)
├── services/               # Business logic (API, secure storage)
├── state/                  # State management (app_state.dart)
├── widgets/                # Reusable UI components (luci_app_bar.dart)
└── main.dart               # App entry point
```

---

## Development & Contribution

- Run in dev mode: `flutter run`
- Build for release: `flutter build apk --release` or `flutter build ios --release`
- Analyze code: `flutter analyze`

**Contributions welcome!** Please fork, branch, and submit a pull request.

---

## Security & Privacy
- All credentials are stored securely on-device
- HTTPS and self-signed certificate support
- No analytics or tracking

---

## Troubleshooting

- **Connection Failed:** Check router IP, LuCI web interface, firewall, and try both HTTP/HTTPS.
- **Authentication Failed:** Verify credentials and admin privileges.
- **No Data Displayed:** Ensure the router has LuCI RPC support: `opkg update && opkg install luci-mod-rpc rpcd-mod-luci rpcd-mod-iwinfo luci-mod-status`, restart `rpcd` (or reboot), then verify with `ubus list luci-rpc` and `ubus call luci-rpc getNetworkDevices '{}'`.

---

## License

GPL v3.0. See [LICENSE](LICENSE).

---

## Acknowledgments
- OpenWrt community for LuCI
- Flutter team
- [OpenWrtManager](https://github.com/hagaygo/OpenWrtManager) inspiration
- Contributors and testers

---

**Note:** This app requires an OpenWrt router with LuCI web interface enabled. Make sure your router is properly configured before use.
