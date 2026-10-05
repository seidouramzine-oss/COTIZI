import 'dart:math';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// Accès aux données COTIZI (Supabase).
class Api {
  Api._();

  static SupabaseClient get _db => Supabase.instance.client;

  static String get uid => _db.auth.currentUser!.id;

  /// Le numéro sert d'identifiant : même règle que la fonction « signup ».
  static String phoneToEmail(String phone) =>
      '${phone.replaceFirst('+', '')}@phone.cotizi.app';

  // ---------------------------------------------------------------- Compte

  static Future<void> signUp({
    required String phone,
    required String password,
    required String fullName,
  }) async {
    await _db.functions.invoke(
      'signup',
      body: {'phone': phone, 'password': password, 'full_name': fullName},
    );
    await signIn(phone: phone, password: password);
  }

  static Future<void> signIn({
    required String phone,
    required String password,
  }) => _db.auth.signInWithPassword(
    email: phoneToEmail(phone),
    password: password,
  );

  static Future<void> signOut() => _db.auth.signOut();

  static Future<Profile> myProfile() async {
    final row = await _db
        .from('profiles')
        .select('full_name, phone')
        .eq('id', uid)
        .single();
    return Profile.maybe(row)!;
  }

  // -------------------------------------------------------------- Tontines

  static Future<List<Tontine>> myTontines() async {
    final rows = await _db
        .from('tontines')
        .select('*, groups(count), carnets(count)')
        .eq('owner_id', uid)
        .order('created_at', ascending: false);
    return rows.map(Tontine.fromJson).toList();
  }

  static Future<Tontine> createTontine(String name, TontineType type) async {
    final row = await _db
        .from('tontines')
        .insert({'name': name.trim(), 'type': type.name})
        .select()
        .single();
    return Tontine.fromJson(row);
  }

  // ------------------------------------------------- Tontine à cagnotte

  static const _groupDetail =
      '*, tontine:tontines(id, name, owner_id, owner:profiles(full_name, phone)),'
      ' members:group_members(id, user_id, draw_position,'
      ' profile:profiles(full_name, phone))';

  static Future<List<Group>> groupsOf(String tontineId) async {
    final rows = await _db
        .from('groups')
        .select('*, group_members(count), payments(count)')
        .eq('tontine_id', tontineId)
        .eq('payments.status', 'pending')
        .order('created_at');
    return rows.map(Group.fromJson).toList();
  }

  static Future<List<Group>> myGroups() async {
    final rows = await _db
        .from('group_members')
        .select('group:groups($_groupDetail)')
        .eq('user_id', uid)
        .order('joined_at', ascending: false);
    return rows
        .map((r) => Group.fromJson(r['group'] as Map<String, dynamic>))
        .toList();
  }

  static Future<Group> group(String id) async {
    final row = await _db
        .from('groups')
        .select(_groupDetail)
        .eq('id', id)
        .single();
    return Group.fromJson(row);
  }

  static Future<Group> createGroup({
    required String tontineId,
    required String name,
    required int memberCount,
    required int contributionAmount,
    required Frequency frequency,
    required DateTime startDate,
    required CommissionType commissionType,
    required double commissionValue,
  }) async {
    final row = await _db
        .from('groups')
        .insert({
          'tontine_id': tontineId,
          'name': name.trim(),
          'member_count': memberCount,
          'contribution_amount': contributionAmount,
          'frequency': frequency.name,
          'start_date': _date(startDate),
          'commission_type': commissionType.name,
          'commission_value': commissionValue,
        })
        .select()
        .single();
    return Group.fromJson(row);
  }

  static Future<List<Payment>> groupPayments(String groupId) async {
    final rows = await _db
        .from('payments')
        .select('*, profile:profiles(full_name, phone)')
        .eq('group_id', groupId)
        .order('declared_at', ascending: false);
    return rows.map(Payment.fromJson).toList();
  }

  static Future<void> startDraw(String groupId) =>
      _db.rpc('start_draw', params: {'p_group_id': groupId});

  static Future<int> drawLot(String groupId) async {
    final position = await _db.rpc('draw_lot', params: {'p_group_id': groupId});
    return (position as num).toInt();
  }

  static Future<void> finishDraw(String groupId) =>
      _db.rpc('finish_draw', params: {'p_group_id': groupId});

  static Future<void> declarePayment({
    required String groupId,
    required int tourNumber,
    required String proofPath,
  }) => _db.rpc(
    'declare_payment',
    params: {
      'p_group_id': groupId,
      'p_tour_number': tourNumber,
      'p_proof_path': proofPath,
    },
  );

  static Future<void> reviewPayment(
    String paymentId,
    bool approve, [
    String? reason,
  ]) => _db.rpc(
    'review_payment',
    params: {
      'p_payment_id': paymentId,
      'p_approve': approve,
      'p_reason': reason,
    },
  );

  // --------------------------------------------------- Tontine à carnet

  static const _carnetDetail =
      '*, tontine:tontines(id, name, owner_id, owner:profiles(full_name, phone)),'
      ' client:profiles(full_name, phone), carnet_payments(case_count, status)';

  static Future<List<Carnet>> carnetsOf(String tontineId) async {
    final rows = await _db
        .from('carnets')
        .select(_carnetDetail)
        .eq('tontine_id', tontineId)
        .order('created_at');
    return rows.map(Carnet.fromJson).toList();
  }

  static Future<List<Carnet>> myCarnets() async {
    final rows = await _db
        .from('carnets')
        .select(_carnetDetail)
        .eq('client_id', uid)
        .order('created_at', ascending: false);
    return rows.map(Carnet.fromJson).toList();
  }

  static Future<Carnet> carnet(String id) async {
    final row = await _db
        .from('carnets')
        .select(_carnetDetail)
        .eq('id', id)
        .single();
    return Carnet.fromJson(row);
  }

  static Future<Carnet> createCarnet({
    required String tontineId,
    required String label,
    required int caseAmount,
  }) async {
    final row = await _db
        .from('carnets')
        .insert({
          'tontine_id': tontineId,
          'label': label.trim(),
          'case_amount': caseAmount,
        })
        .select()
        .single();
    return Carnet.fromJson(row);
  }

  static Future<List<Payment>> carnetPayments(String carnetId) async {
    final rows = await _db
        .from('carnet_payments')
        .select('*, profile:profiles(full_name, phone)')
        .eq('carnet_id', carnetId)
        .order('declared_at', ascending: false);
    return rows.map(Payment.fromJson).toList();
  }

  static Future<void> declareCarnetPayment({
    required String carnetId,
    required int caseCount,
    required String proofPath,
  }) => _db.rpc(
    'declare_carnet_payment',
    params: {
      'p_carnet_id': carnetId,
      'p_case_count': caseCount,
      'p_proof_path': proofPath,
    },
  );

  static Future<void> reviewCarnetPayment(
    String paymentId,
    bool approve, [
    String? reason,
  ]) => _db.rpc(
    'review_carnet_payment',
    params: {
      'p_payment_id': paymentId,
      'p_approve': approve,
      'p_reason': reason,
    },
  );

  // ------------------------------------------------------------ Invitation

  /// Rejoint un groupe ou un carnet ; renvoie (type, id).
  static Future<(String kind, String id)> joinWithCode(String code) async {
    final res = await _db.rpc('join_with_code', params: {'p_code': code});
    final map = res as Map<String, dynamic>;
    return (map['kind'] as String, map['id'] as String);
  }

  // ------------------------------------------------------ Preuves (images)

  static Future<String> uploadProof(XFile file) async {
    final bytes = await file.readAsBytes();
    final name = file.name.toLowerCase();
    final (ext, mime) = name.endsWith('.png')
        ? ('png', 'image/png')
        : name.endsWith('.webp')
        ? ('webp', 'image/webp')
        : name.endsWith('.heic')
        ? ('heic', 'image/heic')
        : ('jpg', 'image/jpeg');
    final rand = Random.secure();
    final id = List.generate(
      12,
      (_) => rand.nextInt(16).toRadixString(16),
    ).join();
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_$id.$ext';
    await _db.storage
        .from('proofs')
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
    return path;
  }

  static Future<String> proofUrl(String path) =>
      _db.storage.from('proofs').createSignedUrl(path, 3600);

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
