/**
 * ATOS — Firestore GUVENLIK KURALLARI birim testleri.
 *
 * Neden var: Flutter tarafindaki 38 test arayuzu koruyor ama tek bir kural
 * satirini bile sinamiyor. Oysa gizlilik ve puan sahtelenemezligi
 * iddialarimizin TAMAMI kurallarda yasiyor. Bu dosya o iddialari olcuye
 * cevirir.
 *
 * Calistirma:
 *   npm test          -> guncel firestore.rules ile
 *   npm run test:before -> P0 duzeltmesi ONCESI kurallarla (zafiyet kaniti)
 *
 * Emulator kullanilir; gercek projeye hicbir sey yazilmaz.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

const RULES_PATH = process.env.RULES_FILE
  ? resolve(process.env.RULES_FILE)
  : resolve(import.meta.dirname, '..', 'firestore.rules');

// --- Aktorler ---
const OWNER = 'isletme-a'; // Talebi olusturan atik ureten
const COLLECTOR = 'toplayici-1'; // Talebi ustlenen toplayici
const STRANGER = 'yabanci-x'; // Sisteme kayitli ama ilgisiz kullanici
const OPERATOR = 'operator-1'; // admins/{uid} kaydi olan yonetici

const REQ_PENDING = 'talep-bekleyen';
const REQ_ASSIGNED = 'talep-atanmis';

let testEnv;

/** Kurallari BYPASS ederek baslangic verisini yazar (test kurulumu). */
async function seed() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    // Operator yetkisi
    await setDoc(doc(db, 'admins', OPERATOR), { name: 'ATOS Operator' });

    // DOGRULANMIS toplayici (beyaz liste). STRANGER bilincli olarak
    // burada YOK: dogrulanmamis hesabi temsil ediyor.
    await setDoc(doc(db, 'collectors', COLLECTOR), {
      name: 'Toplayici Bir',
      approvedBy: OPERATOR,
    });

    // Bekleyen talep (henuz toplayici yok)
    await setDoc(doc(db, 'waste_requests', REQ_PENDING), {
      userId: OWNER,
      wasteTypes: ['kagit'],
      estimatedKg: 100,
      approxLocation: { latitude: 39.6, longitude: 32.1 },
      status: 'bekliyor',
    });
    await setDoc(
      doc(db, 'waste_requests', REQ_PENDING, 'private', 'detail'),
      {
        ownerId: OWNER,
        exactLocation: { latitude: 39.601234, longitude: 32.104321 },
        note: '3. kat, kapiciya birakilacak',
      },
    );

    // Toplayiciya ATANMIS talep
    await setDoc(doc(db, 'waste_requests', REQ_ASSIGNED), {
      userId: OWNER,
      wasteTypes: ['metal'],
      estimatedKg: 60,
      approxLocation: { latitude: 39.6, longitude: 32.1 },
      status: 'yolda',
      collectorId: COLLECTOR,
      collectorName: 'Toplayici Bir',
    });
    await setDoc(
      doc(db, 'waste_requests', REQ_ASSIGNED, 'private', 'detail'),
      {
        ownerId: OWNER,
        exactLocation: { latitude: 39.602, longitude: 32.105 },
        note: 'Arka kapidan',
      },
    );

    // Odul katalogu + bekleyen odul talebi
    await setDoc(doc(db, 'rewards', 'odul-1'), {
      title: 'Fidan Sertifikasi',
      costPoints: 500,
      isActive: true,
    });
    await setDoc(doc(db, 'redemptions', 'talep-odul-1'), {
      userId: OWNER,
      rewardId: 'odul-1',
      rewardTitle: 'Fidan Sertifikasi',
      costPoints: 500,
      status: 'beklemede',
    });
  });
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'atos-rules-test',
    firestore: { rules: readFileSync(RULES_PATH, 'utf8') },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await seed();
});

// Yardimcilar
const asOwner = () => testEnv.authenticatedContext(OWNER).firestore();
const asCollector = () => testEnv.authenticatedContext(COLLECTOR).firestore();
const asStranger = () => testEnv.authenticatedContext(STRANGER).firestore();
const asOperator = () => testEnv.authenticatedContext(OPERATOR).firestore();
const asAnon = () => testEnv.unauthenticatedContext().firestore();

// =====================================================================
describe('1) Anonim erisim tamamen kapali', () => {
  test('anonim talepleri okuyamaz', async () => {
    await assertFails(getDocs(collection(asAnon(), 'waste_requests')));
  });

  test('anonim odul katalogunu okuyamaz', async () => {
    await assertFails(getDocs(collection(asAnon(), 'rewards')));
  });

  test('anonim talep olusturamaz', async () => {
    await assertFails(
      setDoc(doc(asAnon(), 'waste_requests', 'yeni'), {
        userId: OWNER,
        wasteTypes: ['kagit'],
        estimatedKg: 10,
        approxLocation: { latitude: 39.6, longitude: 32.1 },
        status: 'bekliyor',
      }),
    );
  });
});

// =====================================================================
describe('2) P0 — kimlik denetimi (yetki calma)', () => {
  test('ustlenirken BASKASININ UID ini toplayici yazamaz', async () => {
    // Kritik: yabanci, isi COLLECTOR adina ustlenip sonra kendi
    // yetkisiyle adrese ulasmayi deneyemez.
    await assertFails(
      updateDoc(doc(asStranger(), 'waste_requests', REQ_PENDING), {
        status: 'atandi',
        collectorId: COLLECTOR,
      }),
    );
  });

  test('YABANCI, talebi tamamlandi isaretleyip puan uretemez', async () => {
    // Bu gecerse: sinirsiz Yesil Puan uretilebilir.
    await assertFails(
      updateDoc(doc(asStranger(), 'waste_requests', REQ_ASSIGNED), {
        status: 'tamamlandi',
        confirmedKg: 999,
      }),
    );
  });

  test('YABANCI, devam eden teslimati calamaz', async () => {
    await assertFails(
      updateDoc(doc(asStranger(), 'waste_requests', REQ_ASSIGNED), {
        collectorId: STRANGER,
      }),
    );
  });

  test('toplayici BEKLEYEN talebi kendi UID ile ustlenebilir', async () => {
    await assertSucceeds(
      updateDoc(doc(asCollector(), 'waste_requests', REQ_PENDING), {
        status: 'atandi',
        collectorId: COLLECTOR,
        collectorName: 'Toplayici Bir',
        collectorLocation: { latitude: 39.61, longitude: 32.18 },
      }),
    );
  });

  test('ATANMIS toplayici CANLI KONUM yayinlayabilir', async () => {
    // Demo sirasinda ~900 ms'de bir calisan yazma. Bu kirilirsa
    // kullanicinin takip ekrani donar — kural testinin en kritik
    // "calismaya devam etmeli" senaryosu.
    await assertSucceeds(
      updateDoc(doc(asCollector(), 'waste_requests', REQ_ASSIGNED), {
        collectorLocation: { latitude: 39.605, longitude: 32.11 },
        collectorBearing: 42.5,
        status: 'yolda',
      }),
    );
  });

  test('yeni ATANMIS talepte ilk konum yayini da gecerli', async () => {
    // status 'atandi' -> 'yolda' ilk gecisi
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'waste_requests', REQ_PENDING), {
        userId: OWNER,
        wasteTypes: ['kagit'],
        estimatedKg: 100,
        approxLocation: { latitude: 39.6, longitude: 32.1 },
        status: 'atandi',
        collectorId: COLLECTOR,
      });
    });
    await assertSucceeds(
      updateDoc(doc(asCollector(), 'waste_requests', REQ_PENDING), {
        collectorLocation: { latitude: 39.6, longitude: 32.1 },
        collectorBearing: 10,
        status: 'yolda',
      }),
    );
  });

  test('TAMAMLANMIS talep yeniden tamamlanamaz (puan tekrar uretilemez)',
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'waste_requests', REQ_ASSIGNED), {
          userId: OWNER,
          wasteTypes: ['metal'],
          estimatedKg: 60,
          approxLocation: { latitude: 39.6, longitude: 32.1 },
          status: 'tamamlandi',
          collectorId: COLLECTOR,
          confirmedKg: 60,
        });
      });
      await assertFails(
        updateDoc(doc(asCollector(), 'waste_requests', REQ_ASSIGNED), {
          status: 'tamamlandi',
          confirmedKg: 5000,
        }),
      );
    });

  test('ATANMIS toplayici konum guncelleyip teslimati tamamlayabilir', async () => {
    await assertSucceeds(
      updateDoc(doc(asCollector(), 'waste_requests', REQ_ASSIGNED), {
        status: 'tamamlandi',
        confirmedKg: 60,
      }),
    );
  });

  test('toplayici BASKASININ isini tamamlayamaz', async () => {
    await assertFails(
      updateDoc(doc(asStranger(), 'waste_requests', REQ_ASSIGNED), {
        status: 'tamamlandi',
        confirmedKg: 60,
      }),
    );
  });
});

// =====================================================================
describe('3) Iptal is kurali SUNUCUDA', () => {
  test('sahibi BEKLEYEN talebini iptal edebilir', async () => {
    await assertSucceeds(
      updateDoc(doc(asOwner(), 'waste_requests', REQ_PENDING), {
        status: 'iptal',
      }),
    );
  });

  test('sahibi YOLA CIKMIS talebi iptal EDEMEZ', async () => {
    // Bu kural bugune kadar yalnizca arayuzdeydi; artik sunucuda.
    await assertFails(
      updateDoc(doc(asOwner(), 'waste_requests', REQ_ASSIGNED), {
        status: 'iptal',
      }),
    );
  });

  test('yabanci baskasinin talebini iptal edemez', async () => {
    await assertFails(
      updateDoc(doc(asStranger(), 'waste_requests', REQ_PENDING), {
        status: 'iptal',
      }),
    );
  });
});

// =====================================================================
describe('4) Gizlilik maskesi — acik adres', () => {
  test('talep sahibi kendi adresini okuyabilir', async () => {
    await assertSucceeds(
      getDoc(doc(asOwner(), 'waste_requests', REQ_PENDING, 'private', 'detail')),
    );
  });

  test('ATANMAMIS toplayici acik adresi OKUYAMAZ', async () => {
    await assertFails(
      getDoc(
        doc(asCollector(), 'waste_requests', REQ_PENDING, 'private', 'detail'),
      ),
    );
  });

  test('ATANMIS toplayici acik adresi okuyabilir', async () => {
    await assertSucceeds(
      getDoc(
        doc(asCollector(), 'waste_requests', REQ_ASSIGNED, 'private', 'detail'),
      ),
    );
  });

  test('yabanci acik adresi okuyamaz', async () => {
    await assertFails(
      getDoc(
        doc(asStranger(), 'waste_requests', REQ_ASSIGNED, 'private', 'detail'),
      ),
    );
  });

  test('adres sonradan DEGISTIRILEMEZ', async () => {
    await assertFails(
      updateDoc(
        doc(asOwner(), 'waste_requests', REQ_PENDING, 'private', 'detail'),
        { note: 'degistirildi' },
      ),
    );
  });
});

// =====================================================================
describe('5) Talep olusturma dogrulamalari', () => {
  test('acik dokumana note/location yazilamaz', async () => {
    await assertFails(
      setDoc(doc(asOwner(), 'waste_requests', 'sizinti'), {
        userId: OWNER,
        wasteTypes: ['kagit'],
        estimatedKg: 10,
        approxLocation: { latitude: 39.6, longitude: 32.1 },
        status: 'bekliyor',
        note: 'acik adres burada',
      }),
    );
  });

  test('baskasi adina talep olusturulamaz', async () => {
    await assertFails(
      setDoc(doc(asStranger(), 'waste_requests', 'sahte'), {
        userId: OWNER,
        wasteTypes: ['kagit'],
        estimatedKg: 10,
        approxLocation: { latitude: 39.6, longitude: 32.1 },
        status: 'bekliyor',
      }),
    );
  });

  test('talep dogrudan tamamlandi olarak olusturulamaz', async () => {
    await assertFails(
      setDoc(doc(asOwner(), 'waste_requests', 'hileli'), {
        userId: OWNER,
        wasteTypes: ['metal'],
        estimatedKg: 1000,
        approxLocation: { latitude: 39.6, longitude: 32.1 },
        status: 'tamamlandi',
        confirmedKg: 1000,
      }),
    );
  });

  test('talep silinemez', async () => {
    const { deleteDoc } = await import('firebase/firestore');
    await assertFails(
      deleteDoc(doc(asOwner(), 'waste_requests', REQ_PENDING)),
    );
  });
});

// =====================================================================
describe('6) Odul ekonomisi ve operator yetkisi', () => {
  test('kullanici kendi odul talebini okuyabilir', async () => {
    await assertSucceeds(
      getDocs(
        query(
          collection(asOwner(), 'redemptions'),
          where('userId', '==', OWNER),
        ),
      ),
    );
  });

  test('kullanici BASKASININ odul taleplerini okuyamaz', async () => {
    await assertFails(
      getDocs(
        query(
          collection(asStranger(), 'redemptions'),
          where('userId', '==', OWNER),
        ),
      ),
    );
  });

  test('operator TUM bekleyen talepleri okuyabilir', async () => {
    await assertSucceeds(
      getDocs(
        query(
          collection(asOperator(), 'redemptions'),
          where('status', '==', 'beklemede'),
        ),
      ),
    );
  });

  test('operator OLMAYAN kendi talebini onaylayamaz', async () => {
    await assertFails(
      updateDoc(doc(asOwner(), 'redemptions', 'talep-odul-1'), {
        status: 'onaylandi',
        decidedBy: OWNER,
      }),
    );
  });

  test('operator bekleyen talebi onaylayabilir', async () => {
    await assertSucceeds(
      updateDoc(doc(asOperator(), 'redemptions', 'talep-odul-1'), {
        status: 'onaylandi',
        decidedBy: OPERATOR,
      }),
    );
  });

  test('operator PUANI degistiremez', async () => {
    await assertFails(
      updateDoc(doc(asOperator(), 'redemptions', 'talep-odul-1'), {
        status: 'onaylandi',
        decidedBy: OPERATOR,
        costPoints: 1,
      }),
    );
  });

  test('kimse kendini operator yapamaz', async () => {
    await assertFails(
      setDoc(doc(asStranger(), 'admins', STRANGER), { name: 'hile' }),
    );
  });

  test('operator listesi disariya sizmaz', async () => {
    await assertFails(getDoc(doc(asStranger(), 'admins', OPERATOR)));
  });

  test('odul katalogu uygulamadan degistirilemez', async () => {
    await assertFails(
      updateDoc(doc(asOwner(), 'rewards', 'odul-1'), { costPoints: 1 }),
    );
  });
});

// =====================================================================
describe('7) CANLI AKIS REPLAY — demodaki birebir yazma dizisi', () => {
  test('ustlen -> 9 kez konum yayini -> teslim onayi: hepsi gecmeli',
    async () => {
      const collectorDb = asCollector();
      const ref = doc(collectorDb, 'waste_requests', REQ_PENDING);

      // 1) Talebi ustlen (acceptRequest transaction'inin yazdigi alanlar)
      await assertSucceeds(
        updateDoc(ref, {
          status: 'atandi',
          collectorId: COLLECTOR,
          collectorName: 'Toplayici Bir',
          acceptedAt: new Date(),
          collectorLocation: { latitude: 39.61, longitude: 32.18 },
        }),
      );

      // 2) 8 saniyelik yolculukta ~900 ms'de bir konum yayini
      for (let i = 0; i < 9; i++) {
        await assertSucceeds(
          updateDoc(ref, {
            collectorLocation: {
              latitude: 39.61 - i * 0.001,
              longitude: 32.18 - i * 0.002,
            },
            collectorBearing: 180 + i,
            status: 'yolda',
          }),
        );
      }

      // 3) Varista teslim onayi
      await assertSucceeds(
        updateDoc(ref, { status: 'tamamlandi', confirmedKg: 180 }),
      );
    });

  test('konum HIC DEGISMESE bile yazma reddedilmez', async () => {
    // Arac duruyorsa diff() bos kalir; hasOnly([]) true olmali.
    const ref = doc(asCollector(), 'waste_requests', REQ_ASSIGNED);
    await assertSucceeds(
      updateDoc(ref, { collectorBearing: 0, status: 'yolda' }),
    );
    await assertSucceeds(
      updateDoc(ref, { collectorBearing: 0, status: 'yolda' }),
    );
  });

  test('bearing NaN olsa bile kural reddetmez (tip dogrulamasi yok)',
    async () => {
      const ref = doc(asCollector(), 'waste_requests', REQ_ASSIGNED);
      await assertSucceeds(
        updateDoc(ref, {
          collectorLocation: { latitude: 39.6, longitude: 32.1 },
          collectorBearing: Number.NaN,
          status: 'yolda',
        }),
      );
    });
});

// =====================================================================
describe('8) TOPLAYICI DOGRULAMASI — collectors/{uid} beyaz listesi', () => {
  // Kapatilan zafiyet: rol secimi yalnizca bir ARAYUZ tercihiydi. Bu yuzden
  // e-postayla kayit olan herkes "Toplayici" secip bekleyen bir isi
  // ustlenebiliyor ve ustlendigi anda o isletmenin ACIK ADRESINI
  // okuyabiliyordu. Maskeleme adresleri toplu taramayi engelliyordu ama
  // teker teker gormeyi engellemiyordu.
  //
  // Artik is ustlenmek `collectors/{uid}` kaydi sart. Adres okuma zaten
  // collectorId'ye bagli oldugundan, dogrulanmamis hesap adrese TRANSITIF
  // olarak da ulasamaz.

  test('DOGRULANMAMIS hesap bekleyen isi USTLENEMEZ', async () => {
    await assertFails(
      updateDoc(doc(asStranger(), 'waste_requests', REQ_PENDING), {
        status: 'atandi',
        collectorId: STRANGER,
        collectorName: 'Dogrulanmamis',
      }),
    );
  });

  test('DOGRULANMAMIS hesap is ustlenemedigi icin ACIK ADRESI goremez',
    async () => {
      // Once ustlenmeyi dene (reddedilmeli)
      await assertFails(
        updateDoc(doc(asStranger(), 'waste_requests', REQ_PENDING), {
          status: 'atandi',
          collectorId: STRANGER,
        }),
      );
      // Dolayisiyla korumali detay da kapali kalir
      await assertFails(
        getDoc(
          doc(asStranger(), 'waste_requests', REQ_PENDING, 'private', 'detail'),
        ),
      );
    });

  test('DOGRULANMIS toplayici isi ustlenebilir ve adresi okuyabilir',
    async () => {
      await assertSucceeds(
        updateDoc(doc(asCollector(), 'waste_requests', REQ_PENDING), {
          status: 'atandi',
          collectorId: COLLECTOR,
          collectorName: 'Toplayici Bir',
          collectorLocation: { latitude: 39.61, longitude: 32.18 },
        }),
      );
      await assertSucceeds(
        getDoc(
          doc(asCollector(), 'waste_requests', REQ_PENDING, 'private', 'detail'),
        ),
      );
    });

  test('kimse kendini toplayici yapamaz', async () => {
    await assertFails(
      setDoc(doc(asStranger(), 'collectors', STRANGER), { name: 'hile' }),
    );
  });

  test('toplayici kendi kaydini okuyabilir', async () => {
    await assertSucceeds(getDoc(doc(asCollector(), 'collectors', COLLECTOR)));
  });

  test('toplayici listesi disariya sizmaz', async () => {
    await assertFails(getDoc(doc(asStranger(), 'collectors', COLLECTOR)));
  });

  // TASARIM KARARI: dogrulama YALNIZCA is ustlenirken aranir.
  // Sebep 1 (dogruluk): yolculuk ortasinda yetkisi kaldirilan toplayicinin
  //   teslimati askida kalmamali — atama zaten yetkinin kendisidir.
  // Sebep 2 (maliyet): konum yayini ~900 ms'de bir calisiyor; her yazmaya
  //   exists() eklemek her yayina fazladan bir dokuman okumasi bindirirdi.
  test('devam eden teslimat, yetki sonradan kaldirilsa da bitirilebilir',
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        // Toplayici beyaz listeden cikarildi
        const { deleteDoc } = await import('firebase/firestore');
        await deleteDoc(doc(ctx.firestore(), 'collectors', COLLECTOR));
      });

      // Uzerindeki is devam edebilmeli
      await assertSucceeds(
        updateDoc(doc(asCollector(), 'waste_requests', REQ_ASSIGNED), {
          collectorLocation: { latitude: 39.6, longitude: 32.1 },
          collectorBearing: 90,
          status: 'yolda',
        }),
      );
      await assertSucceeds(
        updateDoc(doc(asCollector(), 'waste_requests', REQ_ASSIGNED), {
          status: 'tamamlandi',
          confirmedKg: 60,
        }),
      );

      // Ama YENI is ustlenemez
      await assertFails(
        updateDoc(doc(asCollector(), 'waste_requests', REQ_PENDING), {
          status: 'atandi',
          collectorId: COLLECTOR,
        }),
      );
    });
});
