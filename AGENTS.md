## Learned User Preferences

- Always respond in Russian.
- Do not create `.md` files unless explicitly requested.
- Login should use phone + password (offline-capable), not OTP or WhatsApp-based auth.
- App must work fully offline — all core features should function without internet.

## Learned Workspace Facts

- Flutter/Dart project targeting Android tablets and iOS (internal cemetery manager app, not public-facing).
- Stack: Flutter, `yandex_maps_mapkit_lite: 4.29.0-beta` (official Yandex package with offline tile caching; replaces old `yandex_mapkit`), `geolocator` (GNSS), `sqflite` (local DB), `connectivity_plus`, `shared_preferences`, `flutter_svg` (^2.0.10+1), `easy_localization` (^3.0.8), `http` (^1.2.0).
- Offline-first architecture: local SQLite storage via `local_db_service.dart`, background sync via `sync_service.dart` when network is available.
- Key pages: `manager_login_page.dart`, `manager_home_page.dart`, `manager_map_page.dart`, `grave_detail_page.dart`, `manager_profile_page.dart` (three sections: Личные данные, Заявки на захоронение, Обращения в администрацию; SharedPreferences caching); `ProfileSection` enum is public — `ManagerProfilePage` accepts `initialSection` for deep-linking to a specific tab.
- Key services: `api_service.dart`, `auth_service.dart`, `auth_state_manager.dart`, `cemetery_service.dart`, `local_db_service.dart`, `sync_service.dart`, `location_service.dart`, `audit_service.dart`.
- Styles/constants are in `lib/constants.dart` (`AppColors`, `AppSizes`) — do not modify without reason.
- Phone number format: Kazakhstan (+7), mask pattern `+7 (___) ___-__-__`.
- App label in AndroidManifest: `Orynai Manager`; UI title shown as "Кабинет Менеджера"; permissions include `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `ACCESS_NETWORK_STATE`.
- Global AppBar theme in `main.dart` ThemeData: `scrolledUnderElevation: 0`, `surfaceTintColor: Colors.transparent` (prevents tint on scroll in Material 3).
- Grave statuses displayed on map: свободно, забронировано, захоронено, резерв; selection by tap on map OR by number search.
- `YandexMap` widget and `MapKit.initialize()` in `main.dart` are wrapped in `Platform.isAndroid` guards — map is Android-only; iOS shows a placeholder or is skipped.
- Android build requires Yandex Maven repo in `android/build.gradle.kts`; native dependency is `maps.mobile:4.29.0-lite`.
- `location_service.dart` uses `forceLocationManager: false` and `timeLimit: Duration(seconds: 30)` in `LocationSettings`.
- Reusable `OrynaiAppBar` widget in `lib/widgets/orynai_app_bar.dart` — used across manager_map, manager_profile, place_booking, grave_detail pages; header background `rgba(250,247,238,0.85)`, border-bottom `rgba(0,0,0,0.08)`.
- On HTTP 401 response, app redirects user to login page; `manager_home_page.dart` also fetches current user on load to verify auth state.
- `api_service.dart` `post()` accepts all 2xx codes (`>= 200 && < 300`), not just 200 — server returns 201 for `POST /api/v8/burial-requests`.
- `PlaceBookingPage`: IIN field (12 digits) triggers `GET /rip-fcb/v1/deceased?iin=...` to auto-fill deceased's name (field becomes read-only); optional dates toggle; "Создать заявку" in profile navigates to main screen (`popUntil isFirst`) instead of opening an inline form.
