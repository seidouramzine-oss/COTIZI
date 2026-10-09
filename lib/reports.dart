import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'format.dart';
import 'models.dart';
import 'pro.dart';

/// Relevés PDF (participant, bilan du groupe, carnet) à partager.

const _green = PdfColor.fromInt(0xFF0B7A5A);
const _grey = PdfColor.fromInt(0xFF5F6B66);
const _light = PdfColor.fromInt(0xFFEAF3EF);

pw.ThemeData? _theme;

Future<pw.ThemeData> _loadTheme() async => _theme ??= pw.ThemeData.withFont(
  base: pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
  bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
);

/// Montant lisible dans le PDF (espaces ordinaires).
String _m(num v) => money(v).replaceAll(' ', ' ').replaceAll(' ', ' ');

String _d(DateTime d) => dateShort(d);

pw.Widget _header(Business? business, String ownerName, String title) {
  final logo = business?.logo;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logo != null)
            pw.Container(
              width: 46,
              height: 46,
              margin: const pw.EdgeInsets.only(right: 12),
              child: pw.Image(pw.MemoryImage(base64.decode(logo))),
            ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  business?.name ?? ownerName,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: _green,
                  ),
                ),
                pw.Text(
                  [
                    if (business != null) 'Tontinier : $ownerName',
                    if (business?.city.isNotEmpty ?? false) business!.city,
                    if (business?.contactPhone.isNotEmpty ?? false)
                      business!.contactPhone,
                  ].join(' · '),
                  style: const pw.TextStyle(fontSize: 9, color: _grey),
                ),
              ],
            ),
          ),
          pw.Text(
            'COTIZI',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: _grey,
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 14),
      pw.Text(
        title,
        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
      ),
      pw.Text(
        'Édité le ${dateTime(DateTime.now())}',
        style: const pw.TextStyle(fontSize: 9, color: _grey),
      ),
      pw.SizedBox(height: 12),
    ],
  );
}

pw.Widget _info(List<(String, String)> rows) => pw.Container(
  padding: const pw.EdgeInsets.all(10),
  decoration: pw.BoxDecoration(
    color: _light,
    borderRadius: pw.BorderRadius.circular(6),
  ),
  child: pw.Column(
    children: [
      for (final (label, value) in rows)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  label,
                  style: const pw.TextStyle(fontSize: 10, color: _grey),
                ),
              ),
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
    ],
  ),
);

pw.Widget _section(String title) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
  child: pw.Text(
    title,
    style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
  ),
);

pw.Widget _table(List<String> headers, List<List<String>> rows) => rows.isEmpty
    ? pw.Text('Aucun', style: const pw.TextStyle(fontSize: 10, color: _grey))
    : pw.TableHelper.fromTextArray(
        headers: headers,
        data: rows,
        headerStyle: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
        headerDecoration: const pw.BoxDecoration(color: _green),
        cellStyle: const pw.TextStyle(fontSize: 9),
        oddRowDecoration: const pw.BoxDecoration(color: _light),
        cellAlignment: pw.Alignment.centerLeft,
      );

String _status(Payment p) =>
    p.recordedByOwner ? 'Encaissé' : paymentStatusLabel(p.status);

List<String> _paymentRow(Payment p, String units) => [
  _d(p.reviewedAt ?? p.declaredAt),
  units,
  methodLabel(p.method),
  p.penalty > 0 ? _m(p.penalty) : '—',
  _m(p.amount),
  _status(p),
];

Future<void> _share(pw.Document doc, String fileName, String text) async {
  final bytes = await doc.save();
  await SharePlus.instance.share(
    ShareParams(
      text: text,
      files: [
        XFile.fromData(bytes, mimeType: 'application/pdf', name: fileName),
      ],
      fileNameOverrides: [fileName],
    ),
  );
}

String _slug(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

/// Relevé d'un participant dans un groupe.
Future<void> shareMemberStatement({
  required Group group,
  required GroupMember member,
  required List<Payment> payments,
  required Map<int, Payout> payouts,
  Business? business,
}) async {
  final theme = await _loadTheme();
  final s = group.standingOf(member, DateTime.now());
  final mine = payments
      .where((p) => member.paymentIds.contains(p.userId))
      .toList();
  final paid = mine
      .where((p) => p.status == PaymentStatus.approved)
      .fold<int>(0, (n, p) => n + p.amount);
  final pos = member.drawPosition;
  final payout = pos == null ? null : payouts[pos];
  final doc = pw.Document(theme: theme)
    ..addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _header(business, group.ownerName, 'Relevé de participation'),
          _info([
            ('Participant', '${member.name} (${member.profile.phone})'),
            ('Groupe', '${group.name} · ${group.tontineName}'),
            (
              'Période',
              group.isStarted
                  ? periodLabel(group.startDate, group.endDate)
                  : 'pas encore démarrée',
            ),
            (
              'Cotisation',
              '${_m(group.contributionAmount)} ${frequencyLower(group.frequency)}',
            ),
            if (pos != null)
              (
                'Sa cagnotte',
                'n°$pos · ${_m(group.netPot)} le ${_d(group.payoutDate(pos))}',
              ),
          ]),
          _section('Situation'),
          _info([
            ('Cotisations validées', '${s.approved} / ${s.total}'),
            if (s.pending > 0) ('En attente de validation', '${s.pending}'),
            (
              'Situation',
              s.upToDate
                  ? 'à jour'
                  : '${s.late} en retard (${_m(s.late * group.contributionAmount)}'
                        '${s.penaltyDue > 0 ? ' + ${_m(s.penaltyDue)} de pénalités' : ''})',
            ),
            if (member.penaltyPaid > 0)
              ('Pénalités payées', _m(member.penaltyPaid)),
            ('Total versé (validé)', _m(paid)),
            if (payout != null)
              (
                'Cagnotte reçue',
                '${_m(payout.amount)} le ${_d(payout.paidAt)}'
                    '${payout.confirmed ? ' (réception confirmée)' : ''}',
              ),
          ]),
          _section('Paiements (${mine.length})'),
          _table(
            ['Date', 'Cotisations', 'Mode', 'Pénalité', 'Montant', 'Statut'],
            [for (final p in mine) _paymentRow(p, '${p.count}')],
          ),
        ],
      ),
    );
  await _share(
    doc,
    'releve-${_slug(member.name)}-${_slug(group.name)}.pdf',
    'Relevé de ${member.name} — ${group.name}',
  );
}

/// Bilan d'un groupe pour le tontinier.
Future<void> shareGroupReport({
  required Group group,
  required List<Payment> payments,
  required Map<int, Payout> payouts,
  Business? business,
}) async {
  final theme = await _loadTheme();
  final now = DateTime.now();
  final approved = payments.where((p) => p.status == PaymentStatus.approved);
  final total = approved.fold<int>(0, (n, p) => n + p.amount);
  final penalties = approved.fold<int>(0, (n, p) => n + p.penalty);
  final doc = pw.Document(theme: theme)
    ..addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _header(business, group.ownerName, 'Bilan du groupe ${group.name}'),
          _info([
            ('Tontine', group.tontineName),
            ('Statut', groupStatusLabel(group.status)),
            (
              'Période',
              group.isStarted
                  ? periodLabel(group.startDate, group.endDate)
                  : 'début prévu le ${_d(group.startDate)}',
            ),
            ('Participants', '${group.joinedCount} / ${group.memberCount}'),
            (
              'Cotisation',
              '${_m(group.contributionAmount)} ${frequencyLower(group.frequency)}',
            ),
            ('Cagnotte', '${_m(group.grossPot)} (reçu : ${_m(group.netPot)})'),
            ('Commission', commissionLabel(group).replaceAll(' ', ' ')),
          ]),
          _section('Totaux'),
          _info([
            ('Total encaissé (validé)', _m(total)),
            if (penalties > 0) ('Dont pénalités', _m(penalties)),
            (
              'Remises effectuées',
              '${group.paidOutCount} / ${group.memberCount}',
            ),
            ('Commissions gagnées', _m(group.paidOutCount * group.commission)),
          ]),
          _section('Participants'),
          _table(
            [
              'N°',
              'Participant',
              'Téléphone',
              'Validées',
              'Attente',
              'Retard',
              'Pénalités',
            ],
            [
              for (final m in group.members)
                () {
                  final s = group.standingOf(m, now);
                  return [
                    '${m.drawPosition ?? '—'}',
                    m.name,
                    m.profile.phone,
                    '${s.approved}/${s.total}',
                    '${s.pending}',
                    s.late == 0 ? 'à jour' : '${s.late}',
                    m.penaltyPaid > 0 ? _m(m.penaltyPaid) : '—',
                  ];
                }(),
            ],
          ),
          if (group.isStarted) ...[
            _section('Remises'),
            _table(
              [
                'N°',
                'Bénéficiaire',
                'Prévue le',
                'Remise le',
                'Montant',
                'Reçue',
              ],
              [
                for (var pot = 1; pot <= group.memberCount; pot++)
                  [
                    '$pot',
                    group.beneficiaryOf(pot)?.name ?? '—',
                    _d(group.payoutDate(pot)),
                    payouts[pot] == null ? '—' : _d(payouts[pot]!.paidAt),
                    payouts[pot] == null ? '—' : _m(payouts[pot]!.amount),
                    payouts[pot]?.confirmed == true ? 'confirmée' : '—',
                  ],
              ],
            ),
          ],
          _section('Paiements validés (${approved.length})'),
          _table(
            ['Date', 'Participant', 'Cotis.', 'Mode', 'Pénalité', 'Montant'],
            [
              for (final p in approved)
                [
                  _d(p.reviewedAt ?? p.declaredAt),
                  p.payer.fullName,
                  '${p.count}',
                  methodLabel(p.method),
                  p.penalty > 0 ? _m(p.penalty) : '—',
                  _m(p.amount),
                ],
            ],
          ),
        ],
      ),
    );
  await _share(
    doc,
    'bilan-${_slug(group.name)}.pdf',
    'Bilan du groupe ${group.name}',
  );
}

/// Relevé d'un carnet de 31 cases.
Future<void> shareCarnetStatement({
  required Carnet carnet,
  required List<Payment> payments,
  Business? business,
}) async {
  final theme = await _loadTheme();
  final doc = pw.Document(theme: theme)
    ..addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _header(business, carnet.ownerName, 'Relevé du ${carnet.label}'),
          _info([
            (
              'Client',
              carnet.client == null
                  ? '—'
                  : '${carnet.client!.fullName} (${carnet.client!.phone})',
            ),
            ('Tontine', carnet.tontineName),
            ('Montant par case', _m(carnet.caseAmount)),
            ('Cases validées', '${carnet.approvedCases} / ${carnet.caseCount}'),
            if (carnet.pendingCases > 0)
              ('Cases en attente', '${carnet.pendingCases}'),
            ('Montant validé', _m(carnet.approvedCases * carnet.caseAmount)),
            ('À remettre au client', _m(carnet.clientPayout)),
          ]),
          _section('Paiements (${payments.length})'),
          _table(
            ['Date', 'Cases', 'Mode', 'Pénalité', 'Montant', 'Statut'],
            [for (final p in payments) _paymentRow(p, '${p.caseCount}')],
          ),
        ],
      ),
    );
  await _share(
    doc,
    'releve-${_slug(carnet.label)}.pdf',
    'Relevé du ${carnet.label}',
  );
}

/// Relevé comptable d'un mois (plan Pro).
Future<void> shareAccounting({
  required Accounting accounting,
  required String ownerName,
  Business? business,
}) async {
  final theme = await _loadTheme();
  final a = accounting;
  final month = DateFormat('MMMM yyyy', 'fr').format(a.month);
  final doc = pw.Document(theme: theme)
    ..addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _header(business, ownerName, 'Comptabilité de $month'),
          _info([
            ('Argent reçu des clients', _m(a.received)),
            ('dont pénalités', _m(a.penalties)),
            ('Cagnottes remises', _m(a.paidOut)),
            ('Carnets remis ou remboursés', _m(a.carnetsPaid)),
            ('Dépenses', _m(a.expenses)),
            ('Solde du mois (entrées - sorties)', _m(a.balance)),
            ('Commissions gagnées', _m(a.commissions)),
            ('Bénéfice (commissions + pénalités - dépenses)', _m(a.profit)),
          ]),
          _section('Opérations (${a.lines.length})'),
          _table(
            ['Date', 'Opération', 'Détail', 'Montant'],
            [
              for (final l in a.lines)
                [
                  DateFormat('d MMM yyyy', 'fr').format(l.date),
                  l.label,
                  l.detail,
                  '${l.amount > 0 ? '+' : '-'} ${_m(l.amount.abs())}',
                ],
            ],
          ),
        ],
      ),
    );
  await _share(
    doc,
    'comptabilite-${DateFormat('yyyy-MM').format(a.month)}.pdf',
    'Comptabilité de $month',
  );
}
