import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const String apiUrl = 'https://hen-price-api.onrender.com/predict';

// Test RMSE of the Random Forest, used to show the likely price range
const double typicalError = 330;

const Color kGreen = Color(0xFF1F4D36);
const Color kGold = Color(0xFFF6D49A);
const Color kBackground = Color(0xFFF6F4EE);
const Color kCardBorder = Color(0xFFE5E1D5);
const Color kFieldFill = Color(0xFFF4F2EC);
const Color kFieldBorder = Color(0xFFE2DED2);
const Color kText = Color(0xFF1A2420);
const Color kLabel = Color(0xFF34433A);
const Color kMuted = Color(0xFF5A675F);
const Color kHint = Color(0xFF6B776F);
const Color kError = Color(0xFFB3261E);
const Color kErrorFill = Color(0xFFFDF1EF);
const Color kErrorBorder = Color(0xFFF1C4BE);
const Color kErrorText = Color(0xFF8C1D18);

// All 30 districts of Rwanda, grouped by province
const Map<String, List<String>> districtsByProvince = {
  'Eastern Province': [
    'Bugesera',
    'Gatsibo',
    'Kayonza',
    'Kirehe',
    'Ngoma',
    'Nyagatare',
    'Rwamagana',
  ],
  'Kigali City': ['Gasabo', 'Kicukiro', 'Nyarugenge'],
  'Northern Province': ['Burera', 'Gakenke', 'Gicumbi', 'Musanze', 'Rulindo'],
  'Southern Province': [
    'Gisagara',
    'Huye',
    'Kamonyi',
    'Muhanga',
    'Nyamagabe',
    'Nyanza',
    'Nyaruguru',
    'Ruhango',
  ],
  'Western Province': [
    'Karongi',
    'Ngororero',
    'Nyabihu',
    'Nyamasheke',
    'Rubavu',
    'Rusizi',
    'Rutsiro',
  ],
};

// [latitude, longitude] for each district.
const Map<String, List<double>> districtCoordinates = {
  'Bugesera': [-2.18, 30.16],
  'Gatsibo': [-1.78, 30.38],
  'Kayonza': [-2.02, 30.55],
  'Kirehe': [-2.28, 30.61],
  'Ngoma': [-2.16, 30.54],
  'Nyagatare': [-1.23, 30.36],
  'Rwamagana': [-1.94, 30.37],
  'Gasabo': [-1.88, 30.13],
  'Kicukiro': [-1.98, 30.11],
  'Nyarugenge': [-1.95, 30.06],
  'Burera': [-1.60, 29.88],
  'Gakenke': [-1.66, 29.81],
  'Gicumbi': [-1.58, 30.08],
  'Musanze': [-1.53, 29.61],
  'Rulindo': [-1.68, 29.98],
  'Gisagara': [-2.65, 29.78],
  'Huye': [-2.53, 29.70],
  'Kamonyi': [-2.01, 29.88],
  'Muhanga': [-2.08, 29.75],
  'Nyamagabe': [-2.48, 29.53],
  'Nyanza': [-2.35, 29.75],
  'Nyaruguru': [-2.67, 29.61],
  'Ruhango': [-2.23, 29.66],
  'Karongi': [-2.06, 29.35],
  'Ngororero': [-1.75, 29.54],
  'Nyabihu': [-1.62, 29.55],
  'Nyamasheke': [-2.36, 29.11],
  'Rubavu': [-1.70, 29.33],
  'Rusizi': [-2.48, 28.90],
  'Rutsiro': [-1.93, 29.41],
};

// The 11 model inputs: the name the API expects -> a readable name for messages
const Map<String, String> fieldNames = {
  'province': 'Province',
  'district': 'District',
  'latitude': 'Latitude',
  'longitude': 'Longitude',
  'year': 'Year',
  'month': 'Month',
  'egg_price': 'Egg price',
  'maize_price': 'Maize price',
  'soybean_price': 'Soybean price',
  'beans_price': 'Dry beans price',
  'beef_price': 'Beef price',
};
const List<String> textInputs = ['province', 'district'];
const List<String> wholeNumberInputs = ['year', 'month'];

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hen Price Predictor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kGreen, primary: kGreen),
        scaffoldBackgroundColor: kBackground,
      ),
      home: const PredictionPage(),
    );
  }
}

class PredictionPage extends StatefulWidget {
  const PredictionPage({super.key});

  @override
  State<PredictionPage> createState() => _PredictionPageState();
}

class _PredictionPageState extends State<PredictionPage> {
  final Map<String, TextEditingController> _c = {
    for (final key in fieldNames.keys) key: TextEditingController(),
  };
  final ScrollController _scroll = ScrollController();

  String? _province; // chosen from the list; used to filter the districts
  double? _price;
  String? _error;
  String? _errorField; // the field to outline in red
  bool _loading = false;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  // 3923.4 -> "3,923"
  String _fmt(double value) {
    final s = value.round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // The result sits below the form, so bring it into view after each prediction
  void _scrollToResult() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _fail(String message, String? field) {
    setState(() {
      _error = message;
      _errorField = field;
      _price = null;
    });
    _scrollToResult();
  }

  // Turns the API's 422 response (wrong type / out of range) into readable text
  void _handleValidationError(String body) {
    try {
      final detail = jsonDecode(body)['detail'];
      if (detail is List && detail.isNotEmpty) {
        String? firstField;
        final lines = <String>[];
        for (final e in detail) {
          final key = (e['loc'] as List).last.toString();
          firstField ??= key;
          final name = fieldNames[key] ?? key;
          final msg = e['type'] == 'literal_error'
              ? 'please choose one from the list'
              : e['msg'].toString();
          lines.add('$name: $msg');
        }
        _fail(lines.join('\n'), firstField);
        return;
      }
    } catch (_) {}
    _fail('The server rejected the input. Please check your values.', null);
  }

  Future<void> _predict() async {
    FocusScope.of(context).unfocus();

    // Catch empty fields and non-numbers before calling the API;
    // range checks are left to the API's Pydantic validation
    final Map<String, dynamic> body = {};
    for (final key in fieldNames.keys) {
      final name = fieldNames[key]!;
      final text = _c[key]!.text.trim();

      if (text.isEmpty) {
        _fail(
          textInputs.contains(key)
              ? 'Please select a ${name.toLowerCase()}.'
              : 'Please fill in the ${name.toLowerCase()}.',
          key,
        );
        return;
      }

      if (textInputs.contains(key)) {
        body[key] = text;
      } else if (wholeNumberInputs.contains(key)) {
        final v = int.tryParse(text);
        if (v == null) {
          _fail('$name must be a whole number (you entered "$text").', key);
          return;
        }
        body[key] = v;
      } else {
        final v = double.tryParse(text.replaceAll(',', ''));
        if (v == null) {
          _fail('$name must be a number (you entered "$text").', key);
          return;
        }
        body[key] = v;
      }
    }

    setState(() {
      _loading = true;
      _error = null;
      _errorField = null;
      _price = null;
    });
    _scrollToResult();

    try {
      // Long timeout: a sleeping free Render service can take up to a minute to wake
      final response = await http
          .post(
            Uri.parse(apiUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(
          () => _price = (data['predicted_hen_price_rwf'] as num).toDouble(),
        );
      } else if (response.statusCode == 422) {
        _handleValidationError(response.body);
      } else {
        _fail('Server error (${response.statusCode}). Please try again.', null);
      }
    } on TimeoutException {
      _fail(
        'The server took too long to respond. It may be waking up, please try again.',
        null,
      );
    } catch (_) {
      _fail(
        'Could not reach the server. Check your internet connection and try again.',
        null,
      );
    } finally {
      setState(() => _loading = false);
      _scrollToResult();
    }
  }

  void _clearAll() {
    for (final c in _c.values) {
      c.clear();
    }
    setState(() {
      _province = null;
      _price = null;
      _error = null;
      _errorField = null;
    });
  }

  OutlineInputBorder _border(Color color, double width) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: color, width: width),
  );

  InputDecoration _decoration(String hint, bool hasError, {String? unit}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: kHint, fontSize: 14),
      filled: true,
      fillColor: hasError ? kErrorFill : kFieldFill,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      suffixText: unit,
      suffixStyle: const TextStyle(
        color: kMuted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
      enabledBorder: _border(
        hasError ? kError : kFieldBorder,
        hasError ? 2 : 1,
      ),
      focusedBorder: _border(hasError ? kError : kGreen, 2),
    );
  }

  Widget _label(String text, bool hasError) => Text(
    text,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: hasError ? kError : kLabel,
    ),
  );

  Widget _numberField(String key, String label, String hint, {String? unit}) {
    final hasError = _errorField == key;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label, hasError),
        const SizedBox(height: 6),
        TextField(
          controller: _c[key],
          keyboardType: wholeNumberInputs.contains(key)
              ? TextInputType.number
              : const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
          textInputAction: TextInputAction.next,
          style: const TextStyle(fontSize: 15, color: kText),
          decoration: _decoration(hint, hasError, unit: unit),
        ),
      ],
    );
  }

  // DropdownMenu is a real text field with a list attached:
  // the user can type to filter or pick from the list
  Widget _dropdownField({
    required String key,
    required String label,
    required String hint,
    required List<String> options,
    required ValueChanged<String?> onSelected,
  }) {
    final hasError = _errorField == key;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label, hasError),
        const SizedBox(height: 6),
        DropdownMenu<String>(
          // A new key when the province changes rebuilds the district list
          key: ValueKey('$key-$_province'),
          controller: _c[key],
          expandedInsets: EdgeInsets.zero,
          requestFocusOnTap: true,
          enableFilter: true,
          menuHeight: 300,
          hintText: hint,
          textStyle: const TextStyle(fontSize: 15, color: kText),
          trailingIcon: const Icon(Icons.keyboard_arrow_down, color: kLabel),
          selectedTrailingIcon: const Icon(
            Icons.keyboard_arrow_up,
            color: kLabel,
          ),
          inputDecorationTheme: InputDecorationTheme(
            hintStyle: const TextStyle(color: kHint, fontSize: 14),
            filled: true,
            fillColor: hasError ? kErrorFill : kFieldFill,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            enabledBorder: _border(
              hasError ? kError : kFieldBorder,
              hasError ? 2 : 1,
            ),
            focusedBorder: _border(kGreen, 2),
          ),
          menuStyle: MenuStyle(
            backgroundColor: const WidgetStatePropertyAll(Colors.white),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          dropdownMenuEntries: [
            for (final o in options) DropdownMenuEntry(value: o, label: o),
          ],
          onSelected: onSelected,
        ),
      ],
    );
  }

  Widget _pair(Widget a, Widget b) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: a),
      const SizedBox(width: 12),
      Expanded(child: b),
    ],
  );

  List<Widget> _withGaps(List<Widget> items, double gap) {
    final out = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      if (i > 0) out.add(SizedBox(height: gap));
      out.add(items[i]);
    }
    return out;
  }

  Widget _section({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: kGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: kText,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 2),
              child: Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: kMuted),
              ),
            ),
          const SizedBox(height: 14),
          ..._withGaps(children, 14),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    // Extend the green header behind the phone's status bar
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, top + 22, 20, 24),
      decoration: const BoxDecoration(
        color: kGreen,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0x24FFFFFF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.egg_outlined, color: kGold),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hen Price Predictor',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Rwanda · market price estimate',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: kGold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Know what your hens are worth before you go to market.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Color(0xE0FFFFFF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationSection() {
    final districts = _province != null
        ? districtsByProvince[_province]!
        : (districtCoordinates.keys.toList()..sort());
    return _section(
      icon: Icons.location_on_outlined,
      title: 'Market location',
      subtitle: 'Latitude and longitude fill in from the district',
      children: [
        _dropdownField(
          key: 'province',
          label: 'Province',
          hint: 'Select province',
          options: districtsByProvince.keys.toList(),
          onSelected: (p) => setState(() {
            _province = p;
            _c['district']!.clear();
            _c['latitude']!.clear();
            _c['longitude']!.clear();
          }),
        ),
        _dropdownField(
          key: 'district',
          label: 'District',
          hint: 'Select district',
          options: districts,
          onSelected: (d) {
            final coords = districtCoordinates[d];
            if (coords == null) return;
            setState(() {
              _c['latitude']!.text = coords[0].toString();
              _c['longitude']!.text = coords[1].toString();
            });
          },
        ),
        _pair(
          _numberField('latitude', 'Latitude', '-2.9 to -1.0'),
          _numberField('longitude', 'Longitude', '28.8 to 30.9'),
        ),
      ],
    );
  }

  Widget _timeSection() => _section(
    icon: Icons.calendar_month_outlined,
    title: 'Time of sale',
    children: [
      _pair(
        _numberField('year', 'Year', '2012 – 2030'),
        _numberField('month', 'Month', '1 – 12'),
      ),
    ],
  );

  Widget _pricesSection() => _section(
    icon: Icons.sell_outlined,
    title: 'Local prices',
    subtitle: 'In RWF, same market and month',
    children: [
      _pair(
        _numberField('egg_price', 'Egg (each)', '20 – 1,000', unit: 'RWF'),
        _numberField('maize_price', 'Maize (kg)', '50 – 2,000', unit: 'RWF'),
      ),
      _pair(
        _numberField(
          'soybean_price',
          'Soybeans (kg)',
          '100 – 3,000',
          unit: 'RWF',
        ),
        _numberField(
          'beans_price',
          'Dry beans (kg)',
          '100 – 2,000',
          unit: 'RWF',
        ),
      ),
      _numberField('beef_price', 'Beef (kg)', '500 – 10,000', unit: 'RWF'),
    ],
  );

  Widget _predictButton() {
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: _loading ? null : _predict,
        style: FilledButton.styleFrom(
          backgroundColor: kGreen,
          disabledBackgroundColor: const Color(0x991F4D36),
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _loading
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Predicting...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Predict',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(width: 10),
                  Icon(Icons.arrow_forward, size: 20),
                ],
              ),
      ),
    );
  }

  Widget _stat(String title, String value, CrossAxisAlignment align) => Column(
    crossAxisAlignment: align,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 13, color: Color(0xBFFFFFFF)),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    ],
  );

  // One display area for every outcome: waiting, loading, error or prediction
  Widget _resultArea() {
    if (_loading) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kCardBorder),
        ),
        child: const Text(
          'Contacting the server... the first request can take up to a minute while it wakes up.',
          style: TextStyle(fontSize: 14, color: kMuted, height: 1.4),
        ),
      );
    }

    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: kErrorFill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kErrorBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF8DAD5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.error_outline, color: kError, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Check your input',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: kErrorText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: kErrorText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_price != null) {
      final price = _price!;
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: kGreen,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Estimated live hen price',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: kGold,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _fmt(price),
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'RWF',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xD9FFFFFF),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(height: 1, color: const Color(0x2EFFFFFF)),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _stat(
                    'Likely range',
                    '${_fmt(price - typicalError)} - ${_fmt(price + typicalError)} RWF',
                    CrossAxisAlignment.start,
                  ),
                ),
                _stat(
                  'Typical error',
                  '+or- ${typicalError.round()} RWF',
                  CrossAxisAlignment.end,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Random Forest model · trained on WFP market prices, 2012–2015',
              style: TextStyle(fontSize: 11, color: Color(0xBFFFFFFF)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFCFCAB9), width: 1.5),
      ),
      child: const Text(
        'Your estimated price will appear here',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, color: kMuted),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // White status-bar icons on the green header
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          controller: _scroll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _withGaps([
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton(
                        onPressed: _clearAll,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kGreen,
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFFCFCAB9)),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('Clear all'),
                      ),
                    ),
                    _locationSection(),
                    _timeSection(),
                    _pricesSection(),
                    _predictButton(),
                    _resultArea(),
                  ], 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
