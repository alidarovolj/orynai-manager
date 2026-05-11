package kz.orynai.app

import android.app.Application

class MainApplication: Application() {
  override fun onCreate() {
    super.onCreate()
    // Инициализация MapKit полностью делегирована Flutter-плагину (initMapkit).
    // yandex_maps_mapkit_lite 4.x использует Runtime/FFI API — вызовы
    // MapKitFactory.setApiKey/setLocale из старого SDK 3.x несовместимы
    // и мешают авторизации тайлов.
  }
}
