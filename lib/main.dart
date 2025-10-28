// lib/main.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(PetCareApp());
}

/// -----------------------------
/// Constants / Pref keys
/// -----------------------------
const String _kProfilesKey = 'petcare_profiles_v1';
const String _kActiveProfileKey = 'petcare_active_profile_v1';
const String _kLegacyPetsKey = 'petcare_pets_v1';
const String _kReminderKeySuffix =
    '_reminders_v1'; // stored per-profile as map petId->HH:mm

/// -----------------------------
/// Small helper: white/black foreground contrast
/// -----------------------------
bool useWhiteForeground(Color backgroundColor, {double bias = 0.0}) {
  final double v = (0.299 * backgroundColor.red +
          0.587 * backgroundColor.green +
          0.114 * backgroundColor.blue) /
      255;
  return v < 0.5 + bias;
}

/// -----------------------------
/// Pet model (with reminder field kept external in prefs)
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
      avatarColorValue: j.containsKey('avatarColorValue')
          ? (j['avatarColorValue'] as num).toInt()
          : Colors.blue.value,
      avatarEmoji: j.containsKey('avatarEmoji')
          ? (j['avatarEmoji'] as String)
          : _defaultEmojiForType(j['type'] as String),
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
    return Profile(
        id: 'profile_${now.millisecondsSinceEpoch}',
        name: name,
        createdAt: now);
  }

  factory Profile.fromJson(Map<String, dynamic> j) {
    return Profile(
      id: j['id'] as String,
      name: j['name'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'createdAt': createdAt.toIso8601String()};
}

/// -----------------------------
/// App widget
/// -----------------------------
class PetCareApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pet Care App (Stage 7)',
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
/// HomeScreen: now with reminders scheduler (in-app)
/// -----------------------------
class HomeScreen extends StatefulWidget {
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  SharedPreferences? _prefs;
  bool loading = true;

  // data
  List<Profile> profiles = [];
  String? activeProfileId;
  List<Pet> pets = [];
  List<String> activity = [];

  // reminder map (petId -> "HH:mm")
  Map<String, String> reminders = {};

  // check timer
  Timer? _reminderTimer;

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
  final List<String> _emojiChoices = [
    '🐶',
    '🐱',
    '🐰',
    '🐹',
    '🐾',
    '🦊',
    '🐻',
    '🐼'
  ];

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    super.dispose();
  }

  Future<void> _initAndLoad() async {
    _prefs = await SharedPreferences.getInstance();
    await _maybeMigrateLegacyPets();
    _loadProfiles();
    _loadActiveProfile();
    _loadPetsForActiveProfile();
    _loadActivity();
    _loadReminders();
    _startReminderChecker();
    setState(() {
      loading = false;
    });
  }

  /// Migration (same as earlier stages)
  Future<void> _maybeMigrateLegacyPets() async {
    final lp = _prefs;
    if (lp == null) return;
    final legacy = lp.getString(_kLegacyPetsKey);
    final existingProfiles = lp.getString(_kProfilesKey);
    if (legacy != null &&
        (existingProfiles == null || existingProfiles.isEmpty)) {
      try {
        final list = json.decode(legacy) as List<dynamic>;
        final movedPets =
            list.map((e) => Pet.fromJson(e as Map<String, dynamic>)).toList();
        final defaultProfile = Profile.create('You');
        await lp.setString(
            _kProfilesKey, json.encode([defaultProfile.toJson()]));
        await lp.setString(_kActiveProfileKey, defaultProfile.id);
        final petKey = _petsKeyForProfile(defaultProfile.id);
        await lp.setString(
            petKey, json.encode(movedPets.map((p) => p.toJson()).toList()));
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
      profiles =
          list.map((e) => Profile.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      profiles = [];
    }
  }

  void _loadActiveProfile() {
    final s = _prefs?.getString(_kActiveProfileKey);
    if (s == null) {
      activeProfileId = profiles.isNotEmpty ? profiles.first.id : null;
      if (activeProfileId != null)
        _prefs?.setString(_kActiveProfileKey, activeProfileId!);
      return;
    }
    activeProfileId = s;
    if (activeProfileId != null &&
        !profiles.any((p) => p.id == activeProfileId)) {
      activeProfileId = profiles.isNotEmpty ? profiles.first.id : null;
      if (activeProfileId != null)
        _prefs?.setString(_kActiveProfileKey, activeProfileId!);
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

  String petsKeyForProfile(String profileId) => 'pets_for$profileId';
  String activityKeyForProfile(String profileId) => 'activity_for$profileId';
  String reminderKeyForProfile(String profileId) =>
      'reminders_for$profileId$_kReminderKeySuffix';

  Future<void> _saveProfiles() async {
    if (_prefs == null) return;
    await _prefs!.setString(
        _kProfilesKey, json.encode(profiles.map((p) => p.toJson()).toList()));
  }

  Future<void> _setActiveProfile(String profileId) async {
    if (_prefs == null) return;
    activeProfileId = profileId;
    await _prefs!.setString(_kActiveProfileKey, profileId);
    _loadPetsForActiveProfile();
    _loadActivity();
    _loadReminders();
    setState(() {});
  }

  Future<void> _savePetsForActiveProfile() async {
    if (_prefs == null || activeProfileId == null) return;
    final key = _petsKeyForProfile(activeProfileId!);
    await _prefs!
        .setString(key, json.encode(pets.map((p) => p.toJson()).toList()));
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

  // ---------- Reminders storage ----------
  void _loadReminders() {
    reminders = {};
    if (activeProfileId == null) return;
    final s = _prefs?.getString(_reminderKeyForProfile(activeProfileId!));
    if (s == null) {
      reminders = {};
      return;
    }
    try {
      final map = json.decode(s) as Map<String, dynamic>;
      reminders = map.map((k, v) => MapEntry(k, v as String));
    } catch (e) {
      reminders = {};
    }
  }

  Future<void> _saveReminders() async {
    if (_prefs == null || activeProfileId == null) return;
    final key = _reminderKeyForProfile(activeProfileId!);
    await _prefs!.setString(key, json.encode(reminders));
  }

  // ---------- Profiles & pets ----------
  Future<void> _addProfile(String name) async {
    final p = Profile.create(name.isEmpty ? 'Profile' : name);
    profiles.add(p);
    await _saveProfiles();
    await _setActiveProfile(p.id);
    _showSnack('Created profile "${p.name}" and switched to it');
  }

  Future<void> _deleteProfile(String profileId) async {
    final toRemove = profiles.firstWhere((p) => p.id == profileId,
        orElse: () => throw StateError('not found'));
    await _prefs?.remove(_petsKeyForProfile(profileId));
    await _prefs?.remove(_activityKeyForProfile(profileId));
    await _prefs?.remove(_reminderKeyForProfile(profileId));
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
        reminders = {};
        setState(() {});
      }
    } else {
      setState(() {});
    }

    _showSnack('Removed profile "${toRemove.name}"');
  }

  Future<void> _addPet(String name, String type,
      {int? avatarColorValue, String? avatarEmoji}) async {
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
    final removed = pets.firstWhere((p) => p.id == id,
        orElse: () => throw StateError('not found'));
    pets.removeWhere((p) => p.id == id);
    activity.insert(
        0, '${removed.name} removed • ${_formatRelative(DateTime.now())}');
    // remove reminder if any
    reminders.remove(removed.id);
    await _savePetsForActiveProfile();
    await _saveActivity();
    await _saveReminders();
    setState(() {});
  }

  Future<void> _updatePet(Pet pet, {String? actionLabel}) async {
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

  // ---------- Reminder checking ----------
  void _startReminderChecker() {
    _reminderTimer?.cancel();
    // runs every 30 seconds: checks if any reminder matches current HH:mm
    reminderTimer =
        Timer.periodic(Duration(seconds: 30), () => _checkRemindersOnce());
  }

  void _checkRemindersOnce() {
    if (activeProfileId == null || reminders.isEmpty) return;
    final now = DateTime.now();
    final hhmm = DateFormat('HH:mm').format(now);
    // we fire once per minute (approx): show snack for each matching reminder not fired in same minute
    // to avoid duplicates we could track last-fired timestamps; keep minimal: only show if matches now and we haven't fired for that pet in last minute.
    for (final petId in reminders.keys) {
      if (reminders[petId] == hhmm) {
        final p = pets.firstWhere((x) => x.id == petId,
            orElse: () => Pet.createSeed(name: 'Unknown', type: 'Dog'));
        // Show a SnackBar to simulate a reminder
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Reminder: ${p.name} — ${_friendlyReminderLabel(petId)}'),
          duration: Duration(seconds: 6),
        ));
        activity.insert(
            0, 'Reminder fired for ${p.name} • ${_formatRelative(now)}');
        _saveActivity();
      }
    }
  }

  String _friendlyReminderLabel(String petId) {
    final t = reminders[petId];
    if (t == null) return 'Reminder';
    return 'Time to care (${t})';
  }

  // ---------- UI: create profile, adopt, edit, set reminder ----------
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
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: Text('Cancel')),
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
    final active = profiles.firstWhere((p) => p.id == activeProfileId,
        orElse: () =>
            Profile(id: 'none', name: 'No profile', createdAt: DateTime.now()));
    return PopupMenuButton<String>(
      tooltip: 'Profiles',
      icon: CircleAvatar(
        radius: 16,
        backgroundColor:
            Theme.of(context).colorScheme.primary.withOpacity(0.12),
        child: Text(active.name.isNotEmpty ? active.name[0].toUpperCase() : '?',
            style: TextStyle(color: Theme.of(context).colorScheme.primary)),
      ),
      itemBuilder: (_) {
        final items = <PopupMenuEntry<String>>[];
        if (profiles.isEmpty) {
          items.add(
              PopupMenuItem(child: Text('No profiles yet'), value: 'noop'));
        } else {
          for (final p in profiles) {
            items.add(PopupMenuItem(
              value: p.id,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(p.name),
                  if (p.id == activeProfileId)
                    Icon(Icons.check,
                        size: 18, color: Theme.of(context).colorScheme.primary),
                ],
              ),
            ));
          }
        }
        items.add(const PopupMenuDivider());
        items
            .add(PopupMenuItem(value: 'create', child: Text('Create profile')));
        if (profiles.isNotEmpty)
          items.add(
              PopupMenuItem(value: 'manage', child: Text('Manage profiles')));
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
            Text('Manage profiles',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
                          leading: CircleAvatar(
                              child: Text(p.name.isNotEmpty
                                  ? p.name[0].toUpperCase()
                                  : '?')),
                          title: Text(p.name),
                          subtitle: Text('Created ${_formatDate(p.createdAt)}'),
                          trailing:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            if (isActive)
                              Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Chip(label: Text('Active'))),
                            IconButton(
                              icon: Icon(Icons.delete_outline),
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (dctx) => AlertDialog(
                                    title: Text('Remove profile "${p.name}"?'),
                                    content: Text(
                                        'This will delete the profile and its local pets.'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.of(dctx).pop(false),
                                          child: Text('Cancel')),
                                      ElevatedButton(
                                          onPressed: () =>
                                              Navigator.of(dctx).pop(true),
                                          child: Text('Remove')),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  await _deleteProfile(p.id);
                                  Navigator.of(context)
                                      .pop(); // close sheet and reopen to refresh
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
                TextField(
                    decoration: InputDecoration(labelText: 'Pet name'),
                    onChanged: (v) => name = v),
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
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Choose avatar emoji',
                        style: TextStyle(fontWeight: FontWeight.w600))),
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
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Choose avatar color',
                        style: TextStyle(fontWeight: FontWeight.w600))),
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
                          border: isSelected
                              ? Border.all(color: Colors.black26, width: 3)
                              : null,
                        ),
                        child: isSelected
                            ? Icon(Icons.check,
                                color: useWhiteForeground(c)
                                    ? Colors.white
                                    : Colors.black)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _addPet(name, selectedType,
                    avatarColorValue: selectedColor.value,
                    avatarEmoji: selectedEmoji);
              },
              child: Text('Adopt'),
            )
          ],
        ),
      ),
    );
  }

  void _openPetDetail(Pet pet) {
    // bottom sheet with set reminder action
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.95,
        minChildSize: 0.25,
        builder: (_, ctl) {
          return Container(
            decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
            padding: EdgeInsets.all(12),
            child: ListView(
              controller: ctl,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(4)))),
                SizedBox(height: 12),
                Row(children: [
                  CircleAvatar(
                      radius: 36,
                      backgroundColor:
                          Color(pet.avatarColorValue).withOpacity(0.18),
                      child: Text(pet.avatarEmoji,
                          style: TextStyle(fontSize: 28))),
                  SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(pet.name,
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700)),
                        SizedBox(height: 4),
                        Text(pet.type, style: TextStyle(color: Colors.black54))
                      ])),
                  IconButton(
                      icon: Icon(Icons.delete_outline),
                      onPressed: () async {
                        Navigator.of(context).pop();
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (dctx) => AlertDialog(
                            title: Text('Remove ${pet.name}?'),
                            content: Text(
                                'This will permanently remove the pet from this profile.'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.of(dctx).pop(false),
                                  child: Text('Cancel')),
                              ElevatedButton(
                                  onPressed: () => Navigator.of(dctx).pop(true),
                                  child: Text('Remove')),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await _deletePet(pet.id);
                        }
                      })
                ]),
                SizedBox(height: 12),
                _statRow('Mood', pet.mood),
                SizedBox(height: 8),
                _statRow('Energy', pet.energy),
                SizedBox(height: 8),
                _statRow('Hunger', 100 - pet.hunger, suffixHint: '(fullness)'),
                SizedBox(height: 8),
                _statRow('Health', pet.health),
                SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Reminder'),
                  subtitle: Text(reminders.containsKey(pet.id)
                      ? 'Daily at ${reminders[pet.id]}'
                      : 'No reminder set'),
                  trailing: ElevatedButton.icon(
                    icon: Icon(Icons.alarm),
                    label: Text(reminders.containsKey(pet.id) ? 'Edit' : 'Set'),
                    onPressed: () async {
                      // pick time
                      Navigator.of(context).pop();
                      final time = await _pickTimeForPet(pet);
                      if (time != null) {
                        reminders[pet.id] = time;
                        await _saveReminders();
                        _showSnack('Reminder set for ${pet.name} at $time');
                        setState(() {});
                      }
                    },
                  ),
                ),
                SizedBox(height: 12),
                Text('Last fed: ${_formatRelative(pet.lastFed)}',
                    style: TextStyle(color: Colors.black54)),
                SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: ElevatedButton.icon(
                          onPressed: () async {
                            pet.feed();
                            await _updatePet(pet,
                                actionLabel: 'Fed ${pet.name}');
                          },
                          icon: Icon(Icons.fastfood),
                          label: Text('Feed'))),
                  SizedBox(width: 8),
                  Expanded(
                      child: OutlinedButton.icon(
                          onPressed: () async {
                            pet.play();
                            await _updatePet(pet,
                                actionLabel: 'Played with ${pet.name}');
                          },
                          icon: Icon(Icons.sports_esports),
                          label: Text('Play'))),
                  SizedBox(width: 8),
                  Expanded(
                      child: OutlinedButton.icon(
                          onPressed: () async {
                            pet.rest();
                            await _updatePet(pet,
                                actionLabel: '${pet.name} rested');
                          },
                          icon: Icon(Icons.hotel),
                          label: Text('Rest'))),
                ]),
                SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<String?> _pickTimeForPet(Pet pet) async {
    final now = TimeOfDay.now();
    TimeOfDay? picked =
        await showTimePicker(context: context, initialTime: now);
    if (picked == null) return null;
    final fmt = picked.hour.toString().padLeft(2, '0') +
        ':' +
        picked.minute.toString().padLeft(2, '0');
    return fmt;
  }

  Widget _statRow(String label, int value, {String? suffixHint}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.w700)),
        if (suffixHint != null) ...[
          SizedBox(width: 6),
          Text(suffixHint,
              style: TextStyle(color: Colors.black54, fontSize: 12))
        ]
      ]),
      SizedBox(height: 6),
      Stack(children: [
        Container(
            height: 10,
            decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(6))),
        FractionallySizedBox(
            widthFactor: (value.clamp(0, 100)) / 100.0,
            child: Container(
                height: 10,
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(6))))
      ]),
      SizedBox(height: 6),
      Text('$value / 100', style: TextStyle(color: Colors.black54)),
    ]);
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatRelative(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return _formatDate(dt);
  }

  // UI Build (kept compact)
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.background,
      appBar: AppBar(
        title: Text('Pet Care App — Stage 7 (Reminders)'),
        actions: [
          _profileSelector(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAdoptDialog,
          icon: Icon(Icons.pets),
          label: Text('Adopt')),
      body: SafeArea(
        minimum: EdgeInsets.all(16),
        child: loading
            ? Center(child: CircularProgressIndicator())
            : activeProfileId == null
                ? Center(
                    child: ElevatedButton.icon(
                        onPressed: _showCreateProfileDialog,
                        icon: Icon(Icons.add),
                        label: Text('Create profile')))
                : Column(
                    children: [
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(color: Colors.black12, blurRadius: 8)
                            ]),
                        child: Row(children: [
                          CircleAvatar(
                              radius: 26,
                              backgroundColor: cs.primary.withOpacity(0.12),
                              child: Text(
                                  _activeProfileName().isNotEmpty
                                      ? _activeProfileName()[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(color: cs.primary))),
                          SizedBox(width: 12),
                          Expanded(
                              child: Text(
                                  'Profile: ${_activeProfileName()} · ${pets.length} pet(s)',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700))),
                          TextButton.icon(
                              onPressed: () => _exportJson(),
                              icon: Icon(Icons.share),
                              label: Text('Export')),
                        ]),
                      ),
                      SizedBox(height: 12),
                      Expanded(
                        child: pets.isEmpty
                            ? Center(
                                child: Text(
                                    'No pets — adopt one using the + button'))
                            : ListView.builder(
                                itemCount: pets.length,
                                itemBuilder: (_, i) {
                                  final p = pets[i];
                                  return GestureDetector(
                                    onTap: () => _openPetDetail(p),
                                    child: Container(
                                      margin: EdgeInsets.symmetric(vertical: 8),
                                      padding: EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          boxShadow: [
                                            BoxShadow(
                                                color: Colors.black12,
                                                blurRadius: 8)
                                          ]),
                                      child: Row(children: [
                                        CircleAvatar(
                                            radius: 28,
                                            backgroundColor:
                                                Color(p.avatarColorValue)
                                                    .withOpacity(0.14),
                                            child: Text(p.avatarEmoji,
                                                style:
                                                    TextStyle(fontSize: 24))),
                                        SizedBox(width: 12),
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              Row(children: [
                                                Expanded(
                                                    child: Text(p.name,
                                                        style: TextStyle(
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700))),
                                                Text(p.type,
                                                    style: TextStyle(
                                                        color: Colors.black54))
                                              ]),
                                              SizedBox(height: 6),
                                              Text(
                                                  reminders.containsKey(p.id)
                                                      ? 'Reminder: ${reminders[p.id]}'
                                                      : 'No reminder',
                                                  style: TextStyle(
                                                      color: Colors.black54))
                                            ])),
                                        IconButton(
                                            icon: Icon(Icons.alarm),
                                            onPressed: () async {
                                              final time =
                                                  await _pickTimeForPet(p);
                                              if (time != null) {
                                                reminders[p.id] = time;
                                                await _saveReminders();
                                                _showSnack(
                                                    'Reminder set for ${p.name} at $time');
                                                setState(() {});
                                              }
                                            }),
                                        PopupMenuButton<String>(
                                          onSelected: (v) async {
                                            if (v == 'feed') {
                                              p.feed();
                                              await _updatePet(p,
                                                  actionLabel: 'Fed ${p.name}');
                                            } else if (v == 'play') {
                                              p.play();
                                              await _updatePet(p,
                                                  actionLabel:
                                                      'Played with ${p.name}');
                                            } else if (v == 'rest') {
                                              p.rest();
                                              await _updatePet(p,
                                                  actionLabel:
                                                      '${p.name} rested');
                                            } else if (v == 'delete') {
                                              final ok = await showDialog<bool>(
                                                context: context,
                                                builder: (dctx) => AlertDialog(
                                                  title:
                                                      Text('Remove ${p.name}?'),
                                                  content: Text(
                                                      'This will permanently remove the pet from this profile.'),
                                                  actions: [
                                                    TextButton(
                                                        onPressed: () =>
                                                            Navigator.of(dctx)
                                                                .pop(false),
                                                        child: Text('Cancel')),
                                                    ElevatedButton(
                                                        onPressed: () =>
                                                            Navigator.of(dctx)
                                                                .pop(true),
                                                        child: Text('Remove')),
                                                  ],
                                                ),
                                              );
                                              if (ok == true) {
                                                await _deletePet(p.id);
                                              }
                                            }
                                          },
                                          itemBuilder: (_) => [
                                            PopupMenuItem(
                                                value: 'feed',
                                                child: Text('Feed')),
                                            PopupMenuItem(
                                                value: 'play',
                                                child: Text('Play')),
                                            PopupMenuItem(
                                                value: 'rest',
                                                child: Text('Rest')),
                                            PopupMenuDivider(),
                                            PopupMenuItem(
                                                value: 'delete',
                                                child: Text('Delete')),
                                          ],
                                          child: Icon(Icons.more_vert),
                                        ),
                                      ]),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }

  void _exportJson() {
    final s = json.encode(pets.map((p) => p.toJson()).toList());
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
                title: Text('Profile JSON snapshot'),
                content: SingleChildScrollView(child: SelectableText(s)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Close'))
                ]));
  }

  String _activeProfileName() {
    final p = profiles.firstWhere((p) => p.id == activeProfileId,
        orElse: () =>
            Profile(id: 'none', name: 'No profile', createdAt: DateTime.now()));
    return p.name;
  }
}
