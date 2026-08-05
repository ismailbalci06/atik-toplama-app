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
  // BILINEN SINIR — bilincli olarak belgeleniyor:
  // Sistemde toplayici DOGRULAMASI yok. Rol secimi sadece bir arayuz
  // tercihi oldugu icin, giris yapmis herhangi bir kullanici bekleyen bir
  // isi ustlenebilir; ustlendigi ANDA da o talebin acik adresini okumaya
  // hak kazanir (kural boyle tasarlandi).
  //
  // Yani maskeleme "adresleri tarayarak toplamayi" engeller, ama kayit
  // olan birinin TEK BIR adresi is ustlenerek gormesini engellemez.
  // Kapatmak icin `collectors/{uid}` beyaz listesi gerekir (bkz. admins
  // ile ayni desen). Bu test o sinirin farkinda oldugumuzu ve kazara
  // degismedigini garanti eder.
  test('BILINEN SINIR: kayitli her kullanici bekleyen isi ustlenebilir',
    async () => {
      await assertSucceeds(
        updateDoc(doc(asStranger(), 'waste_requests', REQ_PENDING), {
          status: 'atandi',
          collectorId: STRANGER,
          collectorName: 'Yabanci',
        }),
      );
    });

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
