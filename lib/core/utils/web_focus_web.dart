import 'dart:html' as html;

/// Odaklanmis DOM ogesinin (genelde Google Haritalar konteyneri) odagini
/// birakir ve odagi Flutter gorunumune tasir.
///
/// Boylece klavye olaylari (ok tuslari) haritaya degil Flutter'a gider —
/// slider hareket eder, harita SABIT kalir.
void releaseDomFocusFromMap() {
  // 1) Su an odakta olan ogeyi (harita olabilir) blur et
  final active = html.document.activeElement;
  if (active is html.HtmlElement) {
    active.blur();
  }

  // 2) Odagi Flutter'in kok gorunumune al
  final view = html.document.querySelector('flutter-view') ??
      html.document.querySelector('flt-glass-pane');
  if (view is html.HtmlElement) {
    // tabIndex atanmadan focus() bazi tarayicilarda calismaz
    view.tabIndex = -1;
    view.focus();
  }
}
