import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.instance.initDB();
  runApp(TireWorkshopApp());
}

class TireWorkshopApp extends StatelessWidget {
  const TireWorkshopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reifenverwaltung',
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF00897B),
        colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.teal)
            .copyWith(secondary: const Color(0xFFFFA000)),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        fontFamily: 'Roboto',
        cardTheme: CardThemeData(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 8.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          prefixIconColor: Colors.teal,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00897B),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        dataTableTheme: DataTableThemeData(
          headingRowColor: WidgetStateProperty.all(Colors.teal.shade100),
          dataRowColor: WidgetStateProperty.all(Colors.white),
          dividerThickness: 0,
        ),
      ),
      home: TireManagementScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Datenmodell für einen Reifen.
class Tire {
  final String number;
  final double size; // Zoll
  final int shelf;
  final String zustand; // Neu | Gebraucht
  final String saison;  // Alle Wetter | Sommer | Winter

  Tire({
    required this.number,
    required this.size,
    required this.shelf,
    required this.zustand,
    required this.saison,
  });

  Map<String, dynamic> toMap() {
    return {
      'number': number,
      'size': size,
      'shelf': shelf,
      'zustand': zustand,
      'saison': saison,
    };
  }

  factory Tire.fromMap(Map<String, dynamic> map) {
    return Tire(
      number: map['number'],
      size: (map['size'] ?? 0.0).toDouble(),
      shelf: map['shelf'],
      zustand: map['zustand'] ?? 'Gebraucht',
      saison: map['saison'] ?? 'Alle Wetter',
    );
    // Hinweis: Altes Feld 'brand' wird ignoriert.
  }
}

// SQLite-Verwaltung mit Migration auf Version 2 (Zustand + Saison, ohne Marke).
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  DatabaseHelper._internal();
  Database? _db;

  Future<void> initDB() async {
    final path = p.join(await getDatabasesPath(), 'tires_workshop_de.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        // Neuinstallation: Tabelle direkt im neuen Schema anlegen.
        await db.execute('''
          CREATE TABLE tires(
            number TEXT PRIMARY KEY,
            size REAL NOT NULL,
            shelf INTEGER NOT NULL,
            zustand TEXT NOT NULL DEFAULT 'Gebraucht',
            saison TEXT NOT NULL DEFAULT 'Alle Wetter'
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Migration von v1 (mit brand) zu v2 (zustand + saison, ohne brand).
          await db.execute('''
            CREATE TABLE tires_v2(
              number TEXT PRIMARY KEY,
              size REAL NOT NULL,
              shelf INTEGER NOT NULL,
              zustand TEXT NOT NULL DEFAULT 'Gebraucht',
              saison TEXT NOT NULL DEFAULT 'Alle Wetter'
            )
          ''');
          await db.execute('''
            INSERT INTO tires_v2 (number, size, shelf, zustand, saison)
            SELECT number, size, shelf, 'Gebraucht', 'Alle Wetter' FROM tires
          ''');
          await db.execute('DROP TABLE tires');
          await db.execute('ALTER TABLE tires_v2 RENAME TO tires');
        }
      },
    );
  }

  Future<void> insertTire(Tire tire) async =>
      await _db!.insert('tires', tire.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Tire>> getTires() async {
    final maps = await _db!.query('tires', orderBy: 'shelf, number');
    return List.generate(maps.length, (i) => Tire.fromMap(maps[i]));
  }

  Future<void> deleteTire(String number) async =>
      await _db!.delete('tires', where: 'number = ?', whereArgs: [number]);
}

// Hauptbildschirm der App.
class TireManagementScreen extends StatefulWidget {
  const TireManagementScreen({super.key});

  @override
  _TireManagementScreenState createState() => _TireManagementScreenState();
}

class _TireManagementScreenState extends State<TireManagementScreen> {
  List<Tire> tires = [];
  String searchQuery = '';
  int selectedShelf = 1;

  final numberController = TextEditingController();
  final sizeController = TextEditingController();

  // Neu: Zustand & Saison statt Marke
  String _zustand = 'Gebraucht';
  String _saison = 'Alle Wetter';

  @override
  void initState() {
    super.initState();
    loadTires();
  }

  Future<void> loadTires() async {
    final data = await DatabaseHelper.instance.getTires();
    setState(() => tires = data);
  }

  Future<void> addTire() async {
    final number = numberController.text.trim();
    final sizeText = sizeController.text.trim().replaceAll(',', '.');

    if (number.isEmpty || sizeText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte alle Felder ausfüllen.')),
      );
      return;
    }

    final size = double.tryParse(sizeText);
    if (size == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ungültige Größe.')),
      );
      return;
    }

    if (tires.any((t) => t.number == number)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diese Reifennummer existiert bereits!')),
      );
      return;
    }

    final newTire = Tire(
      number: number,
      size: size,
      shelf: selectedShelf,
      zustand: _zustand,
      saison: _saison,
    );
    await DatabaseHelper.instance.insertTire(newTire);

    numberController.clear();
    sizeController.clear();
    // Optional: Dropdowns zurücksetzen
    setState(() {
      _zustand = 'Gebraucht';
      _saison = 'Alle Wetter';
    });
    FocusScope.of(context).unfocus();

    await loadTires();
  }

  Future<void> deleteTire(String number) async {
    await DatabaseHelper.instance.deleteTire(number);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reifen "$number" gelöscht.')),
    );
    await loadTires();
  }

  // Suche: nach Nummer ODER Größe (Zoll)
  List<Tire> get filteredTires {
    if (searchQuery.isEmpty) return tires;
    final q = searchQuery.toLowerCase();
    final qNum = double.tryParse(q.replaceAll(',', '.'));
    return tires.where((t) {
      final byNumber = t.number.toLowerCase().contains(q);
      final byZoll = qNum != null
          ? (t.size == qNum || t.size.toString().contains(q.replaceAll(',', '.')))
          : false;
      return byNumber || byZoll;
    }).toList();
  }

  // Nur Anzahl pro Regal (Gesamtgröße entfällt)
  Map<int, Map<String, dynamic>> get shelfStats {
    final Map<int, Map<String, dynamic>> stats = {};
    for (var tire in filteredTires) {
      stats.putIfAbsent(tire.shelf, () => {'count': 0});
      stats[tire.shelf]!['count'] += 1;
    }
    return Map.fromEntries(
      stats.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reifenverwaltung'),
        centerTitle: true,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildInputCard(),
            _buildSearchCard(),
            _buildTireList(),
            _buildStatsTable(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: numberController,
              decoration: const InputDecoration(
                labelText: 'Reifennummer',
                prefixIcon: Icon(Icons.confirmation_number),
              ),
            ),
            const SizedBox(height: 12),
            // Neu: Zustand & Saison statt Marke
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _zustand,
                    decoration: const InputDecoration(
                      labelText: 'Zustand',
                      prefixIcon: Icon(Icons.build_circle_outlined),
                    ),
                    items: ['Neu', 'Gebraucht']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) => setState(() => _zustand = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _saison,
                    decoration: const InputDecoration(
                      labelText: 'Saison',
                      prefixIcon: Icon(Icons.wb_sunny_outlined),
                    ),
                    items: ['Alle Wetter', 'Sommer', 'Winter']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) => setState(() => _saison = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: sizeController,
                    decoration: const InputDecoration(
                      labelText: 'Größe (Zoll)',
                      prefixIcon: Icon(Icons.aspect_ratio),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+([.,]\d{0,2})?$')),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: selectedShelf,
                    decoration: const InputDecoration(
                      labelText: 'Regal',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                    ),
                    items: [1, 2, 3, 4]
                        .map((s) => DropdownMenuItem(value: s, child: Text('Regal $s')))
                        .toList(),
                    onChanged: (v) => setState(() => selectedShelf = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: addTire,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Hinzufügen'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: TextField(
          decoration: const InputDecoration(
            labelText: 'Suchen (Nummer, Zoll)',
            prefixIcon: Icon(Icons.search),
            border: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
          onChanged: (value) => setState(() => searchQuery = value.trim()),
        ),
      ),
    );
  }

  Widget _buildTireList() {
    final list = filteredTires;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(
          child: Text(
            'Keine Reifen gefunden.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final tire = list[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
              child: Text(
                tire.shelf.toString(),
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(tire.number),
            subtitle: Text('Größe: ${tire.size}"  •  Zustand: ${tire.zustand}  •  Saison: ${tire.saison}'),
            trailing: IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
              onPressed: () => deleteTire(tire.number),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatsTable() {
    final stats = shelfStats;
    final totalCount = filteredTires.length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: DataTable(
        columns: const [
          DataColumn(
            label: Text('Regal', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          DataColumn(
            label: Text('Anzahl', style: TextStyle(fontWeight: FontWeight.bold)),
            numeric: true,
          ),
        ],
        rows: [
          ...stats.entries.map((entry) {
            return DataRow(
              cells: [
                DataCell(Text('Regal ${entry.key}')),
                DataCell(Text(entry.value['count'].toString())),
              ],
            );
          }).toList(),
          DataRow(
            color: WidgetStateProperty.all(Colors.amber.shade100),
            cells: [
              const DataCell(Text('Gesamt', style: TextStyle(fontWeight: FontWeight.bold))),
              DataCell(Text(totalCount.toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
        ],
      ),
    );
  }
}  