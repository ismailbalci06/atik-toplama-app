import 'dart:html' as html;

/// Baglantiyi YENI SEKMEDE acar.
///
/// `noopener` guvenlik icin sart: acilan sayfa `window.opener` uzerinden
/// bizim sekmemizi yonlendiremesin (tabnabbing).
void openExternalUrl(String url) {
  html.window.open(url, '_blank', 'noopener,noreferrer');
}
