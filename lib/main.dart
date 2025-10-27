import 'package:flutter/material.dart';

void main() {
  runApp(PetCareApp());
}

class PetCareApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pet Care App',
      theme: ThemeData(
        // Modern, warm color theme
        colorScheme: ColorScheme.fromSeed(
          seedColor: Color(0xFF6C63FF),
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFFFFB86B),
          background: Color(0xFFF6F7FB),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black87,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ),
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Stage 1: placeholder dashboard with single-file UI.
/// Later stages will add models, persistence, actions, and other screens.
class _HomeScreenState extends State<HomeScreen> {
  String _status = 'No pets yet';
  int _seedCounter = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.background,
      appBar: AppBar(
        title: Text('Pet Care App'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header card with warm gradient
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [
                    cs.primary.withOpacity(0.95),
                    cs.secondary.withOpacity(0.9),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  )
                ],
              ),
              child: Row(
                children: [
                  // Minimal circular placeholder "avatar"
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: Colors.white.withOpacity(0.25),
                    child: Icon(Icons.pets, size: 34, color: Colors.white),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Welcome to Pet Care',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700)),
                        SizedBox(height: 6),
                        Text(
                          'Adopt a virtual pet and give it love ✨',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 18),

            // Quick actions placeholder
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ActionCard(
                  icon: Icons.pets,
                  label: 'Adopt',
                  onTap: () => _showAdoptDialog(context),
                ),
                _ActionCard(
                  icon: Icons.fastfood,
                  label: 'Feed',
                  onTap: () => _showToast('Feed action will be added in Stage 6'),
                ),
                _ActionCard(
                  icon: Icons.vaccines,
                  label: 'Vet',
                  onTap: () => _showToast('Vet visits will be added in Stage 9'),
                ),
              ],
            ),

            SizedBox(height: 18),

            // Status box
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pet Status',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    SizedBox(height: 12),
                    Center(
                      child: Column(
                        children: [
                          Icon(Icons.pets, size: 86, color: cs.primary),
                          SizedBox(height: 8),
                          Text(_status, style: TextStyle(fontSize: 18)),
                          SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _seedCounter++;
                                _status = 'You have nurtured $_seedCounter tiny seeds — adopt soon!';
                              });
                              _showToast('Seed +1 (just a playful placeholder)');
                            },
                            icon: Icon(Icons.add),
                            label: Text('Nurture a seed (placeholder)'),
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Spacer(),
                    Text(
                      'Stage 1: scaffold only — future stages will add persistence, pet models, animations and shop.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showToast(String msg) {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.hideCurrentSnackBar();
    scaffold.showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showAdoptDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) {
        String name = '';
        String selectedType = 'Dog';
        return AlertDialog(
          title: Text('Adopt a pet (placeholder)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(labelText: 'Pet name'),
                onChanged: (v) => name = v,
              ),
              SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedType,
                items: ['Dog', 'Cat', 'Bunny', 'Hamster']
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => selectedType = v ?? 'Dog',
                decoration: InputDecoration(labelText: 'Pet type'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _status = 'Ready to adopt: ${name.isEmpty ? 'Unnamed' : name} the $selectedType';
                });
                Navigator.of(context).pop();
                _showToast('Adoption stub saved to UI state (no persistence in Stage 1)');
              },
              child: Text('Adopt'),
            ),
          ],
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionCard({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.primary.withOpacity(0.12)),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0,4))],
          ),
          child: Column(
            children: [
              CircleAvatar(
                backgroundColor: cs.primary.withOpacity(0.12),
                child: Icon(icon, color: cs.primary),
              ),
              SizedBox(height: 8),
              Text(label, style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
