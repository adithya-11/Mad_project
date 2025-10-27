// lib/main.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(PetCareApp());
}

class PetCareApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pet Care App',
      theme: ThemeData(
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
        ),
      ),
      home: HomeScreen(),
    );
  }
}

/// -----------------------------
/// Pet model + persistence keys
/// -----------------------------
class Pet {
  final String id;
  String name;
  String type; // Dog, Cat, Bunny, Hamster
  int mood; // 0-100
  int energy; // 0-100
  int hunger; // 0-100 (0 = full, 100 = starving)
  int health; // 0-100
  DateTime lastFed;
  DateTime createdAt;

  Pet({
    required this.id,
    required this.name,
    required this.type,
    required this.mood,
    required this.energy,
    required this.hunger,
    required this.health,
    required this.lastFed,
    required this.createdAt,
  });

  factory Pet.createSeed({required String name, required String type}) {
    final now = DateTime.now();
    return Pet(
      id: 'pet_${now.millisecondsSinceEpoch}',
      name: name,
      type: type,
      mood: 70,
      energy: 80,
      hunger: 20,
      health: 90,
      lastFed: now.subtract(Duration(hours: 4)),
      createdAt: now,
    );
  }

  factory Pet.fromJson(Map<String, dynamic> j) {
    return Pet(
      id: j['id'] as String,
      name: j['name'] as String,
      type: j['type'] as String,
      mood: (j['mood'] as num).toInt(),
      energy: (j['energy'] as num).toInt(),
      hunger: (j['hunger'] as num).toInt(),
      health: (j['health'] as num).toInt(),
      lastFed: DateTime.parse(j['lastFed'] as String),
      createdAt: DateTime.parse(j['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'mood': mood,
        'energy': energy,
        'hunger': hunger,
        'health': health,
        'lastFed': lastFed.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };

  // simple small helpers to clamp values
  void _clampAll() {
    mood = mood.clamp(0, 100);
    energy = energy.clamp(0, 100);
    hunger = hunger.clamp(0, 100);
    health = health.clamp(0, 100);
  }

  void feed() {
    hunger -= 30; // reduce hunger
    mood += 8;
    energy += 10;
    lastFed = DateTime.now();
    _clampAll();
  }

  void play() {
    mood += 12;
    energy -= 18;
    hunger += 12;
    _clampAll();
  }

  void rest() {
    energy += 24;
    mood += 6;
    hunger += 6;
    _clampAll();
  }

  // small decay over time (call occasionally)
  void timeTick(Duration elapsed) {
    // every hour increases hunger slightly and decreases energy
    final hours = elapsed.inHours;
    if (hours <= 0) return;
    hunger += (hours * 2);
    energy -= (hours * 1);
    mood -= (hours * 1);
    // if starving, health drops
    if (hunger > 80) health -= (hours * 1);
    _clampAll();
  }
}

const String _kPetsKey = 'petcare_pets_v1';

/// -----------------------------
/// Home Screen: loads/saves pets
/// -----------------------------
class HomeScreen extends StatefulWidget {
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Pet> pets = [];
  bool loading = true;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    _prefs = await SharedPreferences.getInstance();
    _loadPets();
    setState(() {
      loading = false;
    });
  }

  void _loadPets() {
    final s = _prefs?.getString(_kPetsKey);
    if (s == null) {
      // seed sample pet so UI isn't empty
      pets = [
        Pet.createSeed(name: 'Mochi', type: 'Cat'),
      ];
      _savePets();
      return;
    }
    try {
      final list = json.decode(s) as List<dynamic>;
      pets = list.map((e) => Pet.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      pets = [Pet.createSeed(name: 'Mochi', type: 'Cat')];
      _savePets();
    }
  }

  Future<void> _savePets() async {
    if (_prefs == null) return;
    final s = json.encode(pets.map((p) => p.toJson()).toList());
    await _prefs!.setString(_kPetsKey, s);
  }

  Future<void> _addPet(String name, String type) async {
    final pet = Pet.createSeed(name: name.isEmpty ? 'Unnamed' : name, type: type);
    setState(() {
      pets.add(pet);
    });
    await _savePets();
    _showSnack('Adopted ${pet.name} the ${pet.type}!');
  }

  Future<void> _deletePet(String id) async {
    setState(() {
      pets.removeWhere((p) => p.id == id);
    });
    await _savePets();
    _showSnack('Pet removed');
  }

  Future<void> _updatePet(Pet pet) async {
    final index = pets.indexWhere((p) => p.id == pet.id);
    if (index >= 0) {
      pets[index] = pet;
      await _savePets();
      setState(() {});
    }
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _showAdoptDialog() async {
    String name = '';
    String selectedType = 'Dog';
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Adopt a pet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(decoration: InputDecoration(labelText: 'Pet name'), onChanged: (v) => name = v),
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
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              _addPet(name, selectedType);
              Navigator.of(ctx).pop();
            },
            child: Text('Adopt'),
          )
        ],
      ),
    );
  }

  // Open pet detail sheet
  void _openPetDetail(Pet pet) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.64,
        minChildSize: 0.36,
        maxChildSize: 0.9,
        builder: (_, ctl) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: ListView(
              controller: ctl,
              children: [
                Center(
                  child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(4))),
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(radius: 36, backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.14), child: Icon(Icons.pets, size: 36, color: Theme.of(context).colorScheme.primary)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(pet.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                        SizedBox(height: 4),
                        Text(pet.type, style: TextStyle(color: Colors.black54)),
                      ]),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline),
                      onPressed: () {
                        Navigator.of(context).pop();
                        _confirmDelete(pet);
                      },
                    ),
                  ],
                ),
                SizedBox(height: 18),
                _statRow('Mood', pet.mood),
                SizedBox(height: 8),
                _statRow('Energy', pet.energy),
                SizedBox(height: 8),
                _statRow('Hunger', 100 - pet.hunger, suffixHint: '(fullness)'), // show fullness
                SizedBox(height: 8),
                _statRow('Health', pet.health),
                SizedBox(height: 16),
                Text('Last fed: ${_formatRelative(pet.lastFed)}', style: TextStyle(color: Colors.black54)),
                SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.fastfood),
                        label: Text('Feed'),
                        onPressed: () async {
                          pet.feed();
                          await _updatePet(pet);
                          setState(() {});
                          _showSnack('Fed ${pet.name}');
                        },
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.sports_esports),
                        label: Text('Play'),
                        onPressed: () async {
                          pet.play();
                          await _updatePet(pet);
                          setState(() {});
                          _showSnack('Played with ${pet.name}');
                        },
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.hotel),
                        label: Text('Rest'),
                        onPressed: () async {
                          pet.rest();
                          await _updatePet(pet);
                          setState(() {});
                          _showSnack('${pet.name} is resting');
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 18),
                Text('Tip: Actions update the on-device saved state. Stage 3 will add user profiles and Stage 6 will add richer interactions & animations.', style: TextStyle(color: Colors.black54)),
                SizedBox(height: 18),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(Pet pet) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${pet.name}?'),
        content: Text('This will permanently remove the pet from local storage.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('Remove')),
        ],
      ),
    );
    if (ok == true) {
      await _deletePet(pet.id);
      setState(() {});
    }
  }

  String _formatRelative(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _statRow(String label, int value, {String? suffixHint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w600)),
          if (suffixHint != null) Text(suffixHint, style: TextStyle(color: Colors.black45, fontSize: 12)),
        ]),
        SizedBox(height: 6),
        LinearProgressIndicator(value: value / 100.0, minHeight: 8),
        SizedBox(height: 6),
        Text('$value / 100', style: TextStyle(color: Colors.black54, fontSize: 12)),
      ],
    );
  }

  // quick compact pet card for list
  Widget _petCard(Pet p) {
    return GestureDetector(
      onTap: () => _openPetDetail(p),
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 8),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
        ),
        child: Row(
          children: [
            CircleAvatar(radius: 28, backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.12), child: Icon(Icons.pets, color: Theme.of(context).colorScheme.primary)),
            SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    Expanded(child: Text(p.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                    Text(p.type, style: TextStyle(color: Colors.black54)),
                  ],
                ),
                SizedBox(height: 8),
                LinearProgressIndicator(value: p.mood / 100.0, minHeight: 6),
                SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.favorite, size: 14, color: Colors.redAccent),
                    SizedBox(width: 6),
                    Text('Mood ${p.mood}'),
                    SizedBox(width: 12),
                    Icon(Icons.local_fire_department, size: 14, color: Colors.orange),
                    SizedBox(width: 6),
                    Text('Energy ${p.energy}'),
                  ],
                ),
              ]),
            ),
            SizedBox(width: 8),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'feed') {
                  p.feed();
                  await _updatePet(p);
                  _showSnack('Fed ${p.name}');
                } else if (v == 'play') {
                  p.play();
                  await _updatePet(p);
                  _showSnack('Played with ${p.name}');
                } else if (v == 'rest') {
                  p.rest();
                  await _updatePet(p);
                  _showSnack('${p.name} rested');
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'feed', child: Text('Feed')),
                PopupMenuItem(value: 'play', child: Text('Play')),
                PopupMenuItem(value: 'rest', child: Text('Rest')),
              ],
              child: Icon(Icons.more_vert),
            ),
          ],
        ),
      ),
    );
  }

  // main UI build
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.background,
      appBar: AppBar(
        title: Text('Pet Care App'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(icon: Icon(Icons.refresh_rounded), onPressed: () {
            // manual small "tick" to simulate time passing 1 hour
            for (var p in pets) {
              p.timeTick(Duration(hours: 1));
            }
            _savePets();
            setState(() {});
            _showSnack('Simulated 1 hour tick for all pets');
          }),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAdoptDialog,
        icon: Icon(Icons.pets),
        label: Text('Adopt'),
      ),
      body: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: loading
            ? Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(colors: [cs.primary.withOpacity(0.95), cs.secondary.withOpacity(0.9)]),
                      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 6))],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(radius: 30, backgroundColor: Colors.white.withOpacity(0.2), child: Icon(Icons.emoji_emotions, color: Colors.white)),
                        SizedBox(width: 12),
                        Expanded(child: Text('Welcome back! ${pets.isEmpty ? 'No pets yet' : 'You have ${pets.length} pet(s)'}', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                        TextButton.icon(
                          onPressed: () {
                            // quick backup/export to console (for dev)
                            final s = json.encode(pets.map((p) => p.toJson()).toList());
                            showDialog(context: context, builder: (_) => AlertDialog(title: Text('Local JSON snapshot'), content: SingleChildScrollView(child: SelectableText(s)), actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Close'))]));
                          },
                          icon: Icon(Icons.share, color: Colors.white),
                          label: Text('Export', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 14),
                  Expanded(
                    child: pets.isEmpty
                        ? Center(child: Text('No pets yet — adopt one using the + button', style: TextStyle(color: Colors.black54)))
                        : ListView.builder(
                            itemCount: pets.length,
                            itemBuilder: (_, i) => _petCard(pets[i]),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
