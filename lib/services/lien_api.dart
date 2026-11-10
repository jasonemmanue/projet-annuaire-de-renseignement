// lib/services/lien_api.dart
// ─────────────────────────────────────────────────────────────────────────────
// Adresse de l'API jamais écrite en clair dans l'application : un `strings` ou
// un extracteur d'APK ne la trouve pas. Elle est rangée en 3 morceaux chiffrés
// (XOR avec une clé et un masque selon la position) et reconstituée en mémoire
// au premier usage.
//
// Ce n'est pas un secret absolu : l'adresse reste visible dans le trafic du
// téléphone de son propriétaire. La vraie protection est côté serveur.
// Les builds de production ne passent pas `--dart-define=API_BASE_URL`, qui
// serait compilé en clair.
// ─────────────────────────────────────────────────────────────────────────────

const List<int> _cle = [70, 102, 227, 181, 128, 126, 29, 251, 33, 89, 193, 62, 39, 173, 18, 43, 24, 31, 13, 30, 244, 56, 132];
const List<int> _m1 = [221, 170, 85, 75, 46, 138, 17, 235, 61, 140, 196, 14, 20, 93, 138, 185];
const List<int> _m2 = [223, 217, 76, 7, 125, 200, 193, 31, 93, 113, 47, 10, 97, 114, 207, 66];
const List<int> _m3 = [102, 30, 73, 92, 200, 67, 251, 209, 66, 149, 94, 100, 18, 29, 78, 95, 185, 184];

String? _cache;

/// Lien définitif de l'API (production), reconstitué en mémoire.
String lienApiDefinitif() {
  final c = _cache;
  if (c != null) return c;
  final octets = [..._m1, ..._m2, ..._m3];
  final sortie = List<int>.generate(
      octets.length, (i) => octets[i] ^ _cle[(i * 7 + 3) % _cle.length] ^ ((i * 31) & 0xFF));
  return _cache = String.fromCharCodes(sortie);
}
