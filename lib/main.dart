// lib/main.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(PetCareApp());
}

/// -----------------------------
/// Models
/// -----------------------------
class Pet {
  final String id;
  String name;
  String type;
  int mood;
  int energy;
  int hunger;
  int health;
  DateTime lastFed;

  Pet({
    required this.id,
    required this.name,
    required this.type,
    this.mood = 70,
    this.energy = 80,
    this.hunger = 20,
    this.health = 90,
    DateTime? lastFed,
  }) : lastFed = lastFed ?? DateTime.now();

  factory Pet.fromJson(Map<String, dynamic> j) {
    return Pet(
      id: j['id'],
      name: j['name'],
      type: j['type'],
      mood: j['mood'],
      energy: j['energy'],
      hunger: j['hunger'],
      health: j['health'],
      lastFed: DateTime.parse(j['lastFed']),
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
  };

  void feed() {
    hunger -= 30;
    mood += 10;
    energy += 10;
    lastFed = DateTime.now();
    _clampAll();
  }

  void play() {
    mood += 15;
    energy -= 20;
    hunger += 10;
    _clampAll();
  }

  void rest() {
    energy += 20;
    mood += 5;
    hunger += 5;
    _clampAll();
  }

  void _clampAll() {
    mood = mood.clamp(0, 100);
    energy = energy.clamp(0, 100);
    hunger = hunger.clamp(0, 100);
    health = health.clamp(0, 100);
  }
}

class Profile {
  final String id;
  String name;

  Profile({required this.id, required this.name});

  factory Profile.fromJson(Map<String, dynamic> j) {
    return Profile(id: j['id'], name: j['name']);
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// -----------------------------
/// App
/// -----------------------------
class PetCareApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pet Care Stage 6',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: HomeScreen(),
    );
  }
}

/// -----------------------------
/// HomeScreen
/// -----------------------------
class HomeScreen extends StatefulWidget {
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SharedPreferences? _prefs;
  List<Profile> profiles = [];
  String? activeProfileId;
  List<Pet> pets = [];

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Future<void> _initAll() async {
    _prefs = await SharedPreferences.getInstance();
    _loadProfiles();
    _loadActiveProfile();
    _loadPets();
    setState(() {});
  }

  void _loadProfiles() {
    final s = _prefs?.getString('profiles');
    if (s == null) {
      profiles = [];
      return;
    }
    try {
      final list = json.decode(s) as List;
      profiles = list.map((e) => Profile.fromJson(e)).toList();
    } catch (e) {
      profiles = [];
    }
  }

  void _saveProfiles() {
    if (_prefs == null) return;
    _prefs!.setString(
      'profiles',
      json.encode(profiles.map((p) => p.toJson()).toList()),
    );
  }

  void _loadActiveProfile() {
    final s = _prefs?.getString('activeProfile');
    if (s != null) {
      activeProfileId = s;
    } else if (profiles.isNotEmpty) {
      activeProfileId = profiles.first.id;
      _prefs?.setString('activeProfile', activeProfileId!);
    }
  }

  void _setActiveProfile(String id) {
    activeProfileId = id;
    _prefs?.setString('activeProfile', id);
    _loadPets();
    setState(() {});
  }

  String petsKey() => 'pets$activeProfileId';

  void _loadPets() {
    pets = [];
    if (activeProfileId == null) return;
    final s = _prefs?.getString(_petsKey());
    if (s == null) return;
    try {
      final list = json.decode(s) as List;
      pets = list.map((e) => Pet.fromJson(e)).toList();
    } catch (e) {
      pets = [];
    }
  }

  void _savePets() {
    if (_prefs == null || activeProfileId == null) return;
    _prefs!.setString(
      _petsKey(),
      json.encode(pets.map((p) => p.toJson()).toList()),
    );
  }

  // UI Helpers
  void _addProfile() async {
    final nameController = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: Text('New Profile'),
          content: TextField(
            controller: nameController,
            decoration: InputDecoration(hintText: 'Profile name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final p = Profile(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameController.text,
                );
                profiles.add(p);
                _saveProfiles();
                _setActiveProfile(p.id);
                Navigator.pop(context);
              },
              child: Text('Create'),
            ),
          ],
        );
      },
    );
    setState(() {});
  }

  void _addPet() async {
    final nameController = TextEditingController();
    final typeController = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: Text('Adopt Pet'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(hintText: 'Pet name'),
              ),
              TextField(
                controller: typeController,
                decoration: InputDecoration(hintText: 'Pet type'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final pet = Pet(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameController.text,
                  type: typeController.text,
                );
                pets.add(pet);
                _savePets();
                Navigator.pop(context);
                setState(() {});
              },
              child: Text('Adopt'),
            ),
          ],
        );
      },
    );
  }

  Widget _petCard(Pet pet) {
    return Card(
      child: ListTile(
        title: Text('${pet.name} (${pet.type})'),
        subtitle: Text(
          'Mood: ${pet.mood}, Energy: ${pet.energy}, Hunger: ${pet.hunger}',
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) {
            if (action == 'Feed') pet.feed();
            if (action == 'Play') pet.play();
            if (action == 'Rest') pet.rest();
            _savePets();
            setState(() {});
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'Feed', child: Text('Feed')),
            PopupMenuItem(value: 'Play', child: Text('Play')),
            PopupMenuItem(value: 'Rest', child: Text('Rest')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeProfile = profiles.firstWhere(
      (p) => p.id == activeProfileId,
      orElse: () => Profile(id: '0', name: 'None'),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text('Pet Care Stage 6'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (id) => _setActiveProfile(id),
            itemBuilder: (_) => profiles
                .map((p) => PopupMenuItem(value: p.id, child: Text(p.name)))
                .toList(),
            icon: Icon(Icons.person),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              'Active Profile: ${activeProfile.name}',
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 12),
            Expanded(
              child: pets.isEmpty
                  ? Center(child: Text('No pets yet. Adopt one!'))
                  : ListView(children: pets.map((p) => _petCard(p)).toList()),
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            onPressed: _addProfile,
            child: Icon(Icons.person_add),
            heroTag: 'profile',
          ),
          SizedBox(height: 8),
          FloatingActionButton(
            onPressed: _addPet,
            child: Icon(Icons.pets),
            heroTag: 'pet',
          ),
        ],
      ),
    );
  }
}
