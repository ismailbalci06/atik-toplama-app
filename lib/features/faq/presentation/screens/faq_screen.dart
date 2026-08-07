import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';

/// SIKCA SORULAN SORULAR.
///
/// TAMAMEN DURUMSUZ (stateless) ve BAGIMSIZ: hicbir provider dinlemez,
/// Firestore'a dokunmaz, hicbir mevcut widget'i degistirmez. Metin
/// disinda calisan bir parcasi yoktur — bu yuzden kod dondurma
/// doneminde eklenmesi guvenlidir.
///
/// ONEMLI — ICERIK ILKESI:
/// Bu sayfa juriye karsi bir taahhut metnidir. Buradaki her cumle
/// SISTEMDE GERCEKTEN OLAN bir davranisi anlatir. Projenin bastan beri
/// surdugu ilke burada da gecerli: yapilan ile planlanan karistirilmaz.
/// Bir cevabi degistirecek olan, once kodun oyle davrandigindan emin
/// olmalidir.
class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Sıkça Sorulan Sorular')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          Text(
            'ATOS nasıl çalışıyor?',
            style: text.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Güvenlik, gizlilik ve puan ekonomisi hakkındaki soruların '
            'yanıtları. Buradaki her madde sistemin gerçek davranışını '
            'anlatır.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 20),
          ..._sections.map((s) => _FaqSectionView(section: s)),
        ],
      ),
    );
  }
}

// =====================================================================
// ICERIK
// =====================================================================

class _FaqEntry {
  const _FaqEntry(this.question, this.answer);
  final String question;
  final String answer;
}

class _FaqCategory {
  const _FaqCategory(this.title, this.emoji, this.entries);
  final String title;
  final String emoji;
  final List<_FaqEntry> entries;
}

const _sections = <_FaqCategory>[
  // -------------------------------------------------------------------
  _FaqCategory('Genel Kullanım ve İşleyiş', '📱', [
    _FaqEntry(
      'ATOS nedir ve kimler içindir?',
      'ATOS; site yönetimleri, kafeler ve marketler gibi düzenli atık '
          'üreten işletmeler ile doğrulanmış saha görevlilerini tek '
          'platformda buluşturan, "boş kilometreyi" sıfırlamayı hedefleyen '
          'bir toplama sistemidir. Tersine lojistikte sefer maliyeti '
          'sabittir; değişen tek şey duraktan alınan kilodur.',
    ),
    _FaqEntry(
      'Uygulamayı kullanmak ücretli mi?',
      'Hayır. İşletmelerin atıklarını ekonomiye ve doğaya kazandırması '
          'için altyapı ücretsiz sunulur.',
    ),
    _FaqEntry(
      'Nasıl atık toplama talebi oluşturabilirim?',
      'Ana sayfadaki "Talep Oluştur" butonuna dokunun, atık türünü ve '
          'tahmini kiloyu seçin. Konumunuz cihazınızın konum servisinden '
          'alınır; dilerseniz not alanına kat ve kapı detayı ekleyebilirsiniz.',
    ),
    _FaqEntry(
      'Hangi tür atıkları sisteme verebilirim?',
      'Şu an altı tür desteklenir: Kâğıt, Plastik, Cam, Metal, Pil ve '
          'Elektronik. Bir talepte birden fazla tür seçebilirsiniz. '
          'Tekstil, atık yağ ve inşaat molozu gibi türler henüz kapsam '
          'dışıdır; bunlar farklı taşıma ve mevzuat şartları gerektirdiği '
          'için sonraki fazda planlanmaktadır.',
    ),
    _FaqEntry(
      'Takvim (Düzenli Toplama) özelliği nasıl çalışır?',
      'Deponuzun dolma ritmine göre bir plan tanımlarsınız (örneğin "her '
          'ayın 3\'ü"). İki şekilde hatırlatılır: (1) gün yaklaştığında '
          'uygulamanın ana sayfasında bir hatırlatma şeridi çıkar; '
          '(2) plan kartındaki "Takvime ekle" butonuna bir kez '
          'dokunduğunuzda, kendi takviminize aylık tekrar eden bir '
          'etkinlik eklenir ve bildirimi kendi takviminiz verir.',
    ),
  ]),

  // -------------------------------------------------------------------
  _FaqCategory('Roller, Yetkilendirme ve Güvenlik', '🛡️', [
    _FaqEntry(
      'Kayıt olurken "Toplayıcı" seçersem hemen atık toplayabilir miyim?',
      'Hayır. Uygulamadaki rol seçimi yalnızca bir arayüz tercihidir. '
          'Gerçek yetki veritabanı güvenlik kurallarında tanımlıdır ve o '
          'listeye uygulama üzerinden yazılamaz. Yönetici tarafından '
          'onaylanmamış hiçbir hesap iş üstlenemez. Bu davranışı 61 '
          'otomatik güvenlik kuralı testiyle sürekli doğruluyoruz.',
    ),
    _FaqEntry(
      'Onaysız bir hesap haritada atık adreslerini görebilir mi?',
      'Göremez. Onaysız bir hesap haritada yalnızca yaklaşık 500 metre '
          'yarıçapında bir bölge çemberi görür. Tam koordinat ve açık '
          'adres, işi üstlenen doğrulanmış görevliye açılır. Bu bir arayüz '
          'gizlemesi değildir: veri sunucudan hiç gönderilmez.',
    ),
    _FaqEntry(
      'Toplayıcı hesabımı nasıl doğrulatabilirim?',
      'Doğrulamalar şu an kapalı devre yürütülmektedir; yetkili tesis '
          'veya belediye yöneticisi tarafından elle tanımlanır. '
          'Uygulama içi başvuru ve onay akışı sonraki fazda planlanmıştır.',
    ),
    _FaqEntry(
      'Saha görevlisinin yanındaki ⭐ ve rozet ne anlama geliyor?',
      'Teslimat sonrasında işletme, görevliyi 1-5 yıldız arasında '
          'değerlendirir. En az 5 değerlendirme almış ve ortalaması 4,5 '
          'üzerinde olan görevliler "Güvenilir görevli" rozeti kazanır. '
          'Tek bir yüksek puan rozet için yeterli değildir.',
    ),
  ]),

  // -------------------------------------------------------------------
  _FaqCategory('Gizlilik ve Kişisel Veri', '🔒', [
    _FaqEntry(
      'Açık adresim ve notlarım herkes tarafından görülüyor mu?',
      'Hayır. Tam koordinatınız ve notunuz, herkesin okuyabildiği talep '
          'kaydında tutulmaz; ayrı ve korumalı bir kayıtta durur. Bu '
          'kaydı yalnızca iki taraf okuyabilir: talebi oluşturan siz ve '
          'talebi üstlenmiş olan doğrulanmış görevli.',
    ),
    _FaqEntry(
      'Görevli işi aldıktan sonra talebimi iptal edebilir miyim?',
      'Talep "bekliyor" durumundayken dilediğiniz an iptal edebilirsiniz. '
          'Bir görevli talebi üstlendiği anda iptal butonu kalkar. Bunun '
          'sebebi, yola çıkmış bir görevlinin boşuna yol ve yakıt '
          'harcamasını önlemektir. Bu kural yalnızca arayüzde değil, '
          'veritabanı kuralında da uygulanır.',
    ),
    _FaqEntry(
      'Verilerim nerede tutuluyor, güvende mi?',
      'Veriler Google Cloud altyapısındaki Firestore veritabanında '
          'tutulur; aktarım sırasında TLS ile, sunucuda ise disk '
          'seviyesinde şifrelenir. Buna ek olarak her koleksiyon için '
          'kimin neyi okuyup yazabileceğini belirleyen katı erişim '
          'kuralları tanımlıdır: kimlik doğrulaması olmayan bir istek '
          'hiçbir veriye erişemez. Uçtan uca (yalnızca cihazlarda '
          'çözülebilen) şifreleme kullanılmamaktadır.',
    ),
  ]),

  // -------------------------------------------------------------------
  _FaqCategory('Puanlama ve Karbon Tasarrufu', '🌱', [
    _FaqEntry(
      'Yeşil Puan neye göre hesaplanıyor?',
      'Puan rastgele bir katsayı değildir: kurtarılan atığın türüne göre '
          'önlenen karbon salımından (kg CO₂) türetilir. Aynı hesap hem '
          'puanınızı hem "Önlenen CO₂" göstergenizi besler; iki ayrı '
          'formül yoktur.',
    ),
    _FaqEntry(
      'Kiloyu yüksek girersem daha çok puan kazanır mıyım?',
      'Hayır. Sizin girdiğiniz miktar yalnızca bir beyandır ve puan '
          'üretmez. Puan, sahadaki görevli teslim aldığı gerçek miktarı '
          'onayladığında doğar. Beyan alanı, veritabanı kuralı gereği '
          'sonradan değiştirilemez.',
    ),
    _FaqEntry(
      'Neden metal atık, camdan daha fazla puan veriyor?',
      'Çünkü kilogram başına önlenen karbon salımı metalde camdan '
          'yaklaşık 13 kat fazladır (4,0 kg CO₂ / 0,3 kg CO₂). '
          'Katsayılar yaygın kabul gören ortalama geri kazanım '
          'verilerinden alınmıştır ve tüm hesaplarda tek bir tablodan '
          'kullanılır.',
    ),
    _FaqEntry(
      'Kendi karbon tasarrufumu görebilir miyim?',
      'Evet. Ana sayfadaki "Tesisinizin Çevresel Etkisi" paneli yalnızca '
          'sizin tamamlanmış teslimatlarınızdan hesaplanır. Rol seçim '
          'ekranındaki pano ise sistem genelini gösterir; iki rakamın '
          'farklı olması normaldir ve her panelde kapsamı yazar.',
    ),
  ]),

  // -------------------------------------------------------------------
  _FaqCategory('Ödül Sistemi ve Yönetim', '🎁', [
    _FaqEntry(
      'Kazandığım puanları nerede kullanabilirim?',
      'Puanlarınızı "Ödüller" sekmesindeki katalogdan seçtiğiniz '
          'ödüllere dönüştürebilirsiniz. Katalog, işletme ortaklıkları '
          'geliştikçe güncellenir; güncel içerik her zaman uygulamadaki '
          'listede görünür.',
    ),
    _FaqEntry(
      'Ödül taleplerim anında onaylanıyor mu?',
      'Hayır. Talebiniz önce operatör onayına düşer ve bu sürede puanınız '
          'bakiyenizden ayrılmış sayılır; böylece aynı puanı iki ödüle '
          'birden harcayamazsınız. Talebiniz reddedilirse puan bakiyenize '
          'geri döner.',
    ),
    _FaqEntry(
      'Operatör benim puanımı değiştirebilir mi?',
      'Hayır. Puan bakiyesi hiçbir yerde saklanmaz; her seferinde '
          'teslimat geçmişinizden yeniden hesaplanır. Veritabanında '
          'yazılabilir bir puan alanı olmadığı için şişirilebilecek bir '
          'alan da yoktur. Operatör yalnızca "onaylandı" veya '
          '"reddedildi" kararını yazabilir.',
    ),
  ]),

  // -------------------------------------------------------------------
  _FaqCategory('Teknik Altyapı', '⚙️', [
    _FaqEntry(
      'Uygulama kapalıyken takvim hatırlatması alır mıyım?',
      'Plan kartındaki "Takvime ekle" adımını bir kez uyguladıysanız '
          'evet: etkinlik kendi takviminize yazıldığı için bildirimi '
          'takvim uygulamanız verir ve ATOS kapalı olsa da çalışır. Bu '
          'adımı uygulamadıysanız hatırlatma yalnızca uygulama içinde, '
          'gün yaklaştığında ana sayfada görünür. ATOS\'un kendi anlık '
          'bildirim kanalı sonraki fazda planlanmıştır.',
    ),
    _FaqEntry(
      'Haritadaki aracın hareketi gerçek mi?',
      'Görevlinin konumu gerçekten kendi cihazından alınır ve canlı '
          'olarak takip ekranınıza akar. Aracın harita üzerindeki '
          'ilerleyişi ise zaman-sıkıştırmalı bir simülasyondur; bu ayrım '
          'takip ekranında da yazılıdır.',
    ),
  ]),
];

// =====================================================================
// GORUNUM
// =====================================================================

/// Bir kategori: baslik + akordeon kart
class _FaqSectionView extends StatelessWidget {
  const _FaqSectionView({required this.section});

  final _FaqCategory section;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                Text(section.emoji, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(section.title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              border: Border.all(color: AppColors.border),
              boxShadow: AppColors.softShadow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              child: Column(
                children: [
                  for (var i = 0; i < section.entries.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _FaqTile(entry: section.entries[i]),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tek soru — akordeon
class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.entry});

  final _FaqEntry entry;

  @override
  Widget build(BuildContext context) {
    return Theme(
      // ExpansionTile varsayilan olarak acilirken kenarlik cizer;
      // kart zaten kenarlikli oldugu icin onu kaldiriyoruz.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        iconColor: AppColors.primary,
        collapsedIconColor: AppColors.textSecondary,
        title: Text(
          entry.question,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        children: [
          Text(
            entry.answer,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.55,
                ),
          ),
        ],
      ),
    );
  }
}
