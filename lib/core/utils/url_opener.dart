/// Harici bir baglantiyi yeni sekmede acar.
///
/// Kosullu import: web'de gercek uygulama, diger platformlarda no-op.
/// url_launcher paketi EKLENMEDI — projede zaten bu desen var
/// (bkz. web_focus.dart) ve dondurma oncesi yeni bagimlilik riski
/// almak istemiyoruz.
export 'url_opener_stub.dart' if (dart.library.html) 'url_opener_web.dart';
