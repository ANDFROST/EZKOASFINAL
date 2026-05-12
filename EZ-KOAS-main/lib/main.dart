import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const VitalsApp());
}

// --- DATA MANAGER ---
// Mengelola penyimpanan dan pengambilan data secara global menggunakan SharedPreferences (Mendukung Web LocalStorage & Mobile)
class PatientDataManager {
  static List<PatientRecord> savedPatients = [];
  static const String _storageKey = 'ezkoas_patients_data';

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? contents = prefs.getString(_storageKey);

      if (contents != null) {
        final List<dynamic> jsonData = json.decode(contents);
        savedPatients.clear();
        savedPatients.addAll(
          jsonData.map((item) => PatientRecord.fromJson(item)).toList(),
        );
      }
    } catch (e) {
      debugPrint('Error loading patient data: $e');
    }
  }

  static Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final jsonData = savedPatients.map((patient) => patient.toJson()).toList();
      final String contents = json.encode(jsonData);

      await prefs.setString(_storageKey, contents);
    } catch (e) {
      debugPrint('Error saving patient data: $e');
    }
  }
}

// --- DATA STRUCTURE 1: Holds one specific time entry ---
class VitalsEntry {
  final String time;
  final String bp;
  final String sens;
  final String gcs;
  final String hr;
  final String rr;
  final String spo2;
  final String o2Method;
  final String lpm;
  final String temp;
  final bool isGdsChecked;
  final String gdsValue;
  final bool isOnIVDrug;
  final List<String> ivDrugNames;
  final List<String> ivDrugRates;
  final String keluhan;

  VitalsEntry({
    required this.time,
    required this.bp,
    required this.sens,
    required this.gcs,
    required this.hr,
    required this.rr,
    required this.spo2,
    required this.o2Method,
    required this.lpm,
    required this.temp,
    required this.isGdsChecked,
    required this.gdsValue,
    required this.isOnIVDrug,
    required this.ivDrugNames,
    required this.ivDrugRates,
    required this.keluhan,
  });

  String toFormattedString() {
    List<String> lines = [];

    if (time.isNotEmpty) lines.add('($time)');
    if (keluhan.isNotEmpty) lines.add('Keluhan: $keluhan');
    
    if (sens.isNotEmpty || gcs.isNotEmpty) {
      final sensLabel = sens == 'Compos mentis' ? 'CM' : sens;
      String combinedSens = '';
      if (sensLabel.isNotEmpty && gcs.isNotEmpty) {
        combinedSens = 'Sens: $sensLabel $gcs';
      } else if (sensLabel.isNotEmpty) {
        combinedSens = 'Sens: $sensLabel';
      } else if (gcs.isNotEmpty) {
        combinedSens = 'Sens: $gcs';
      }
      lines.add(combinedSens);
    }

    if (bp.isNotEmpty) lines.add('TD: $bp mmHg');
    if (hr.isNotEmpty) lines.add('HR: $hr x/i');
    if (rr.isNotEmpty) lines.add('RR: $rr x/i');

    if (spo2.isNotEmpty) {
      String o2Abbr = '';
      if (o2Method == 'Room Air (RA)') {
        o2Abbr = 'RA';
      } else if (o2Method == 'Nasal Cannula (NK)') {
        o2Abbr = 'NK';
      } else if (o2Method == 'Non Rebreathing Mask (NRM)') {
        o2Abbr = 'NRM';
      }

      if (o2Abbr == 'RA') {
        lines.add('SpO2: $spo2% $o2Abbr');
      } else {
        String lpmStr = lpm.isNotEmpty ? ' $lpm lpm' : '';
        lines.add('SpO2: $spo2% on $o2Abbr$lpmStr');
      }
    }

    if (temp.isNotEmpty) lines.add('Temp: $temp C');

    if (isGdsChecked && gdsValue.isNotEmpty) lines.add('GDS: $gdsValue mg/dL');

    if (isOnIVDrug && ivDrugNames.isNotEmpty) {
      for (int i = 0; i < ivDrugNames.length; i++) {
        String rate = ivDrugRates.length > i && ivDrugRates[i].isNotEmpty
            ? ' ${ivDrugRates[i]} cc/jam'
            : '';
        lines.add('Terpasang ${ivDrugNames[i]}$rate');
      }
    }

    return lines.join('\n');
  }

  Map<String, dynamic> toJson() {
    return {
      'time': time,
      'bp': bp,
      'sens': sens,
      'gcs': gcs,
      'hr': hr,
      'rr': rr,
      'spo2': spo2,
      'o2Method': o2Method,
      'lpm': lpm,
      'temp': temp,
      'isGdsChecked': isGdsChecked,
      'gdsValue': gdsValue,
      'isOnIVDrug': isOnIVDrug,
      'ivDrugNames': ivDrugNames,
      'ivDrugRates': ivDrugRates,
      'keluhan': keluhan,
    };
  }

  factory VitalsEntry.fromJson(Map<String, dynamic> json) {
    return VitalsEntry(
      time: json['time'] ?? '',
      bp: json['bp'] ?? '',
      sens: json['sens'] ?? '',
      gcs: json['gcs'] ?? '',
      hr: json['hr'] ?? '',
      rr: json['rr'] ?? '',
      spo2: json['spo2'] ?? '',
      o2Method: json['o2Method'] ?? 'Room Air (RA)',
      lpm: json['lpm'] ?? '',
      temp: json['temp'] ?? '',
      isGdsChecked: json['isGdsChecked'] ?? false,
      gdsValue: json['gdsValue'] ?? '',
      isOnIVDrug: json['isOnIVDrug'] ?? false,
      ivDrugNames: List<String>.from(json['ivDrugNames'] ?? []),
      ivDrugRates: List<String>.from(json['ivDrugRates'] ?? []),
      keluhan: json['keluhan'] ?? '',
    );
  }
}

// --- DATA STRUCTURE 2: Holds Patient ID and a LIST of Vitals ---
class PatientRecord {
  String room;
  String rm;
  String name;
  String gender;
  String age; 
  List<VitalsEntry> vitals;

  PatientRecord({
    required this.room,
    required this.rm,
    required this.name,
    required this.gender,
    required this.age,
    required this.vitals,
  });

  void sortVitals() {
    vitals.sort((a, b) {
      int parseTime(String t) {
        List<String> parts = t.split(':');
        if (parts.length == 2) {
          int hours = int.tryParse(parts[0].trim()) ?? 0;
          int minutes = int.tryParse(parts[1].trim()) ?? 0;
          return (hours * 60) + minutes;
        }
        return 0;
      }

      return parseTime(a.time).compareTo(parseTime(b.time));
    });
  }

  String toFormattedString() {
    List<String> headerParts = [];

    if (room.isNotEmpty) headerParts.add(room);
    if (name.isNotEmpty) headerParts.add(name);

    headerParts.add(gender == 'Laki-laki (L)' ? 'L' : 'P');
    
    if (age.isNotEmpty) {
      String ageStr = age.toLowerCase().contains('thn') || age.toLowerCase().contains('tahun') 
          ? age 
          : '$age thn';
      headerParts.add(ageStr);
    }

    if (rm.isNotEmpty) headerParts.add(rm);

    String header = headerParts.join(' / ');
    String vitalsStr = vitals.map((v) => v.toFormattedString()).join('\n\n');

    return '''
$header

TTV
$vitalsStr
'''
        .trim();
  }

  Map<String, dynamic> toJson() {
    return {
      'room': room,
      'rm': rm,
      'name': name,
      'gender': gender,
      'age': age,
      'vitals': vitals.map((v) => v.toJson()).toList(),
    };
  }

  factory PatientRecord.fromJson(Map<String, dynamic> json) {
    return PatientRecord(
      room: json['room'] ?? '',
      rm: json['rm'] ?? '',
      name: json['name'] ?? '',
      gender: json['gender'] ?? 'Laki-laki (L)',
      age: json['age'] ?? '',
      vitals: (json['vitals'] as List<dynamic>?)
              ?.map((v) => VitalsEntry.fromJson(v as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class VitalsApp extends StatelessWidget {
  const VitalsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EZKOAS - TTV Pasien Gampang',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const MainMenuScreen(),
    );
  }
}

// --- MAIN MENU SCREEN ---
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  @override
  void initState() {
    super.initState();
    PatientDataManager.load().then((_) {
      setState(() {}); 
    });
  }

  void _copyAllToClipboard({bool useIzinFormat = false}) {
    if (PatientDataManager.savedPatients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada data untuk di-copy.')),
      );
      return;
    }

    String allDataCombined = PatientDataManager.savedPatients
        .map((record) => record.toFormattedString())
        .join('\n\n------------------\n\n');

    if (useIzinFormat) {
      allDataCombined =
          'Izin kak/bang, izin mengirimkan folket atas nama:\n\n$allDataCombined';
    }

    Clipboard.setData(ClipboardData(text: allDataCombined));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Berhasil meng-copy ${PatientDataManager.savedPatients.length} pasien!',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _resetAllData() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Data Pasien?'),
        content: const Text(
          'Semua data pasien yang tersimpan akan dihapus permanen. Apakah Anda yakin ingin melanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                PatientDataManager.savedPatients.clear();
              });
              PatientDataManager.save();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Semua data pasien telah dihapus.')),
              );
            },
            child: const Text(
              'RESET SEMUA',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('About EZKOAS', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_hospital, size: 64, color: Colors.teal),
              SizedBox(height: 16),
              Text(
                'EZKOAS - TTV Pasien Gampang\nVersion 1.2.0',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 16),
              Text(
                'Copyright © 2026 Andy Sitanggang.\nAll rights reserved.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 40,
              width: 40,
              child: Image.asset(
                'assets/logo_white.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.local_hospital),
              ),
            ),
            const SizedBox(width: 12),
            const Text('EZKOAS Menu Utama'),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VitalsScreen()),
                );
                setState(() {});
              },
              icon: const Icon(Icons.person_add, size: 28),
              label: const Text('Tambah Pasien Baru', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SavedPatientsListScreen()),
                );
                setState(() {});
              },
              icon: const Icon(Icons.edit_note, size: 28),
              label: const Text('Edit / Tambah TTV Pasien', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
                backgroundColor: Colors.teal.shade50,
                foregroundColor: Colors.teal.shade900,
                side: BorderSide(color: Colors.teal.shade200),
              ),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _copyAllToClipboard(useIzinFormat: false),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy Standar', style: TextStyle(fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _copyAllToClipboard(useIzinFormat: true),
                    icon: const Icon(Icons.send),
                    label: const Text('Copy + Izin', style: TextStyle(fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _resetAllData,
              icon: const Icon(Icons.delete_forever, size: 24),
              label: const Text('RESET PATIENT DATA', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.red.shade100,
                foregroundColor: Colors.red.shade900,
              ),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: _showAboutDialog,
              icon: const Icon(Icons.info_outline, size: 24),
              label: const Text('Tentang Aplikasi (About)', style: TextStyle(fontSize: 16)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- SAVED PATIENTS LIST SCREEN ---
class SavedPatientsListScreen extends StatefulWidget {
  const SavedPatientsListScreen({super.key});

  @override
  State<SavedPatientsListScreen> createState() => _SavedPatientsListScreenState();
}

class _SavedPatientsListScreenState extends State<SavedPatientsListScreen> {
  
  @override
  void initState() {
    super.initState();
    _refreshList();
  }

  void _refreshList() {
    setState(() {});
  }

  void _deletePatient(int index) {
    setState(() {
      PatientDataManager.savedPatients.removeAt(index);
    });
    PatientDataManager.save();
  }

  @override
  Widget build(BuildContext context) {
    final patients = PatientDataManager.savedPatients;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daftar Pasien Tersimpan'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: patients.isEmpty
          ? const Center(
              child: Text(
                'No patient Data',
                style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: patients.length,
              itemBuilder: (context, index) {
                final patient = patients[index];
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ExpansionTile(
                    title: Text(
                      patient.name.isNotEmpty ? patient.name : 'Pasien Tanpa Nama',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    subtitle: Text('RM: ${patient.rm} | Kamar: ${patient.room}'),
                    leading: const CircleAvatar(
                      backgroundColor: Colors.teal,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    children: [
                      const Divider(height: 1),
                      Container(
                        color: Colors.grey.shade50,
                        child: Row(
                          children: [
                            Expanded(
                              child: TextButton.icon(
                                onPressed: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => VitalsScreen(
                                        patientIndex: index,
                                      ),
                                    ),
                                  );
                                  _refreshList();
                                },
                                icon: const Icon(Icons.add_alarm, color: Colors.green, size: 18),
                                label: const Text('Tambah', style: TextStyle(color: Colors.green, fontSize: 12)),
                              ),
                            ),
                            Expanded(
                              child: TextButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: patient.toFormattedString()));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Data ${patient.name} berhasil di-copy!')),
                                  );
                                },
                                icon: const Icon(Icons.copy, color: Colors.blue, size: 18),
                                label: const Text('Copy', style: TextStyle(color: Colors.blue, fontSize: 12)),
                              ),
                            ),
                            Expanded(
                              child: TextButton.icon(
                                onPressed: () => _deletePatient(index),
                                icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                                label: const Text('Hapus', style: TextStyle(color: Colors.red, fontSize: 12)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      if (patient.vitals.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('Belum ada data TTV', style: TextStyle(fontStyle: FontStyle.italic)),
                        )
                      else
                        ...patient.vitals.asMap().entries.map((entry) {
                          int vIndex = entry.key;
                          VitalsEntry vitals = entry.value;
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.monitor_heart, color: Colors.teal, size: 20),
                            title: Text('Jam: ${vitals.time}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('TD: ${vitals.bp} | HR: ${vitals.hr} | SpO2: ${vitals.spo2}%'),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                              tooltip: 'Edit TTV ini',
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => VitalsScreen(
                                      patientIndex: index,
                                      vitalsIndex: vIndex,
                                    ),
                                  ),
                                );
                                _refreshList();
                              },
                            ),
                          );
                        }),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// --- GCS CALCULATOR SCREEN ---
class GcsCalculatorScreen extends StatefulWidget {
  const GcsCalculatorScreen({super.key});

  @override
  State<GcsCalculatorScreen> createState() => _GcsCalculatorScreenState();
}

class _GcsCalculatorScreenState extends State<GcsCalculatorScreen> {
  int? _eye;
  int? _verbal;
  int? _motor;

  final Map<String, int> _eyeOptions = {
    'Spontan (+4)': 4,
    'Terhadap suara (+3)': 3,
    'Terhadap nyeri (+2)': 2,
    'Tidak ada (+1)': 1,
    'NT (Not Testable)': 0,
  };

  final Map<String, int> _verbalOptions = {
    'Orientasi baik (+5)': 5,
    'Bingung (+4)': 4,
    'Kata tidak sesuai (+3)': 3,
    'Suara tidak dimengerti (+2)': 2,
    'Tidak ada (+1)': 1,
    'NT (Not Testable)': 0,
  };

  final Map<String, int> _motorOptions = {
    'Mematuhi perintah (+6)': 6,
    'Melokalisasi nyeri (+5)': 5,
    'Menarik diri (+4)': 4,
    'Fleksi abnormal (+3)': 3,
    'Ekstensi abnormal (+2)': 2,
    'Tidak ada (+1)': 1,
    'NT (Not Testable)': 0,
  };

  Widget _buildCategory(String title, Map<String, int> options, int? groupValue, ValueChanged<int?> onChanged) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.shade100,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal),
            ),
          ),
          ...options.entries.map((entry) {
            return RadioListTile<int>(
              title: Text(entry.key),
              value: entry.value,
              groupValue: groupValue,
              activeColor: Colors.teal,
              onChanged: onChanged,
            );
          }),
        ],
      ),
    );
  }

  void _saveGcs() {
    if (_eye != null && _verbal != null && _motor != null) {
      String result = '(E${_eye}V${_verbal}M$_motor)';
      Navigator.pop(context, result);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Harap pilih semua komponen (Eye, Verbal, Motorik)')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kalkulator GCS'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildCategory('Mata (Eye)', _eyeOptions, _eye, (val) => setState(() => _eye = val)),
            _buildCategory('Verbal', _verbalOptions, _verbal, (val) => setState(() => _verbal = val)),
            _buildCategory('Motorik', _motorOptions, _motor, (val) => setState(() => _motor = val)),
            
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                border: Border.all(color: Colors.blue.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Tips Interpretasi GCS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text('• Skor 13-15 : Cedera Kepala Ringan (CKR)\n• Skor 9-12 : Cedera Kepala Sedang (CKS)\n• Skor 3-8 : Cedera Kepala Berat (CKB) / Koma\n\n*Pilih NT (0) jika komponen tidak dapat dinilai (misal mata bengkak hebat atau pasien terintubasi).', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saveGcs,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('Simpan / Hitung', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// --- VITALS SCREEN ---
class VitalsScreen extends StatefulWidget {
  final int? patientIndex;
  final int? vitalsIndex;

  const VitalsScreen({super.key, this.patientIndex, this.vitalsIndex});

  @override
  State<VitalsScreen> createState() => _VitalsScreenState();
}

class _VitalsScreenState extends State<VitalsScreen> {
  bool _isSearchMode = false;
  bool _isSearching = false;
  final TextEditingController _searchNameController = TextEditingController();
  final TextEditingController _searchRmController = TextEditingController();
  final TextEditingController _searchRoomController = TextEditingController();

  final String _sheetApiUrl = 'https://script.google.com/macros/s/AKfycbxzLPBdLsAb1ht-VecBhFW_5Jp00h3b_lhCM_nBXuuUHO5vD8EpWA-xnIl8gKvssROR0g/exec';
  List<Map<String, dynamic>> _sheetDatabase = [];
  bool _isLoadingDatabase = false;

  final TextEditingController _keluhanController = TextEditingController();
  final TextEditingController _roomController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _rmController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();

  final List<String> _genderOptions = ['Laki-laki (L)', 'Perempuan (P)'];
  String _selectedGender = 'Laki-laki (L)';

  final List<String> _sensOptions = [
    'Compos mentis',
    'Apatis',
    'Somnolen',
    'Delirium',
    'Coma',
  ];
  String? _selectedSens;
  String _gcsResult = ''; 

  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _bpController = TextEditingController();
  final TextEditingController _hrController = TextEditingController();
  final TextEditingController _rrController = TextEditingController();
  final TextEditingController _spo2Controller = TextEditingController();
  final TextEditingController _tempController = TextEditingController();
  final TextEditingController _lpmController = TextEditingController();

  bool _showOtherExams = false; // Toggles the visibility of GDS and IV sections
  bool _isGdsChecked = false;
  final TextEditingController _gdsController = TextEditingController();

  final List<String> _o2Options = [
    'Room Air (RA)',
    'Nasal Cannula (NK)',
    'Non Rebreathing Mask (NRM)',
  ];
  String _selectedO2Method = 'Room Air (RA)';

  bool _isOnIVDrug = false;
  final List<String> _ivDrugSelections = [];
  final List<String> _ivDrugRates = [];
  final List<String?> _customIVDrugs = [];
  final List<TextEditingController> _ivRateControllers = [];
  final List<String> _ivDrugOptions = [
    'Novorapid',
    'Norepinephrine',
    'Furosemide',
    'Nicardipine',
    'Dopamine',
    'Dobutamine',
    'Lainnya',
  ];

  String? _gdsProtocolMessage;
  String? _suggestedNovorapidRate;

  final TextEditingController _notesController = TextEditingController();
  bool _isHyperglycemiaExpanded = false;
  bool _isHypoglycemiaExpanded = false;

  @override
  void initState() {
    super.initState();
    _timeController.text = _getCurrentTime();

    _notesController.text = '''Protokol Hiperglikemia
"Protokol Hiperglikemia jika GDS di atas 200
Drip Novorapid 50 unit dalam 50cc NaCl 0.9% dalam syringe pump --> Start 3 cc/jam
Jika KGD > 400 : 6 cc/jam
KGD 350-400 : 3,5 cc/jam
KGD 300-350 : 3 cc/jam
KGD 250-300 : 2,5 cc/jam
KGD 200-250 : 2 cc/jam
KGD 150-200 : 1 cc/jam
KGD 100-150 : 0,5 cc/jam
KGD < 100 : stop, Lapor

Follow up KGDs per 3 jam dan naikkan dosis sesuai protokol setiap 3 jam

Jika KGD>450, follow up KGDs per 1 jam, dan naikkan dosis drip 1 cc/jam sampai KGDs mencapai <400"

Protokol Hipoglikemia
"Rencana protap hipoglikemia

Jika KGDs <70, berikan bolus D40% 2flc, cek ulang KGD dalam 30 menit.

Jika KGD masih <70, ulangi pemberian D40% 1flc per 30 menit sampai tercapai target KGD >70. Cek kgd selanjutnya per 1 jam.

Jika KGD >70 dan masih <100, berikan cairan D10% 20gtt/menit.

Pada follow up KGD 1 jam kemudian, jika KGD >100, lanjutkan D10% 20 gtt/menit, dan cek KGD per 4 jam.

Jika pada follow up KGD per 4 jam berikutnya, KGD >200, aff cairan D10% dan ganti dengan NaCl 0.9% maintenance.

Jika pada follow up KGD per 4 jam, KGD kembali <70, kembali pada protokol awal."''';
    
    _fetchDatabase(); 

    if (widget.patientIndex != null) {
      _loadDataForEditing();
    }
  }

  void _loadDataForEditing() {
    final patient = PatientDataManager.savedPatients[widget.patientIndex!];
    _roomController.text = patient.room;
    _rmController.text = patient.rm;
    _nameController.text = patient.name;
    _ageController.text = patient.age;
    _selectedGender = _genderOptions.contains(patient.gender) ? patient.gender : 'Laki-laki (L)';

    if (widget.vitalsIndex != null) {
      final vitalsToEdit = patient.vitals[widget.vitalsIndex!];
      _timeController.text = vitalsToEdit.time;
      _keluhanController.text = vitalsToEdit.keluhan;
      _bpController.text = vitalsToEdit.bp;
      _selectedSens = _sensOptions.contains(vitalsToEdit.sens) ? vitalsToEdit.sens : null;
      _gcsResult = vitalsToEdit.gcs;
      _hrController.text = vitalsToEdit.hr;
      _rrController.text = vitalsToEdit.rr;
      _spo2Controller.text = vitalsToEdit.spo2;
      _selectedO2Method = vitalsToEdit.o2Method;
      _lpmController.text = vitalsToEdit.lpm;
      _tempController.text = vitalsToEdit.temp;

      _isGdsChecked = vitalsToEdit.isGdsChecked;
      _gdsController.text = vitalsToEdit.gdsValue;

      _isOnIVDrug = vitalsToEdit.isOnIVDrug;
      
      if (_isGdsChecked || _isOnIVDrug) {
        _showOtherExams = true;
      }

      for (int i = 0; i < vitalsToEdit.ivDrugNames.length; i++) {
        final name = vitalsToEdit.ivDrugNames[i];
        final rate = vitalsToEdit.ivDrugRates.length > i ? vitalsToEdit.ivDrugRates[i] : '';
        if (_ivDrugOptions.contains(name)) {
          _ivDrugSelections.add(name);
          _customIVDrugs.add(null);
        } else {
          _ivDrugSelections.add('Lainnya');
          _customIVDrugs.add(name);
        }
        _ivDrugRates.add(rate);
        _ivRateControllers.add(TextEditingController(text: rate));
      }
      _evaluateGDSProtocol(vitalsToEdit.gdsValue);
    }
  }

  Future<void> _fetchDatabase() async {
    setState(() => _isLoadingDatabase = true);
    try {
      final response = await http.get(Uri.parse(_sheetApiUrl));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _sheetDatabase = data.map((e) => e as Map<String, dynamic>).toList();
        });
      }
    } catch (e) {
      debugPrint('Error fetching database: $e');
    }
    setState(() => _isLoadingDatabase = false);
  }

  Future<bool> _searchAndFillFromSheet({String? nama, String? rm, String? ruang}) async {
    if (_sheetDatabase.isEmpty) {
      await _fetchDatabase();
    }
    if (_sheetDatabase.isEmpty) return false;

    Map<String, dynamic>? bestMatch;

    for (var row in _sheetDatabase) {
      bool isMatch = false;

      if (nama != null && nama.isNotEmpty) {
        String searchName = nama.toLowerCase().trim();
        String dbName = (row['Nama']?.toString() ?? '').toLowerCase();
        if (dbName.contains(searchName)) {
          isMatch = true;
        }
      } 
      else if (rm != null && rm.isNotEmpty) {
        String searchRm = rm.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        String dbRm = (row['No RM']?.toString() ?? row['No. RM']?.toString() ?? row['RM']?.toString() ?? '')
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        
        if (dbRm.contains(searchRm) && searchRm.isNotEmpty) {
          isMatch = true;
        }
      } 
      else if (ruang != null && ruang.isNotEmpty) {
        String searchRuang = ruang.toLowerCase().trim();
        String dbRuang = (row['Ruang Rawat']?.toString() ?? '').toLowerCase();
        if (dbRuang.contains(searchRuang)) {
          isMatch = true;
        }
      }

      if (isMatch) {
        bestMatch = row;
        break; 
      }
    }

    if (bestMatch != null) {
      setState(() {
        _nameController.text = bestMatch!['Nama']?.toString() ?? '';
        _rmController.text = bestMatch['No RM']?.toString() ?? bestMatch['No. RM']?.toString() ?? bestMatch['RM']?.toString() ?? '';
        _roomController.text = bestMatch['Ruang Rawat']?.toString() ?? '';
        _ageController.text = bestMatch['Umur']?.toString() ?? bestMatch['Usia']?.toString() ?? '';

        String sheetGender = (bestMatch['Jenis Kelamin']?.toString() ?? '').trim().toLowerCase();
        if (sheetGender == 'l' || sheetGender.contains('laki') || sheetGender.contains('pria')) {
          _selectedGender = 'Laki-laki (L)';
        } else if (sheetGender == 'p' || sheetGender.contains('perempuan') || sheetGender.contains('wanita')) {
          _selectedGender = 'Perempuan (P)';
        }
      });
      return true; 
    }
    return false; 
  }

  Future<void> _performSearch() async {
    FocusScope.of(context).unfocus();
    
    String nama = _searchNameController.text.trim();
    String rm = _searchRmController.text.trim();
    String ruang = _searchRoomController.text.trim();

    if (nama.isEmpty && rm.isEmpty && ruang.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Harap isi minimal satu kolom untuk mencari.')),
      );
      return;
    }

    setState(() {
      _isSearching = true;
    });

    bool isFound = await _searchAndFillFromSheet(nama: nama, rm: rm, ruang: ruang);

    setState(() {
      _isSearching = false;
    });

    if (isFound) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data berhasil ditemukan dan diisi!'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _isSearchMode = false;
        _searchNameController.clear();
        _searchRmController.clear();
        _searchRoomController.clear();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing found (Data tidak ditemukan)'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  String _getCurrentTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  String _formatTime(String input) {
    if (input.trim().isEmpty) return _getCurrentTime();

    String sanitized = input.replaceAll('.', ':');
    List<String> parts = sanitized.split(':');

    if (parts.length == 2) {
      String hours = parts[0].trim().padLeft(2, '0');
      String minutes = parts[1].trim();
      if (minutes.length == 1) {
        minutes = '0$minutes';
      } else {
        minutes = minutes.padLeft(2, '0');
      }
      return '$hours:$minutes';
    }
    return sanitized;
  }

  void _evaluateGDSProtocol(String gdsInput) {
    double? gds = double.tryParse(gdsInput);

    if (gds == null) {
      setState(() {
        _gdsProtocolMessage = null;
        _suggestedNovorapidRate = null;
      });
      return;
    }

    String message = '';
    String? rate;

    if (gds < 70) {
      message =
          'Protokol Hipoglikemia:\nJika KGDs <70, berikan bolus D40% 2flc\nCek ulang KGD dalam 30 menit.';
      rate = null;
    } else if (gds >= 70 && gds < 100) {
      message = 'GDS < 100\nSTOP Drip. Lapor Residen/DPJP!';
      rate = '0.5';
    } else if (gds >= 100 && gds <= 150) {
      message =
          'Protokol Hiperglikemia:\nDosis: 0.5 cc/jam\nFollow-up GDS per 3 jam.';
      rate = '0.5';
    } else if (gds > 150 && gds <= 200) {
      message =
          'Protokol Hiperglikemia:\nDosis: 1 cc/jam\nFollow-up GDS per 3 jam.';
      rate = '1';
    } else if (gds > 200 && gds <= 250) {
      message =
          'Protokol Hiperglikemia:\nDosis: 2 cc/jam\nFollow-up GDS per 3 jam.';
      rate = '2';
    } else if (gds > 250 && gds <= 300) {
      message =
          'Protokol Hiperglikemia:\nDosis: 2.5 cc/jam\nFollow-up GDS per 3 jam.';
      rate = '2.5';
    } else if (gds > 300 && gds <= 350) {
      message =
          'Protokol Hiperglikemia:\nDosis: 3 cc/jam\nFollow-up GDS per 3 jam.';
      rate = '3';
    } else if (gds > 350 && gds <= 400) {
      message =
          'Protokol Hiperglikemia:\nDosis: 3.5 cc/jam\nFollow-up GDS per 3 jam.';
      rate = '3.5';
    } else if (gds > 400 && gds <= 450) {
      message =
          'Protokol Hiperglikemia:\nDosis: 6 cc/jam\nFollow-up GDS per 3 jam.';
      rate = '6';
    } else if (gds > 450) {
      message =
          'PERINGATAN: GDS > 450!\nNaikkan dosis 1 cc/jam.\nFollow-up GDS PER 1 JAM sampai < 400.';
      rate = null;
    }

    setState(() {
      _gdsProtocolMessage = message.isNotEmpty ? message : null;
      _suggestedNovorapidRate = rate;
    });
  }

  void _savePatient() {
    if (_nameController.text.isEmpty && _rmController.text.isEmpty) return;

    final List<String> ivDrugNames = [];
    final List<String> ivDrugRates = [];
    for (int i = 0; i < _ivDrugSelections.length; i++) {
      final name = _ivDrugSelections[i] == 'Lainnya'
          ? (_customIVDrugs[i] ?? '')
          : _ivDrugSelections[i];
      final rate = _ivDrugRates[i];
      ivDrugNames.add(name);
      ivDrugRates.add(rate);
    }

    final newVitals = VitalsEntry(
      time: _formatTime(_timeController.text),
      bp: _bpController.text,
      sens: _selectedSens ?? '',
      gcs: _gcsResult,
      hr: _hrController.text,
      rr: _rrController.text,
      spo2: _spo2Controller.text,
      o2Method: _selectedO2Method,
      lpm: _lpmController.text,
      temp: _tempController.text,
      isGdsChecked: _isGdsChecked,
      gdsValue: _gdsController.text,
      isOnIVDrug: _isOnIVDrug,
      ivDrugNames: ivDrugNames,
      ivDrugRates: ivDrugRates,
      keluhan: _keluhanController.text,
    );

    setState(() {
      if (widget.patientIndex != null && widget.vitalsIndex != null) {
        PatientDataManager.savedPatients[widget.patientIndex!].room = _roomController.text;
        PatientDataManager.savedPatients[widget.patientIndex!].rm = _rmController.text;
        PatientDataManager.savedPatients[widget.patientIndex!].name = _nameController.text;
        PatientDataManager.savedPatients[widget.patientIndex!].gender = _selectedGender;
        PatientDataManager.savedPatients[widget.patientIndex!].age = _ageController.text;
        PatientDataManager.savedPatients[widget.patientIndex!].vitals[widget.vitalsIndex!] = newVitals;
        PatientDataManager.savedPatients[widget.patientIndex!].sortVitals();
      } else if (widget.patientIndex != null && widget.vitalsIndex == null) {
        PatientDataManager.savedPatients[widget.patientIndex!].room = _roomController.text;
        PatientDataManager.savedPatients[widget.patientIndex!].rm = _rmController.text;
        PatientDataManager.savedPatients[widget.patientIndex!].name = _nameController.text;
        PatientDataManager.savedPatients[widget.patientIndex!].gender = _selectedGender;
        PatientDataManager.savedPatients[widget.patientIndex!].age = _ageController.text;
        PatientDataManager.savedPatients[widget.patientIndex!].vitals.add(newVitals);
        PatientDataManager.savedPatients[widget.patientIndex!].sortVitals();
      } else {
        int existingIdx = -1;
        if (_rmController.text.isNotEmpty) {
          existingIdx = PatientDataManager.savedPatients.indexWhere(
            (p) => p.rm == _rmController.text,
          );
        }

        if (existingIdx != -1) {
          PatientDataManager.savedPatients[existingIdx].vitals.add(newVitals);
          PatientDataManager.savedPatients[existingIdx].sortVitals();
        } else {
          PatientDataManager.savedPatients.add(
            PatientRecord(
              room: _roomController.text,
              rm: _rmController.text,
              name: _nameController.text,
              gender: _selectedGender,
              age: _ageController.text,
              vitals: [newVitals],
            ),
          );
        }
      }
    });

    PatientDataManager.save();
    FocusScope.of(context).unfocus();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Data disimpan! Total pasien: ${PatientDataManager.savedPatients.length}',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
    Navigator.pop(context); 
  }

  void _showNotesDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            String notesContent = _notesController.text;
            String hyperglycemiaProtocol = '';
            String hypoglycemiaProtocol = '';
            String generalNotes = '';

            int hyperStart = notesContent.indexOf('Protokol Hiperglikemia');
            int hyperEnd = notesContent.indexOf('Protokol Hipoglikemia');
            if (hyperStart != -1 && hyperEnd != -1) {
              hyperglycemiaProtocol = notesContent
                  .substring(hyperStart, hyperEnd)
                  .trim();
            } else if (hyperStart != -1) {
              hyperglycemiaProtocol = notesContent.substring(hyperStart).trim();
            }

            int hypoStart = notesContent.indexOf('Protokol Hipoglikemia');
            if (hypoStart != -1) {
              hypoglycemiaProtocol = notesContent.substring(hypoStart).trim();
            }

            if (hyperStart > 0) {
              generalNotes = notesContent.substring(0, hyperStart).trim();
            }

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.8,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.inversePrimary,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(4),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Catatan Medis',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (generalNotes.isNotEmpty) ...[
                              const Text(
                                'Catatan Umum',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: TextEditingController(
                                  text: generalNotes,
                                ),
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  hintText: 'Tambahkan catatan umum...',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.all(8),
                                ),
                                style: const TextStyle(fontSize: 14),
                                onChanged: (value) {
                                  String updatedContent =
                                      '$value\n\n$hyperglycemiaProtocol\n\n$hypoglycemiaProtocol';
                                  _notesController.text = updatedContent.trim();
                                },
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (hyperglycemiaProtocol.isNotEmpty) ...[
                              Card(
                                elevation: 2,
                                child: Column(
                                  children: [
                                    ListTile(
                                      title: const Text(
                                        'Protokol Hiperglikemia',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red,
                                        ),
                                      ),
                                      trailing: IconButton(
                                        icon: Icon(
                                          _isHyperglycemiaExpanded
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _isHyperglycemiaExpanded =
                                                !_isHyperglycemiaExpanded;
                                          });
                                        },
                                      ),
                                    ),
                                    if (_isHyperglycemiaExpanded) ...[
                                      Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Text(
                                          hyperglycemiaProtocol.replaceFirst(
                                            'Protokol Hiperglikemia\n',
                                            '',
                                          ),
                                          style: const TextStyle(
                                            fontSize: 14,
                                            height: 1.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (hypoglycemiaProtocol.isNotEmpty) ...[
                              Card(
                                elevation: 2,
                                child: Column(
                                  children: [
                                    ListTile(
                                      title: const Text(
                                        'Protokol Hipoglikemia',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue,
                                        ),
                                      ),
                                      trailing: IconButton(
                                        icon: Icon(
                                          _isHypoglycemiaExpanded
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _isHypoglycemiaExpanded =
                                                !_isHypoglycemiaExpanded;
                                          });
                                        },
                                      ),
                                    ),
                                    if (_isHypoglycemiaExpanded) ...[
                                      Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Text(
                                          hypoglycemiaProtocol.replaceFirst(
                                            'Protokol Hipoglikemia\n',
                                            '',
                                          ),
                                          style: const TextStyle(
                                            fontSize: 14,
                                            height: 1.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            const Text(
                              'Catatan Tambahan',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const TextField(
                              maxLines: 5,
                              decoration: InputDecoration(
                                hintText:
                                    'Tambahkan catatan tambahan di sini...',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.all(8),
                              ),
                              style: TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _addIVDrug() {
    setState(() {
      _ivDrugSelections.add('Novorapid');
      _ivDrugRates.add('');
      _customIVDrugs.add(null);
      _ivRateControllers.add(TextEditingController());
    });
  }

  void _removeIVDrug(int index) {
    setState(() {
      _ivDrugSelections.removeAt(index);
      _ivDrugRates.removeAt(index);
      _customIVDrugs.removeAt(index);
      _ivRateControllers[index].dispose();
      _ivRateControllers.removeAt(index);
    });
  }

  @override
  void dispose() {
    _roomController.dispose();
    _nameController.dispose();
    _rmController.dispose();
    _ageController.dispose(); 
    _keluhanController.dispose();
    _timeController.dispose();
    _bpController.dispose();
    _hrController.dispose();
    _rrController.dispose();
    _spo2Controller.dispose();
    _tempController.dispose();
    _lpmController.dispose();
    _gdsController.dispose();
    _searchNameController.dispose();
    _searchRmController.dispose();
    _searchRoomController.dispose();
    for (var controller in _ivRateControllers) {
      controller.dispose();
    }
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.patientIndex != null ? 'Edit TTV Pasien' : 'Form Pasien Baru'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _isLoadingDatabase ? null : _fetchDatabase,
            tooltip: 'Sync Database',
          ),
        ],
      ),

      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.patientIndex == null) ...[
                  CheckboxListTile(
                    value: _isSearchMode,
                    onChanged: (val) {
                      setState(() {
                        _isSearchMode = val ?? false;
                      });
                    },
                    title: const Text('Cari Data Pasien (Auto-fill)'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    activeColor: Colors.teal,
                  ),
                  
                  if (_isSearchMode)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Masukkan minimal satu data untuk mencari:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _searchNameController,
                            decoration: const InputDecoration(
                              labelText: 'Nama Pasien',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _searchRmController,
                            decoration: const InputDecoration(
                              labelText: 'No. RM',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _searchRoomController,
                            decoration: const InputDecoration(
                              labelText: 'Ruangan/Kamar',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _isSearching
                              ? const Center(child: CircularProgressIndicator())
                              : ElevatedButton.icon(
                                  onPressed: _performSearch,
                                  icon: const Icon(Icons.search),
                                  label: const Text('Cari Pasien'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                        ],
                      ),
                    ),
                ],

                Text(
                  widget.patientIndex != null ? 'Edit Identitas' : 'Identitas Pasien',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: widget.patientIndex != null ? Colors.orange : Colors.teal,
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _roomController,
                        decoration: const InputDecoration(
                          labelText: 'Ruangan/Kamar',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _rmController,
                        decoration: const InputDecoration(
                          labelText: 'No. RM',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nama Pasien',
                          border: OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _selectedGender,
                        decoration: const InputDecoration(
                          labelText: 'Gender',
                          border: OutlineInputBorder(),
                        ),
                        items: _genderOptions.map((String gender) {
                          return DropdownMenuItem<String>(
                            value: gender,
                            child: Text(
                              gender,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (String? newValue) =>
                                setState(() => _selectedGender = newValue!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _ageController,
                        decoration: const InputDecoration(
                          labelText: 'Umur',
                          suffixText: 'thn',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),

                Row(
                  children: [
                    const Expanded(
                      flex: 2,
                      child: Text(
                        'Tanda-Tanda Vital',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _timeController,
                        decoration: const InputDecoration(
                          labelText: 'Waktu (Jam)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.access_time, size: 18),
                        ),
                        keyboardType: TextInputType.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _selectedSens,
                        decoration: const InputDecoration(
                          labelText: 'Sens',
                          hintText: 'Pilih sens',
                          border: OutlineInputBorder(),
                        ),
                        items: _sensOptions.map((String option) {
                          return DropdownMenuItem<String>(
                            value: option,
                            child: Text(
                              option,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (String? newValue) =>
                            setState(() => _selectedSens = newValue),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _selectedSens = null),
                      tooltip: 'Clear Sens',
                    ),
                    IconButton(
                      icon: const Icon(Icons.calculate, color: Colors.teal, size: 28),
                      tooltip: 'Hitung GCS',
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const GcsCalculatorScreen()),
                        );
                        if (result != null) {
                          setState(() {
                            _gcsResult = result as String;
                          });
                        }
                      },
                    ),
                  ],
                ),
                
                if (_gcsResult.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, left: 4.0),
                    child: Row(
                      children: [
                        const Icon(Icons.psychology, size: 16, color: Colors.teal),
                        const SizedBox(width: 8),
                        Text(
                          'Hasil GCS: $_gcsResult',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () => setState(() => _gcsResult = ''),
                          child: const Text('Hapus GCS', style: TextStyle(color: Colors.red, fontSize: 12)),
                        )
                      ],
                    ),
                  ),

                const SizedBox(height: 16),

                TextField(
                  controller: _keluhanController,
                  decoration: const InputDecoration(
                    labelText: 'Keluhan',
                    hintText: 'Keluhan yang sedang dialami pasien',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _bpController,
                  decoration: const InputDecoration(
                    labelText: 'Tekanan Darah (TD)',
                    suffixText: 'mmHg',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.text,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
                  ],
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _hrController,
                  decoration: const InputDecoration(
                    labelText: 'Heart Rate (HR)',
                    suffixText: 'x/i',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _rrController,
                  decoration: const InputDecoration(
                    labelText: 'Respiratory Rate (RR)',
                    suffixText: 'x/i',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _spo2Controller,
                        decoration: const InputDecoration(
                          labelText: 'SpO2 ',
                          suffixText: '%',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),

                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _selectedO2Method,
                        decoration: const InputDecoration(
                          labelText: 'Oksigen',
                          border: OutlineInputBorder(),
                        ),
                        items: _o2Options.map((String method) {
                          return DropdownMenuItem<String>(
                            value: method,
                            child: Text(
                              method,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14),
                            ),
                          );
                        }).toList(),
                        onChanged: (String? newValue) =>
                            setState(() => _selectedO2Method = newValue!),
                      ),
                    ),

                    if (_selectedO2Method != 'Room Air (RA)') ...[
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _lpmController,
                          decoration: const InputDecoration(
                            labelText: 'LPM',
                            suffixText: 'lpm',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: _tempController,
                  decoration: const InputDecoration(
                    labelText: 'Temperature',
                    suffixText: 'C',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),

                const SizedBox(height: 24),

                // Button to reveal other exams
                if (!_showOtherExams)
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showOtherExams = true;
                      });
                    },
                    icon: const Icon(Icons.add_circle_outline, color: Colors.teal),
                    label: const Text('Tambahkan Pemeriksaan lainnya', style: TextStyle(color: Colors.teal)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: Colors.teal.shade300),
                    ),
                  )
                else ...[
                  const Divider(),
                  const Text(
                    'Pemeriksaan Lainnya',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Checkbox(
                                value: _isGdsChecked,
                                activeColor: Colors.teal,
                                onChanged: (bool? value) {
                                  setState(() {
                                    _isGdsChecked = value ?? false;
                                    if (!_isGdsChecked) {
                                      _gdsProtocolMessage = null; 
                                    }
                                  });
                                },
                              ),
                              const Expanded(
                                child: Text(
                                  'Cek GDS',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 30,
                          color: Colors.grey.shade300,
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              Checkbox(
                                value: _isOnIVDrug,
                                activeColor: Colors.teal,
                                onChanged: (bool? value) =>
                                    setState(() => _isOnIVDrug = value ?? false),
                              ),
                              const Expanded(
                                child: Text(
                                  'Obat IV / Pump',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  if (_isGdsChecked || _isOnIVDrug) const SizedBox(height: 16),

                  if (_isGdsChecked) ...[
                    TextField(
                      controller: _gdsController,
                      decoration: const InputDecoration(
                        labelText: 'Hasil GDS',
                        suffixText: 'mg/dL',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) => _evaluateGDSProtocol(value),
                    ),

                    if (_gdsProtocolMessage != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          border: Border.all(color: Colors.orange),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _gdsProtocolMessage!,
                                    style: TextStyle(
                                      color: Colors.orange.shade900,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (_suggestedNovorapidRate != null) ...[
                                    const SizedBox(height: 8),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _isOnIVDrug = true;
                                          if (_ivDrugSelections.isEmpty) {
                                            _addIVDrug();
                                          }
                                          _ivDrugSelections[0] = 'Novorapid';
                                          _ivDrugRates[0] = _suggestedNovorapidRate!;
                                          _ivRateControllers[0].text = _suggestedNovorapidRate!;
                                          FocusScope.of(context).unfocus();
                                        });
                                      },
                                      child: const Text(
                                        'Terapkan Dosis Novorapid',
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],

                  if (_isOnIVDrug) ...[
                    Column(
                      children: [
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _ivDrugSelections.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      initialValue: _ivDrugSelections[index],
                                      decoration: const InputDecoration(
                                        labelText: 'Nama Obat IV',
                                        border: OutlineInputBorder(),
                                      ),
                                      items: _ivDrugOptions.map((String drug) {
                                        return DropdownMenuItem<String>(
                                          value: drug,
                                          child: Text(
                                            drug,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (String? newValue) => setState(
                                        () =>
                                            _ivDrugSelections[index] = newValue!,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: _ivRateControllers[index],
                                      decoration: const InputDecoration(
                                        labelText: 'Rate',
                                        suffixText: 'cc/jam',
                                        border: OutlineInputBorder(),
                                      ),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      onChanged: (value) =>
                                          _ivDrugRates[index] = value,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                      color: Colors.red,
                                    ),
                                    onPressed: () => _removeIVDrug(index),
                                    tooltip: 'Hapus Obat',
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _addIVDrug,
                          icon: const Icon(Icons.add),
                          label: const Text('Tambah Obat IV'),
                        ),
                        ..._ivDrugSelections
                            .asMap()
                            .entries
                            .where((entry) => entry.value == 'Lainnya')
                            .map((entry) {
                              int index = entry.key;
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: TextFormField(
                                  initialValue: _customIVDrugs[index],
                                  onChanged: (value) {
                                    _customIVDrugs[index] = value;
                                  },
                                  decoration: InputDecoration(
                                    labelText: 'Nama Obat IV Lainnya (${index + 1})',
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              );
                            }),
                      ],
                    ),
                  ],
                ],

                const SizedBox(height: 32),

                OutlinedButton.icon(
                  onPressed: _savePatient,
                  icon: Icon(
                    widget.patientIndex != null ? Icons.save_as : Icons.add,
                  ),
                  label: Text(
                    widget.patientIndex != null
                        ? 'Update Data Pasien'
                        : 'Simpan ke Antrean',
                    style: const TextStyle(fontSize: 16),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
                
                const SizedBox(height: 80),
              ],
            ),
          ),

          // Notes FAB
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'notes_fab',
              onPressed: _showNotesDialog,
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              elevation: 6,
              icon: const Icon(Icons.note),
              label: const Text('Catatan'),
            ),
          ),
        ],
      ),
    );
  }
}