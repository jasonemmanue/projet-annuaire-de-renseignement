import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import 'detail_logement_screen.dart';
import '../widgets/shared_widgets.dart' as sw;

// ============================================================
// FICHIER : lib/screens/favoris_screen.dart
// Écran Favoris - Annonces sauvegardées (§3.1 UC-C08)
// + Mode hors connexion (consultation sans internet)
// ============================================================

class FavorisScreen extends StatefulWidget {
  const FavorisScreen({super.key});

  @override
  State<FavorisScreen> createState() => _FavorisScreenState();
}

class _FavorisScreenState extends State<FavorisScreen> {
  // Mock favoris (à gérer via SharedPreferences / Hive pour hors connexion §5.4)
  final List<Logement> _favoris = [
    Logement(id: '1', titre: 'Studio moderne à Bastos', description: 'Beau studio meublé.',
        prix: 150000, typeLocation: 'location', typeBien: 'Studio',
        ville: 'Yaoundé', quartier: 'Bastos', latitude: 3.8667, longitude: 11.5167,
        photos: ['https://picsum.photos/seed/l1/400/300'],
        surface: 30, nbPieces: 1, equipements: ['Meublé', 'Wifi'],
        estVerifie: true, estSponsorie: false,
        prestatireId: 'p1', prestatireNom: 'Jean Dupont', prestatirePhone: '+237 655 123 456',
        datePublication: DateTime.now().subtract(const Duration(days: 2)), nbVues: 234, disponible: true),
  ];

  bool _modeHorsConnexion = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes Favoris'),
        actions: [
          // Toggle mode hors connexion (§3.1 UC-C08, §5.4)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                const Icon(Icons.wifi_off, size: 16),
                const SizedBox(width: 4),
                Switch(
                  value: _modeHorsConnexion,
                  activeColor: AppColors.accent,
                  onChanged: (v) => setState(() => _modeHorsConnexion = v),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_modeHorsConnexion)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.accent.withOpacity(0.15),
              child: const Row(
                children: [
                  Icon(Icons.wifi_off, size: 14, color: Colors.brown),
                  SizedBox(width: 8),
                  Text('Mode hors connexion · Annonces en cache', style: TextStyle(fontSize: 12, color: Colors.brown)),
                ],
              ),
            ),
          Expanded(
            child: _favoris.isEmpty
                ? sw.EmptyState(
              icon: Icons.favorite_border,
              title: 'Aucun favori',
              subtitle: 'Ajoutez des logements à vos favoris en appuyant sur le ❤️',
              action: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Explorer les annonces'),
              ),
            )
                : ListView.builder(
              itemCount: _favoris.length,
              itemBuilder: (_, i) => Dismissible(
                key: Key(_favoris[i].id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: AppColors.error,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) => setState(() => _favoris.removeAt(i)),
                child: sw.LogementCard(
                  logement: _favoris[i],
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => DetailLogementScreen(logement: _favoris[i]))),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}