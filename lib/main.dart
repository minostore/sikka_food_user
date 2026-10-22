import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maa_messaging/maa_messaging.dart';

import 'firebase_options.dart';
import 'open_street_map.dart';

const coral = Color(0xFFFF6B4A);
const plum = Color(0xFF4A1E3D);
const cream = Color(0xFFFFF8F1);
const mint = Color(0xFFA7E3C1);
const nearbyKm = 10.0;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MaaSession? session;
  final options = maaFirebaseOptions();
  if (options != null) {
    try {
      await Firebase.initializeApp(options: options);
      session = MaaSession('customer')..start();
      await MaaMessaging.initialize('customer', accent: coral);
    } catch (error) {
      debugPrint('Firebase is not configured yet: $error');
    }
  }
  runApp(MaaCustomerApp(session: session));
}

class MaaCustomerApp extends StatelessWidget {
  const MaaCustomerApp({super.key, required this.session});
  final MaaSession? session;

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: MaaMessaging.navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'معًا',
        locale: const Locale('ar', 'EG'),
        supportedLocales: const [Locale('ar', 'EG'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.white,
          colorScheme: ColorScheme.fromSeed(
              seedColor: coral, primary: coral, secondary: plum, surface: Colors.white),
          textTheme: ThemeData.light().textTheme.apply(fontFamily: 'Tajawal'),
          appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white, foregroundColor: plum, centerTitle: false, elevation: 0),
        ),
        home: session == null
            ? const FirebaseSetupNeeded()
            : MaaAuthGate(
                session: session!,
                accent: coral,
                appTitle: 'معًا — تطبيق العميل',
                builder: (_) => MaaUpdateGate(
                    role: 'customer',
                    accent: coral,
                    enabled: true,
                    child: Directionality(
                        textDirection: TextDirection.rtl,
                        child: CustomerShell(session: session!))),
              ),
      );
}

class FirebaseSetupNeeded extends StatelessWidget {
  const FirebaseSetupNeeded({super.key});
  @override
  Widget build(BuildContext context) => const Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
          body: Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                  child: Text(
                      'لم يُربط التطبيق بمشروع Firebase بعد.\nابنِ التطبيق مع قيم FIREBASE_* و MAA_API_URL كما في ملف README.',
                      textAlign: TextAlign.center,
                      style: TextStyle(height: 1.7, fontSize: 16))))));
}

// ───────────────────────── العناوين المحفوظة ─────────────────────────

List<Map<String, dynamic>> savedAddresses(MaaSession s) =>
    ((s.profile['addresses'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

Map<String, dynamic>? selectedAddress(MaaSession s) {
  final list = savedAddresses(s);
  if (list.isEmpty) return null;
  final id = '${s.profile['selectedAddressId'] ?? ''}';
  return list.firstWhere((a) => '${a['id']}' == id, orElse: () => list.first);
}

({double lat, double lng})? selectedPoint(MaaSession s) {
  final a = selectedAddress(s);
  if (a == null || a['lat'] is! num || a['lng'] is! num) return null;
  return (lat: (a['lat'] as num).toDouble(), lng: (a['lng'] as num).toDouble());
}

Map<String, dynamic> _selectionFields(Map<String, dynamic> a) => {
      'selectedAddressId': a['id'],
      'address': a['address'] ?? '',
      'lat': a['lat'],
      'lng': a['lng'],
      'governorate': a['governorate'] ?? '',
      'area': a['area'] ?? '',
    };

Future<void> saveAddress(MaaSession s, Map<String, dynamic> addr) async {
  final list = savedAddresses(s)..add(addr);
  await s.profileRef.update({'addresses': list, ..._selectionFields(addr)});
}

Future<void> selectAddress(MaaSession s, Map<String, dynamic> addr) =>
    s.profileRef.update(_selectionFields(addr));

Future<void> deleteAddress(MaaSession s, String id) async {
  final list = savedAddresses(s)..removeWhere((a) => '${a['id']}' == id);
  final patch = <String, dynamic>{'addresses': list};
  if ('${s.profile['selectedAddressId']}' == id) {
    patch.addAll(list.isEmpty
        ? {'selectedAddressId': '', 'address': '', 'lat': null, 'lng': null, 'governorate': '', 'area': ''}
        : _selectionFields(list.first));
  }
  await s.profileRef.update(patch);
}

void _snack(BuildContext context, String text) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

Future<void> addCurrentLocation(BuildContext context, MaaSession s) async {
  final here = await maaCurrentPosition();
  if (here == null) {
    _snack(context, 'تعذر تحديد موقعك. فعّل خدمة الموقع وامنح التطبيق الإذن.');
    return;
  }
  final place = await maaReverseGeocode(here.lat, here.lng);
  await saveAddress(s, {
    'id': '${DateTime.now().millisecondsSinceEpoch}',
    'label': 'الموقع الحالي',
    'address': place?.address.isNotEmpty == true ? place!.address : 'موقعي الحالي',
    'lat': here.lat,
    'lng': here.lng,
    'governorate': place?.governorate ?? '',
    'area': place?.area ?? '',
  });
}

/// قائمة «التوصيل إلى»: العناوين المحفوظة + إضافة عنوان من الخريطة أو الموقع الحالي.
Future<void> showAddressesSheet(BuildContext context, MaaSession session) {
  return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            final list = savedAddresses(session);
            final selected = selectedAddress(session);
            return SafeArea(
                child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .85),
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            const Expanded(child: Text('العناوين المحفوظة', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: plum))),
                            IconButton.outlined(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                          ]),
                          const SizedBox(height: 6),
                          if (list.isEmpty)
                            const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Text('لا توجد عناوين بعد. أضف عنوانك لتظهر لك المطاعم القريبة.', style: TextStyle(color: Colors.black54, height: 1.6))),
                          Flexible(
                              child: ListView(shrinkWrap: true, children: [
                            for (final a in list)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.location_on_outlined, color: plum),
                                title: Text('${a['label'] ?? 'عنوان'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                                subtitle: Text('${a['address']}'),
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  if (selected != null && '${selected['id']}' == '${a['id']}') const CircleAvatar(radius: 12, backgroundColor: coral, child: Icon(Icons.check, size: 16, color: Colors.white)),
                                  IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => deleteAddress(session, '${a['id']}')),
                                ]),
                                onTap: () async {
                                  await selectAddress(session, a);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                              ),
                          ])),
                          const SizedBox(height: 10),
                          _SheetAction(
                              icon: Icons.pin_drop_outlined,
                              title: 'التوصيل إلى عنوان آخر',
                              subtitle: 'اختر موقعًا على الخريطة',
                              onTap: () async {
                                Navigator.pop(ctx);
                                await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AddressPickerPage(session: session)));
                              }),
                          const SizedBox(height: 10),
                          _SheetAction(
                              icon: Icons.near_me_outlined,
                              title: 'التوصيل إلى الموقع الحالي',
                              subtitle: 'استخدم موقعك الحالي',
                              onTap: () async {
                                Navigator.pop(ctx);
                                await addCurrentLocation(context, session);
                              }),
                        ]))));
          }));
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Icon(icon, color: plum),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(subtitle, style: const TextStyle(color: Colors.black54)),
            ])),
            const Icon(Icons.chevron_left),
          ])));
}

/// اختيار موقع على الخريطة؛ المحافظة والمنطقة تُحدَّدان تلقائيًا.
class AddressPickerPage extends StatefulWidget {
  const AddressPickerPage({super.key, required this.session});
  final MaaSession session;
  @override
  State<AddressPickerPage> createState() => _AddressPickerPageState();
}

class _AddressPickerPageState extends State<AddressPickerPage> {
  final MapController _map = MapController();
  late ll.LatLng _center;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = selectedPoint(widget.session);
    _center = p == null ? defaultMapCenter : ll.LatLng(p.lat, p.lng);
    if (p == null) _goHere();
  }

  Future<void> _goHere() async {
    final here = await maaCurrentPosition();
    if (here != null && mounted) {
      _center = ll.LatLng(here.lat, here.lng);
      _map.move(_center, 16.5);
    }
  }

  Future<void> _confirm() async {
    final label = TextEditingController();
    final details = TextEditingController();
    String kind = 'منزل';
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setLocal) => AlertDialog(
                  title: const Text('تفاصيل العنوان'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Wrap(spacing: 8, children: [
                      for (final k in ['منزل', 'شقة', 'عمل', 'أخرى'])
                        ChoiceChip(label: Text(k), selected: kind == k, onSelected: (_) => setLocal(() => kind = k)),
                    ]),
                    TextField(controller: details, decoration: const InputDecoration(labelText: 'رقم المبنى / الدور / علامة مميزة')),
                  ])),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ العنوان')),
                  ],
                )));
    label.dispose();
    if (ok != true) return;
    setState(() => _busy = true);
    final place = await maaReverseGeocode(_center.latitude, _center.longitude);
    final base = place?.address ?? '';
    final text = [details.text.trim(), base].where((e) => e.isNotEmpty).join('، ');
    await saveAddress(widget.session, {
      'id': '${DateTime.now().millisecondsSinceEpoch}',
      'label': kind,
      'address': text.isEmpty ? 'موقع على الخريطة' : text,
      'lat': _center.latitude,
      'lng': _center.longitude,
      'governorate': place?.governorate ?? '',
      'area': place?.area ?? '',
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('اختر موقع التوصيل')),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
              initialCenter: _center,
              initialZoom: 16,
              onPositionChanged: (camera, _) => _center = camera.center),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.maa.delivery.maaCustomer', maxZoom: 19),
            const RichAttributionWidget(alignment: AttributionAlignment.bottomRight, attributions: [TextSourceAttribution('© OpenStreetMap contributors')]),
          ],
        ),
        const Center(child: Padding(padding: EdgeInsets.only(bottom: 46), child: Icon(Icons.location_pin, size: 52, color: coral))),
        Positioned(
            right: 16,
            bottom: 100,
            child: FloatingActionButton.small(heroTag: 'here', backgroundColor: Colors.white, foregroundColor: plum, onPressed: _goHere, child: const Icon(Icons.my_location))),
        Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: FilledButton(
                onPressed: _busy ? null : _confirm,
                style: FilledButton.styleFrom(backgroundColor: coral, minimumSize: const Size.fromHeight(54)),
                child: _busy ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : const Text('تأكيد الموقع'))),
      ]));
}

class CartLine {
  CartLine(this.itemId, this.name, this.price, this.qty);
  final String itemId, name;
  final num price;
  int qty;
}

class Cart extends ChangeNotifier {
  String? restaurantUid;
  Map<String, dynamic> restaurant = {};
  final Map<String, CartLine> lines = {};

  int get count => lines.values.fold(0, (n, l) => n + l.qty);
  num get subtotal => lines.values.fold<num>(0, (n, l) => n + l.price * l.qty);

  /// يعيد false إذا كانت السلة تخص مطعمًا آخر.
  bool add(String uid, Map<String, dynamic> rest, String itemId,
      Map<String, dynamic> item) {
    if (restaurantUid != null && restaurantUid != uid && lines.isNotEmpty) {
      return false;
    }
    restaurantUid = uid;
    restaurant = rest;
    final existing = lines[itemId];
    if (existing != null) {
      existing.qty++;
    } else {
      lines[itemId] = CartLine(
          itemId, (item['name'] ?? '').toString(), maaNum(item['price']), 1);
    }
    notifyListeners();
    return true;
  }

  void change(String itemId, int delta) {
    final line = lines[itemId];
    if (line == null) return;
    line.qty += delta;
    if (line.qty <= 0) lines.remove(itemId);
    if (lines.isEmpty) restaurantUid = null;
    notifyListeners();
  }

  void clear() {
    lines.clear();
    restaurantUid = null;
    restaurant = {};
    notifyListeners();
  }
}

// ───────────────────────── الهيكل ─────────────────────────

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key, required this.session});
  final MaaSession session;
  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int tab = 0;
  final cart = Cart();

  @override
  void dispose() {
    cart.dispose();
    super.dispose();
  }

  void openMenu(String uid, Map<String, dynamic> restaurant) => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => MenuPage(
              session: widget.session,
              cart: cart,
              restaurantUid: uid,
              restaurant: restaurant,
              onOpenCart: openCart)));

  void openCart() => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => CartPage(
                session: widget.session,
                cart: cart,
                onPlaced: () {
                  Navigator.popUntil(context, (route) => route.isFirst);
                  setState(() => tab = 1);
                },
              )));

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeView(session: widget.session, cart: cart, onOpenMenu: openMenu, onCart: openCart),
      OrdersView(session: widget.session, cart: cart, onOpenCart: openCart),
      AccountView(session: widget.session, onOpenOrders: () => setState(() => tab = 1)),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: tab, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        backgroundColor: Colors.white,
        indicatorColor: coral.withValues(alpha: .16),
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'طلباتك'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'حسابك'),
        ],
      ),
    );
  }
}

// ───────────────────────── الرئيسية ─────────────────────────

class HomeView extends StatefulWidget {
  const HomeView({super.key, required this.session, required this.cart, required this.onOpenMenu, required this.onCart});
  final MaaSession session;
  final Cart cart;
  final void Function(String uid, Map<String, dynamic> restaurant) onOpenMenu;
  final VoidCallback onCart;
  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  String search = '';
  String cuisine = '';
  bool _prompted = false;
  final PageController _pager = PageController(viewportFraction: .92);

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _openBanner(Map<String, dynamic> b) async {
    final uid = '${b['restaurantUid'] ?? ''}';
    if (uid.isEmpty) return;
    final snap = await widget.session.db.collection('restaurants').doc(uid).get();
    final data = snap.data();
    if (data != null && mounted) widget.onOpenMenu(uid, data);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return ListenableBuilder(
      listenable: Listenable.merge([session, widget.cart]),
      builder: (context, _) {
        if (!_prompted && session.profile.isNotEmpty && savedAddresses(session).isEmpty) {
          _prompted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) showAddressesSheet(context, session);
          });
        }
        final addr = selectedAddress(session);
        final point = selectedPoint(session);
        return Scaffold(
          backgroundColor: Colors.white,
          bottomSheet: widget.cart.count == 0 ? null : _CartBar(cart: widget.cart, onTap: widget.onCart),
          body: ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, widget.cart.count == 0 ? 20 : 90), children: [
            InkWell(
              onTap: () => showAddressesSheet(context, session),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  const Icon(Icons.location_on, color: coral),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('التوصيل إلى ${addr == null ? '' : addr['label'] ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: plum)),
                    Text(addr == null ? 'أضف عنوان التوصيل' : '${addr['address']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  ])),
                  const Icon(Icons.keyboard_arrow_down),
                  const MaaNotificationButton(role: 'customer', accent: coral),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
                onChanged: (v) => setState(() => search = v.trim()),
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'ابحث عن مطعم أو أكلة',
                    filled: true,
                    fillColor: const Color(0xFFF4F1EE),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none))),
            const SizedBox(height: 14),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: session.db.collection('banners').snapshots(),
              builder: (context, snap) {
                final banners = (snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                    .map((d) => d.data())
                    .where((b) => b['active'] != false && '${b['imageB64'] ?? ''}'.isNotEmpty)
                    .toList();
                if (banners.isEmpty) return const SizedBox.shrink();
                return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: SizedBox(
                        height: 150,
                        child: PageView.builder(
                            controller: _pager,
                            itemCount: banners.length,
                            itemBuilder: (context, i) => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: InkWell(
                                    onTap: () => _openBanner(banners[i]),
                                    child: MaaImage(b64: banners[i]['imageB64'] as String?, width: double.infinity, height: 150, radius: 20, color: coral))))));
              },
            ),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: session.db.collection('restaurants').snapshots(),
              builder: (context, snap) {
                if (snap.hasError) return const Padding(padding: EdgeInsets.all(20), child: Text('تعذر تحميل المطاعم. تحقق من الاتصال.'));
                if (!snap.hasData) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));
                if (point == null) {
                  return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(18)),
                      child: Column(children: [
                        const Text('حدّد موقع التوصيل لعرض المطاعم القريبة منك (ضمن 10 كم).', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, height: 1.6)),
                        const SizedBox(height: 10),
                        FilledButton(onPressed: () => showAddressesSheet(context, session), style: FilledButton.styleFrom(backgroundColor: coral), child: const Text('تحديد الموقع')),
                      ]));
                }
                final nearby = snap.data!.docs.where((d) {
                  final m = d.data();
                  if (m['accountStatus'] != statusActive) return false;
                  if (m['lat'] is! num || m['lng'] is! num) return false;
                  return maaDistanceKm(point.lat, point.lng, (m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()) <= nearbyKm;
                }).toList();
                final cuisines = <String>{for (final d in nearby) if ('${d.data()['cuisine'] ?? ''}'.isNotEmpty) '${d.data()['cuisine']}'}.toList();
                final docs = nearby.where((d) {
                  final m = d.data();
                  if (cuisine.isNotEmpty && m['cuisine'] != cuisine) return false;
                  return search.isEmpty || '${m['name']}'.contains(search) || '${m['cuisine'] ?? ''}'.contains(search);
                }).toList();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (cuisines.isNotEmpty)
                    SizedBox(
                        height: 44,
                        child: ListView(scrollDirection: Axis.horizontal, children: [
                          Padding(padding: const EdgeInsets.only(left: 8), child: ChoiceChip(label: const Text('الكل'), selected: cuisine.isEmpty, onSelected: (_) => setState(() => cuisine = ''))),
                          for (final c in cuisines) Padding(padding: const EdgeInsets.only(left: 8), child: ChoiceChip(label: Text(c), selected: cuisine == c, onSelected: (_) => setState(() => cuisine = c))),
                        ])),
                  const Padding(padding: EdgeInsets.only(top: 12, bottom: 10), child: Text('كل المطاعم', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: plum))),
                  if (docs.isEmpty)
                    const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('لا توجد مطاعم ضمن 10 كم من عنوانك الآن.', style: TextStyle(color: Colors.black54))))
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: docs.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: .82, crossAxisSpacing: 12, mainAxisSpacing: 14),
                      itemBuilder: (context, i) {
                        final d = docs[i];
                        final m = d.data();
                        final km = maaDistanceKm(point.lat, point.lng, (m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
                        return RestaurantTile(
                            name: '${m['name']}',
                            rating: '${m['rating'] ?? '—'}',
                            meta: '${m['prepTime'] ?? ''} • ${maaMoney(maaNum(m['deliveryFee']))} • ${km.toStringAsFixed(1)} كم',
                            open: m['accepting'] == 'مفتوح',
                            logo: m['logoB64'] as String?,
                            onTap: () => widget.onOpenMenu(d.id, m));
                      },
                    ),
                ]);
              },
            ),
          ]),
        );
      },
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({required this.cart, required this.onTap});
  final Cart cart;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SafeArea(
      child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(backgroundColor: coral, minimumSize: const Size.fromHeight(56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
              child: Row(children: [
                CircleAvatar(radius: 14, backgroundColor: Colors.white24, child: Text('${cart.count}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                const SizedBox(width: 12),
                const Expanded(child: Text('اطّلع على سلتك', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                Text(maaMoney(cart.subtotal), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              ]))));
}

class RestaurantTile extends StatelessWidget {
  const RestaurantTile({super.key, required this.name, required this.rating, required this.meta, required this.open, required this.onTap, this.logo});
  final String? logo;
  final String name, rating, meta;
  final bool open;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Stack(children: [
          Positioned.fill(child: MaaImage(b64: logo, width: double.infinity, height: double.infinity, radius: 18, color: open ? coral : Colors.grey)),
          if (!open)
            Positioned.fill(
                child: Container(
                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(18)),
                    alignment: Alignment.center,
                    child: const Text('مغلق مؤقتًا', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)))),
        ])),
        const SizedBox(height: 8),
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: plum)),
        Row(children: [
          const Icon(Icons.star, color: Color(0xFFFFB547), size: 16),
          const SizedBox(width: 3),
          Text(rating, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ]),
        Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54, fontSize: 12)),
      ]));
}

// ───────────────────────── صفحة المطعم ─────────────────────────

class _CatBarDelegate extends SliverPersistentHeaderDelegate {
  _CatBarDelegate({required this.child});
  final Widget child;
  @override
  double get minExtent => 58;
  @override
  double get maxExtent => 58;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Material(color: Colors.white, elevation: overlapsContent ? 3 : 0, child: child);
  @override
  bool shouldRebuild(covariant _CatBarDelegate oldDelegate) => true;
}

class MenuPage extends StatefulWidget {
  const MenuPage({super.key, required this.session, required this.cart, required this.restaurantUid, required this.restaurant, required this.onOpenCart});
  final MaaSession session;
  final Cart cart;
  final String restaurantUid;
  final Map<String, dynamic> restaurant;
  final VoidCallback onOpenCart;
  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  final Map<String, GlobalKey> _keys = {};

  Future<void> _add(String id, Map<String, dynamic> item) async {
    final cart = widget.cart;
    final restaurant = widget.restaurant;
    if (restaurant['accepting'] != 'مفتوح') {
      _snack(context, 'المطعم مغلق مؤقتًا ولا يستقبل الطلبات.');
      return;
    }
    if (!cart.add(widget.restaurantUid, restaurant, id, item)) {
      final replace = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: const Text('بدء سلة جديدة؟'),
                content: Text('سلتك الحالية من «${cart.restaurant['name']}». هل تريد تفريغها والطلب من «${restaurant['name']}»؟'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تفريغ وبدء جديد')),
                ],
              ));
      if (replace == true) {
        cart.clear();
        cart.add(widget.restaurantUid, restaurant, id, item);
      }
    }
  }

  void _scrollTo(String cat) {
    final ctx = _keys[cat]?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), alignment: .12);
  }

  void _showCategories(Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> grouped) {
    showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (ctx) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    const Expanded(child: Text('أقسام قائمة الطعام', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
                    IconButton.outlined(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                  ]),
                  Flexible(
                      child: ListView(shrinkWrap: true, children: [
                    for (final e in grouped.entries)
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                          trailing: Text('${e.value.length}', style: const TextStyle(color: Colors.black54)),
                          onTap: () {
                            Navigator.pop(ctx);
                            _scrollTo(e.key);
                          }),
                  ])),
                ]))));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.restaurant;
    final minOrder = maaNum(r['minOrder']);
    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: ListenableBuilder(
          listenable: widget.cart,
          builder: (context, _) => SafeArea(
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: widget.cart.count == 0
                      ? (minOrder > 0
                          ? Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text('أضف منتجات بقيمة ${maaMoney(minOrder)} لتبدأ الطلب', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54, fontSize: 16)))
                          : const SizedBox.shrink())
                      : _CartBar(cart: widget.cart, onTap: widget.onOpenCart)))),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: widget.session.db.collection('menuItems').where('restaurantUid', isEqualTo: widget.restaurantUid).snapshots(),
        builder: (context, snap) {
          final items = (snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]).where((d) => d.data()['available'] != false).toList();
          final grouped = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
          for (final d in items) {
            grouped.putIfAbsent('${d.data()['category'] ?? 'عام'}', () => []).add(d);
          }
          for (final k in grouped.keys) {
            _keys.putIfAbsent(k, () => GlobalKey());
          }
          return CustomScrollView(slivers: [
            SliverAppBar(
              pinned: false,
              expandedHeight: 210,
              backgroundColor: Colors.white,
              leading: Padding(padding: const EdgeInsets.all(6), child: CircleAvatar(backgroundColor: Colors.white, child: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => Navigator.pop(context)))),
              flexibleSpace: FlexibleSpaceBar(
                  background: Stack(fit: StackFit.expand, children: [
                MaaImage(b64: r['logoB64'] as String?, width: double.infinity, height: 210, radius: 0, color: coral),
                Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black26, Colors.transparent]))),
              ])),
            ),
            SliverToBoxAdapter(
                child: Transform.translate(
                    offset: const Offset(0, -34),
                    child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.black12)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            MaaImage(b64: r['logoB64'] as String?, width: 72, height: 72, radius: 16, color: coral),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${r['name']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: plum)),
                              if ('${r['cuisine'] ?? ''}'.isNotEmpty) Text('${r['cuisine']}', style: const TextStyle(color: Colors.black54)),
                              Container(
                                  margin: const EdgeInsets.only(top: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: const Color(0xFFF4F1EE), borderRadius: BorderRadius.circular(8)),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.star, size: 15, color: Color(0xFFFFB547)), const SizedBox(width: 4), Text('${r['rating'] ?? '—'}')])),
                            ])),
                          ]),
                          const Divider(height: 22),
                          Row(children: [
                            const Icon(Icons.schedule, size: 18),
                            const SizedBox(width: 4),
                            Text('${r['prepTime'] ?? ''}'),
                            const SizedBox(width: 14),
                            const Icon(Icons.delivery_dining, size: 18),
                            const SizedBox(width: 4),
                            Text(maaMoney(maaNum(r['deliveryFee']))),
                          ]),
                          if (r['accepting'] != 'مفتوح') const Padding(padding: EdgeInsets.only(top: 8), child: Text('المطعم مغلق مؤقتًا', style: TextStyle(color: Color(0xFFC62828), fontWeight: FontWeight.bold))),
                        ])))),
            if (grouped.isNotEmpty)
              SliverPersistentHeader(
                  pinned: true,
                  delegate: _CatBarDelegate(
                      child: Row(children: [
                    IconButton(onPressed: () => _showCategories(grouped), icon: const Icon(Icons.menu)),
                    Expanded(
                        child: ListView(scrollDirection: Axis.horizontal, children: [
                      for (final k in grouped.keys)
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9), child: ActionChip(label: Text(k), backgroundColor: const Color(0xFFF4F1EE), side: BorderSide.none, onPressed: () => _scrollTo(k))),
                    ])),
                  ]))),
            if (snap.hasError)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(24), child: Text('تعذر تحميل القائمة.')))
            else if (!snap.hasData)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())))
            else if (items.isEmpty)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(30), child: Center(child: Text('لم يضف المطعم أصنافًا بعد.', style: TextStyle(color: Colors.black54)))))
            else
              for (final e in grouped.entries) ...[
                SliverToBoxAdapter(child: Padding(key: _keys[e.key], padding: const EdgeInsets.fromLTRB(16, 20, 16, 10), child: Text(e.key, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: plum)))),
                SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: .72, crossAxisSpacing: 12, mainAxisSpacing: 14),
                        delegate: SliverChildBuilderDelegate((context, i) {
                          final d = e.value[i];
                          final m = d.data();
                          return ListenableBuilder(
                              listenable: widget.cart,
                              builder: (context, _) => ItemTile(
                                  name: '${m['name']}',
                                  description: '${m['description'] ?? ''}',
                                  price: maaMoney(maaNum(m['price'])),
                                  image: m['imageB64'] as String?,
                                  qty: widget.cart.lines[d.id]?.qty ?? 0,
                                  onAdd: () => _add(d.id, m),
                                  onRemove: () => widget.cart.change(d.id, -1)));
                        }, childCount: e.value.length))),
              ],
            const SliverToBoxAdapter(child: SizedBox(height: 30)),
          ]);
        },
      ),
    );
  }
}

class ItemTile extends StatelessWidget {
  const ItemTile({super.key, required this.name, required this.description, required this.price, required this.qty, required this.onAdd, required this.onRemove, this.image});
  final String? image;
  final String name, description, price;
  final int qty;
  final VoidCallback onAdd, onRemove;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onAdd,
      borderRadius: BorderRadius.circular(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Stack(children: [
          Positioned.fill(child: MaaImage(b64: image, width: double.infinity, height: double.infinity, radius: 18, fallback: Icons.set_meal, color: coral)),
          Positioned(
              left: 8,
              bottom: 8,
              child: qty == 0
                  ? CircleAvatar(radius: 20, backgroundColor: Colors.white, child: IconButton(padding: EdgeInsets.zero, onPressed: onAdd, icon: const Icon(Icons.add, color: coral)))
                  : Container(
                      decoration: BoxDecoration(color: coral, borderRadius: BorderRadius.circular(22)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(visualDensity: VisualDensity.compact, onPressed: onRemove, icon: const Icon(Icons.remove, color: Colors.white, size: 18)),
                        Text('$qty', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        IconButton(visualDensity: VisualDensity.compact, onPressed: onAdd, icon: const Icon(Icons.add, color: Colors.white, size: 18)),
                      ]))),
        ])),
        const SizedBox(height: 8),
        Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        Text(price, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: plum)),
      ]));
}

// ───────────────────────── السلة وإتمام الطلب ─────────────────────────

class CartPage extends StatefulWidget {
  const CartPage({super.key, required this.session, required this.cart, required this.onPlaced});
  final MaaSession session;
  final Cart cart;
  final VoidCallback onPlaced;
  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final notes = TextEditingController();
  bool busy = false;
  String error = '';

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Future<void> place() async {
    final cart = widget.cart;
    final s = widget.session;
    if (cart.lines.isEmpty || cart.restaurantUid == null) return;
    final addr = selectedAddress(s);
    final point = selectedPoint(s);
    if (addr == null || point == null) {
      setState(() => error = 'حدّد عنوان التوصيل أولًا.');
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final restSnap = await s.db.collection('restaurants').doc(cart.restaurantUid).get();
      final rest = restSnap.data() ?? {};
      if (rest['accountStatus'] != statusActive || rest['accepting'] != 'مفتوح') {
        throw Exception('المطعم لا يستقبل الطلبات الآن.');
      }
      if (rest['lat'] is num && rest['lng'] is num &&
          maaDistanceKm(point.lat, point.lng, (rest['lat'] as num).toDouble(), (rest['lng'] as num).toDouble()) > nearbyKm) {
        throw Exception('هذا المطعم بعيد عن عنوانك (أكثر من 10 كم).');
      }
      final minOrder = maaNum(rest['minOrder']);
      if (cart.subtotal < minOrder) {
        throw Exception('الحد الأدنى للطلب ${maaMoney(minOrder)}.');
      }
      final fee = maaNum(rest['deliveryFee']);
      final number = await s.nextCounter('orders');
      final serial = number.toString().padLeft(4, '0');
      final id = 'ORD-$serial';
      final now = maaNow();
      final lines = cart.lines.values.toList();
      await s.db.collection('orders').doc(id).set({
        'id': id,
        'order': '#$serial',
        'customerUid': s.uid,
        'customerId': s.publicId,
        'customer': s.name,
        'customerPhone': s.phone,
        'restaurantUid': cart.restaurantUid,
        'restaurantId': rest['id'] ?? '',
        'restaurant': rest['name'] ?? '',
        'governorate': rest['governorate'] ?? '',
        'restaurantArea': rest['area'] ?? '',
        'driverUid': '',
        'driverId': '',
        'driver': '',
        'region': '${addr['address']}',
        'address': '${addr['address']}',
        'status': orderNew,
        'subtotal': cart.subtotal,
        'deliveryFee': fee,
        'total': cart.subtotal + fee,
        'paymentMethod': 'نقدًا عند الاستلام',
        'paymentStatus': 'بانتظار الدفع',
        'date': now,
        'created': now,
        'updated': now,
        'items': lines.map((l) => '${l.name} × ${l.qty}').join('، '),
        'itemsList': lines.map((l) => {'id': l.itemId, 'name': l.name, 'qty': l.qty, 'price': l.price}).toList(),
        'notes': notes.text.trim(),
        'cancelReason': '',
        'coordinates': [point.lat, point.lng],
        'history': '${maaClock()} — تم إنشاء الطلب',
        'createdAt': FieldValue.serverTimestamp(),
      });
      cart.clear();
      if (mounted) {
        _snack(context, 'تم إرسال طلبك إلى ${rest['name']}.');
        widget.onPlaced();
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('السلة')),
      body: ListenableBuilder(
          listenable: Listenable.merge([widget.cart, widget.session]),
          builder: (context, _) {
            final cart = widget.cart;
            if (cart.lines.isEmpty) return const Center(child: Text('سلتك فارغة. اختر مطعمًا وأضف وجبتك.'));
            final fee = maaNum(cart.restaurant['deliveryFee']);
            final addr = selectedAddress(widget.session);
            return ListView(padding: const EdgeInsets.all(18), children: [
              Text('الطلب من ${cart.restaurant['name']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: plum)),
              const SizedBox(height: 8),
              ...cart.lines.values.map((l) => Card(
                  color: const Color(0xFFF8F6F4),
                  elevation: 0,
                  child: ListTile(
                    title: Text(l.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(maaMoney(l.price * l.qty)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(onPressed: () => cart.change(l.itemId, -1), icon: const Icon(Icons.remove_circle_outline)),
                      Text('${l.qty}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(onPressed: () => cart.change(l.itemId, 1), icon: const Icon(Icons.add_circle, color: coral)),
                    ]),
                  ))),
              const SizedBox(height: 10),
              Card(
                  color: const Color(0xFFF8F6F4),
                  elevation: 0,
                  child: ListTile(
                      leading: const Icon(Icons.location_on, color: coral),
                      title: Text(addr == null ? 'حدّد عنوان التوصيل' : '${addr['label']}'),
                      subtitle: addr == null ? null : Text('${addr['address']}'),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => showAddressesSheet(context, widget.session))),
              const SizedBox(height: 10),
              TextField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات للمطعم (اختياري)', prefixIcon: Icon(Icons.edit_note))),
              const SizedBox(height: 14),
              _totalRow('المجموع', maaMoney(cart.subtotal)),
              _totalRow('رسوم التوصيل', maaMoney(fee)),
              const Divider(),
              _totalRow('الإجمالي', maaMoney(cart.subtotal + fee), bold: true),
              const SizedBox(height: 6),
              const Text('الدفع: نقدًا عند الاستلام', style: TextStyle(color: Colors.black54)),
              if (error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error, style: const TextStyle(color: Color(0xFFC62828)))),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: busy ? null : place,
                  style: FilledButton.styleFrom(backgroundColor: coral, minimumSize: const Size.fromHeight(56)),
                  child: busy ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : const Text('تأكيد الطلب')),
            ]);
          }));

  Widget _totalRow(String label, String value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.normal)),
        Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.normal, color: plum)),
      ]));
}

// ───────────────────────── طلباتك ─────────────────────────

Stream<List<Map<String, dynamic>>> customerOrders(MaaSession s) => s.db
    .collection('orders')
    .where('customerUid', isEqualTo: s.uid)
    .snapshots()
    .map((q) => maaSortedOrders(q.docs.map((d) => d.data())));

class OrdersView extends StatelessWidget {
  const OrdersView({super.key, required this.session, required this.cart, required this.onOpenCart});
  final MaaSession session;
  final Cart cart;
  final VoidCallback onOpenCart;

  Future<void> _cancel(BuildContext context, Map<String, dynamic> o) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('إلغاء الطلب؟'),
              content: Text('سيُلغى طلبك من ${o['restaurant']} قبل أن يبدأ المطعم تحضيره.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إلغاء الطلب')),
              ],
            ));
    if (ok != true) return;
    try {
      await session.db.collection('orders').doc('${o['id']}').update({
        'status': orderCancelled,
        'updated': maaNow(),
        'cancelReason': 'ألغاه العميل قبل بدء التحضير',
        'history': maaAppendHistory(o['history'], 'ألغى العميل الطلب'),
      });
    } catch (_) {
      _snack(context, 'تعذر الإلغاء؛ ربما بدأ المطعم التحضير.');
    }
  }

  Future<void> _reorder(BuildContext context, Map<String, dynamic> o) async {
    try {
      final restSnap = await session.db.collection('restaurants').doc('${o['restaurantUid']}').get();
      final rest = restSnap.data();
      if (rest == null || rest['accountStatus'] != statusActive) {
        _snack(context, 'هذا المطعم غير متاح حاليًا.');
        return;
      }
      cart.clear();
      var added = 0;
      for (final l in ((o['itemsList'] as List?) ?? const [])) {
        final m = Map<String, dynamic>.from(l as Map);
        final snap = await session.db.collection('menuItems').doc('${m['id']}').get();
        final d = snap.data();
        if (d == null || d['available'] == false) continue;
        final qty = (m['qty'] as num?)?.toInt() ?? 1;
        for (var i = 0; i < qty; i++) {
          cart.add('${o['restaurantUid']}', rest, snap.id, d);
        }
        added++;
      }
      if (!context.mounted) return;
      if (added == 0) {
        _snack(context, 'أصناف هذا الطلب لم تعد متاحة.');
      } else {
        onOpenCart();
      }
    } catch (_) {
      _snack(context, 'تعذر تكرار الطلب.');
    }
  }

  void _paymentDetails(BuildContext context, Map<String, dynamic> o) {
    showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('تفاصيل الدفع'),
              content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${o['items']}'),
                const Divider(),
                Text('المجموع: ${maaMoney(maaNum(o['subtotal']))}'),
                Text('رسوم التوصيل: ${maaMoney(maaNum(o['deliveryFee']))}'),
                Text('الإجمالي: ${maaMoney(maaNum(o['total']))}', style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text('طريقة الدفع: ${o['paymentMethod']}'),
                Text('حالة الدفع: ${o['paymentStatus']}'),
              ]),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
            ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('طلباتك', style: TextStyle(fontWeight: FontWeight.w900))),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: session.db.collection('restaurants').snapshots(),
          builder: (context, restSnap) {
            final logos = <String, String>{
              for (final d in restSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) d.id: '${d.data()['logoB64'] ?? ''}'
            };
            return StreamBuilder<List<Map<String, dynamic>>>(
                stream: customerOrders(session),
                builder: (context, snap) {
                  if (snap.hasError) return const Center(child: Text('تعذر تحميل الطلبات.'));
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  if (snap.data!.isEmpty) return const Center(child: Text('لم تطلب شيئًا بعد.'));
                  return ListView(padding: const EdgeInsets.all(16), children: [
                    for (final o in snap.data!)
                      _OrderCard(
                          session: session,
                          order: o,
                          logo: logos['${o['restaurantUid']}'],
                          onTrack: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TrackOrderPage(session: session, orderId: '${o['id']}'))),
                          onReorder: () => _reorder(context, o),
                          onCancel: () => _cancel(context, o),
                          onPayment: () => _paymentDetails(context, o)),
                  ]);
                });
          }));
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.session, required this.order, required this.logo, required this.onTrack, required this.onReorder, required this.onCancel, required this.onPayment});
  final MaaSession session;
  final Map<String, dynamic> order;
  final String? logo;
  final VoidCallback onTrack, onReorder, onCancel, onPayment;

  Future<void> _rate(BuildContext context, int stars) async {
    try {
      await session.db.collection('orders').doc('${order['id']}').update({'rating': stars, 'ratingAt': maaNow()});
    } catch (_) {
      _snack(context, 'تعذر حفظ التقييم.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = '${order['status']}';
    final active = activeOrderStatuses.contains(status);
    final done = status == orderDone;
    final label = done ? 'تم الاستلام' : status;
    final rating = (order['rating'] as num?)?.toInt() ?? 0;
    final count = ((order['itemsList'] as List?) ?? const []).fold<int>(0, (n, l) => n + ((l as Map)['qty'] as num? ?? 1).toInt());
    return Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(22)),
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: active ? coral.withValues(alpha: .14) : const Color(0xFFF1EFED), borderRadius: BorderRadius.circular(8)), child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: active ? coral : Colors.black87))),
                const SizedBox(width: 10),
                Expanded(child: Text('${order['date']}', style: const TextStyle(color: Colors.black54, fontSize: 12))),
                PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'complaint') maaFileComplaint(context, session, order);
                    },
                    itemBuilder: (_) => const [PopupMenuItem(value: 'complaint', child: Text('تقديم شكوى'))]),
              ])),
          const Divider(height: 1),
          Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                Row(children: [
                  MaaImage(b64: logo, width: 62, height: 62, radius: 14, color: coral),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${order['restaurant']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: plum)),
                    Text('$count منتجات', style: const TextStyle(color: Colors.black54)),
                  ])),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(maaMoney(maaNum(order['total'])), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    InkWell(onTap: onPayment, child: const Text('تفاصيل الدفع', style: TextStyle(decoration: TextDecoration.underline, fontWeight: FontWeight.bold))),
                  ])),
                  if (active)
                    OutlinedButton(onPressed: onTrack, style: OutlinedButton.styleFrom(shape: const StadiumBorder(), side: const BorderSide(color: Colors.black87), foregroundColor: Colors.black87, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)), child: const Text('تتبع الطلب'))
                  else
                    OutlinedButton(onPressed: onReorder, style: OutlinedButton.styleFrom(shape: const StadiumBorder(), side: const BorderSide(color: Colors.black87), foregroundColor: Colors.black87, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)), child: const Text('اطلب مجددًا')),
                ]),
                if (status == orderNew)
                  Align(alignment: AlignmentDirectional.centerStart, child: TextButton(onPressed: onCancel, child: const Text('إلغاء الطلب', style: TextStyle(color: Color(0xFFC62828))))),
              ])),
          if (done)
            Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: const BoxDecoration(color: Color(0xFFF4F4F4), borderRadius: BorderRadius.vertical(bottom: Radius.circular(22))),
                child: rating > 0
                    ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.star, color: Color(0xFFFFB547)), const SizedBox(width: 6), Text('تقييمك للطلب $rating/5')])
                    : Row(children: [
                        const Text('قيّم', style: TextStyle(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        for (var i = 1; i <= 5; i++) IconButton(visualDensity: VisualDensity.compact, onPressed: () => _rate(context, i), icon: const Icon(Icons.star_border)),
                      ])),
        ]));
  }
}

class TrackOrderPage extends StatelessWidget {
  const TrackOrderPage({super.key, required this.session, required this.orderId});
  final MaaSession session;
  final String orderId;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('تتبع الطلب')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: session.db.collection('orders').doc(orderId).snapshots(),
          builder: (context, snap) {
            final o = snap.data?.data();
            if (o == null) return const Center(child: CircularProgressIndicator());
            return ListView(padding: const EdgeInsets.all(20), children: [_TrackedOrder(session: session, order: o)]);
          }));
}

// ───────────────────────── حسابك ─────────────────────────

class AccountView extends StatelessWidget {
  const AccountView({super.key, required this.session, required this.onOpenOrders});
  final MaaSession session;
  final VoidCallback onOpenOrders;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final name = session.name.isEmpty ? 'حسابك' : session.name;
        return Scaffold(
            backgroundColor: Colors.white,
            body: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
              Row(children: [
                IconButton.outlined(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SettingsPage(session: session))), icon: const Icon(Icons.settings_outlined)),
                const Spacer(),
              ]),
              Row(children: [
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: plum)),
                  const SizedBox(height: 4),
                  Row(children: [const Text('🇪🇬 '), const Text('مصر', style: TextStyle(color: Colors.black54))]),
                  Text(session.publicId, style: const TextStyle(color: Colors.black45, fontSize: 12)),
                ])),
                CircleAvatar(radius: 34, backgroundColor: const Color(0xFFFFE5DC), child: Text(name.characters.first.toUpperCase(), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: plum))),
              ]),
              const SizedBox(height: 20),
              const Divider(),
              _AccountRow(icon: Icons.receipt_long_outlined, label: 'طلباتي السابقة', onTap: onOpenOrders),
              _AccountRow(icon: Icons.help_outline, label: 'احصل على المساعدة', onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => MaaSupportPage(session: session, accent: coral)))),
              _AccountRow(
                  icon: Icons.info_outline,
                  label: 'حول التطبيق',
                  onTap: () => showAboutDialog(context: context, applicationName: 'معًا', applicationVersion: '1.0', children: const [Text('تطبيق توصيل الطعام من المطاعم القريبة منك.')])),
              _AccountRow(icon: Icons.storefront_outlined, label: 'انضم كشريك', onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => PartnerPage(session: session)))),
            ]));
      });
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(children: [
            Icon(icon, color: plum),
            const SizedBox(width: 16),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
            const Icon(Icons.chevron_left, color: Colors.black38),
          ])));
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.session});
  final MaaSession session;

  Future<void> _editInfo(BuildContext context) async {
    final name = TextEditingController(text: session.name);
    final phone = TextEditingController(text: session.phone);
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('معلومات الحساب'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Align(alignment: AlignmentDirectional.centerStart, child: Text(session.user?.email ?? '', style: const TextStyle(color: Colors.black54))),
                TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
                TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'الهاتف')),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
              ],
            ));
    if (ok == true) {
      try {
        await session.profileRef.update({'name': name.text.trim(), 'phone': phone.text.trim()});
      } catch (_) {
        _snack(context, 'تعذر الحفظ.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('الإعدادات', style: TextStyle(fontWeight: FontWeight.w900))),
      body: ListView(padding: const EdgeInsets.symmetric(horizontal: 20), children: [
        _SettingRow(label: 'معلومات الحساب', onTap: () => _editInfo(context)),
        _SettingRow(label: 'عناوين التوصيل', onTap: () => showAddressesSheet(context, session)),
        _SettingRow(label: 'الإشعارات', value: 'مفعّلة', trailing: const MaaNotificationButton(role: 'customer', accent: coral)),
        const _SettingRow(label: 'اللغة', value: 'العربية'),
        const _SettingRow(label: 'الدولة', value: 'مصر'),
        _SettingRow(label: 'تسجيل الخروج', onTap: () async {
          Navigator.popUntil(context, (r) => r.isFirst);
          await session.signOut();
        }),
      ]));
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, this.value, this.onTap, this.trailing});
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Column(children: [
        InkWell(
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(children: [
                  Expanded(child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
                  if (value != null) Text(value!, style: const TextStyle(color: Colors.black54, decoration: TextDecoration.underline)),
                  trailing ?? const Icon(Icons.chevron_left, color: Colors.black38),
                ]))),
        const Divider(height: 1),
      ]);
}

class PartnerPage extends StatefulWidget {
  const PartnerPage({super.key, required this.session});
  final MaaSession session;
  @override
  State<PartnerPage> createState() => _PartnerPageState();
}

class _PartnerPageState extends State<PartnerPage> {
  final owner = TextEditingController();
  final restaurant = TextEditingController();
  final address = TextEditingController();
  bool busy = false;
  String error = '';

  Future<void> _send() async {
    if (owner.text.trim().isEmpty || restaurant.text.trim().isEmpty || address.text.trim().isEmpty) {
      setState(() => error = 'أكمل جميع الحقول.');
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    final s = widget.session;
    try {
      await s.db.collection('partnerRequests').add({
        'requesterUid': s.uid,
        'requesterId': s.publicId,
        'requesterName': s.name,
        'requesterPhone': s.phone,
        'ownerName': owner.text.trim(),
        'restaurantName': restaurant.text.trim(),
        'address': address.text.trim(),
        'status': 'جديد',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        _snack(context, 'تم إرسال طلبك. سنتواصل معك قريبًا.');
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) setState(() => error = 'تعذر إرسال الطلب. حاول لاحقًا.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('انضم كشريك')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('اترك بيانات مطعمك وسيتواصل معك فريق معًا لإنشاء حسابك.', style: TextStyle(height: 1.6, color: Colors.black54)),
        const SizedBox(height: 14),
        TextField(controller: owner, decoration: const InputDecoration(labelText: 'اسم المسؤول', prefixIcon: Icon(Icons.badge_outlined))),
        const SizedBox(height: 10),
        TextField(controller: restaurant, decoration: const InputDecoration(labelText: 'اسم المطعم', prefixIcon: Icon(Icons.storefront_outlined))),
        const SizedBox(height: 10),
        TextField(controller: address, decoration: const InputDecoration(labelText: 'عنوان المطعم', prefixIcon: Icon(Icons.location_on_outlined))),
        if (error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error, style: const TextStyle(color: Color(0xFFC62828)))),
        const SizedBox(height: 18),
        FilledButton(onPressed: busy ? null : _send, style: FilledButton.styleFrom(backgroundColor: coral, minimumSize: const Size.fromHeight(54)), child: busy ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : const Text('إرسال الطلب')),
      ]));
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: plum));
}

class _TrackedOrder extends StatelessWidget {
  const _TrackedOrder({required this.session, required this.order});
  final MaaSession session;
  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final status = '${order['status']}';
    final stepIndex = maaOrderSteps.indexOf(status);
    final driverUid = '${order['driverUid'] ?? ''}';
    final coords = order['coordinates'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: driverUid.isEmpty
              ? const Stream.empty()
              : session.db.collection('drivers').doc(driverUid).snapshots(),
          builder: (context, driverSnap) {
            final d = driverSnap.data?.data();
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: session.db
                  .collection('restaurants')
                  .doc('${order['restaurantUid']}')
                  .snapshots(),
              builder: (context, restSnap) {
                final r = restSnap.data?.data();
                final pins = <MapPin>[
                  if (coords is List && coords.length == 2)
                    MapPin(maaNum(coords[0]).toDouble(),
                        maaNum(coords[1]).toDouble(), Icons.home, coral),
                  if (r != null && r['lat'] is num)
                    MapPin((r['lat'] as num).toDouble(),
                        (r['lng'] as num).toDouble(), Icons.restaurant, plum),
                  if (d != null && d['lat'] is num)
                    MapPin(
                        (d['lat'] as num).toDouble(),
                        (d['lng'] as num).toDouble(),
                        Icons.delivery_dining,
                        const Color(0xFF35A879)),
                ];
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OpenStreetMapPreview(height: 220, pins: pins),
                      if (pins.isEmpty)
                        const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text('ستظهر المواقع على الخريطة عند توفرها.',
                                style: TextStyle(
                                    color: Colors.black54, fontSize: 12))),
                      if (d != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Row(children: [
                              const Icon(Icons.delivery_dining,
                                  color: Color(0xFF35A879)),
                              const SizedBox(width: 8),
                              Text('السائق: ${d['name']}  •  ${d['phone'] ?? ''}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ])),
                    ]);
              },
            );
          },
        ),
        const SizedBox(height: 14),
        Text('${order['restaurant']}  •  ${order['order']}',
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w900, color: plum)),
        Text(status,
            style: const TextStyle(color: coral, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (var i = 0; i < maaOrderSteps.length; i++)
          StepLine(label: maaOrderSteps[i], done: i <= stepIndex),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (driverUid.isNotEmpty)
            FilledButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => MaaOrderChatPage(session: session, orderId: '${order['id']}', title: 'محادثة مع السائق', accent: coral))),
                style: FilledButton.styleFrom(backgroundColor: coral),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('دردشة مع السائق')),
          OutlinedButton.icon(onPressed: () => maaFileComplaint(context, session, order), icon: const Icon(Icons.report_gmailerrorred), label: const Text('تقديم شكوى')),
        ]),
      ]),
    );
  }
}

class StepLine extends StatelessWidget {
  const StepLine({super.key, required this.label, required this.done});
  final String label;
  final bool done;
  @override
  Widget build(BuildContext context) => ListTile(
      dense: true,
      leading: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
          color: done ? const Color(0xFF35A879) : Colors.black26),
      title: Text(label));
}

