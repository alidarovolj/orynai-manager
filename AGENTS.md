## Learned User Preferences

- Always respond in Russian.
- Do not create `.md` files unless explicitly requested.
- Login should use phone + password (offline-capable), not OTP or WhatsApp-based auth.
- App must work fully offline — all core features should function without internet.

## Learned Workspace Facts

- Flutter/Dart project targeting Android tablets (internal cemetery manager app, not public-facing).
- Stack: Flutter, Yandex MapKit (`yandex_mapkit`), `geolocator` (GNSS), `sqflite` (local DB), `connectivity_plus`, `shared_preferences`.
- Offline-first architecture: local SQLite storage via `local_db_service.dart`, background sync via `sync_service.dart` when network is available.
- Key pages: `manager_login_page.dart`, `manager_home_page.dart`, `manager_map_page.dart`, `grave_detail_page.dart`.
- Key services: `api_service.dart`, `auth_service.dart`, `auth_state_manager.dart`, `cemetery_service.dart`, `local_db_service.dart`, `sync_service.dart`, `location_service.dart`.
- Styles/constants are in `lib/constants.dart` (`AppColors`, `AppSizes`) — do not modify without reason.
- Phone number format: Kazakhstan (+7), mask pattern `+7 (___) ___-__-__`.
- App label in AndroidManifest: `Orynai Manager`; permissions include `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `ACCESS_NETWORK_STATE`.
- Grave statuses displayed on map: свободно, забронировано, захоронено, резерв.
- `audit_service.dart` is a new untracked file in the workspace.
