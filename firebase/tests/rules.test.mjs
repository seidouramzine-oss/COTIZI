// Scénario de bout en bout des règles Firestore de COTIZI.
// Lancer depuis le dossier firebase/ :  npm test
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import firebase from 'firebase/compat/app';
import 'firebase/compat/firestore';

const now = () => firebase.firestore.FieldValue.serverTimestamp();

const people = {
  t: { phone: '+22901000000', name: 'Tontinier' },
  a: { phone: '+22901000001', name: 'Alice' },
  b: { phone: '+22901000002', name: 'Bob' },
  c: { phone: '+22901000003', name: 'Chloe' },
  d: { phone: '+22901000004', name: 'David' },
  z: { phone: '+22997000099', name: 'Zoé' },
  e: { phone: '+22997000098', name: 'Emma' },
};

let env;
const db = (id) =>
  env
    .authenticatedContext(id, { email: `${people[id].phone.slice(1)}@phone.cotizi.app` })
    .firestore();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'cotizi-test',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
  await env.clearFirestore();
});

after(async () => {
  await env?.cleanup();
});

// --------------------------------------------------------------- Actions
// (mêmes écritures que l'application, voir lib/api.dart)

async function createGroup(fs, tontineId, code, fields = {}) {
  const ref = fs.collection('groups').doc();
  const batch = fs.batch();
  batch.set(ref, {
    tontineId,
    tontineName: 'Tontine du marché',
    ownerId: 't',
    ownerName: 'Tontinier',
    name: 'Groupe 1',
    memberCount: 3,
    contributionAmount: 10000,
    frequency: 'weekly',
    startDate: '2026-10-10',
    contributionsPerPot: 3,
    firstPayoutDate: '2026-10-12',
    paidOutCount: 0,
    orderMode: 'draw',
    penaltyAmount: 500,
    penaltyGraceDays: 0,
    commissionType: 'percent',
    commissionValue: 5,
    inviteCode: code,
    status: 'recruiting',
    joinedCount: 0,
    drawnCount: 0,
    memberIds: [],
    startedAt: null,
    createdAt: now(),
    ...fields,
  });
  batch.set(fs.collection('invites').doc(code), { kind: 'group', targetId: ref.id, ownerId: 't' });
  await batch.commit();
  return ref.id;
}

async function joinGroup(id, groupId) {
  // Le futur membre ne peut pas lire le groupe : incrément et ajout « à l'aveugle »,
  // les règles vérifient le résultat (groupe non complet, pas déjà membre).
  const fs = db(id);
  const ref = fs.collection('groups').doc(groupId);
  const batch = fs.batch();
  batch.update(ref, {
    joinedCount: firebase.firestore.FieldValue.increment(1),
    memberIds: firebase.firestore.FieldValue.arrayUnion(id),
  });
  batch.set(ref.collection('members').doc(id), {
    fullName: people[id].name,
    phone: people[id].phone,
    joinedAt: now(),
    drawPosition: null,
    declaredCount: 0,
    approvedCount: 0,
    lastPaymentId: null,
    penaltyPaid: 0,
  });
  await batch.commit();
}

async function adminGet(path) {
  let data;
  await env.withSecurityRulesDisabled(async (ctx) => {
    data = (await ctx.firestore().doc(path).get()).data();
  });
  return data;
}

async function startDraw(groupId, memberIds) {
  const fs = db('t');
  const batch = fs.batch();
  batch.update(fs.doc(`groups/${groupId}`), { status: 'drawing' });
  const positions = memberIds.map((_, i) => i + 1).sort(() => Math.random() - 0.5);
  memberIds.forEach((m, i) =>
    batch.set(fs.doc(`groups/${groupId}/draws/${m}`), { position: positions[i] }));
  await batch.commit();
}

async function drawLot(id, groupId) {
  const fs = db(id);
  return fs.runTransaction(async (tx) => {
    const g = (await tx.get(fs.doc(`groups/${groupId}`))).data();
    const pos = (await tx.get(fs.doc(`groups/${groupId}/draws/${id}`))).data().position;
    tx.update(fs.doc(`groups/${groupId}/members/${id}`), { drawPosition: pos });
    tx.update(fs.doc(`groups/${groupId}`), { drawnCount: g.drawnCount + 1 });
    return pos;
  });
}

function proof(fs, owner, kind, targetId) {
  const ref = fs.collection('proofs').doc();
  return [ref, {
    ownerId: owner,
    reviewerId: 't',
    kind,
    targetId,
    data: 'aGVsbG8=',
    mime: 'image/jpeg',
    createdAt: now(),
  }];
}

// Référence Mobile Money unique pour chaque déclaration de test
let refCounter = 0;
const nextRef = () => `MP${Date.now() % 100000}${++refCounter}`;

// Enregistre la référence d'un paiement Mobile Money dans le même envoi
function setRef(batch, fs, ref, paymentPath, payerId, ownerId = 't') {
  batch.set(fs.doc(`paymentRefs/${ref}`), { payment: paymentPath, payerId, ownerId, at: now() });
}

// Note de confiance du tontinier : créée à zéro si absente
async function ensureTrust(fs, ownerId = 't') {
  if (!(await adminGet(`trust/${ownerId}`))) {
    await fs.doc(`trust/${ownerId}`).set({
      payoutsDone: 0, payoutsConfirmed: 0, payoutsDisputed: 0, last: null,
    });
  }
}

// Fait avancer un compteur de la note de confiance dans le même envoi
async function moveTrust(batch, fs, field, payoutPath, ownerId = 't') {
  const tr = await adminGet(`trust/${ownerId}`);
  batch.update(fs.doc(`trust/${ownerId}`), { [field]: (tr?.[field] ?? 0) + 1, last: payoutPath });
}

// Déclare [count] cotisations : paiement + compteur du membre dans le même envoi
async function declare(id, groupId, count,
  { amount, counter = true, payment = true, method = 'mobile_money', penalty = 0, proofId,
    reference = null, registerRef = true, proofHash, registerHash = true } = {}) {
  const fs = db(id);
  const g = await adminGet(`groups/${groupId}`);
  const m = await adminGet(`groups/${groupId}/members/${id}`);
  const batch = fs.batch();
  let proofRef = null;
  if (method === 'mobile_money' && proofId === undefined) {
    const [pRef, pData] = proof(fs, id, 'group', groupId);
    batch.set(pRef, pData);
    proofRef = pRef.id;
  }
  const payRef = fs.collection(`groups/${groupId}/payments`).doc();
  const ref = reference;
  const hash = proofHash === undefined ? (method === 'mobile_money' ? 'IMG' + nextRef() : null) : proofHash;
  if (payment) {
    batch.set(payRef, {
      userId: id, payerName: people[id].name, payerPhone: people[id].phone, count,
      amount: amount ?? count * g.contributionAmount + penalty, penalty, method,
      note: method === 'cash' ? 'Remis au marché' : null,
      proofId: proofId === undefined ? proofRef : proofId, status: 'pending',
      rejectionReason: null, declaredAt: now(), reviewedAt: null, recordedBy: 'member',
      reference: ref, proofHash: hash,
    });
    if (ref && registerRef) setRef(batch, fs, ref, `groups/${groupId}/payments/${payRef.id}`, id, g.ownerId);
    if (hash && registerHash) setRef(batch, fs, hash, `groups/${groupId}/payments/${payRef.id}`, id, g.ownerId);
  }
  if (counter) {
    batch.update(fs.doc(`groups/${groupId}/members/${id}`), {
      declaredCount: (m.declaredCount ?? 0) + count, lastPaymentId: payRef.id,
    });
  }
  await batch.commit();
  return payRef.id;
}

// Niveaux du groupe après le passage d'un participant de [from] à [to]
// cotisations validées (null : niveau inchangé)
function levelsPatch(g, memberId, from, to) {
  if (!g.levels) return null;
  const a = String(Math.floor(from / g.contributionsPerPot));
  const b = String(Math.floor(to / g.contributionsPerPot));
  if (a === b) return null;
  const levels = { ...g.levels };
  levels[a] -= 1;
  if (levels[a] === 0) delete levels[a];
  levels[b] = (levels[b] ?? 0) + 1;
  return { levels, levelsMember: memberId };
}

// Validation / refus par le tontinier : paiement + compteurs du membre
// (+ niveaux du groupe)
async function review(groupId, paymentId, approve, { counters = true, levels = true } = {}) {
  const T = db('t');
  const pay = await adminGet(`groups/${groupId}/payments/${paymentId}`);
  const m = await adminGet(`groups/${groupId}/members/${pay.userId}`);
  const g = await adminGet(`groups/${groupId}`);
  const batch = T.batch();
  const patch = approve
    ? levelsPatch(g, pay.userId, m.approvedCount, m.approvedCount + pay.count) : null;
  if (patch && levels) batch.update(T.doc(`groups/${groupId}`), patch);
  batch.update(T.doc(`groups/${groupId}/payments/${paymentId}`), approve
    ? { status: 'approved', rejectionReason: null, reviewedAt: now() }
    : { status: 'rejected', rejectionReason: 'Montant incorrect', reviewedAt: now() });
  if (counters) {
    batch.update(T.doc(`groups/${groupId}/members/${pay.userId}`), approve
      ? { approvedCount: m.approvedCount + pay.count, penaltyPaid: (m.penaltyPaid ?? 0) + (pay.penalty ?? 0) }
      : { declaredCount: m.declaredCount - pay.count });
  }
  await batch.commit();
}

// ------------------------------------------------------------- Scénario

test('scénario complet', async (t) => {
  for (const id of Object.keys(people)) {
    await assertSucceeds(db(id).doc(`users/${id}`).set({
      fullName: people[id].name, phone: people[id].phone,
      role: id === 't' ? 'tontinier' : 'membre', createdAt: now(),
    }));
  }

  await t.test('profil avec un autre numéro que celui du compte : refusé', () =>
    assertFails(db('a').doc('users/a').set({
      fullName: 'Alice', phone: '+22999999999', createdAt: now(),
    })));

  await t.test('profil d\'un autre : illisible', () =>
    assertFails(db('a').doc('users/b').get()));

  await t.test('rôle inconnu à l\'inscription : refusé', async () => {
    const env2 = env.authenticatedContext('x', { email: '22999000000@phone.cotizi.app' }).firestore();
    await assertFails(env2.doc('users/x').set({
      fullName: 'Xavier', phone: '+22999000000', role: 'admin', createdAt: now(),
    }));
  });
  await t.test('un membre (inscrit par invitation) ne crée pas de tontine', async () => {
    const m = env.authenticatedContext('m', { email: '22999000001@phone.cotizi.app' }).firestore();
    await assertSucceeds(m.doc('users/m').set({
      fullName: 'Membre', phone: '+22999000001', role: 'membre', createdAt: now(),
    }));
    await assertFails(m.collection('tontines').doc().set({
      ownerId: 'm', ownerName: 'Membre', name: 'X', type: 'cagnotte', createdAt: now(),
    }));
    await assertFails(m.doc('users/m').update({ role: 'tontinier' }));
  });

  const T = db('t');
  const tontine = T.collection('tontines').doc();
  await assertSucceeds(tontine.set({
    ownerId: 't', ownerName: 'Tontinier', name: 'Tontine du marché', type: 'cagnotte', createdAt: now(),
  }));
  const carnetTontine = T.collection('tontines').doc();
  await assertSucceeds(carnetTontine.set({
    ownerId: 't', ownerName: 'Tontinier', name: 'Carnets', type: 'carnet', createdAt: now(),
  }));

  await t.test('tontine créée au nom d\'un autre : refusé', () =>
    assertFails(db('a').collection('tontines').doc().set({
      ownerId: 't', ownerName: 'Tontinier', name: 'X', type: 'cagnotte', createdAt: now(),
    })));

  const groupId = await createGroup(T, tontine.id, 'ABC234');

  await t.test('commission fixe supérieure à la cagnotte : refusé', () =>
    assertFails(createGroup(T, tontine.id, 'BAD234', { commissionType: 'fixed', commissionValue: 100000 })));
  await t.test('groupe dans une tontine à carnet : refusé', () =>
    assertFails(createGroup(T, carnetTontine.id, 'BAD235')));
  await t.test('code d\'invitation déjà pris : refusé', () =>
    assertFails(createGroup(T, tontine.id, 'ABC234')));
  await t.test('groupe créé déjà « en tirage » : refusé', () =>
    assertFails(createGroup(T, tontine.id, 'BAD236', { status: 'drawing' })));

  await t.test('lecture d\'un code d\'invitation', () =>
    assertSucceeds(db('a').doc('invites/ABC234').get()));
  await t.test('liste de tous les codes : refusé', () =>
    assertFails(db('a').collection('invites').get()));
  await t.test('groupe illisible avant d\'avoir rejoint', () =>
    assertFails(db('a').doc(`groups/${groupId}`).get()));

  await t.test('le tontinier ne peut pas rejoindre son groupe', () =>
    assertFails(joinGroup('t', groupId)));

  await assertSucceeds(joinGroup('a', groupId));
  await t.test('rejoindre deux fois : refusé', () => assertFails(joinGroup('a', groupId)));
  await assertSucceeds(db('a').doc(`groups/${groupId}`).get());
  await t.test('« mes groupes » (array-contains)', async () => {
    const q = await assertSucceeds(
      db('a').collection('groups').where('memberIds', 'array-contains', 'a').get());
    if (q.size !== 1) throw new Error(`attendu 1 groupe, obtenu ${q.size}`);
  });

  await t.test('membre qui modifie le statut : refusé', () =>
    assertFails(db('a').doc(`groups/${groupId}`).update({ status: 'drawing' })));
  await assertSucceeds(joinGroup('b', groupId));
  await t.test('tirage sur groupe incomplet : refusé', () =>
    assertFails(startDraw(groupId, ['a', 'b'])));
  await assertSucceeds(joinGroup('c', groupId));
  await t.test('rejoindre un groupe complet : refusé', () => assertFails(joinGroup('d', groupId)));

  await t.test('déclarer avant le tirage : refusé', () => assertFails(declare('a', groupId, 1)));

  await assertSucceeds(startDraw(groupId, ['a', 'b', 'c']));
  await t.test('relancer le tirage (réécrire les numéros) : refusé', () =>
    assertFails(db('t').doc(`groups/${groupId}/draws/a`).set({ position: 1 })));
  await t.test('lire le numéro d\'un autre : refusé', () =>
    assertFails(db('a').doc(`groups/${groupId}/draws/b`).get()));

  const posA = await assertSucceeds(drawLot('a', groupId));
  await t.test('tirer deux fois : refusé', () => assertFails(drawLot('a', groupId)));
  await t.test('choisir son numéro : refusé', async () => {
    const fs = db('b');
    const real = (await fs.doc(`groups/${groupId}/draws/b`).get()).data().position;
    const fake = real === 1 ? 2 : 1;
    await assertFails(fs.runTransaction(async (tx) => {
      const g = (await tx.get(fs.doc(`groups/${groupId}`))).data();
      tx.update(fs.doc(`groups/${groupId}/members/b`), { drawPosition: fake });
      tx.update(fs.doc(`groups/${groupId}`), { drawnCount: g.drawnCount + 1 });
    }));
  });
  await t.test('révéler sans faire avancer le compteur : refusé', () =>
    assertFails(db('b').doc(`groups/${groupId}/members/b`).get().then(async () => {
      const pos = (await db('b').doc(`groups/${groupId}/draws/b`).get()).data().position;
      await db('b').doc(`groups/${groupId}/members/b`).update({ drawPosition: pos });
    })));

  // Le tontinier termine le tirage pour b et c
  await t.test('le tontinier tire pour les retardataires', () => assertSucceeds((async () => {
    const batch = T.batch();
    for (const m of ['b', 'c']) {
      const pos = (await T.doc(`groups/${groupId}/draws/${m}`).get()).data().position;
      batch.update(T.doc(`groups/${groupId}/members/${m}`), { drawPosition: pos });
    }
    batch.update(T.doc(`groups/${groupId}`), { drawnCount: 3 });
    await batch.commit();
  })()));

  const g = await adminGet(`groups/${groupId}`);
  if (g.drawnCount !== 3) throw new Error('le groupe devrait être en cours');
  const members = await assertSucceeds(db('a').collection(`groups/${groupId}/members`).get());
  const positions = members.docs.map((d) => d.data().drawPosition).sort();
  if (positions.join() !== '1,2,3') throw new Error(`numéros ${positions}`);
  if (!posA) throw new Error('numéro de A manquant');

  await t.test('déclarer avant le démarrage : refusé', () => assertFails(declare('a', groupId, 1)));
  const start = (fs, fields = {}) => fs.doc(`groups/${groupId}`).update({
    status: 'active', startDate: '2026-10-12', firstPayoutDate: '2026-10-26', startedAt: now(),
    levels: { 0: 3 }, ...fields,
  });
  await t.test('un membre démarre la tontine : refusé', () => assertFails(start(db('a'))));
  await t.test('démarrer sans les niveaux : refusé', () =>
    assertFails(start(T, { levels: { 0: 2 } })));
  await t.test('démarrer avec des participants déjà « à jour » : refusé', () =>
    assertFails(start(T, { levels: { 1: 3 } })));
  await t.test('démarrer avec une remise avant le début : refusé', () =>
    assertFails(start(T, { firstPayoutDate: '2026-10-01' })));
  await assertSucceeds(start(T));
  await t.test('modifier le groupe une fois démarré : refusé', () =>
    assertFails(T.doc(`groups/${groupId}`).update({ contributionAmount: 1 })));
  await t.test('supprimer le groupe une fois démarré : refusé', () =>
    assertFails(T.doc(`groups/${groupId}`).delete()));

  // Paiements : 3 cotisations par cagnotte, 3 cagnottes -> 9 cotisations chacun
  const pay1 = await assertSucceeds(declare('a', groupId, 2));
  let ma = await adminGet(`groups/${groupId}/members/a`);
  if (ma.declaredCount !== 2) throw new Error(`déclarées : ${ma.declaredCount}`);
  await t.test('déclarer plus que le total des cotisations : refusé', () =>
    assertFails(declare('a', groupId, 8)));
  await t.test('montant modifié : refusé', () =>
    assertFails(declare('a', groupId, 1, { amount: 1 })));
  await t.test('paiement sans faire avancer son compteur : refusé', () =>
    assertFails(declare('a', groupId, 1, { counter: false })));
  await t.test('compteur avancé sans paiement : refusé', () =>
    assertFails(declare('a', groupId, 1, { payment: false })));
  await t.test('se valider soi-même ses cotisations : refusé', () =>
    assertFails(db('a').doc(`groups/${groupId}/members/a`).update({ approvedCount: 2 })));
  await t.test('déclarer « déjà validé » : refusé', async () => {
    const fs = db('b');
    const batch = fs.batch();
    const [pRef, pData] = proof(fs, 'b', 'group', groupId);
    batch.set(pRef, pData);
    const payRef = fs.collection(`groups/${groupId}/payments`).doc();
    batch.set(payRef, {
      userId: 'b', payerName: 'Bob', payerPhone: people.b.phone, count: 1,
      amount: 10000, proofId: pRef.id, status: 'approved', rejectionReason: null,
      declaredAt: now(), reviewedAt: null,
    });
    batch.update(fs.doc(`groups/${groupId}/members/b`), { declaredCount: 1, lastPaymentId: payRef.id });
    await assertFails(batch.commit());
  });
  await t.test('valider son propre paiement : refusé', () =>
    assertFails(db('a').doc(`groups/${groupId}/payments/${pay1}`).update({
      status: 'approved', rejectionReason: null, reviewedAt: now(),
    })));
  await t.test('B ne voit pas le paiement de A', () =>
    assertFails(db('b').doc(`groups/${groupId}/payments/${pay1}`).get()));
  await t.test('B liste seulement ses paiements', () =>
    assertSucceeds(db('b').collection(`groups/${groupId}/payments`).where('userId', '==', 'b').get()));
  await t.test('B liste tous les paiements : refusé', () =>
    assertFails(db('b').collection(`groups/${groupId}/payments`).get()));

  const pay = await adminGet(`groups/${groupId}/payments/${pay1}`);
  await t.test('B ne voit pas la preuve de A', () =>
    assertFails(db('b').doc(`proofs/${pay.proofId}`).get()));
  await t.test('le tontinier voit la preuve de A', () =>
    assertSucceeds(T.doc(`proofs/${pay.proofId}`).get()));
  await t.test('le tontinier liste tous les paiements', () =>
    assertSucceeds(T.collection(`groups/${groupId}/payments`).get()));
  await t.test('lister les paiements en attente', () =>
    assertSucceeds(T.collection(`groups/${groupId}/payments`).where('status', '==', 'pending').get()));

  await t.test('refus sans raison : refusé', () =>
    assertFails(T.doc(`groups/${groupId}/payments/${pay1}`).update({
      status: 'rejected', rejectionReason: '  ', reviewedAt: now(),
    })));
  await t.test('validation sans mettre à jour les compteurs : refusé', () =>
    assertFails(review(groupId, pay1, true, { counters: false })));
  await assertSucceeds(review(groupId, pay1, false));
  ma = await adminGet(`groups/${groupId}/members/a`);
  if (ma.declaredCount !== 0) throw new Error(`après refus : ${ma.declaredCount}`);

  const pay2 = await assertSucceeds(declare('a', groupId, 3));
  await t.test('valider sans mettre à jour les niveaux du groupe : refusé', () =>
    assertFails(review(groupId, pay2, true, { levels: false })));
  await t.test('niveaux modifiés sans paiement validé : refusé', () =>
    assertFails(T.doc(`groups/${groupId}`).update({ levels: { 0: 2, 1: 1 }, levelsMember: 'b' })));
  await assertSucceeds(review(groupId, pay2, true));
  const gl = await adminGet(`groups/${groupId}`);
  if (JSON.stringify(gl.levels) !== JSON.stringify({ 0: 2, 1: 1 })) throw new Error(JSON.stringify(gl.levels));
  ma = await adminGet(`groups/${groupId}/members/a`);
  if (ma.approvedCount !== 3 || ma.declaredCount !== 3) throw new Error(JSON.stringify(ma));
  await t.test('modifier un paiement validé : refusé', () =>
    assertFails(T.doc(`groups/${groupId}/payments/${pay2}`).update({
      status: 'rejected', rejectionReason: 'x', reviewedAt: now(),
    })));
  await t.test('les membres voient l\'avancée des cotisations du groupe', () =>
    assertSucceeds(db('b').collection(`groups/${groupId}/members`).get()));

  // Remise de la cagnotte 1 au membre qui a tiré le n°1
  const ms = (await assertSucceeds(T.collection(`groups/${groupId}/members`).get())).docs;
  const byPos = Object.fromEntries(ms.map((d) => [d.data().drawPosition, d.id]));
  await ensureTrust(T);
  const payout = async (fs, pot, beneficiary, { trust = true } = {}) => {
    const batch = fs.batch();
    batch.set(fs.doc(`groups/${groupId}/payouts/${pot}`), {
      tour: pot, beneficiaryId: beneficiary, beneficiaryName: people[beneficiary].name,
      amount: 85500, paidAt: now(), receivedAt: null, problem: null,
    });
    batch.update(fs.doc(`groups/${groupId}`), { paidOutCount: pot });
    if (trust) await moveTrust(batch, fs, 'payoutsDone', `groups/${groupId}/payouts/${pot}`);
    return batch.commit();
  };
  await t.test('un membre confirme une remise : refusé', () =>
    assertFails(payout(db('a'), 1, byPos[1])));
  await t.test('remise au mauvais bénéficiaire : refusé', () =>
    assertFails(payout(T, 1, byPos[2])));
  await t.test('remise de la cagnotte 2 avant la 1 : refusé', () =>
    assertFails(payout(T, 2, byPos[2])));
  await t.test('remise avant la fin de la collecte : refusé', () =>
    assertFails(payout(T, 1, byPos[1])));
  for (const id of ['b', 'c']) {
    await assertSucceeds(review(groupId, await declare(id, groupId, 2), true));
    await t.test(`collecte presque complète (${id}) : remise refusée`, () =>
      assertFails(payout(T, 1, byPos[1])));
    await assertSucceeds(review(groupId, await declare(id, groupId, 1), true));
  }
  await t.test('remise avec un mode inconnu : refusé', () => assertFails((() => {
    const batch = T.batch();
    batch.set(T.doc(`groups/${groupId}/payouts/1`), {
      tour: 1, beneficiaryId: byPos[1], beneficiaryName: people[byPos[1]].name,
      amount: 85500, method: 'cheque', paidAt: now(), receivedAt: null, problem: null,
    });
    batch.update(T.doc(`groups/${groupId}`), { paidOutCount: 1 });
    return batch.commit();
  })()));
  await t.test('remise sans compter dans la note de confiance : refusé', () =>
    assertFails(payout(T, 1, byPos[1], { trust: false })));
  await assertSucceeds(payout(T, 1, byPos[1]));
  await t.test('note de confiance : 1 remise', async () => {
    const tr = await adminGet('trust/t');
    if (tr.payoutsDone !== 1) throw new Error(JSON.stringify(tr));
  });
  await t.test('gonfler sa note sans remise : refusé', () =>
    assertFails(T.doc('trust/t').update({ payoutsDone: 5, last: `groups/${groupId}/payouts/1` })));
  await t.test('remise confirmée deux fois : refusé', () =>
    assertFails(payout(T, 1, byPos[1])));
  await t.test('les membres voient les remises', () =>
    assertSucceeds(db('b').collection(`groups/${groupId}/payouts`).get()));
  await t.test('une personne extérieure ne voit pas les remises', () =>
    assertFails(db('d').collection(`groups/${groupId}/payouts`).get()));

  // Groupe d'une ancienne version : lecture seule
  await t.test('ancien groupe : nouvelle déclaration refusée', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const fs = ctx.firestore();
      await fs.doc('groups/ancien').set({
        tontineId: tontine.id, tontineName: 'Tontine du marché', ownerId: 't', ownerName: 'Tontinier',
        name: 'Ancien', memberCount: 2, contributionAmount: 1000, frequency: 'weekly',
        startDate: '2026-09-01', contributionsPerPot: 2, firstPayoutDate: '2026-09-08',
        paidOutCount: 0, commissionType: 'percent', commissionValue: 0, inviteCode: 'OLD999',
        status: 'drawing', joinedCount: 2, drawnCount: 2, memberIds: ['a', 'b'],
      });
      await fs.doc('groups/ancien/members/a').set({
        fullName: 'Alice', phone: people.a.phone, drawPosition: 1,
      });
    });
    await assertFails(declare('a', 'ancien', 1));
  });
  await t.test('groupe sans durée de collecte : refusé', () =>
    assertFails(createGroup(T, tontine.id, 'BAD237', { contributionsPerPot: null })));
  await t.test('1re remise avant la 1re cotisation : refusé', () =>
    assertFails(createGroup(T, tontine.id, 'BAD238', { firstPayoutDate: '2026-10-01' })));

  // ----------------------------------------------------------- Carnet
  const carnetRef = T.collection('carnets').doc();
  const cBatch = T.batch();
  cBatch.set(carnetRef, {
    tontineId: carnetTontine.id, tontineName: 'Carnets', ownerId: 't', ownerName: 'Tontinier',
    label: 'Carnet n°1', caseAmount: 500, caseCount: 31, clientId: null, clientName: null,
    clientPhone: null, inviteCode: 'CAR234', usedCases: 0, approvedCases: 0,
    lastPaymentId: null, createdAt: now(),
  });
  cBatch.set(T.collection('invites').doc('CAR234'), { kind: 'carnet', targetId: carnetRef.id, ownerId: 't' });
  await assertSucceeds(cBatch.commit());

  const joinCarnet = (id) => db(id).doc(`carnets/${carnetRef.id}`).update({
    clientId: id, clientName: people[id].name, clientPhone: people[id].phone,
  });
  await assertSucceeds(joinCarnet('d'));
  await t.test('carnet déjà pris : refusé', () => assertFails(joinCarnet('a')));
  await t.test('A ne voit pas le carnet', () => assertFails(db('a').doc(`carnets/${carnetRef.id}`).get()));
  await t.test('« mes carnets »', () =>
    assertSucceeds(db('d').collection('carnets').where('clientId', '==', 'd').get()));

  async function declareCases(id, cases, amount) {
    const fs = db(id);
    await fs.runTransaction(async (tx) => {
      const c = (await tx.get(fs.doc(`carnets/${carnetRef.id}`))).data();
      const [pRef, pData] = proof(fs, id, 'carnet', carnetRef.id);
      tx.set(pRef, pData);
      const payRef = fs.collection(`carnets/${carnetRef.id}/payments`).doc();
      const ref = nextRef();
      tx.set(payRef, {
        userId: id, payerName: people[id].name, payerPhone: people[id].phone, caseCount: cases,
        amount: amount ?? cases * c.caseAmount, proofId: pRef.id, status: 'pending',
        rejectionReason: null, declaredAt: now(), reviewedAt: null, proofHash: ref,
      });
      tx.set(fs.doc(`paymentRefs/${ref}`), {
        payment: `carnets/${carnetRef.id}/payments/${payRef.id}`, payerId: id, ownerId: 't', at: now(),
      });
      tx.update(fs.doc(`carnets/${carnetRef.id}`), {
        usedCases: c.usedCases + cases, lastPaymentId: payRef.id,
      });
    });
  }

  await assertSucceeds(declareCases('d', 30));
  await t.test('dépasser 31 cases : refusé', () => assertFails(declareCases('d', 2)));
  await t.test('montant faux : refusé', () => assertFails(declareCases('d', 1, 100)));

  const cPays = await T.collection(`carnets/${carnetRef.id}/payments`).get();
  const cPay = cPays.docs[0];
  await t.test('validation sans mettre à jour le carnet : refusé', () =>
    assertFails(cPay.ref.update({ status: 'approved', rejectionReason: null, reviewedAt: now() })));
  await assertSucceeds((async () => {
    const batch = T.batch();
    batch.update(cPay.ref, { status: 'approved', rejectionReason: null, reviewedAt: now() });
    batch.update(T.doc(`carnets/${carnetRef.id}`), { approvedCases: 30 });
    await batch.commit();
  })());
  await assertSucceeds(declareCases('d', 1));
  const c = await adminGet(`carnets/${carnetRef.id}`);
  if (c.usedCases !== 31 || c.approvedCases !== 30) throw new Error(JSON.stringify(c));

  await t.test('non connecté : rien de lisible', () =>
    assertFails(env.unauthenticatedContext().firestore().doc(`groups/${groupId}`).get()));
});

// ------------------------------------------- Abonnement et administration

test('abonnement des tontiniers et administration', async (t) => {
  const DAY = 24 * 3600 * 1000;
  const ts = (ms) => firebase.firestore.Timestamp.fromMillis(ms);
  const account = (id, phone) =>
    env.authenticatedContext(id, { email: `${phone.slice(1)}@phone.cotizi.app` }).firestore();
  const asAdmin = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));
  const newTontine = (fs, id, name) => fs.collection('tontines').doc().set({
    ownerId: id, ownerName: name, name: 'Ma tontine', type: 'cagnotte', createdAt: now(),
  });

  // Nouveau tontinier : essai gratuit de 30 jours
  const neuf = account('neuf', '+22997000001');
  await assertSucceeds(neuf.doc('users/neuf').set({
    fullName: 'Nouveau', phone: '+22997000001', role: 'tontinier', createdAt: now(),
  }));
  await t.test('essai gratuit : création de tontine autorisée', () =>
    assertSucceeds(newTontine(neuf, 'neuf', 'Nouveau')));
  await t.test('fixer soi-même son abonnement à l\'inscription : refusé', () =>
    assertFails(account('triche', '+22997000009').doc('users/triche').set({
      fullName: 'Triche', phone: '+22997000009', role: 'tontinier', createdAt: now(),
      subscriptionEnd: ts(Date.now() + 365 * DAY),
    })));
  await t.test('prolonger soi-même son abonnement : refusé', () =>
    assertFails(neuf.doc('users/neuf').update({ subscriptionEnd: ts(Date.now() + 365 * DAY) })));

  // Tontinier inscrit il y a 31 jours : essai terminé
  const ancien = account('ancien', '+22997000002');
  await asAdmin((fs) => fs.doc('users/ancien').set({
    fullName: 'Ancien', phone: '+22997000002', role: 'tontinier',
    createdAt: ts(Date.now() - 31 * DAY),
  }));
  const vieilleTontine = 'tontine-ancien';
  await asAdmin((fs) => fs.doc(`tontines/${vieilleTontine}`).set({
    ownerId: 'ancien', ownerName: 'Ancien', name: 'Ancienne', type: 'cagnotte',
    createdAt: ts(Date.now() - 20 * DAY),
  }));
  await t.test('essai terminé : plan Gratuit, création de tontine autorisée', () =>
    assertSucceeds(newTontine(ancien, 'ancien', 'Ancien')));
  await t.test('essai terminé : son tableau de bord reste lisible', () =>
    assertSucceeds(ancien.collection('tontines').where('ownerId', '==', 'ancien').get()));

  // Administrateur (document admins/{uid} créé dans la console)
  const admin = account('adm', '+22997000003');
  await asAdmin(async (fs) => {
    await fs.doc('users/adm').set({
      fullName: 'Admin', phone: '+22997000003', role: 'tontinier',
      createdAt: ts(Date.now() - 400 * DAY),
    });
    await fs.doc('admins/adm').set({ note: 'propriétaire' });
  });
  await t.test('savoir si l\'on est administrateur', async () => {
    await assertSucceeds(admin.doc('admins/adm').get());
    await assertSucceeds(neuf.doc('admins/neuf').get());
  });
  await t.test('vérifier qu\'un compte est administrateur (accès illimité) : autorisé', () =>
    assertSucceeds(neuf.doc('admins/adm').get()));
  await t.test('lister les administrateurs : refusé', () =>
    assertFails(neuf.collection('admins').get()));
  await t.test('se déclarer administrateur : refusé', () =>
    assertFails(neuf.doc('admins/neuf').set({ note: 'moi' })));
  await t.test('l\'administrateur crée des tontines sans abonnement', () =>
    assertSucceeds(newTontine(admin, 'adm', 'Admin')));
  await t.test('l\'administrateur voit tous les comptes', () =>
    assertSucceeds(admin.collection('users').get()));
  await t.test('liste des comptes par un tontinier : refusé', () =>
    assertFails(neuf.collection('users').get()));
  await t.test('prolonger l\'abonnement d\'un autre (non administrateur) : refusé', () =>
    assertFails(neuf.doc('users/ancien').update({ subscriptionEnd: ts(Date.now() + 30 * DAY) })));

  await assertSucceeds(admin.doc('users/ancien').update({
    subscriptionEnd: ts(Date.now() + 30 * DAY),
  }));
  await t.test('abonnement prolongé : création de nouveau autorisée', () =>
    assertSucceeds(newTontine(ancien, 'ancien', 'Ancien')));
  await t.test('l\'administrateur ne modifie que l\'abonnement', () =>
    assertFails(admin.doc('users/ancien').update({ fullName: 'Autre nom' })));
  await t.test('abonnement sur un compte client : refusé', async () => {
    await asAdmin((fs) => fs.doc('users/client').set({
      fullName: 'Client', phone: '+22997000004', role: 'membre', createdAt: now(),
    }));
    await assertFails(admin.doc('users/client').update({ subscriptionEnd: ts(Date.now() + DAY) }));
  });

  // Arrêt de l'abonnement (fin = maintenant)
  await assertSucceeds(admin.doc('users/neuf').update({ subscriptionEnd: now() }));
  await t.test('abonnement arrêté : retour au plan Gratuit, création autorisée', () =>
    assertSucceeds(newTontine(neuf, 'neuf', 'Nouveau')));

  // Prix et numéro de paiement
  const settings = { monthlyPrice: 5000, paymentPhone: '+229 01 97 00 00 00' };
  await t.test('réglages de l\'abonnement par un tontinier : refusé', () =>
    assertFails(neuf.doc('settings/subscription').set(settings)));
  await assertSucceeds(admin.doc('settings/subscription').set(settings));
  await t.test('réglages lisibles par tous les comptes', () =>
    assertSucceeds(account('client', '+22997000004').doc('settings/subscription').get()));
  await t.test('prix invalide : refusé', () =>
    assertFails(admin.doc('settings/subscription').set({ ...settings, monthlyPrice: -1 })));
  await t.test('autre document de réglages : refusé', () =>
    assertFails(admin.doc('settings/autre').set(settings)));
});

// ------------------------------------------------------------ Version 2.0

test('version 2 : ordre, places réservées, démarrage, espèces, encaissement, remises, journal', async (t) => {
  const T = db('t');
  const tontine = T.collection('tontines').doc();
  await assertSucceeds(tontine.set({
    ownerId: 't', ownerName: 'Tontinier', name: 'Tontine du marché', type: 'cagnotte', createdAt: now(),
  }));

  // --- Ordre fixé par le tontinier
  const M = await createGroup(T, tontine.id, 'MAN234', { memberCount: 2, orderMode: 'manual' });
  await assertSucceeds(joinGroup('a', M));
  await assertSucceeds(joinGroup('b', M));
  const setOrder = (fs, order) => {
    const batch = fs.batch();
    order.forEach((id, i) => batch.update(fs.doc(`groups/${M}/members/${id}`), { drawPosition: i + 1 }));
    batch.update(fs.doc(`groups/${M}`), { status: 'drawing', drawnCount: 2 });
    return batch.commit();
  };
  await t.test('un membre fixe l\'ordre : refusé', () => assertFails(setOrder(db('a'), ['a', 'b'])));
  await assertSucceeds(setOrder(T, ['b', 'a']));
  await t.test('le tontinier change l\'ordre avant le démarrage', () => assertSucceeds((async () => {
    const batch = T.batch();
    batch.update(T.doc(`groups/${M}/members/a`), { drawPosition: 1 });
    batch.update(T.doc(`groups/${M}/members/b`), { drawPosition: 2 });
    await batch.commit();
  })()));

  // --- Suppression d'un groupe pas encore démarré
  await t.test('supprimer un groupe avant le démarrage', () => assertSucceeds((async () => {
    const batch = T.batch();
    batch.delete(T.doc(`groups/${M}/members/a`));
    batch.delete(T.doc(`groups/${M}/members/b`));
    batch.delete(T.doc(`groups/${M}`));
    batch.delete(T.doc('invites/MAN234'));
    await batch.commit();
  })()));

  // --- Modification et retrait pendant les inscriptions
  const P = await createGroup(T, tontine.id, 'PLA234', { memberCount: 3 });
  await assertSucceeds(joinGroup('a', P));
  await t.test('modifier les conditions pendant les inscriptions', () =>
    assertSucceeds(T.doc(`groups/${P}`).update({ contributionAmount: 2000, penaltyGraceDays: 2 })));
  await t.test('moins de places que d\'inscrits : refusé', () =>
    assertFails(T.doc(`groups/${P}`).update({ memberCount: 0 })));
  await t.test('un membre modifie le groupe : refusé', () =>
    assertFails(db('a').doc(`groups/${P}`).update({ contributionAmount: 1 })));
  await t.test('retirer un participant pendant les inscriptions', () => assertSucceeds((async () => {
    const batch = T.batch();
    batch.delete(T.doc(`groups/${P}/members/a`));
    batch.update(T.doc(`groups/${P}`), {
      joinedCount: firebase.firestore.FieldValue.increment(-1),
      memberIds: firebase.firestore.FieldValue.arrayRemove('a'),
    });
    await batch.commit();
  })()));

  // --- Participant sans application (place réservée à son numéro)
  const addManaged = (fs, id, phone, fields = {}) => {
    const batch = fs.batch();
    batch.set(fs.doc(`groups/${P}/members/${id}`), {
      fullName: 'Zoé Sans Appli', phone, joinedAt: now(), drawPosition: null, declaredCount: 0,
      approvedCount: 0, lastPaymentId: null, penaltyPaid: 0, managed: true, claimedBy: null,
      ...fields,
    });
    batch.update(fs.doc(`groups/${P}`), { joinedCount: firebase.firestore.FieldValue.increment(1) });
    return batch.commit();
  };
  await t.test('place réservée avec un identifiant différent du numéro : refusé', () =>
    assertFails(addManaged(T, 'p22900000000', people.z.phone)));
  await t.test('place réservée avec des cotisations déjà payées : refusé', () =>
    assertFails(addManaged(T, 'p22997000099', people.z.phone, { approvedCount: 3 })));
  await t.test('un client réserve une place : refusé', () =>
    assertFails(addManaged(db('a'), 'p22997000099', people.z.phone)));
  await assertSucceeds(addManaged(T, 'p22997000099', people.z.phone));
  await assertSucceeds(joinGroup('b', P));
  await assertSucceeds(joinGroup('c', P));
  await t.test('Zoé voit la place réservée à son numéro', () =>
    assertSucceeds(db('z').doc(`groups/${P}/members/p22997000099`).get()));
  await t.test('une autre personne ne voit pas cette place', () =>
    assertFails(db('d').doc(`groups/${P}/members/p22997000099`).get()));

  // Tirage : b tire, le tontinier tire pour c et la place réservée
  await assertSucceeds(T.batch()
    .update(T.doc(`groups/${P}`), { status: 'drawing' })
    .set(T.doc(`groups/${P}/draws/b`), { position: 1 })
    .set(T.doc(`groups/${P}/draws/c`), { position: 2 })
    .set(T.doc(`groups/${P}/draws/p22997000099`), { position: 3 })
    .commit());
  await assertSucceeds(drawLot('b', P));
  await assertSucceeds(T.batch()
    .update(T.doc(`groups/${P}/members/c`), { drawPosition: 2 })
    .update(T.doc(`groups/${P}/members/p22997000099`), { drawPosition: 3 })
    .update(T.doc(`groups/${P}`), { drawnCount: 3 })
    .commit());

  // Zoé s'inscrit et reprend sa place (numéro déjà attribué : place conservée)
  const claim = (id, from) => {
    const fs = db(id);
    const batch = fs.batch();
    batch.set(fs.doc(`groups/${P}/members/${id}`), {
      fullName: people[id].name, phone: people[id].phone, joinedAt: now(), drawPosition: 3,
      declaredCount: 0, approvedCount: 0, lastPaymentId: null, penaltyPaid: 0, claimedFrom: from,
    });
    batch.update(fs.doc(`groups/${P}/members/${from}`), { claimedBy: id });
    batch.update(fs.doc(`groups/${P}`), { memberIds: firebase.firestore.FieldValue.arrayUnion(id) });
    return batch.commit();
  };
  await t.test('reprendre la place d\'un autre numéro : refusé', () =>
    assertFails(claim('d', 'p22997000099')));
  await t.test('reprendre sa place avec un autre numéro tiré : refusé', async () => {
    const fs = db('z');
    const batch = fs.batch();
    batch.set(fs.doc(`groups/${P}/members/z`), {
      fullName: 'Zoé', phone: people.z.phone, joinedAt: now(), drawPosition: 1,
      declaredCount: 0, approvedCount: 0, lastPaymentId: null, penaltyPaid: 0, claimedFrom: 'p22997000099',
    });
    batch.update(fs.doc(`groups/${P}/members/p22997000099`), { claimedBy: 'z' });
    batch.update(fs.doc(`groups/${P}`), { memberIds: firebase.firestore.FieldValue.arrayUnion('z') });
    await assertFails(batch.commit());
  });
  await assertSucceeds(claim('z', 'p22997000099'));
  let gP = await adminGet(`groups/${P}`);
  if (gP.joinedCount !== 3 || !gP.memberIds.includes('z')) throw new Error(JSON.stringify(gP));

  // Démarrage
  await assertSucceeds(T.doc(`groups/${P}`).update({
    status: 'active', startDate: '2026-10-12', firstPayoutDate: '2026-10-26', startedAt: now(),
    levels: { 0: 3 },
  }));

  // --- Espèces et pénalités (2 000 F la cotisation, 500 F de pénalité)
  await t.test('espèces avec une capture : refusé', async () => {
    const fs = db('c');
    const batch = fs.batch();
    const [pRef, pData] = proof(fs, 'c', 'group', P);
    batch.set(pRef, pData);
    await batch.commit();
    await assertFails(declare('c', P, 1, { method: 'cash', proofId: pRef.id }));
  });
  await t.test('Mobile Money sans capture : refusé', () =>
    assertFails(declare('c', P, 1, { method: 'mobile_money', proofId: null })));
  await t.test('pénalité supérieure au maximum : refusé', () =>
    assertFails(declare('c', P, 1, { method: 'cash', penalty: 1000 })));
  const cash = await assertSucceeds(declare('c', P, 1, { method: 'cash', penalty: 500 }));
  const cashPay = await adminGet(`groups/${P}/payments/${cash}`);
  if (cashPay.amount !== 2500) throw new Error(`montant ${cashPay.amount}`);
  await assertSucceeds(review(P, cash, true));
  const mc = await adminGet(`groups/${P}/members/c`);
  if (mc.approvedCount !== 1 || mc.penaltyPaid !== 500) throw new Error(JSON.stringify(mc));

  // --- Le tontinier encaisse lui-même
  const record = (fs, memberId, count, fields = {}) => (async () => {
    const m = await adminGet(`groups/${P}/members/${memberId}`);
    const batch = fs.batch();
    const ref = fs.collection(`groups/${P}/payments`).doc();
    batch.set(ref, {
      userId: memberId, payerName: m.fullName, payerPhone: m.phone, count,
      amount: count * 2000, penalty: 0, method: 'cash', note: null, proofId: null,
      status: 'approved', rejectionReason: null, declaredAt: now(), reviewedAt: now(),
      recordedBy: 'owner', ...fields,
    });
    batch.update(fs.doc(`groups/${P}/members/${memberId}`), {
      declaredCount: m.declaredCount + count, approvedCount: m.approvedCount + count,
      penaltyPaid: (m.penaltyPaid ?? 0) + (fields.penalty ?? 0),
    });
    const patch = levelsPatch(await adminGet(`groups/${P}`), memberId, m.approvedCount,
      m.approvedCount + count);
    if (patch) batch.update(fs.doc(`groups/${P}`), patch);
    await batch.commit();
    return ref.id;
  })();
  await t.test('un membre « encaisse » pour lui-même : refusé', () => assertFails(record(db('b'), 'b', 1)));
  await t.test('encaisser sur une place déjà reprise : refusé', () =>
    assertFails(record(T, 'p22997000099', 1)));
  const rec = await assertSucceeds(record(T, 'z', 2));
  await t.test('Zoé voit le paiement encaissé pour elle', () =>
    assertSucceeds(db('z').doc(`groups/${P}/payments/${rec}`).get()));
  await t.test('Zoé liste ses paiements (son compte et sa place réservée)', () =>
    assertSucceeds(db('z').collection(`groups/${P}/payments`)
      .where('userId', 'in', ['z', 'p22997000099']).get()));

  // --- Remise confirmée par le tontinier puis par le bénéficiaire (rang 1 : b)
  await ensureTrust(T);
  const payoutP = async () => {
    const batch = T.batch()
      .set(T.doc(`groups/${P}/payouts/1`), {
        tour: 1, beneficiaryId: 'b', beneficiaryName: 'Bob', amount: 17100, method: 'mobile_money',
        paidAt: now(), receivedAt: null, problem: null,
      })
      .update(T.doc(`groups/${P}`), { paidOutCount: 1 });
    await moveTrust(batch, T, 'payoutsDone', `groups/${P}/payouts/1`);
    return batch.commit();
  };
  const answer = async (fs, fields, field) => {
    const batch = fs.batch().update(fs.doc(`groups/${P}/payouts/1`), fields);
    if (field) await moveTrust(batch, fs, field, `groups/${P}/payouts/1`);
    return batch.commit();
  };
  await t.test('remise : collecte incomplète, refusé', () => assertFails(payoutP()));
  await assertSucceeds(record(T, 'b', 3));
  await assertSucceeds(record(T, 'c', 2));
  await t.test('remise : il manque une cotisation de Zoé, refusé', () => assertFails(payoutP()));
  await assertSucceeds(record(T, 'z', 1));
  await assertSucceeds(payoutP());
  await t.test('un autre participant confirme la réception : refusé', () =>
    assertFails(answer(db('c'), { receivedAt: now(), problem: null }, 'payoutsConfirmed')));
  await t.test('le tontinier confirme à la place du bénéficiaire : refusé', () =>
    assertFails(answer(T, { receivedAt: now(), problem: null }, 'payoutsConfirmed')));
  await t.test('le tontinier compte une confirmation sans réception : refusé', () =>
    assertFails(answer(T, {}, 'payoutsConfirmed')));
  await t.test('signaler un problème sans le compter : refusé', () =>
    assertFails(answer(db('b'), { receivedAt: null, problem: 'Il manque 1 000 F' })));
  await assertSucceeds(answer(db('b'), { receivedAt: null, problem: 'Il manque 1 000 F' }, 'payoutsDisputed'));
  await t.test('confirmer sans le compter : refusé', () =>
    assertFails(answer(db('b'), { receivedAt: now(), problem: null })));
  await assertSucceeds(answer(db('b'), { receivedAt: now(), problem: null }, 'payoutsConfirmed'));
  await t.test('note de confiance : remise, problème signalé, réception confirmée', async () => {
    const tr = await adminGet('trust/t');
    if (tr.payoutsConfirmed !== 1 || tr.payoutsDisputed !== 1) throw new Error(JSON.stringify(tr));
  });
  await t.test('tout le monde lit la note de confiance', () =>
    assertSucceeds(db('d').doc('trust/t').get()));
  await t.test('changer sa confirmation : refusé', () =>
    assertFails(db('b').doc(`groups/${P}/payouts/1`).update({ receivedAt: null, problem: 'Non' })));

  // --- Journal
  const event = (fs, actor, fields = {}) => fs.collection(`groups/${P}/events`).doc().set({
    type: 'payment', text: 'Paiement déclaré', actorId: actor, actorName: 'X', memberId: actor,
    visibility: 'member', at: now(), ...fields,
  });
  await assertSucceeds(event(T, 't', { visibility: 'all', memberId: null, type: 'started', text: 'Tontine démarrée' }));
  await assertSucceeds(event(db('c'), 'c'));
  await t.test('écrire au nom d\'un autre : refusé', () => assertFails(event(db('c'), 'b')));
  await t.test('une personne extérieure écrit dans le journal : refusé', () => assertFails(event(db('d'), 'd')));
  await t.test('un membre lit les étapes du groupe', () =>
    assertSucceeds(db('b').collection(`groups/${P}/events`).where('visibility', '==', 'all').get()));
  await t.test('un membre lit ses propres actions', () =>
    assertSucceeds(db('c').collection(`groups/${P}/events`).where('memberId', '==', 'c').get()));
  await t.test('un membre lit tout le journal : refusé', () =>
    assertFails(db('b').collection(`groups/${P}/events`).get()));
  await t.test('le tontinier lit tout le journal', () =>
    assertSucceeds(T.collection(`groups/${P}/events`).get()));
  await t.test('modifier le journal : refusé', async () => {
    const ev = (await T.collection(`groups/${P}/events`).get()).docs[0];
    await assertFails(ev.ref.update({ text: 'autre' }));
  });

  // --- Profil pro
  const biz = (fs, id, fields = {}) => fs.doc(`businesses/${id}`).set({
    name: 'Tontines Mama Awa', city: 'Cotonou', contactPhone: '+229 01 97 00 00 00',
    logo: null, logoMime: null,
    accounts: [{ operator: 'MTN MoMo', number: '+229 01 97 00 00 00', holder: 'Awa' }],
    updatedAt: now(), ...fields,
  });
  await assertSucceeds(biz(T, 't'));
  await t.test('un client lit le profil pro du tontinier', () =>
    assertSucceeds(db('c').doc('businesses/t').get()));
  await t.test('modifier le profil pro d\'un autre : refusé', () => assertFails(biz(db('c'), 't')));
  await t.test('plus de 3 numéros de paiement : refusé', () =>
    assertFails(biz(T, 't', { accounts: [{}, {}, {}, {}] })));

  // --- Place reprise pendant les inscriptions : la place réservée est remplacée
  const Q = await createGroup(T, tontine.id, 'QQQ234', { memberCount: 2 });
  await assertSucceeds(T.batch()
    .set(T.doc(`groups/${Q}/members/p22997000098`), {
      fullName: 'Emma Sans Appli', phone: people.e.phone, joinedAt: now(), drawPosition: null,
      declaredCount: 0, approvedCount: 0, lastPaymentId: null, penaltyPaid: 0, managed: true,
      claimedBy: null,
    })
    .update(T.doc(`groups/${Q}`), { joinedCount: firebase.firestore.FieldValue.increment(1) })
    .commit());
  await t.test('reprendre sa place pendant les inscriptions', () => assertSucceeds((async () => {
    const fs = db('e');
    const batch = fs.batch();
    batch.set(fs.doc(`groups/${Q}/members/e`), {
      fullName: 'Emma', phone: people.e.phone, joinedAt: now(), drawPosition: null,
      declaredCount: 0, approvedCount: 0, lastPaymentId: null, penaltyPaid: 0,
      claimedFrom: 'p22997000098',
    });
    batch.delete(fs.doc(`groups/${Q}/members/p22997000098`));
    batch.update(fs.doc(`groups/${Q}`), { memberIds: firebase.firestore.FieldValue.arrayUnion('e') });
    await batch.commit();
  })()));
  const gQ = await adminGet(`groups/${Q}`);
  if (gQ.joinedCount !== 1 || !gQ.memberIds.includes('e')) throw new Error(JSON.stringify(gQ));

  // --- Carnet : espèces et encaissement
  const carnetTontine = T.collection('tontines').doc();
  await assertSucceeds(carnetTontine.set({
    ownerId: 't', ownerName: 'Tontinier', name: 'Carnets', type: 'carnet', createdAt: now(),
  }));
  const cRef = T.collection('carnets').doc();
  await assertSucceeds(T.batch().set(cRef, {
    tontineId: carnetTontine.id, tontineName: 'Carnets', ownerId: 't', ownerName: 'Tontinier',
    label: 'Carnet n°2', caseAmount: 500, caseCount: 31, clientId: null, clientName: null,
    clientPhone: null, inviteCode: 'CAR345', usedCases: 0, approvedCases: 0,
    lastPaymentId: null, createdAt: now(),
  }).set(T.collection('invites').doc('CAR345'), { kind: 'carnet', targetId: cRef.id, ownerId: 't' }).commit());
  await assertSucceeds(db('e').doc(`carnets/${cRef.id}`).update({
    clientId: 'e', clientName: 'Emma', clientPhone: people.e.phone,
  }));
  const fsE = db('e');
  await t.test('le client déclare des cases en espèces (sans capture)', () =>
    assertSucceeds(fsE.runTransaction(async (tx) => {
      const fs = fsE;
      const c = (await tx.get(fs.doc(`carnets/${cRef.id}`))).data();
      const payRef = fs.collection(`carnets/${cRef.id}/payments`).doc();
      tx.set(payRef, {
        userId: 'e', payerName: 'Emma', payerPhone: people.e.phone, caseCount: 2, amount: 1000,
        method: 'cash', note: null, proofId: null, status: 'pending', rejectionReason: null,
        declaredAt: now(), reviewedAt: null, recordedBy: 'member',
      });
      tx.update(fs.doc(`carnets/${cRef.id}`), { usedCases: c.usedCases + 2, lastPaymentId: payRef.id });
    })));
  const recordCases = (fs) => (async () => {
    const c = await adminGet(`carnets/${cRef.id}`);
    const batch = fs.batch();
    batch.set(fs.collection(`carnets/${cRef.id}/payments`).doc(), {
      userId: 'e', payerName: 'Emma', payerPhone: people.e.phone, caseCount: 3, amount: 1500,
      method: 'cash', note: 'Au marché', proofId: null, status: 'approved', rejectionReason: null,
      declaredAt: now(), reviewedAt: now(), recordedBy: 'owner',
    });
    batch.update(fs.doc(`carnets/${cRef.id}`), {
      usedCases: c.usedCases + 3, approvedCases: c.approvedCases + 3,
    });
    await batch.commit();
  })();
  await t.test('le client « encaisse » lui-même : refusé', () => assertFails(recordCases(db('e'))));
  await t.test('le tontinier encaisse des cases', () => assertSucceeds(recordCases(T)));
});


test('version 2.2 : règlement accepté, pénalité en pourcentage, demandes d\'abonnement', async (t) => {
  const T = db('t');
  const tontine = T.collection('tontines').doc();
  await assertSucceeds(tontine.set({
    ownerId: 't', ownerName: 'Tontinier', name: 'Tontine du marché', type: 'cagnotte', createdAt: now(),
  }));
  const terms = {
    memberCount: 2, orderMode: 'manual', contributionAmount: 5000,
    penaltyType: 'percent', penaltyAmount: 10, penaltyGraceDays: 2,
    rulesText: 'Cotisation à payer avant 18 h.', termsVersion: 1, accepted: {},
  };
  await t.test('pénalité de plus de 100 % : refusé', () =>
    assertFails(createGroup(T, tontine.id, 'PCT234', { ...terms, penaltyAmount: 150 })));
  await t.test('règlement trop long : refusé', () =>
    assertFails(createGroup(T, tontine.id, 'PCT235', { ...terms, rulesText: 'x'.repeat(2001) })));
  await t.test('groupe créé avec des accords déjà remplis : refusé', () =>
    assertFails(createGroup(T, tontine.id, 'PCT236', { ...terms, accepted: { a: 1 } })));
  const R = await createGroup(T, tontine.id, 'REG222', terms);
  await assertSucceeds(joinGroup('a', R));
  await assertSucceeds(joinGroup('b', R));
  const accept = (id, version, who = id) =>
    db(who).doc(`groups/${R}`).update({ [`accepted.${id}`]: version });

  await t.test('accepter à la place d\'un autre : refusé', () => assertFails(accept('b', 1, 'a')));
  await t.test('accepter une autre version : refusé', () => assertFails(accept('a', 2)));
  await t.test('une personne extérieure accepte : refusé', () => assertFails(accept('c', 1)));
  await assertSucceeds(accept('a', 1));
  await t.test('changer les montants sans nouvelle version : refusé', () =>
    assertFails(T.doc(`groups/${R}`).update({ contributionAmount: 6000 })));
  await t.test('changer le règlement sans nouvelle version : refusé', () =>
    assertFails(T.doc(`groups/${R}`).update({ rulesText: 'Autre règle' })));
  await assertSucceeds(T.doc(`groups/${R}`).update({ contributionAmount: 6000, termsVersion: 2 }));
  await t.test('changer seulement le nom : même version', () =>
    assertSucceeds(T.doc(`groups/${R}`).update({ name: 'Groupe R' })));

  // Ordre fixé puis démarrage
  const order = T.batch();
  order.update(T.doc(`groups/${R}/members/a`), { drawPosition: 1 });
  order.update(T.doc(`groups/${R}/members/b`), { drawPosition: 2 });
  order.update(T.doc(`groups/${R}`), { status: 'drawing', drawnCount: 2 });
  await assertSucceeds(order.commit());
  const start = () => T.doc(`groups/${R}`).update({
    status: 'active', startDate: '2026-10-12', firstPayoutDate: '2026-10-13', startedAt: now(),
    levels: { 0: 2 },
  });
  await t.test('démarrer sans l\'accord de tous : refusé', () => assertFails(start()));
  await assertSucceeds(accept('b', 2));
  await t.test('démarrer avec un accord d\'une ancienne version : refusé', () => assertFails(start()));
  await assertSucceeds(accept('a', 2));
  await assertSucceeds(start());
  await t.test('accepter après le démarrage : refusé', () => assertFails(accept('a', 3)));

  // Pénalité de 10 % de la cotisation (6 000 F) : 600 F au plus par cotisation
  await t.test('pénalité au-delà de 10 % : refusé', () =>
    assertFails(declare('a', R, 1, { method: 'cash', penalty: 700 })));
  await assertSucceeds(declare('a', R, 1, { method: 'cash', penalty: 600 }));

  // Retrait d'un participant : son accord est effacé, pas celui des autres
  const Q = await createGroup(T, tontine.id, 'RET222', { ...terms, memberCount: 3 });
  await assertSucceeds(joinGroup('a', Q));
  await assertSucceeds(joinGroup('b', Q));
  await assertSucceeds(db('a').doc(`groups/${Q}`).update({ 'accepted.a': 1 }));
  await assertSucceeds(db('b').doc(`groups/${Q}`).update({ 'accepted.b': 1 }));
  const remove = (who, erase) => {
    const batch = T.batch();
    batch.delete(T.doc(`groups/${Q}/members/${who}`));
    batch.update(T.doc(`groups/${Q}`), {
      joinedCount: firebase.firestore.FieldValue.increment(-1),
      memberIds: firebase.firestore.FieldValue.arrayRemove(who),
      [`accepted.${erase}`]: firebase.firestore.FieldValue.delete(),
    });
    return batch.commit();
  };
  await t.test('effacer l\'accord d\'un autre participant : refusé', () => assertFails(remove('a', 'b')));
  await assertSucceeds(remove('a', 'a'));

  // Demandes d'abonnement
  const request = (id, fields = {}) => db(id).doc(`subscriptionRequests/${id}`).set({
    fullName: people[id].name, phone: people[id].phone, months: 3, amount: 15000,
    requestedAt: now(), ...fields,
  });
  await assertSucceeds(request('t'));
  await t.test('demande pour une durée non proposée : refusé', () =>
    assertFails(request('t', { months: 2 })));
  await t.test('demande avec un autre nom : refusé', () =>
    assertFails(request('t', { fullName: 'Autre' })));
  await t.test('un client demande un abonnement : refusé', () => assertFails(request('a')));
  await t.test('lire la demande d\'un autre : refusé', () =>
    assertFails(db('b').doc('subscriptionRequests/t').get()));
  const admin = env.authenticatedContext('adm', { email: '22997000003@phone.cotizi.app' }).firestore();
  await t.test('l\'administrateur voit les demandes', () =>
    assertSucceeds(admin.collection('subscriptionRequests').get()));
  await t.test('l\'administrateur supprime une demande traitée', () =>
    assertSucceeds(admin.doc('subscriptionRequests/t').delete()));
  await t.test('numéro d\'assistance dans les réglages', () =>
    assertSucceeds(admin.doc('settings/subscription').set({
      monthlyPrice: 5000, paymentPhone: '+22901000000', supportPhone: '+22901000001',
    })));
  await t.test('e-mail et horaires de l\'assistance dans les réglages', () =>
    assertSucceeds(admin.doc('settings/subscription').set({
      monthlyPrice: 5000, paymentPhone: '+22901000000', supportPhone: '+22901000001',
      supportEmail: 'assistance@cotizi.app', supportHours: 'du lundi au vendredi (9 h 00 - 17 h 00)',
    })));
  await t.test('prix Business et limites du plan Gratuit dans les réglages', () =>
    assertSucceeds(admin.doc('settings/subscription').set({
      monthlyPrice: 3000, paymentPhone: '+22901000000', businessPrice: 15000,
      freeGroups: 2, freeCarnets: 3, freeClients: 30,
    })));
  await t.test('limite négative : refusé', () =>
    assertFails(admin.doc('settings/subscription').set({
      monthlyPrice: 3000, paymentPhone: '+22901000000', freeGroups: -1,
    })));
  await t.test('un tontinier règle les limites : refusé', () =>
    assertFails(db('t').doc('settings/subscription').set({
      monthlyPrice: 0, paymentPhone: '', freeGroups: 999,
    })));
  await t.test('horaires trop longs : refusé', () =>
    assertFails(admin.doc('settings/subscription').set({
      monthlyPrice: 5000, paymentPhone: '+22901000000', supportHours: 'x'.repeat(200),
    })));
});

test('notifications (cloche)', async (t) => {
  const T = db('t');
  const tontine = T.collection('tontines').doc();
  await assertSucceeds(tontine.set({
    ownerId: 't', ownerName: 'Tontinier', name: 'Tontine du marché', type: 'cagnotte', createdAt: now(),
  }));
  const G = await createGroup(T, tontine.id, 'NOT234', { memberCount: 3 });
  await assertSucceeds(joinGroup('a', G));
  const notify = (from, to, fields = {}) => db(from).collection(`users/${to}/notifications`).add({
    type: 'payment_declared', title: 'Paiement à valider', body: 'Alice : 1 cotisation',
    groupId: G, carnetId: null, actorId: from, actorName: people[from].name, read: false, at: now(),
    ...fields,
  });
  await t.test('un client prévient son tontinier', () => assertSucceeds(notify('a', 't')));
  await t.test('le tontinier prévient un client du groupe', () =>
    assertSucceeds(notify('t', 'a', { actorName: 'Tontinier', type: 'payment_approved' })));
  await t.test('prévenir quelqu\'un hors du groupe : refusé', () => assertFails(notify('a', 'c')));
  await t.test('une personne extérieure écrit au tontinier : refusé', () => assertFails(notify('c', 't')));
  await t.test('se faire passer pour un autre : refusé', () =>
    assertFails(notify('a', 't', { actorId: 'b' })));
  await t.test('le tontinier lit ses notifications', () =>
    assertSucceeds(T.collection('users/t/notifications').where('read', '==', false).get()));
  await t.test('lire les notifications d\'un autre : refusé', () =>
    assertFails(db('a').collection('users/t/notifications').get()));
  const list = await T.collection('users/t/notifications').get();
  await t.test('marquer comme lue', () => assertSucceeds(list.docs[0].ref.update({ read: true })));
  await t.test('modifier le texte : refusé', () => assertFails(list.docs[0].ref.update({ title: 'x' })));
});

test('version 2.4 : référence Mobile Money utilisable une seule fois', async (t) => {
  const T = db('t');
  const tontine = T.collection('tontines').doc();
  await assertSucceeds(tontine.set({
    ownerId: 't', ownerName: 'Tontinier', name: 'Tontine du marché', type: 'cagnotte', createdAt: now(),
  }));
  const G = await createGroup(T, tontine.id, 'REF234', { memberCount: 2 });
  await assertSucceeds(joinGroup('a', G));
  await assertSucceeds(joinGroup('b', G));
  await startDraw(G, ['a', 'b']);
  await drawLot('a', G);
  await drawLot('b', G);
  await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc(`groups/${G}`).update({
    status: 'active', startedAt: new Date(), levels: { '0': 2 },
  }));
  await t.test('Mobile Money sans empreinte de capture : refusé', () =>
    assertFails(declare('a', G, 1, { proofHash: null })));
  await t.test('empreinte de capture non enregistrée : refusé', () =>
    assertFails(declare('a', G, 1, { proofHash: 'IMGABCDEF01', registerHash: false })));
  const pHash = await assertSucceeds(declare('a', G, 1, { proofHash: 'IMGABCDEF01' }));
  await t.test('la même capture une 2e fois : refusé', () =>
    assertFails(declare('b', G, 1, { proofHash: 'IMGABCDEF01' })));
  // Paiement refusé : l'empreinte est libérée
  const mh = await adminGet(`groups/${G}/members/a`);
  await assertSucceeds(T.batch()
    .update(T.doc(`groups/${G}/payments/${pHash}`), {
      status: 'rejected', rejectionReason: 'Capture illisible', reviewedAt: now(),
    })
    .update(T.doc(`groups/${G}/members/a`), { declaredCount: mh.declaredCount - 1 })
    .delete(T.doc('paymentRefs/IMGABCDEF01'))
    .commit());
  await t.test('Mobile Money sans référence (facultative) : accepté', () =>
    assertSucceeds(declare('b', G, 1)));
  const mb = await adminGet(`groups/${G}/members/b`);
  const pb = (await T.collection(`groups/${G}/payments`).where('userId', '==', 'b').get()).docs[0];
  await assertSucceeds(T.batch()
    .update(pb.ref, { status: 'rejected', rejectionReason: 'Test', reviewedAt: now() })
    .update(T.doc(`groups/${G}/members/b`), { declaredCount: mb.declaredCount - 1 })
    .delete(T.doc(`paymentRefs/${pb.data().proofHash}`))
    .commit());
  await t.test('référence mal écrite : refusé', () =>
    assertFails(declare('a', G, 1, { reference: 'ab 12' })));
  await t.test('référence non enregistrée : refusé', () =>
    assertFails(declare('a', G, 1, { reference: 'MP240101', registerRef: false })));
  const p1 = await assertSucceeds(declare('a', G, 1, { reference: 'MP240101' }));
  await t.test('la même référence une 2e fois : refusé', () =>
    assertFails(declare('a', G, 1, { reference: 'MP240101' })));
  await t.test('la référence d\'un autre client : refusé', () =>
    assertFails(declare('b', G, 1, { reference: 'MP240101' })));
  await t.test('une référence libre se vérifie', () =>
    assertSucceeds(db('b').doc('paymentRefs/MP999999').get()));
  await t.test('une référence prise par un autre ne se lit pas', () =>
    assertFails(db('b').doc('paymentRefs/MP240101').get()));
  await t.test('le payeur lit sa référence', () =>
    assertSucceeds(db('a').doc('paymentRefs/MP240101').get()));
  await t.test('effacer une référence d\'un paiement en attente : refusé', () =>
    assertFails(T.doc('paymentRefs/MP240101').delete()));
  await t.test('le client efface sa référence : refusé', () =>
    assertFails(db('a').doc('paymentRefs/MP240101').delete()));
  await t.test('référence pour un paiement inexistant : refusé', () =>
    assertFails(db('a').doc('paymentRefs/MP777777').set({
      payment: `groups/${G}/payments/inconnu`, payerId: 'a', ownerId: 't', at: now(),
    })));
  // Refus du tontinier : la référence est libérée dans le même envoi
  const m = await adminGet(`groups/${G}/members/a`);
  await assertSucceeds(T.batch()
    .update(T.doc(`groups/${G}/payments/${p1}`), {
      status: 'rejected', rejectionReason: 'Montant incorrect', reviewedAt: now(),
    })
    .update(T.doc(`groups/${G}/members/a`), { declaredCount: m.declaredCount - 1 })
    .delete(T.doc('paymentRefs/MP240101'))
    .commit());
  await t.test('après refus, la référence peut être redéclarée', () =>
    assertSucceeds(declare('a', G, 1, { reference: 'MP240101' })));
  await t.test('espèces avec une référence : refusé', () =>
    assertFails(declare('b', G, 1, { method: 'cash', reference: 'MP555555' })));
  await t.test('créer une note de confiance gonflée : refusé', () =>
    assertFails(db('z').doc('trust/z').set({
      payoutsDone: 10, payoutsConfirmed: 10, payoutsDisputed: 0, last: null,
    })));
});

test('version 2.5 : remboursement du carnet, clôture du groupe', async (t) => {
  const T = db('t');
  const ct = T.collection('tontines').doc();
  await assertSucceeds(ct.set({
    ownerId: 't', ownerName: 'Tontinier', name: 'Carnets', type: 'carnet', createdAt: now(),
  }));
  const cRef = T.collection('carnets').doc();
  await assertSucceeds(T.batch().set(cRef, {
    tontineId: ct.id, tontineName: 'Carnets', ownerId: 't', ownerName: 'Tontinier',
    label: 'Carnet R', caseAmount: 300, caseCount: 31, clientId: null, clientName: null,
    clientPhone: null, inviteCode: 'RMB234', usedCases: 0, approvedCases: 0,
    lastPaymentId: null, createdAt: now(),
  }).set(T.collection('invites').doc('RMB234'), { kind: 'carnet', targetId: cRef.id, ownerId: 't' }).commit());
  await assertSucceeds(db('a').doc(`carnets/${cRef.id}`).update({
    clientId: 'a', clientName: 'Alice', clientPhone: people.a.phone,
  }));
  const record = (cases) => (async () => {
    const c = await adminGet(`carnets/${cRef.id}`);
    await T.batch()
      .set(T.collection(`carnets/${cRef.id}/payments`).doc(), {
        userId: 'a', payerName: 'Alice', payerPhone: people.a.phone, caseCount: cases,
        amount: cases * 300, method: 'cash', note: null, proofId: null, status: 'approved',
        rejectionReason: null, declaredAt: now(), reviewedAt: now(), recordedBy: 'owner',
      })
      .update(T.doc(`carnets/${cRef.id}`), {
        usedCases: c.usedCases + cases, approvedCases: c.approvedCases + cases,
      })
      .commit();
  })();
  const ask = (id) => db(id).doc(`carnets/${cRef.id}`).update({
    status: 'refund_requested', refundRequestedAt: now(),
  });
  const close = (fs, amount) => fs.doc(`carnets/${cRef.id}`).update({
    status: 'closed', closedAt: now(), refundAmount: amount,
  });
  await t.test('remboursement demandé sans case payée : refusé', () => assertFails(ask('a')));
  await assertSucceeds(record(20));
  await t.test('clôturer un carnet en cours sans demande : refusé', () =>
    assertFails(close(T, 19 * 300)));
  await t.test('le tontinier demande à la place du client : refusé', () => assertFails(ask('t')));
  await assertSucceeds(ask('a'));
  await t.test('encaisser après la demande : refusé', () => assertFails(record(1)));
  await t.test('le client clôture lui-même : refusé', () => assertFails(close(db('a'), 19 * 300)));
  await t.test('rembourser 20 cases (sans commission) : refusé', () =>
    assertFails(close(T, 20 * 300)));
  await t.test('le tontinier rembourse 19 cases et clôture', () =>
    assertSucceeds(close(T, 19 * 300)));
  await t.test('déclarer sur un carnet clôturé : refusé', () =>
    assertFails(db('a').doc(`carnets/${cRef.id}`).update({ usedCases: 21, lastPaymentId: 'x' })));

  // Groupe : clôture quand toutes les cagnottes sont remises
  const tontine = T.collection('tontines').doc();
  await assertSucceeds(tontine.set({
    ownerId: 't', ownerName: 'Tontinier', name: 'Tontine du marché', type: 'cagnotte', createdAt: now(),
  }));
  const G = await createGroup(T, tontine.id, 'CLO234', { memberCount: 2 });
  await assertSucceeds(joinGroup('a', G));
  await assertSucceeds(joinGroup('b', G));
  await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc(`groups/${G}`).update({
    status: 'active', startedAt: new Date(), paidOutCount: 1,
  }));
  const closeGroup = (fs) => fs.doc(`groups/${G}`).update({ status: 'closed', closedAt: now() });
  await t.test('clôturer avant la dernière remise : refusé', () => assertFails(closeGroup(T)));
  await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc(`groups/${G}`).update({ paidOutCount: 2 }));
  await t.test('un participant clôture le groupe : refusé', () => assertFails(closeGroup(db('a'))));
  await t.test('le tontinier clôture le groupe terminé', () => assertSucceeds(closeGroup(T)));
});

test('version 3.0 : abonnement terminé, plan Gratuit, l\'activité continue', async (t) => {
  const T = db('t');
  const tontine = T.collection('tontines').doc();
  await assertSucceeds(tontine.set({
    ownerId: 't', ownerName: 'Tontinier', name: 'Tontine du marché', type: 'cagnotte', createdAt: now(),
  }));
  const G = await createGroup(T, tontine.id, 'EXP234', { memberCount: 2, contributionsPerPot: 1 });
  await assertSucceeds(joinGroup('a', G));
  await assertSucceeds(joinGroup('b', G));
  await env.withSecurityRulesDisabled(async (ctx) => {
    const fs = ctx.firestore();
    await fs.doc(`groups/${G}`).update({ status: 'active', startedAt: new Date(), levels: { '0': 2 } });
    await fs.doc(`groups/${G}/members/a`).update({ drawPosition: 1 });
    await fs.doc(`groups/${G}/members/b`).update({ drawPosition: 2 });
    await fs.doc(`groups/${G}/payouts/1`).set({
      tour: 1, beneficiaryId: 'a', beneficiaryName: 'Alice', amount: 1000, method: 'cash',
      paidAt: new Date(), receivedAt: null, problem: null,
    });
    await fs.doc(`groups/${G}`).update({ paidOutCount: 1 });
  });
  await ensureTrust(T);
  await t.test('abonnement actif : le client déclare', () => assertSucceeds(declare('a', G, 1, { method: 'cash' })));

  // Carnet d'un client avec 5 cases payées
  const cRef = T.collection('carnets').doc();
  await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc(`carnets/${cRef.id}`).set({
    tontineId: 'x', tontineName: 'Carnets', ownerId: 't', ownerName: 'Tontinier', label: 'Carnet E',
    caseAmount: 500, caseCount: 31, clientId: 'b', clientName: 'Bob', clientPhone: people.b.phone,
    inviteCode: 'EXC234', usedCases: 5, approvedCases: 5, lastPaymentId: null, createdAt: new Date(),
  }));

  // L'abonnement du tontinier expire
  await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('users/t').update({
    subscriptionEnd: new Date(Date.now() - 86400000),
  }));
  await t.test('le client lit le profil de son tontinier (fin d\'abonnement)', () =>
    assertSucceeds(db('a').doc('users/t').get()));
  await t.test('lire le profil d\'un autre client : refusé', () =>
    assertFails(db('a').doc('users/b').get()));
  await t.test('expiré (plan Gratuit) : le client déclare toujours', () =>
    assertSucceeds(declare('b', G, 1, { method: 'cash' })));
  await t.test('expiré : le bénéficiaire peut encore confirmer sa cagnotte', async () => {
    const tr = await adminGet('trust/t');
    const fa = db('a');
    await assertSucceeds(fa.batch()
      .update(fa.doc(`groups/${G}/payouts/1`), { receivedAt: now(), problem: null })
      .update(fa.doc('trust/t'), {
        payoutsConfirmed: (tr.payoutsConfirmed ?? 0) + 1, last: `groups/${G}/payouts/1`,
      })
      .commit());
  });
  await t.test('expiré : le client peut demander le remboursement du carnet', () =>
    assertSucceeds(db('b').doc(`carnets/${cRef.id}`).update({
      status: 'refund_requested', refundRequestedAt: now(),
    })));
  await t.test('expiré : le tontinier peut rembourser et clôturer', () =>
    assertSucceeds(T.doc(`carnets/${cRef.id}`).update({
      status: 'closed', closedAt: now(), refundAmount: 4 * 500,
    })));

  // L'administrateur réactive l'abonnement : tout reprend
  await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('users/t').update({
    subscriptionEnd: new Date(Date.now() + 30 * 86400000),
  }));
  await t.test('abonnement réactivé : le client déclare de nouveau', () =>
    assertSucceeds(declare('b', G, 1, { method: 'cash' })));
});

test('version 2.7 : suggestions pour améliorer COTIZI', async (t) => {
  const suggest = (id, fields = {}) => db(id).collection('suggestions').add({
    userId: id, fullName: people[id].name, phone: people[id].phone,
    role: id === 't' ? 'tontinier' : 'membre', kind: 'idee',
    text: 'Ajouter un rappel par SMS', status: 'new', createdAt: now(), ...fields,
  });
  const ref = await assertSucceeds(suggest('t'));
  await t.test('un client aussi peut faire une suggestion', () => assertSucceeds(suggest('a')));
  await t.test('suggestion au nom d\'un autre : refusé', () => assertFails(suggest('t', { userId: 'a' })));
  await t.test('texte trop court : refusé', () => assertFails(suggest('t', { text: 'ok' })));
  await t.test('catégorie inconnue : refusé', () => assertFails(suggest('t', { kind: 'spam' })));
  await t.test('déjà « traitée » à la création : refusé', () => assertFails(suggest('t', { status: 'done' })));
  await t.test('le tontinier relit sa suggestion', () => assertSucceeds(ref.get()));
  await t.test('lire la suggestion d\'un autre : refusé', () =>
    assertFails(db('b').doc(`suggestions/${ref.id}`).get()));
  await t.test('modifier sa suggestion : refusé', () => assertFails(ref.update({ status: 'done' })));
  const admin = env.authenticatedContext('adm', { email: '22997000003@phone.cotizi.app' }).firestore();
  await t.test('l\'administrateur lit toutes les suggestions', () =>
    assertSucceeds(admin.collection('suggestions').get()));
  await t.test('l\'administrateur la marque comme lue', () =>
    assertSucceeds(admin.doc(`suggestions/${ref.id}`).update({ status: 'read' })));
  await t.test('l\'administrateur la supprime', () =>
    assertSucceeds(admin.doc(`suggestions/${ref.id}`).delete()));
});

test('version 3.1 : comptabilité (dépenses) et badge vérifié du plan Pro', async (t) => {
  let tProfile;
  await env.withSecurityRulesDisabled(async (ctx) => {
    tProfile = (await ctx.firestore().doc('users/t').get()).data();
  });
  const expense = (id, fields = {}) => db(id).collection('expenses').add({
    ownerId: id, label: 'Transport au marché', amount: 1500, category: 'transport',
    date: firebase.firestore.Timestamp.fromDate(new Date()), createdAt: now(), ...fields,
  });
  const exp = await assertSucceeds(expense('t'));
  await t.test('le tontinier relit sa dépense', () => assertSucceeds(exp.get()));
  await t.test('dépense lue par un autre : refusé', () =>
    assertFails(db('a').doc(`expenses/${exp.id}`).get()));
  await t.test('dépense au nom d\'un autre : refusé', () => assertFails(expense('t', { ownerId: 'a' })));
  await t.test('montant négatif : refusé', () => assertFails(expense('t', { amount: -5 })));
  await t.test('catégorie inconnue : refusé', () => assertFails(expense('t', { category: 'luxe' })));
  await t.test('un client ne note pas de dépense', () => assertFails(expense('a')));
  await t.test('modifier une dépense : refusé', () => assertFails(exp.update({ amount: 1 })));
  await t.test('le tontinier supprime sa dépense', () => assertSucceeds(exp.delete()));

  // Badge vérifié
  const fs = db('t');
  const photo = (kind, fields = {}) =>
    fs.doc(`verifications/t/photos/${kind}`).set({ data: 'aGVsbG8=', mime: 'image/jpeg', ...fields });
  const request = (fields = {}) => fs.doc('verifications/t').set({
    fullName: tProfile.fullName, phone: tProfile.phone, idType: 'cni',
    status: 'pending', submittedAt: now(), ...fields,
  });
  await t.test('demande sans photos : refusé', () => assertFails(request()));
  await t.test('photo d\'un type inconnu : refusé', () => assertFails(photo('autre')));
  await t.test('photo pour un autre : refusé', () =>
    assertFails(db('a').doc('verifications/t/photos/id').set({ data: 'x', mime: 'image/jpeg' })));
  await assertSucceeds(photo('id'));
  await assertSucceeds(photo('selfie'));
  await t.test('demande déjà « acceptée » par le tontinier : refusé', () =>
    assertFails(request({ status: 'approved' })));
  await t.test('demande au nom d\'un autre : refusé', () => assertFails(request({ fullName: 'Faux' })));
  await t.test('demande complète : acceptée', () => assertSucceeds(request()));
  await t.test('un autre ne voit pas les photos', () =>
    assertFails(db('a').doc('verifications/t/photos/id').get()));
  await t.test('le tontinier se donne le badge : refusé', () =>
    assertFails(fs.doc('badges/t').set({ fullName: tProfile.fullName, verifiedAt: now() })));

  const admin = env.authenticatedContext('adm', { email: '22997000003@phone.cotizi.app' }).firestore();
  await t.test('l\'administrateur voit les demandes et les photos', async () => {
    await assertSucceeds(admin.collection('verifications').where('status', '==', 'pending').get());
    await assertSucceeds(admin.doc('verifications/t/photos/selfie').get());
  });
  await t.test('badge sans demande acceptée : refusé', () =>
    assertFails(admin.doc('badges/t').set({ fullName: tProfile.fullName, verifiedAt: now() })));
  await t.test('refus sans raison : refusé', () =>
    assertFails(admin.doc('verifications/t').update({ status: 'rejected', decidedAt: now() })));
  await t.test('acceptation : badge donné, photos effacées', async () => {
    const batch = admin.batch();
    batch.update(admin.doc('verifications/t'), { status: 'approved', decidedAt: now() });
    batch.set(admin.doc('badges/t'), { fullName: tProfile.fullName, verifiedAt: now() });
    batch.delete(admin.doc('verifications/t/photos/id'));
    batch.delete(admin.doc('verifications/t/photos/selfie'));
    await assertSucceeds(batch.commit());
  });
  await t.test('le badge est visible des clients', () => assertSucceeds(db('a').doc('badges/t').get()));
  await t.test('un client supprime le badge : refusé', () => assertFails(db('a').doc('badges/t').delete()));
  await t.test('l\'administrateur retire le badge', () => assertSucceeds(admin.doc('badges/t').delete()));
});
