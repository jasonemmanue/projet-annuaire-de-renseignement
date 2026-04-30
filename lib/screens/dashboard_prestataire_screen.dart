import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';

// ============================================================
// FICHIER : lib/screens/dashboard_prestataire_screen.dart
// Écran 6 - Espace Prestataire / Tableau de bord (§4.1.6)
// CRUD annonces, statistiques, paiements, sponsorisation
// Accès réservé aux prestataires connectés (§1.2)
// ============================================================

class DashboardPrestataireScreen extends StatefulWidget {
  const DashboardPrestataireScreen({super.key});

  @override
  State<DashboardPrestataireScreen> createState() => _DashboardPrestataireScreenState();
}

class _DashboardPrestataireScreenState extends State<DashboardPrestataireScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Mock prestataire connecté
  final Utilisateur _moi = Utilisateur(
    id: 'p1', nom: 'Dupont', prenom: 'Jean',
    email: 'jean.dupont@example.com', telephone: '+237 655 123 456',
    estVerifie: true, estPremium: false,
    dateInscription: DateTime(2024, 3, 15),
    nbAnnonces: 3, noteGlobale: 4.5,
  );

  // Mock annonces du prestataire
  final List<Logement> _mesAnnonces = [
    Logement(id: '1', titre: 'Studio moderne à Bastos', description: 'Studio meublé.',
        prix: 150000, typeLocation: 'location', typeBien: 'Studio',
        ville: 'Yaoundé', quartier: 'Bastos', latitude: 3.8667, longitude: 11.5167,
        photos: ['https://picsum.photos/seed/l1/400/300'],
        surface: 30, nbPieces: 1, equipements: ['Meublé', 'Wifi'],
        estVerifie: true, estSponsorie: false,
        prestatireId: 'p1', prestatireNom: 'Jean Dupont', prestatirePhone: '+237 655 123 456',
        datePublication: DateTime.now().subtract(const Duration(days: 10)), nbVues: 234, disponible: true),
    Logement(id: '5', titre: 'F3 à Melen', description: 'Bel appartement F3.',
        prix: 120000, typeLocation: 'location', typeBien: 'F3',
        ville: 'Yaoundé', quartier: 'Melen', latitude: 3.8500, longitude: 11.5000,
        photos: ['https://picsum.photos/seed/l5/400/300'],
        surface: 75, nbPieces: 3, equipements: ['Gardien', 'Parking'],
        estVerifie: true, estSponsorie: false,
        prestatireId: 'p1', prestatireNom: 'Jean Dupont', prestatirePhone: '+237 655 123 456',
        datePublication: DateTime.now().subtract(const Duration(days: 5)), nbVues: 87, disponible: true),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon Espace'),
        actions: [
          if (!_moi.estPremium)
            TextButton.icon(
              onPressed: _upgraderPremium,
              icon: const Icon(Icons.workspace_premium, color: AppColors.accent, size: 18),
              label: const Text('Premium', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Annonces'),
            Tab(text: 'Statistiques'),
            Tab(text: 'Paiements'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _OngletAnnonces(annonces: _mesAnnonces, onAjout: _ajouterAnnonce, estPremium: _moi.estPremium),
          _OngletStatistiques(annonces: _mesAnnonces, estPremium: _moi.estPremium),
          _OngletPaiements(estPremium: _moi.estPremium),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ajouterAnnonce,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nouvelle annonce', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _ajouterAnnonce() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const FormulaireAnnonce()));
  }

  void _upgraderPremium() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PremiumSheet(),
    );
  }
}

// ----------------------------------------------------------
// ONGLET 1 : ANNONCES (CRUD)
// ----------------------------------------------------------
class _OngletAnnonces extends StatelessWidget {
  final List<Logement> annonces;
  final VoidCallback onAjout;
  final bool estPremium;

  const _OngletAnnonces({required this.annonces, required this.onAjout, required this.estPremium});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Quota annonces gratuites (§2.1 - 1 annonce gratuite/mois)
        if (!estPremium)
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Forfait gratuit : 1 annonce/mois\nPassez Premium pour des annonces illimitées',
                    style: TextStyle(color: AppColors.primary, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text('Premium', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),

        Expanded(
          child: annonces.isEmpty
              ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.home_outlined, size: 60, color: AppColors.textHint),
                const SizedBox(height: 12),
                const Text('Aucune annonce publiée', style: AppTextStyles.h3),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: onAjout,
                  icon: const Icon(Icons.add),
                  label: const Text('Publier mon premier bien'),
                ),
              ],
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.only(bottom: 100),
            itemCount: annonces.length,
            itemBuilder: (_, i) => _AnnonceGestionCard(logement: annonces[i]),
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------
// CARTE ANNONCE AVEC ACTIONS CRUD
// ----------------------------------------------------------
class _AnnonceGestionCard extends StatefulWidget {
  final Logement logement;
  const _AnnonceGestionCard({required this.logement});

  @override
  State<_AnnonceGestionCard> createState() => _AnnonceGestionCardState();
}

class _AnnonceGestionCardState extends State<_AnnonceGestionCard> {
  bool _disponible = true;

  @override
  void initState() {
    super.initState();
    _disponible = widget.logement.disponible;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: widget.logement.photos.isNotEmpty
                      ? Image.network(widget.logement.photos.first, width: 70, height: 70, fit: BoxFit.cover)
                      : Container(width: 70, height: 70, color: AppColors.primaryLight, child: const Icon(Icons.home, color: AppColors.primary)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.logement.titre, style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600), maxLines: 1),
                      Text('${widget.logement.quartier}, ${widget.logement.ville}', style: AppTextStyles.bodyMedium),
                      Text(widget.logement.prixLabel, style: AppTextStyles.priceSmall),
                    ],
                  ),
                ),
                // Menu actions
                PopupMenuButton<String>(
                  onSelected: (v) => _handleAction(v, context),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'modifier', child: Row(children: [Icon(Icons.edit_outlined, size: 16), SizedBox(width: 8), Text('Modifier')])),
                    const PopupMenuItem(value: 'sponsoriser', child: Row(children: [Icon(Icons.bolt, size: 16, color: AppColors.accent), SizedBox(width: 8), Text('Sponsoriser')])),
                    const PopupMenuItem(value: 'supprimer', child: Row(children: [Icon(Icons.delete_outline, size: 16, color: AppColors.error), SizedBox(width: 8), Text('Supprimer', style: TextStyle(color: AppColors.error))])),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Stats rapides
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatItem(icon: Icons.remove_red_eye_outlined, value: '${widget.logement.nbVues}', label: 'vues'),
                _StatItem(icon: Icons.chat_bubble_outline, value: '3', label: 'contacts'),
                _StatItem(icon: Icons.trending_up, value: '12%', label: 'taux'),
                // Toggle disponibilité
                Row(
                  children: [
                    Text(_disponible ? 'Dispo' : 'Indispo',
                        style: TextStyle(color: _disponible ? AppColors.success : AppColors.error, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                    Switch(
                      value: _disponible,
                      activeColor: AppColors.success,
                      onChanged: (v) => setState(() => _disponible = v),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _handleAction(String action, BuildContext context) {
    switch (action) {
      case 'modifier':
        Navigator.push(context, MaterialPageRoute(builder: (_) => FormulaireAnnonce(logement: widget.logement)));
        break;
      case 'sponsoriser':
        _afficherSponsorisation(context);
        break;
      case 'supprimer':
        _confirmerSuppression(context);
        break;
    }
  }

  void _afficherSponsorisation(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sponsoriser cette annonce', style: AppTextStyles.h3),
            const SizedBox(height: 16),
            ...['1 semaine - 5 000 XAF', '2 semaines - 9 000 XAF', '1 mois - 15 000 XAF'].map((o) =>
                ListTile(
                  title: Text(o),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () { Navigator.pop(context); _confirmerPaiement(context, o); },
                )
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmerPaiement(BuildContext context, String offre) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmer le paiement'),
        content: Text('Payer $offre via Orange Money / Mobile Money ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); },
            child: const Text('Payer'),
          ),
        ],
      ),
    );
  }

  void _confirmerSuppression(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer l\'annonce ?'),
        content: const Text('Cette action est irréversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _StatItem({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, size: 16, color: AppColors.primary),
      Text(value, style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w700)),
      Text(label, style: AppTextStyles.caption),
    ],
  );
}

// ----------------------------------------------------------
// ONGLET 2 : STATISTIQUES (§4.1.6 - Premium)
// ----------------------------------------------------------
class _OngletStatistiques extends StatelessWidget {
  final List<Logement> annonces;
  final bool estPremium;

  const _OngletStatistiques({required this.annonces, required this.estPremium});

  @override
  Widget build(BuildContext context) {
    final totalVues = annonces.fold(0, (sum, a) => sum + a.nbVues);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats globales
          Row(
            children: [
              Expanded(child: _StatCard(value: '${annonces.length}', label: 'Annonces', icon: Icons.home, color: AppColors.primary)),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(value: '$totalVues', label: 'Vues totales', icon: Icons.remove_red_eye, color: AppColors.success)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _StatCard(value: '8', label: 'Contacts reçus', icon: Icons.chat_bubble, color: AppColors.accent.withRed(200))),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(value: '12%', label: 'Taux conversion', icon: Icons.trending_up, color: Colors.purple)),
            ],
          ),
          const SizedBox(height: 24),

          // Graphique (placeholder - intégrer fl_chart)
          const Text('Évolution des vues (30 jours)', style: AppTextStyles.h3),
          const SizedBox(height: 12),
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(painter: _FakeChartPainter(), size: const Size(double.infinity, 180)),
                const Text('Intégrer fl_chart ou syncfusion_flutter_charts', style: TextStyle(color: AppColors.textHint, fontSize: 12)),
              ],
            ),
          ),

          // Stats Premium (bloquées si non premium)
          const SizedBox(height: 24),
          const Text('Statistiques avancées', style: AppTextStyles.h3),
          const SizedBox(height: 12),
          if (!estPremium) _BlocPremium(message: 'Les statistiques avancées sont réservées aux membres Premium'),
          if (estPremium) ...[
            _StatRow(label: 'Clics sur "Contacter"', value: '24'),
            _StatRow(label: 'Partages', value: '7'),
            _StatRow(label: 'Mise en favori', value: '15'),
            _StatRow(label: 'Durée moyenne de consultation', value: '1m 42s'),
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _StatCard({required this.value, required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: AppTextStyles.bodyMedium),
      ],
    ),
  );
}

class _FakeChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.primary..strokeWidth = 2..style = PaintingStyle.stroke;
    final fillPaint = Paint()..color = AppColors.primary.withOpacity(0.1)..style = PaintingStyle.fill;
    final points = [0.6, 0.4, 0.7, 0.5, 0.8, 0.6, 0.9, 0.7, 0.85, 0.95];
    final path = Path();
    final fillPath = Path();
    for (int i = 0; i < points.length; i++) {
      final x = size.width * 0.1 + i * (size.width * 0.8 / (points.length - 1));
      final y = size.height * (1 - points[i] * 0.7) + 10;
      if (i == 0) { path.moveTo(x, y); fillPath.moveTo(x, size.height - 10); fillPath.lineTo(x, y); }
      else { path.lineTo(x, y); fillPath.lineTo(x, y); }
    }
    fillPath.lineTo(size.width * 0.9, size.height - 10);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.bodyMedium),
        Text(value, style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary)),
      ],
    ),
  );
}

// ----------------------------------------------------------
// ONGLET 3 : PAIEMENTS
// ----------------------------------------------------------
class _OngletPaiements extends StatelessWidget {
  final bool estPremium;
  const _OngletPaiements({required this.estPremium});

  // Mock historique paiements
  final List<Map<String, dynamic>> _paiements = const [
    {'montant': 150000, 'type': 'Loyer reçu', 'date': '15/04/2026', 'statut': 'validé', 'via': 'Orange Money'},
    {'montant': 20000, 'type': 'Pack Premium', 'date': '01/04/2026', 'statut': 'validé', 'via': 'MTN Mobile Money'},
    {'montant': 9000, 'type': 'Sponsorisation', 'date': '20/03/2026', 'statut': 'validé', 'via': 'Orange Money'},
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Récap financier
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Solde du mois', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                const Text('150 000 XAF', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.arrow_upward, color: Colors.greenAccent, size: 14),
                    const Text('+150 000 XAF ce mois', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text('Historique des paiements', style: AppTextStyles.h3),
          const SizedBox(height: 12),

          ..._paiements.map((p) => _PaiementTile(paiement: p)),

          const SizedBox(height: 16),
          // Note paiement intégré Phase 2 (§6.1.2)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.accent.withOpacity(0.5)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.accent, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Paiement intégré Orange Money & MTN Mobile Money disponible en Phase 2',
                    style: TextStyle(fontSize: 12, color: Colors.brown),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaiementTile extends StatelessWidget {
  final Map<String, dynamic> paiement;
  const _PaiementTile({required this.paiement});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).cardTheme.color,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.payment, color: AppColors.success, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(paiement['type'], style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600)),
              Text('${paiement['date']} · ${paiement['via']}', style: AppTextStyles.caption),
            ],
          ),
        ),
        Text(
          '+${paiement['montant'].toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} XAF',
          style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

// ----------------------------------------------------------
// BLOC PREMIUM LOCKÉ
// ----------------------------------------------------------
class _BlocPremium extends StatelessWidget {
  final String message;
  const _BlocPremium({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8E1),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.accent.withOpacity(0.5)),
    ),
    child: Row(
      children: [
        const Icon(Icons.lock, color: AppColors.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: const TextStyle(fontSize: 13, color: Colors.brown)),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: const Text('Passer à Premium - 20 000 XAF/mois', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ----------------------------------------------------------
// SHEET PREMIUM
// ----------------------------------------------------------
class _PremiumSheet extends StatelessWidget {
  const _PremiumSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspace_premium, color: AppColors.accent, size: 48),
          const SizedBox(height: 12),
          const Text('Passez à Premium', style: AppTextStyles.h2),
          const SizedBox(height: 8),
          const Text('20 000 XAF / mois', style: AppTextStyles.price),
          const SizedBox(height: 16),
          ...[
            'Annonces illimitées',
            'Badge prestataire vérifié',
            'Statistiques avancées',
            'Annonces sponsorisées en self-service',
            'Sans publicités',
          ].map((f) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              const Icon(Icons.check_circle, color: AppColors.success, size: 18),
              const SizedBox(width: 8),
              Text(f, style: AppTextStyles.bodyMedium),
            ]),
          )),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
            ),
            child: const Text('Souscrire via Orange Money / MTN', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Plus tard')),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------
// FORMULAIRE AJOUT / MODIFICATION ANNONCE
// ----------------------------------------------------------
class FormulaireAnnonce extends StatefulWidget {
  final Logement? logement; // null = création, non-null = modification

  const FormulaireAnnonce({super.key, this.logement});

  @override
  State<FormulaireAnnonce> createState() => _FormulaireAnnonceState();
}

class _FormulaireAnnonceState extends State<FormulaireAnnonce> {
  final _formKey = GlobalKey<FormState>();
  final _titreCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _prixCtrl = TextEditingController();
  final _surfaceCtrl = TextEditingController();
  String _typeLocation = 'location';
  String _typeBien = 'Studio';
  String _ville = 'Yaoundé';
  final List<String> _equipements = [];
  bool _isSubmitting = false;

  final List<String> _typesBiens = ['Studio', 'F2', 'F3', 'Villa', 'Terrain', 'Appartement'];
  final List<String> _villes = ['Yaoundé', 'Douala', 'Bafoussam', 'Garoua', 'Maroua'];
  final List<String> _equipementsDispos = ['Meublé', 'Wifi', 'Climatiseur', 'Eau chaude', 'Gardien', 'Parking', 'Groupe électrogène', 'Titre foncier'];

  @override
  void initState() {
    super.initState();
    if (widget.logement != null) {
      _titreCtrl.text = widget.logement!.titre;
      _descCtrl.text = widget.logement!.description;
      _prixCtrl.text = widget.logement!.prix.toString();
      _surfaceCtrl.text = widget.logement!.surface.toString();
      _typeLocation = widget.logement!.typeLocation;
      _typeBien = widget.logement!.typeBien;
      _ville = widget.logement!.ville;
      _equipements.addAll(widget.logement!.equipements);
    }
  }

  @override
  void dispose() {
    _titreCtrl.dispose(); _descCtrl.dispose(); _prixCtrl.dispose(); _surfaceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.logement == null ? 'Nouvelle annonce' : 'Modifier l\'annonce'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photos
              const Text('Photos du bien', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              _PhotosUploadWidget(),
              const SizedBox(height: 20),

              // Titre
              const Text('Titre de l\'annonce *', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              TextFormField(
                controller: _titreCtrl,
                decoration: const InputDecoration(hintText: 'Ex: Studio meublé à Bastos'),
                validator: (v) => v!.isEmpty ? 'Champ requis' : null,
              ),
              const SizedBox(height: 16),

              // Type transaction
              const Text('Type de transaction *', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _ChoixCard(label: 'Location', icon: Icons.home_work, selected: _typeLocation == 'location', onTap: () => setState(() => _typeLocation = 'location'))),
                const SizedBox(width: 12),
                Expanded(child: _ChoixCard(label: 'Vente', icon: Icons.sell, selected: _typeLocation == 'vente', onTap: () => setState(() => _typeLocation = 'vente'))),
              ]),
              const SizedBox(height: 16),

              // Type de bien
              const Text('Type de bien *', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _typeBien,
                decoration: const InputDecoration(),
                items: _typesBiens.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => _typeBien = v!),
              ),
              const SizedBox(height: 16),

              // Ville
              const Text('Ville *', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _ville,
                decoration: const InputDecoration(),
                items: _villes.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (v) => setState(() => _ville = v!),
              ),
              const SizedBox(height: 16),

              // Prix
              const Text('Prix (XAF) *', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              TextFormField(
                controller: _prixCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'Ex: 150000',
                  suffixText: _typeLocation == 'location' ? 'XAF/mois' : 'XAF',
                ),
                validator: (v) => v!.isEmpty ? 'Champ requis' : null,
              ),
              const SizedBox(height: 16),

              // Surface
              const Text('Surface (m²)', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              TextFormField(
                controller: _surfaceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'Ex: 45', suffixText: 'm²'),
              ),
              const SizedBox(height: 16),

              // Description
              const Text('Description *', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descCtrl,
                maxLines: 4,
                decoration: const InputDecoration(hintText: 'Décrivez votre bien en détail...'),
                validator: (v) => v!.isEmpty ? 'Champ requis' : null,
              ),
              const SizedBox(height: 16),

              // Équipements
              const Text('Équipements', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _equipementsDispos.map((eq) {
                  final selected = _equipements.contains(eq);
                  return FilterChip(
                    label: Text(eq),
                    selected: selected,
                    selectedColor: AppColors.primaryLight,
                    checkmarkColor: AppColors.primary,
                    onSelected: (v) => setState(() => v ? _equipements.add(eq) : _equipements.remove(eq)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Géolocalisation
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Géolocaliser mon bien sur la carte', style: TextStyle(color: AppColors.primary))),
                    ElevatedButton(onPressed: () {}, child: const Text('Localiser', style: TextStyle(fontSize: 12))),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Bouton publier
              ElevatedButton(
                onPressed: _isSubmitting ? null : _publier,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                child: _isSubmitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(widget.logement == null ? 'Publier l\'annonce' : 'Enregistrer les modifications'),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _publier() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    await Future.delayed(const Duration(seconds: 1)); // Simule API
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.logement == null ? 'Annonce publiée avec succès !' : 'Annonce mise à jour !'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }
}

class _PhotosUploadWidget extends StatefulWidget {
  @override
  State<_PhotosUploadWidget> createState() => _PhotosUploadWidgetState();
}

class _PhotosUploadWidgetState extends State<_PhotosUploadWidget> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 100,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (int i = 0; i < _count; i++)
          Container(
            width: 100, height: 100,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.photo, color: AppColors.primary, size: 32),
          ),
        GestureDetector(
          onTap: () => setState(() => _count++),
          child: Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border, style: BorderStyle.solid, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_photo_alternate_outlined, color: AppColors.primary, size: 28),
                SizedBox(height: 4),
                Text('Ajouter', style: TextStyle(color: AppColors.primary, fontSize: 11)),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _ChoixCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ChoixCard({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: selected ? AppColors.primaryLight : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
      ),
      child: Column(
        children: [
          Icon(icon, color: selected ? AppColors.primary : AppColors.textSecondary, size: 28),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: selected ? AppColors.primary : AppColors.textSecondary, fontWeight: FontWeight.w600)),
        ],
      ),
    ),
  );
}