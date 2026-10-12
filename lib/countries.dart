/// Pays pris en charge : indicatif, monnaie affichée et opérateurs de
/// paiement mobile. COTIZI ne touche jamais l'argent : la monnaie sert
/// seulement à afficher les montants.
class Country {
  const Country(this.dial, this.name, this.currency, this.operators);

  final String dial;
  final String name;

  /// Symbole affiché après les montants (« FCFA », « GNF », « ₦ »…).
  final String currency;
  final List<String> operators;
}

const _xof = 'FCFA';
const _xaf = 'FCFA';

/// Afrique de l'Ouest et du Centre d'abord (zones FCFA), puis le reste du
/// continent, puis la diaspora.
const countries = <Country>[
  // UEMOA (FCFA d'Afrique de l'Ouest)
  Country('+229', 'Bénin', _xof, ['MTN MoMo', 'Moov Money', 'Celtiis Cash']),
  Country('+228', 'Togo', _xof, ['T-Money', 'Flooz (Moov)']),
  Country('+225', 'Côte d\'Ivoire', _xof, [
    'Orange Money',
    'MTN MoMo',
    'Moov Money',
    'Wave',
  ]),
  Country('+226', 'Burkina Faso', _xof, ['Orange Money', 'Moov Money', 'Wave']),
  Country('+227', 'Niger', _xof, ['Airtel Money', 'Moov Money', 'Zamani']),
  Country('+223', 'Mali', _xof, ['Orange Money', 'Moov Money', 'Wave']),
  Country('+221', 'Sénégal', _xof, ['Wave', 'Orange Money', 'Free Money']),
  Country('+245', 'Guinée-Bissau', _xof, ['Orange Money', 'MTN MoMo']),
  // CEMAC (FCFA d'Afrique centrale)
  Country('+237', 'Cameroun', _xaf, ['MTN MoMo', 'Orange Money']),
  Country('+241', 'Gabon', _xaf, ['Airtel Money', 'Moov Money']),
  Country('+242', 'Congo', _xaf, ['MTN MoMo', 'Airtel Money']),
  Country('+235', 'Tchad', _xaf, ['Airtel Money', 'Moov Money']),
  Country('+236', 'Centrafrique', _xaf, ['Orange Money', 'Telecel Money']),
  Country('+240', 'Guinée équatoriale', _xaf, ['Muni Dinero']),
  // Autres pays
  Country('+224', 'Guinée', 'GNF', ['Orange Money', 'MTN MoMo']),
  Country('+243', 'RD Congo', 'FC', ['M-Pesa', 'Orange Money', 'Airtel Money']),
  Country('+234', 'Nigeria', '₦', ['OPay', 'PalmPay', 'MTN MoMo PSB']),
  Country('+233', 'Ghana', 'GH₵', [
    'MTN MoMo',
    'Telecel Cash',
    'AirtelTigo Money',
  ]),
  Country('+254', 'Kenya', 'KSh', ['M-Pesa', 'Airtel Money']),
  Country('+255', 'Tanzanie', 'TSh', ['M-Pesa', 'Tigo Pesa', 'Airtel Money']),
  Country('+256', 'Ouganda', 'USh', ['MTN MoMo', 'Airtel Money']),
  Country('+250', 'Rwanda', 'FRW', ['MTN MoMo', 'Airtel Money']),
  Country('+257', 'Burundi', 'FBu', ['Lumicash', 'Ecocash']),
  Country('+261', 'Madagascar', 'Ar', [
    'MVola',
    'Orange Money',
    'Airtel Money',
  ]),
  Country('+269', 'Comores', 'KMF', ['Huri Money', 'Mvola']),
  Country('+253', 'Djibouti', 'Fdj', ['D-Money', 'Waafi']),
  Country('+222', 'Mauritanie', 'MRU', ['Bankily', 'Masrvi', 'Sedad']),
  Country('+220', 'Gambie', 'D', ['Wave', 'QMoney', 'Afrimoney']),
  Country('+232', 'Sierra Leone', 'Le', ['Orange Money', 'Afrimoney']),
  Country('+231', 'Liberia', 'L\$', ['Orange Money', 'MTN MoMo']),
  Country('+238', 'Cap-Vert', 'Esc', ['Vinti4']),
  Country('+212', 'Maroc', 'DH', ['Orange Money', 'Inwi Money']),
  Country('+216', 'Tunisie', 'DT', ['D17', 'Flouci']),
  Country('+213', 'Algérie', 'DA', ['BaridiMob']),
  Country('+20', 'Égypte', 'E£', ['Vodafone Cash', 'InstaPay']),
  Country('+251', 'Éthiopie', 'Br', ['Telebirr', 'M-Pesa']),
  Country('+258', 'Mozambique', 'MT', ['M-Pesa', 'e-Mola', 'mKesh']),
  Country('+260', 'Zambie', 'ZK', ['MTN MoMo', 'Airtel Money']),
  Country('+265', 'Malawi', 'MK', ['Airtel Money', 'TNM Mpamba']),
  Country('+263', 'Zimbabwe', 'US\$', ['EcoCash', 'OneMoney']),
  Country('+244', 'Angola', 'Kz', ['Unitel Money', 'Multicaixa Express']),
  Country('+27', 'Afrique du Sud', 'R', ['Banque', 'Shoprite Money']),
  // Diaspora
  Country('+33', 'France', '€', ['Virement', 'Wave', 'Lydia']),
  Country('+32', 'Belgique', '€', ['Virement', 'Wave']),
  Country('+39', 'Italie', '€', ['Virement']),
  Country('+34', 'Espagne', '€', ['Virement', 'Bizum']),
  Country('+49', 'Allemagne', '€', ['Virement']),
  Country('+1', 'États-Unis / Canada', '\$', ['Zelle', 'Interac', 'Virement']),
];

/// Pays d'un numéro international (le plus long indicatif qui correspond).
Country? countryOfPhone(String e164) {
  Country? best;
  for (final c in countries) {
    if (e164.startsWith(c.dial) &&
        (best == null || c.dial.length > best.dial.length)) {
      best = c;
    }
  }
  return best;
}

/// Monnaies proposées dans les paramètres (sans doublon).
List<String> get currencies => {for (final c in countries) c.currency}.toList();

/// Opérateurs pour un pays, toujours avec « Espèces » et « Autre ».
List<String> operatorsFor(Country? c) => [
  ...?c?.operators,
  if (c == null) ...['MTN MoMo', 'Orange Money', 'Moov Money', 'Wave'],
  'Autre',
];
