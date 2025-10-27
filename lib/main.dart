// lib/main.dart
import 'dart:async';
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
/// Helper: choose white/black foreground depending on background contrast
/// (top-level so all widgets can call it)
/// -----------------------------
bool useWhiteForeground(Color backgroundColor, {double bias = 0.0}) {
  final double v = (0.299 * backgroundColor.red + 0.587 * backgroundColor.green + 0.114 * backgroundColor.blue) / 255;
  return v < 0.5 + bias;
}

/// -----------------------------
/// Pet model (with avatar fields)
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

  // customization
  int avatarColorValue;
  String avatarEmoji;

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
    required this.avatarColorValue,
    required this.avatarEmoji,
  });

  factory Pet.createSeed({required String name, required String type}) {
    final now = DateTime.now();
    final idx = (now.millisecondsSinceEpoch ~/ 1000) % Colors.primaries.length;
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
      avatarColorValue: Colors.primaries[idx].value,
      avatarEmoji: _defaultEmojiForType(type),
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
      avatarColorValue: j.containsKey('avatarColorValue') ? (j['avatarColorValue'] as num).toInt() : Colors.blue.value,
      avatarEmoji: j.containsKey('avatarEmoji') ? (j['avatarEmoji'] as String) : _defaultEmojiForType(j['type'] as String),
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
        'avatarColorValue': avatarColorValue,
        'avatarEmoji': avatarEmoji,
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

/// helper: choose an emoji based on type
String _defaultEmojiForType(String type) {
  switch (type.toLowerCase()) {
    case 'dog':
      return '🐶';
    case 'cat':
      return '🐱';
    case 'bunny':
      return '🐰';
    case 'hamster':
      return '🐹';
    default:
      return '🐾';
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
/// HomeScreen: manages profiles + pets per-profile + dashboard
/// -----------------------------
class HomeScreen extends StatefulWidget {
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  SharedPreferences? _prefs;
  bool loading = true;

  // profiles and active profile id
  List<Profile> profiles = [];
  String? activeProfileId;

  // pets for the active profile
  List<Pet> pets = [];

  // activity feed per-profile (in-memory; persisted along with pets)
  List<String> activity = [];

  // simulation timer
  Timer? _simTimer;
  bool simulationOn = false;

  // UI palettes
  final List<Color> _palette = [
    Colors.purple,
    Colors.blue,
    Colors.teal,
    Colors.green,
    Colors.orange,
    Colors.pink,
    Colors.indigo,
    Colors.brown,
  ];

  final List<String> _emojiChoices = ['🐶', '🐱', '🐰', '🐹', '🐾', '🦊', '🐻', '🐼'];

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    super.dispose();
  }

  Future<void> _initAndLoad() async {
    _prefs = await SharedPreferences.getInstance();
    await _maybeMigrateLegacyPets();
    _loadProfiles();
    _loadActiveProfile();
    _loadPetsForActiveProfile();
    _loadActivity();
    setState(() {
      loading = false;
    });
  }

  /// Migration from Stage 2 legacy storage
  Future<void> _maybeMigrateLegacyPets() async {
    final lp = _prefs;
    if (lp == null) return;
    final legacy = lp.getString(_kLegacyPetsKey);
    final existingProfiles = lp.getString(_kProfilesKey);
    if (legacy != null && (existingProfiles == null || existingProfiles.isEmpty)) {
      try {
        final list = json.decode(legacy) as List<dynamic>;
        final movedPets = list.map((e) => Pet.fromJson(e as Map<String, dynamic>)).toList();
        final defaultProfile = Profile.create('You');
        await lp.setString(_kProfilesKey, json.encode([defaultProfile.toJson()]));
        await lp.setString(_kActiveProfileKey, defaultProfile.id);
        final petKey = _petsKeyForProfile(defaultProfile.id);
        await lp.setString(petKey, json.encode(movedPets.map((p) => p.toJson()).toList()));
        await lp.remove(_kLegacyPetsKey);
      } catch (e) {
        // ignore
      }
    }
  }

  void _loadProfiles() {
    final s = _prefs?.getString(_kProfilesKey);
    if (s == null) {
      profiles = [];
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
    active_profile_check(s);
  }

  void active_profile_check(String s) {
    activeProfileId = s;
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
  String _activityKeyForProfile(String profileId) => 'activity_for_$profileId';

  Future<void> _saveProfiles() async {
    if (_prefs == null) return;
    await _prefs!.setString(_kProfilesKey, json.encode(profiles.map((p) => p.toJson()).toList()));
  }

  Future<void> _setActiveProfile(String profileId) async {
    if (_prefs == null) return;
    activeProfileId = profileId;
    await _prefs!.setString(_kActiveProfileKey, profileId);
    _loadPetsForActiveProfile();
    _loadActivity();
    setState(() {});
  }

  Future<void> _savePetsForActiveProfile() async {
    if (_prefs == null || activeProfileId == null) return;
    final key = _petsKeyForProfile(activeProfileId!);
    await _prefs!.setString(key, json.encode(pets.map((p) => p.toJson()).toList()));
  }

  Future<void> _saveActivity() async {
    if (_prefs == null || activeProfileId == null) return;
    final key = _activityKeyForProfile(activeProfileId!);
    await _prefs!.setString(key, json.encode(activity));
  }

  void _loadActivity() {
    activity = [];
    if (activeProfileId == null) return;
    final s = _prefs?.getString(_activityKeyForProfile(activeProfileId!));
    if (s == null) {
      activity = ['Welcome! Adopt a pet to begin.'];
      _saveActivity();
      return;
    }
    try {
      final list = json.decode(s) as List<dynamic>;
      activity = list.map((e) => e.toString()).toList();
    } catch (e) {
      activity = ['Welcome!'];
      _saveActivity();
    }
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
    await _prefs?.remove(_petsKeyForProfile(profileId));
    await _prefs?.remove(_activityKeyForProfile(profileId));
    profiles.removeWhere((p) => p.id == profileId);
    await _saveProfiles();

    if (activeProfileId == profileId) {
      if (profiles.isNotEmpty) {
        await _setActiveProfile(profiles.first.id);
      } else {
        activeProfileId = null;
        await _prefs?.remove(_kActiveProfileKey);
        pets = [];
        activity = [];
        setState(() {});
      }
    } else {
      setState(() {});
    }

    _showSnack('Removed profile "${toRemove.name}"');
  }

  Future<void> _addPet(String name, String type, {int? avatarColorValue, String? avatarEmoji}) async {
    final now = DateTime.now();
    final pet = Pet(
      id: 'pet_${now.millisecondsSinceEpoch}',
      name: name.isEmpty ? 'Unnamed' : name,
      type: type,
      mood: 70,
      energy: 80,
      hunger: 20,
      health: 90,
      lastFed: now.subtract(Duration(hours: 4)),
      createdAt: now,
      avatarColorValue: avatarColorValue ?? _palette[0].value,
      avatarEmoji: avatarEmoji ?? _defaultEmojiForType(type),
    );
    pets.add(pet);
    activity.insert(0, '${pet.name} adopted • ${_formatRelative(now)}');
    await _savePetsForActiveProfile();
    await _saveActivity();
    setState(() {});
    _showSnack('Adopted ${pet.name}');
  }

  Future<void> _deletePet(String id) async {
    final removed = pets.firstWhere((p) => p.id == id, orElse: () => throw StateError('not found'));
    pets.removeWhere((p) => p.id == id);
    activity.insert(0, '${removed.name} removed • ${_formatRelative(DateTime.now())}');
    await _savePetsForActiveProfile();
    await _saveActivity();
    setState(() {});
  }

  // Modified _updatePet to handle normal updates and REMOVE:<id> commands
  Future<void> _updatePet(Pet pet, {String? actionLabel}) async {
    // If the actionLabel signals a REMOVE command, perform deletion
    if (actionLabel != null && actionLabel.startsWith('REMOVE:')) {
      final id = actionLabel.substring('REMOVE:'.length);
      // ensure we remove matching id
      await _deletePet(id);
      return;
    }

    final idx = pets.indexWhere((p) => p.id == pet.id);
    if (idx >= 0) {
      pets[idx] = pet;
      if (actionLabel != null) {
        activity.insert(0, '$actionLabel • ${_formatRelative(DateTime.now())}');
      }
      await _savePetsForActiveProfile();
      await _saveActivity();
      setState(() {});
    }
  }

  void _showSnack(String txt) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(txt)));
  }

  // Profile UI
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
                                  await _deleteProfile(p.id);
                                  Navigator.of(context).pop(); // close sheet and reopen to refresh
                                  _showManageProfilesSheet();
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

  // Adopt dialog (supports avatar customization)
  Future<void> _showAdoptDialog() async {
    if (activeProfileId == null) {
      _showSnack('Create a profile first');
      return;
    }
    String name = '';
    String selectedType = 'Dog';
    Color selectedColor = _palette.first;
    String selectedEmoji = _defaultEmojiForType(selectedType);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Adopt a pet'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(decoration: InputDecoration(labelText: 'Pet name'), onChanged: (v) => name = v),
                SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  items: ['Dog', 'Cat', 'Bunny', 'Hamster']
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) {
                    selectedType = v ?? selectedType;
                    selectedEmoji = _defaultEmojiForType(selectedType);
                    setLocal(() {});
                  },
                  decoration: InputDecoration(labelText: 'Pet type'),
                ),
                SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: Text('Choose avatar emoji', style: TextStyle(fontWeight: FontWeight.w600))),
                SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _emojiChoices.map((e) {
                    final isSelected = e == selectedEmoji;
                    return ChoiceChip(
                      label: Text(e, style: TextStyle(fontSize: 20)),
                      selected: isSelected,
                      onSelected: (_) => setLocal(() => selectedEmoji = e),
                    );
                  }).toList(),
                ),
                SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: Text('Choose avatar color', style: TextStyle(fontWeight: FontWeight.w600))),
                SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _palette.map((c) {
                    final isSelected = c.value == selectedColor.value;
                    return GestureDetector(
                      onTap: () => setLocal(() => selectedColor = c),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: isSelected ? Border.all(color: Colors.black26, width: 3) : null,
                        ),
                        child: isSelected ? Icon(Icons.check, color: useWhiteForeground(c) ? Colors.white : Colors.black) : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _addPet(name, selectedType, avatarColorValue: selectedColor.value, avatarEmoji: selectedEmoji);
              },
              child: Text('Adopt'),
            )
          ],
        ),
      ),
    );
  }

  // Pet detail + dashboard entrypoint
  void _openPetDetail(Pet pet) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => DashboardView(pet: pet, onUpdate: (updated, label) => _updatePet(updated, actionLabel: label))));
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

  // Edit pet dialog (simple)
  Future<void> _showEditPetDialog(Pet pet) async {
    String name = pet.name;
    String selectedEmoji = pet.avatarEmoji;
    Color selectedColor = Color(pet.avatarColorValue);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: Text('Edit ${pet.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(decoration: InputDecoration(labelText: 'Pet name'), controller: TextEditingController(text: name), onChanged: (v) => name = v),
                SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: Text('Choose emoji', style: TextStyle(fontWeight: FontWeight.w600))),
                SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _emojiChoices.map((e) {
                    final isSelected = e == selectedEmoji;
                    return ChoiceChip(
                      label: Text(e, style: TextStyle(fontSize: 20)),
                      selected: isSelected,
                      onSelected: (_) => setLocal(() => selectedEmoji = e),
                    );
                  }).toList(),
                ),
                SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: Text('Choose avatar color', style: TextStyle(fontWeight: FontWeight.w600))),
                SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _palette.map((c) {
                    final isSelected = c.value == selectedColor.value;
                    return GestureDetector(
                      onTap: () => setLocal(() => selectedColor = c),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: isSelected ? Border.all(color: Colors.black26, width: 3) : null,
                        ),
                        child: isSelected ? Icon(Icons.check, color: useWhiteForeground(c) ? Colors.white : Colors.black) : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                pet.name = name.isEmpty ? pet.name : name;
                pet.avatarEmoji = selectedEmoji;
                pet.avatarColorValue = selectedColor.value;
                _updatePet(pet);
                Navigator.of(ctx).pop();
                _showSnack('Updated ${pet.name}');
              },
              child: Text('Save'),
            ),
          ],
        );
      }),
    );
  }

  // stat row for compact list (unused by dashboard)
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
            CircleAvatar(
              radius: 28,
              backgroundColor: Color(p.avatarColorValue).withOpacity(0.14),
              child: Text(p.avatarEmoji, style: TextStyle(fontSize: 24)),
            ),
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
                  await _updatePet(p, actionLabel: 'Fed ${p.name}');
                } else if (v == 'play') {
                  p.play();
                  await _updatePet(p, actionLabel: 'Played with ${p.name}');
                } else if (v == 'rest') {
                  p.rest();
                  await _updatePet(p, actionLabel: '${p.name} rested');
                } else if (v == 'edit') {
                  _showEditPetDialog(p);
                } else if (v == 'delete') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (dctx) => AlertDialog(
                      title: Text('Remove ${p.name}?'),
                      content: Text('This will permanently remove the pet from this profile.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: Text('Cancel')),
                        ElevatedButton(onPressed: () => Navigator.of(dctx).pop(true), child: Text('Remove')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await _deletePet(p.id);
                  }
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'feed', child: Text('Feed')),
                PopupMenuItem(value: 'play', child: Text('Play')),
                PopupMenuItem(value: 'rest', child: Text('Rest')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
              child: Icon(Icons.more_vert),
            ),
          ],
        ),
      ),
    );
  }

  // activity and formatting helpers
  String _formatRelative(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
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
            icon: Icon(simulationOn ? Icons.pause_circle_filled : Icons.play_circle_fill),
            tooltip: simulationOn ? 'Pause simulation' : 'Start simulation (10s = 1h)',
            onPressed: () {
              setState(() {
                simulationOn = !simulationOn;
                if (simulationOn) {
                  _simTimer?.cancel();
                  _simTimer = Timer.periodic(Duration(seconds: 10), (_) => _simulateHourTick());
                } else {
                  _simTimer?.cancel();
                  _simTimer = null;
                }
              });
            },
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded),
            tooltip: 'Simulate single hour tick for profile',
            onPressed: () {
              _simulateHourTick();
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
        minimum: const EdgeInsets.all(16),
        child: loading
            ? Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // header card
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
                        CircleAvatar(radius: 30, backgroundColor: Colors.white.withOpacity(0.2), child: Text(_activeProfileName().isNotEmpty ? _activeProfileName()[0].toUpperCase() : '?', style: TextStyle(color: Colors.white, fontSize: 24))),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            activeProfileId == null ? 'No profile — create one' : 'Profile: ${_activeProfileName()} · ${pets.length} pet(s)',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
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

                  // responsive area: left = list, right = dashboard / activity (or stacked on small screens)
                  Expanded(
                    child: LayoutBuilder(builder: (context, constraints) {
                      final wide = constraints.maxWidth > 900;
                      if (activeProfileId == null) {
                        return Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text('No profile yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                            SizedBox(height: 12),
                            ElevatedButton.icon(onPressed: _showCreateProfileDialog, icon: Icon(Icons.add), label: Text('Create profile')),
                          ]),
                        );
                      }

                      final left = Container(
                        width: double.infinity,
                        child: Column(
                          children: [
                            Align(alignment: Alignment.centerLeft, child: Text('Your pets', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                            SizedBox(height: 8),
                            Expanded(
                              child: pets.isEmpty
                                  ? Center(child: Text('No pets — adopt one using the + button', style: TextStyle(color: Colors.black54)))
                                  : ListView.builder(itemCount: pets.length, itemBuilder: (_, i) {
                                      final p = pets[i];
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
                                              CircleAvatar(radius: 28, backgroundColor: Color(p.avatarColorValue).withOpacity(0.14), child: Text(p.avatarEmoji, style: TextStyle(fontSize: 24))),
                                              SizedBox(width: 12),
                                              Expanded(
                                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                  Row(children: [Expanded(child: Text(p.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))), Text(p.type, style: TextStyle(color: Colors.black54))]),
                                                  SizedBox(height: 8),
                                                  LinearProgressIndicator(value: p.mood / 100.0, minHeight: 6),
                                                  SizedBox(height: 6),
                                                  Row(children: [Icon(Icons.favorite, size: 14, color: Colors.redAccent), SizedBox(width: 6), Text('Mood ${p.mood}'), SizedBox(width: 12), Icon(Icons.local_fire_department, size: 14, color: Colors.orange), SizedBox(width: 6), Text('Energy ${p.energy}')]),
                                                ]),
                                              ),
                                              SizedBox(width: 8),
                                              IconButton(icon: Icon(Icons.more_vert), onPressed: () => _openPetDetail(p)),
                                            ],
                                          ),
                                        ),
                                      );
                                    }),
                            ),
                          ],
                        ),
                      );

                      final right = Container(
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Align(alignment: Alignment.centerLeft, child: Text('Dashboard & Activity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                            SizedBox(height: 8),
                            Expanded(
                              child: Container(
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 6))]),
                                child: pets.isEmpty
                                    ? Center(child: Text('Select or adopt a pet to view its dashboard.', style: TextStyle(color: Colors.black54)))
                                    : Column(
                                        children: [
                                          // selected pet summary (default first)
                                          DashboardSummary(
                                            pet: pets.first,
                                            onAction: (label) async {
                                              // apply action mapping
                                              if (label == 'Feed') {
                                                pets.first.feed();
                                              } else if (label == 'Play') {
                                                pets.first.play();
                                              } else if (label == 'Rest') {
                                                pets.first.rest();
                                              }
                                              await _updatePet(pets.first, actionLabel: '$label ${pets.first.name}');
                                            },
                                          ),
                                          SizedBox(height: 12),
                                          Expanded(
                                            child: Row(
                                              children: [
                                                // Activity feed
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text('Activity', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                                                      SizedBox(height: 8),
                                                      Expanded(
                                                        child: activity.isEmpty
                                                            ? Center(child: Text('No recent activity', style: TextStyle(color: Colors.black45)))
                                                            : ListView.builder(
                                                                itemCount: activity.length,
                                                                itemBuilder: (_, i) => ListTile(
                                                                  dense: true,
                                                                  visualDensity: VisualDensity.compact,
                                                                  title: Text(activity[i], style: TextStyle(fontSize: 13)),
                                                                ),
                                                              ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                SizedBox(width: 12),
                                                // Quick stats
                                                Container(
                                                  width: 170,
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text('Quick stats', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                                                      SizedBox(height: 8),
                                                      _quickStat('Pets', '${pets.length}'),
                                                      SizedBox(height: 8),
                                                      _quickStat('Avg mood', '${_average(pets.map((p) => p.mood).toList())}'),
                                                      SizedBox(height: 8),
                                                      _quickStat('Avg energy', '${_average(pets.map((p) => p.energy).toList())}'),
                                                      Spacer(),
                                                      Text('Simulation', style: TextStyle(fontSize: 12, color: Colors.black54)),
                                                      SizedBox(height: 6),
                                                      Row(children: [
                                                        Text(simulationOn ? 'On' : 'Off', style: TextStyle(fontWeight: FontWeight.w700)),
                                                        Spacer(),
                                                        Switch(value: simulationOn, onChanged: (v) {
                                                          setState(() {
                                                            simulationOn = v;
                                                            if (simulationOn) {
                                                              _simTimer?.cancel();
                                                              _simTimer = Timer.periodic(Duration(seconds: 10), (_) => _simulateHourTick());
                                                            } else {
                                                              _simTimer?.cancel();
                                                              _simTimer = null;
                                                            }
                                                          });
                                                        })
                                                      ]),
                                                    ],
                                                  ),
                                                )
                                              ],
                                            ),
                                          )
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        ),
                      );

                      if (wide) {
                        return Row(
                          children: [
                            Flexible(flex: 4, child: left),
                            SizedBox(width: 16),
                            Flexible(flex: 6, child: right),
                          ],
                        );
                      } else {
                        // stacked on narrow screens
                        return Column(
                          children: [
                            Expanded(flex: 5, child: left),
                            SizedBox(height: 12),
                            Expanded(flex: 5, child: right),
                          ],
                        );
                      }
                    }),
                  )
                ],
              ),
      ),
    );
  }

  Widget _quickStat(String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.grey[50]),
      child: Row(children: [Text(label, style: TextStyle(color: Colors.black54)), Spacer(), Text(value, style: TextStyle(fontWeight: FontWeight.w700))]),
    );
  }

  int _average(List<int> xs) => xs.isEmpty ? 0 : (xs.reduce((a, b) => a + b) / xs.length).round();

  // simulate tick of 1 hour for all pets and persist
  void _simulateHourTick() {
    final now = DateTime.now();
    for (var p in pets) {
      p.timeTick(Duration(hours: 1));
    }
    activity.insert(0, 'Time tick: 1h simulated • ${_formatRelative(now)}');
    _savePetsForActiveProfile();
    _saveActivity();
    setState(() {});
  }
}

/// -----------------------------
/// DashboardSummary widget
/// Animated stat bars and large avatar
/// -----------------------------
class DashboardSummary extends StatefulWidget {
  final Pet pet;
  final Future<void> Function(String actionLabel) onAction;

  const DashboardSummary({required this.pet, required this.onAction, Key? key}) : super(key: key);

  @override
  State<DashboardSummary> createState() => _DashboardSummaryState();
}

class _DashboardSummaryState extends State<DashboardSummary> with SingleTickerProviderStateMixin {
  late Pet pet;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    pet = widget.pet;
    _pulseCtrl = AnimationController(vsync: this, duration: Duration(milliseconds: 900))..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant DashboardSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    pet = widget.pet;
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = Color(pet.avatarColorValue);
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))]),
          child: Row(
            children: [
              // large avatar with subtle pulse
              ScaleTransition(
                scale: Tween(begin: 0.98, end: 1.06).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut)),
                child: CircleAvatar(
                  radius: 46,
                  backgroundColor: color.withOpacity(0.16),
                  child: Text(pet.avatarEmoji, style: TextStyle(fontSize: 36)),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: Text(pet.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))), Text(pet.type, style: TextStyle(color: Colors.black54))]),
                  SizedBox(height: 8),
                  _animatedStat('Mood', pet.mood, Icons.emoji_emotions),
                  SizedBox(height: 8),
                  _animatedStat('Energy', pet.energy, Icons.bolt),
                  SizedBox(height: 8),
                  _animatedStat('Fullness', 100 - pet.hunger, Icons.restaurant),
                  SizedBox(height: 8),
                  _animatedStat('Health', pet.health, Icons.health_and_safety),
                  SizedBox(height: 12),
                  Row(children: [
                    ElevatedButton.icon(onPressed: () => widget.onAction('Feed'), icon: Icon(Icons.fastfood), label: Text('Feed')),
                    SizedBox(width: 8),
                    OutlinedButton.icon(onPressed: () => widget.onAction('Play'), icon: Icon(Icons.sports_esports), label: Text('Play')),
                    SizedBox(width: 8),
                    OutlinedButton.icon(onPressed: () => widget.onAction('Rest'), icon: Icon(Icons.hotel), label: Text('Rest')),
                  ])
                ]),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _animatedStat(String label, int value, IconData icon) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: value / 100.0),
      duration: Duration(milliseconds: 700),
      builder: (context, val, _) {
        return Row(
          children: [
            Icon(icon, size: 18, color: Colors.black54),
            SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Stack(
                  children: [
                    Container(height: 10, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(6))),
                    FractionallySizedBox(widthFactor: val, child: Container(height: 10, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(6)))),
                  ],
                ),
                SizedBox(height: 6),
                Row(children: [Text('$label', style: TextStyle(fontSize: 12, color: Colors.black54)), Spacer(), Text('${(val * 100).round()}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))])
              ]),
            )
          ],
        );
      },
    );
  }
}

/// -----------------------------
/// Full-screen DashboardView
/// -----------------------------
class DashboardView extends StatefulWidget {
  final Pet pet;
  final Future<void> Function(Pet updated, String actionLabel) onUpdate;

  const DashboardView({required this.pet, required this.onUpdate, Key? key}) : super(key: key);

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  late Pet pet;

  @override
  void initState() {
    super.initState();
    // create a local mutable copy reference (we update and notify via onUpdate)
    pet = Pet(
      id: widget.pet.id,
      name: widget.pet.name,
      type: widget.pet.type,
      mood: widget.pet.mood,
      energy: widget.pet.energy,
      hunger: widget.pet.hunger,
      health: widget.pet.health,
      lastFed: widget.pet.lastFed,
      createdAt: widget.pet.createdAt,
      avatarColorValue: widget.pet.avatarColorValue,
      avatarEmoji: widget.pet.avatarEmoji,
    );
  }

  Future<void> _performAction(String action) async {
    setState(() {
      if (action == 'Feed') {
        pet.feed();
      } else if (action == 'Play') {
        pet.play();
      } else if (action == 'Rest') {
        pet.rest();
      }
    });
    // notify parent to persist & log activity
    await widget.onUpdate(pet, '$action ${pet.name}');
  }

  Future<void> _editPet() async {
    // Reuse the edit dialog logic from HomeScreen by copying behavior inline here
    String name = pet.name;
    String selectedEmoji = pet.avatarEmoji;
    Color selectedColor = Color(pet.avatarColorValue);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: Text('Edit ${pet.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: InputDecoration(labelText: 'Pet name'),
                  controller: TextEditingController(text: name),
                  onChanged: (v) => name = v,
                ),
                SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: Text('Choose emoji', style: TextStyle(fontWeight: FontWeight.w600))),
                SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['🐶', '🐱', '🐰', '🐹', '🐾', '🦊', '🐻', '🐼'].map((e) {
                    final isSelected = e == selectedEmoji;
                    return ChoiceChip(
                      label: Text(e, style: TextStyle(fontSize: 20)),
                      selected: isSelected,
                      onSelected: (_) => setLocal(() => selectedEmoji = e),
                    );
                  }).toList(),
                ),
                SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: Text('Choose avatar color', style: TextStyle(fontWeight: FontWeight.w600))),
                SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [Colors.purple, Colors.blue, Colors.teal, Colors.green, Colors.orange, Colors.pink].map((c) {
                    final isSelected = c.value == selectedColor.value;
                    return GestureDetector(
                      onTap: () => setLocal(() => selectedColor = c),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: isSelected ? Border.all(color: Colors.black26, width: 3) : null,
                        ),
                        child: isSelected ? Icon(Icons.check, color: useWhiteForeground(c) ? Colors.white : Colors.black) : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                // apply changes locally and persist
                pet.name = name.isEmpty ? pet.name : name;
                pet.avatarEmoji = selectedEmoji;
                pet.avatarColorValue = selectedColor.value;
                widget.onUpdate(pet, 'Updated ${pet.name}');
                Navigator.of(ctx).pop();
                setState(() {});
              },
              child: Text('Save'),
            ),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = Color(pet.avatarColorValue);
    return Scaffold(
      appBar: AppBar(
        title: Text('${pet.name} — Dashboard'),
        actions: [
          IconButton(
            icon: Icon(Icons.edit),
            tooltip: 'Edit pet',
            onPressed: _editPet,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline),
            tooltip: 'Remove pet',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Remove ${pet.name}?'),
                  content: Text('This will remove the pet from your profile.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('Cancel')),
                    ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('Remove')),
                  ],
                ),
              );
              if (ok == true) {
                await widget.onUpdate(pet, 'REMOVE:${pet.id}');
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        minimum: EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))]),
              child: Row(
                children: [
                  CircleAvatar(radius: 52, backgroundColor: color.withOpacity(0.16), child: Text(pet.avatarEmoji, style: TextStyle(fontSize: 42))),
                  SizedBox(width: 18),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [Expanded(child: Text(pet.name, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))), Text(pet.type, style: TextStyle(color: Colors.black54))]),
                      SizedBox(height: 10),
                      _statRowLarge('Mood', pet.mood, Icons.emoji_emotions),
                      SizedBox(height: 8),
                      _statRowLarge('Energy', pet.energy, Icons.bolt),
                      SizedBox(height: 8),
                      _statRowLarge('Fullness', 100 - pet.hunger, Icons.restaurant),
                      SizedBox(height: 8),
                      _statRowLarge('Health', pet.health, Icons.health_and_safety),
                    ]),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12),
            Row(children: [
              Expanded(child: ElevatedButton.icon(onPressed: () => _performAction('Feed'), icon: Icon(Icons.fastfood), label: Text('Feed'))),
              SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: () => _performAction('Play'), icon: Icon(Icons.sports_esports), label: Text('Play'))),
              SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: () => _performAction('Rest'), icon: Icon(Icons.hotel), label: Text('Rest'))),
            ]),
            SizedBox(height: 14),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 6))]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  SizedBox(height: 8),
                  Text('Last fed: ${_formatRelative(pet.lastFed)}', style: TextStyle(color: Colors.black54)),
                  SizedBox(height: 8),
                  Text('Created: ${_formatDate(pet.createdAt)}', style: TextStyle(color: Colors.black54)),
                  SizedBox(height: 12),
                  Text('Quick actions', style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    Chip(label: Text('Name: ${pet.name}')),
                    Chip(label: Text('Type: ${pet.type}')),
                    Chip(label: Text('Mood: ${pet.mood}')),
                    Chip(label: Text('Energy: ${pet.energy}')),
                  ]),
                ]),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _statRowLarge(String label, int value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [Icon(icon, size: 18, color: Colors.black54), SizedBox(width: 8), Text(label, style: TextStyle(fontWeight: FontWeight.w700))]),
        SizedBox(height: 6),
        Stack(
          children: [
            Container(height: 14, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8))),
            FractionallySizedBox(widthFactor: (value.clamp(0, 100)) / 100.0, child: Container(height: 14, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(8)))),
          ],
        ),
        SizedBox(height: 6),
        Text('${value} / 100', style: TextStyle(color: Colors.black54)),
      ],
    );
  }

  String _formatRelative(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';
  }

  String _formatDate(DateTime dt) => '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';
}