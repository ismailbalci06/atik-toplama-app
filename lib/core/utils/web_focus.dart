/// DOM odagini haritadan alip Flutter gorunumune veren yardimci.
///
/// SORUN: Flutter Web'de Google Haritalar bir HTML ogesidir ve klavye
/// odagini (DOM focus) kendinde tutar. Bu durumda ok tuslari Flutter'a
/// HIC ulasmaz; dogrudan haritayi kaydirir. Flutter tarafindaki
/// `autofocus` bunu cozmez, cunku Flutter'in odak agaci ile tarayicinin
/// DOM odagi ayri seylerdir.
///
/// COZUM: Bir alt sayfa (bottom sheet) acildiginda odaklanmis DOM ogesini
/// blur edip odagi `flutter-view` uzerine almak. Boylece ok tuslari
/// Flutter'a (slider'a) gider, harita kaymaz.
///
/// Kosullu import: web'de gercek uygulama, diger platformlarda no-op.
export 'web_focus_stub.dart'
    if (dart.library.html) 'web_focus_web.dart';
