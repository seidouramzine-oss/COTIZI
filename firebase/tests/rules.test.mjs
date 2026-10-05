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
    commissionType: 'percent',
    commissionValue: 5,
    inviteCode: code,
    status: 'recruiting',
    joinedCount: 0,
    drawnCount: 0,
    memberIds: [],
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

async function declarePayment(id, groupId, tour, { update = false } = {}) {
  const fs = db(id);
  const batch = fs.batch();
  const [pRef, pData] = proof(fs, id, 'group', groupId);
  batch.set(pRef, pData);
  const ref = fs.doc(`groups/${groupId}/payments/${id}_${tour}`);
  if (update) {
    batch.update(ref, {
      proofId: pRef.id, status: 'pending', rejectionReason: null,
      declaredAt: now(), reviewedAt: null,
    });
  } else {
    const g = await adminGet(`groups/${groupId}`);
    batch.set(ref, {
      userId: id, payerName: people[id].name, payerPhone: people[id].phone,
      tourNumber: tour, amount: g.contributionAmount, proofId: pRef.id,
      status: 'pending', rejectionReason: null, declaredAt: now(), reviewedAt: null,
    });
  }
  await batch.commit();
  return pRef.id;
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
    assertFails(createGroup(T, tontine.id, 'BAD234', { commissionType: 'fixed', commissionValue: 40000 })));
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

  await t.test('déclarer avant le tirage : refusé', () => assertFails(declarePayment('a', groupId, 1)));

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

  // Paiements
  await assertSucceeds(declarePayment('a', groupId, 1));
  await t.test('déclarer deux fois le même tour : refusé', () =>
    assertFails(declarePayment('a', groupId, 1)));
  await t.test('tour inexistant : refusé', () => assertFails(declarePayment('a', groupId, 4)));
  await t.test('montant modifié : refusé', async () => {
    const fs = db('a');
    const batch = fs.batch();
    const [pRef, pData] = proof(fs, 'a', 'group', groupId);
    batch.set(pRef, pData);
    batch.set(fs.doc(`groups/${groupId}/payments/a_2`), {
      userId: 'a', payerName: 'Alice', payerPhone: people.a.phone, tourNumber: 2,
      amount: 1, proofId: pRef.id, status: 'pending', rejectionReason: null,
      declaredAt: now(), reviewedAt: null,
    });
    await assertFails(batch.commit());
  });
  await t.test('déclarer « déjà validé » : refusé', async () => {
    const fs = db('b');
    const batch = fs.batch();
    const [pRef, pData] = proof(fs, 'b', 'group', groupId);
    batch.set(pRef, pData);
    batch.set(fs.doc(`groups/${groupId}/payments/b_1`), {
      userId: 'b', payerName: 'Bob', payerPhone: people.b.phone, tourNumber: 1,
      amount: 10000, proofId: pRef.id, status: 'approved', rejectionReason: null,
      declaredAt: now(), reviewedAt: null,
    });
    await assertFails(batch.commit());
  });
  await t.test('valider son propre paiement : refusé', () =>
    assertFails(db('a').doc(`groups/${groupId}/payments/a_1`).update({
      status: 'approved', rejectionReason: null, reviewedAt: now(),
    })));
  await t.test('B ne voit pas le paiement de A', () =>
    assertFails(db('b').doc(`groups/${groupId}/payments/a_1`).get()));
  await t.test('B liste seulement ses paiements', () =>
    assertSucceeds(db('b').collection(`groups/${groupId}/payments`).where('userId', '==', 'b').get()));
  await t.test('B liste tous les paiements : refusé', () =>
    assertFails(db('b').collection(`groups/${groupId}/payments`).get()));

  const pay = await adminGet(`groups/${groupId}/payments/a_1`);
  await t.test('B ne voit pas la preuve de A', () =>
    assertFails(db('b').doc(`proofs/${pay.proofId}`).get()));
  await t.test('le tontinier voit la preuve de A', () =>
    assertSucceeds(T.doc(`proofs/${pay.proofId}`).get()));
  await t.test('le tontinier liste tous les paiements', () =>
    assertSucceeds(T.collection(`groups/${groupId}/payments`).get()));
  await t.test('lister les paiements en attente', () =>
    assertSucceeds(T.collection(`groups/${groupId}/payments`).where('status', '==', 'pending').get()));

  await t.test('refus sans raison : refusé', () =>
    assertFails(T.doc(`groups/${groupId}/payments/a_1`).update({
      status: 'rejected', rejectionReason: '  ', reviewedAt: now(),
    })));
  await assertSucceeds(T.doc(`groups/${groupId}/payments/a_1`).update({
    status: 'rejected', rejectionReason: 'Montant incorrect', reviewedAt: now(),
  }));
  await assertSucceeds(declarePayment('a', groupId, 1, { update: true }));
  await assertSucceeds(T.doc(`groups/${groupId}/payments/a_1`).update({
    status: 'approved', rejectionReason: null, reviewedAt: now(),
  }));
  await t.test('modifier un paiement validé : refusé', () =>
    assertFails(T.doc(`groups/${groupId}/payments/a_1`).update({
      status: 'rejected', rejectionReason: 'x', reviewedAt: now(),
    })));

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
      tx.set(payRef, {
        userId: id, payerName: people[id].name, payerPhone: people[id].phone, caseCount: cases,
        amount: amount ?? cases * c.caseAmount, proofId: pRef.id, status: 'pending',
        rejectionReason: null, declaredAt: now(), reviewedAt: null,
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
