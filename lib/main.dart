// lib/main.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(PetCareApp());
}

/// -----------------------------
/// Constants / Pref keys
/// -----------------------------
const String _kProfilesKey = 'petcare_profiles_v1';
const String _kActiveProfileKey = 'petcare_active_profile_v1';
const String _kLegacyPetsKey = 'petcare_pets_v1'; // from Stage 2

/// -----------------------------
/// Pet model (same as Stage 2)
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

  void _clampAll() {
    mood = mood.clamp(0, 100);
    energy = energy.clamp(0, 100);
    hunger = hunger.clamp(0, 100);
    health = health.clamp(0, 100);
  }

  void feed() {
    hunger -= 30;
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

  void timeTick(Duration elapsed) {
    final hours = elapsed.inHours;
    if (hours <= 0) return;
    hunger += (hours * 2);
    energy -= (hours * 1);
    mood -= (hours * 1);
    if (hunger > 80) health -= (hours * 1);
    _clampAll();
  }
}

/// -----------------------------
/// Profile model
/// -----------------------------
class Profile {
  final String id;
  String name;
  DateTime createdAt;

  Profile({required this.id, required this.name, required this.createdAt});

  factory Profile.create(String name) {
    final now = DateTime.now();
    return Profile(id: 'profile_${now.millisecondsSinceEpoch}', name: name, createdAt: now);
  }

  factory Profile.fromJson(Map<String, dynamic> j) {
    return Profile(
      id: j['id'] as String,
      name: j['name'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'createdAt': createdAt.toIso8601String()};
}

/// -----------------------------
/// App widget
/// -----------------------------
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
/// HomeScreen: manages profiles + pets per-profile
/// -----------------------------
class HomeScreen extends StatefulWidget {
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SharedPreferences? _prefs;
  bool loading = true;

  // profiles and active profile id
  List<Profile> profiles = [];
  String? activeProfileId;

  // pets for the active profile
  List<Pet> pets = [];

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    _prefs = await SharedPreferences.getInstance();
    await _maybeMigrateLegacyPets();
    _loadProfiles();
    _loadActiveProfile();
    _loadPetsForActiveProfile();
    setState(() {
      loading = false;
    });
  }

  /// Migration:
  /// If there are pets under legacy key (from Stage 2) and no profiles exist,
  /// create a default profile and move those pets into it.
  Future<void> _maybeMigrateLegacyPets() async {
    final lp = _prefs;
    if (lp == null) return;
    final legacy = lp.getString(_kLegacyPetsKey);
    final existingProfiles = lp.getString(_kProfilesKey);
    if (legacy != null && (existingProfiles == null || existingProfiles.isEmpty)) {
      try {
        final list = json.decode(legacy) as List<dynamic>;
        final movedPets = list.map((e) => Pet.fromJson(e as Map<String, dynamic>)).toList();
        // create default profile
        final defaultProfile = Profile.create('You');
        // save profile list
        await lp.setString(_kProfilesKey, json.encode([defaultProfile.toJson()]));
        // set active profile
        await lp.setString(_kActiveProfileKey, defaultProfile.id);
        // save pets under new per-profile key
        final petKey = _petsKeyForProfile(defaultProfile.id);
        await lp.setString(petKey, json.encode(movedPets.map((p) => p.toJson()).toList()));
        // remove legacy key
        await lp.remove(_kLegacyPetsKey);
      } catch (e) {
        // ignore parse errors; no migration performed
      }
    }
  }

  void _loadProfiles() {
    final s = _prefs?.getString(_kProfilesKey);
    if (s == null) {
      profiles = []; // empty until user creates
      return;
    }
    try {
      final list = json.decode(s) as List<dynamic>;
      profiles = list.map((e) => Profile.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      profiles = [];
    }
  }

  void _loadActiveProfile() {
    final s = _prefs?.getString(_kActiveProfileKey);
    if (s == null) {
      activeProfileId = profiles.isNotEmpty ? profiles.first.id : null;
      if (activeProfileId != null) _prefs?.setString(_kActiveProfileKey, activeProfileId!);
      return;
    }
    activeProfileId = s;
    // ensure active exists; if not, reset to first profile if available
    if (activeProfileId != null && !profiles.any((p) => p.id == activeProfileId)) {
      activeProfileId = profiles.isNotEmpty ? profiles.first.id : null;
      if (activeProfileId != null) _prefs?.setString(_kActiveProfileKey, activeProfileId!);
    }
  }

  void _loadPetsForActiveProfile() {
    pets = [];
    if (activeProfileId == null) return;
    final key = _petsKeyForProfile(activeProfileId!);
    final s = _prefs?.getString(key);
    if (s == null) {
      // seed a friendly pet for new profile
      pets = [Pet.createSeed(name: 'Mochi', type: 'Cat')];
      _savePetsForActiveProfile();
      return;
    }
    try {
      final list = json.decode(s) as List<dynamic>;
      pets = list.map((e) => Pet.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      pets = [Pet.createSeed(name: 'Mochi', type: 'Cat')];
      _savePetsForActiveProfile();
    }
  }

  String _petsKeyForProfile(String profileId) => 'pets_for_$profileId';

  Future<void> _saveProfiles() async {
    if (_prefs == null) return;
    await _prefs!.setString(_kProfilesKey, json.encode(profiles.map((p) => p.toJson()).toList()));
  }

  Future<void> _setActiveProfile(String profileId) async {
    if (_prefs == null) return;
    activeProfileId = profileId;
    await _prefs!.setString(_kActiveProfileKey, profileId);
    _loadPetsForActiveProfile();
    setState(() {});
  }

  Future<void> _savePetsForActiveProfile() async {
    if (_prefs == null || activeProfileId == null) return;
    final key = _petsKeyForProfile(activeProfileId!);
    await _prefs!.setString(key, json.encode(pets.map((p) => p.toJson()).toList()));
  }

  Future<void> _addProfile(String name) async {
    final p = Profile.create(name.isEmpty ? 'Profile' : name);
    profiles.add(p);
    await _saveProfiles();
    await _setActiveProfile(p.id);
    _showSnack('Created profile "${p.name}" and switched to it');
  }

  Future<void> _deleteProfile(String profileId) async {
    final toRemove = profiles.firstWhere((p) => p.id == profileId, orElse: () => throw StateError('not found'));
    // remove associated pets key
    await _prefs?.remove(_petsKeyForProfile(profileId));
    profiles.removeWhere((p) => p.id == profileId);
    await _saveProfiles();

    // if removed active, switch to another or null
    if (activeProfileId == profileId) {
      if (profiles.isNotEmpty) {
        await _setActiveProfile(profiles.first.id);
      } else {
        activeProfileId = null;
        await _prefs?.remove(_kActiveProfileKey);
        pets = [];
        setState(() {});
      }
    } else {
      setState(() {});
    }

    _showSnack('Removed profile "${toRemove.name}"');
  }

  Future<void> _addPet(String name, String type) async {
    final pet = Pet.createSeed(name: name.isEmpty ? 'Unnamed' : name, type: type);
    pets.add(pet);
    await _savePetsForActiveProfile();
    setState(() {});
    _showSnack('Adopted ${pet.name}');
  }

  Future<void> _deletePet(String id) async {
    pets.removeWhere((p) => p.id == id);
    await _savePetsForActiveProfile();
    setState(() {});
  }

  Future<void> _updatePet(Pet pet) async {
    final idx = pets.indexWhere((p) => p.id == pet.id);
    if (idx >= 0) {
      pets[idx] = pet;
      await _savePetsForActiveProfile();
      setState(() {});
    }
  }

  void _showSnack(String txt) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(txt)));
  }

  // UI: create profile dialog
  Future<void> _showCreateProfileDialog() async {
    String name = '';
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Create profile'),
        content: TextField(
          decoration: InputDecoration(labelText: 'Profile name'),
          onChanged: (v) => name = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _addProfile(name.isEmpty ? 'Profile' : name);
            },
            child: Text('Create'),
          ),
        ],
      ),
    );
  }

  // UI: choose/switch profile menu
  Widget _profileSelector() {
    final active = profiles.firstWhere((p) => p.id == activeProfileId, orElse: () => Profile(id: 'none', name: 'No profile', createdAt: DateTime.now()));
    return PopupMenuButton<String>(
      tooltip: 'Profiles',
      icon: CircleAvatar(
        radius: 16,
        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.12),
        child: Text(active.name.isNotEmpty ? active.name[0].toUpperCase() : '?', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
      ),
      itemBuilder: (_) {
        final items = <PopupMenuEntry<String>>[];
        if (profiles.isEmpty) {
          items.add(PopupMenuItem(child: Text('No profiles yet'), value: 'noop'));
        } else {
          for (final p in profiles) {
            items.add(PopupMenuItem(
              value: p.id,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(p.name),
                  if (p.id == activeProfileId) Icon(Icons.check, size: 18, color: Theme.of(context).colorScheme.primary),
                ],
              ),
            ));
          }
        }
        items.add(const PopupMenuDivider());
        items.add(PopupMenuItem(value: 'create', child: Text('Create profile')));
        if (profiles.isNotEmpty) items.add(PopupMenuItem(value: 'manage', child: Text('Manage profiles')));
        return items;
      },
      onSelected: (v) {
        if (v == 'create') {
          _showCreateProfileDialog();
        } else if (v == 'manage') {
          _showManageProfilesSheet();
        } else if (v == 'noop') {
          // do nothing
        } else {
          _setActiveProfile(v);
        }
      },
    );
  }

  Future<void> _showManageProfilesSheet() async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: EdgeInsets.all(12),
        height: 320,
        child: Column(
          children: [
            Text('Manage profiles', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            SizedBox(height: 12),
            Expanded(
              child: profiles.isEmpty
                  ? Center(child: Text('No profiles'))
                  : ListView.builder(
                      itemCount: profiles.length,
                      itemBuilder: (_, i) {
                        final p = profiles[i];
                        final isActive = p.id == activeProfileId;
                        return ListTile(
                          leading: CircleAvatar(child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : '?')),
                          title: Text(p.name),
                          subtitle: Text('Created ${_formatDate(p.createdAt)}'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (isActive) Padding(padding: EdgeInsets.only(right: 8), child: Chip(label: Text('Active'))),
                            IconButton(
                              icon: Icon(Icons.delete_outline),
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (dctx) => AlertDialog(
                                    title: Text('Remove profile "${p.name}"?'),
                                    content: Text('This will delete the profile and its local pets.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: Text('Cancel')),
                                      ElevatedButton(onPressed: () => Navigator.of(dctx).pop(true), child: Text('Remove')),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  // if removing last profile, confirm
                                  await _deleteProfile(p.id);
                                  Navigator.of(context).pop(); // close sheet to refresh gracefully
                                  _showManageProfilesSheet(); // reopen to show updated list
                                }
                              },
                            ),
                          ]),
                          onTap: () {
                            _setActiveProfile(p.id);
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  // Adopt dialog now links pet to active profile
  Future<void> _showAdoptDialog() async {
    if (activeProfileId == null) {
      _showSnack('Create a profile first');
      return;
    }
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
              Navigator.of(ctx).pop();
              _addPet(name, selectedType);
            },
            child: Text('Adopt'),
          )
        ],
      ),
    );
  }

  // Pet detail sheet (same UX as Stage 2), but persists per-profile
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
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(4)))),
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
                _statRow('Hunger', 100 - pet.hunger, suffixHint: '(fullness)'),
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
                          _showSnack('${pet.name} is resting');
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 18),
                Text('Profile: ${_activeProfileName()}', style: TextStyle(color: Colors.black54)),
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
        content: Text('This will permanently remove the pet from this profile.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('Remove')),
        ],
      ),
    );
    if (ok == true) {
      await _deletePet(pet.id);
    }
  }

  String _activeProfileName() {
    final p = profiles.firstWhere((p) => p.id == activeProfileId, orElse: () => Profile(id: 'none', name: 'No profile', createdAt: DateTime.now()));
    return p.name;
  }

  // Helper UI bits: stat row and pet card
  Widget _statRow(String label, int value, {String? suffixHint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w600)),
          if (suffixHint != null) Text(suffixHint, style: TextStyle(color: Colors.black45, fontSize: 12)),
        ]),
        SizedBox(height: 6),
        LinearProgressIndicator(value: (value.clamp(0, 100)) / 100.0, minHeight: 8),
        SizedBox(height: 6),
        Text('$value / 100', style: TextStyle(color: Colors.black54, fontSize: 12)),
      ],
    );
  }

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

  // helper to format last-fed time nicely
  String _formatRelative(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    // older: show date
    return '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';
  }

  // UI build
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.background,
      appBar: AppBar(
        title: Text('Pet Care App'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded),
            onPressed: () {
              // simulate 1 hour for pets
              for (var p in pets) p.timeTick(Duration(hours: 1));
              _savePetsForActiveProfile();
              setState(() {});
              _showSnack('Simulated 1 hour tick for this profile');
            },
          ),
          _profileSelector(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAdoptDialog,
        icon: Icon(Icons.pets),
        label: Text('Adopt'),
      ),
      body: SafeArea(
        minimum: EdgeInsets.all(16),
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
                        Expanded(
                          child: Text(
                            activeProfileId == null ? 'No profile — create one' : 'Profile: ${_activeProfileName()} · ${pets.length} pet(s)',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            // quick export for active profile
                            final s = json.encode(pets.map((p) => p.toJson()).toList());
                            showDialog(context: context, builder: (_) => AlertDialog(title: Text('Profile JSON snapshot'), content: SingleChildScrollView(child: SelectableText(s)), actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Close'))]));
                          },
                          icon: Icon(Icons.share, color: Colors.white),
                          label: Text('Export', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 14),
                  Expanded(
                    child: activeProfileId == null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('No profile yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                                SizedBox(height: 12),
                                ElevatedButton.icon(onPressed: _showCreateProfileDialog, icon: Icon(Icons.add), label: Text('Create profile')),
                              ],
                            ),
                          )
                        : pets.isEmpty
                            ? Center(child: Text('No pets — adopt one using the + button', style: TextStyle(color: Colors.black54)))
                            : ListView.builder(itemCount: pets.length, itemBuilder: (_, i) => _petCard(pets[i])),
                  ),
                ],
              ),
      ),
    );
  }
}
