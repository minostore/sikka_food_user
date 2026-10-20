import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:maa_messaging/maa_messaging.dart';

import 'firebase_options.dart';
import 'open_street_map.dart';

const coral = Color(0xFFFF6B4A);
const plum = Color(0xFF4A1E3D);
const cream = Color(0xFFFFF8F1);
const mint = Color(0xFFA7E3C1);

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
        title: 'طعامك أقرب لك',
        locale: const Locale('ar', 'EG'),
        supportedLocales: const [Locale('ar', 'EG'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: cream,
          colorScheme: ColorScheme.fromSeed(
              seedColor: coral,
              primary: coral,
              secondary: plum,
              surface: cream),
          textTheme: ThemeData.light().textTheme.apply(fontFamily: 'Tajawal'),
          appBarTheme: const AppBarTheme(
              backgroundColor: cream,
              foregroundColor: plum,
              centerTitle: false),
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

// ───────────────────────── السلة ─────────────────────────

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
      HomeView(
          session: widget.session,
          cart: cart,
          onOpenMenu: openMenu,
          onCart: openCart),
      TrackingView(session: widget.session),
      OrdersView(session: widget.session),
      AccountView(session: widget.session),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: tab, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        indicatorColor: coral.withValues(alpha: .16),
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'الرئيسية'),
          NavigationDestination(
              icon: Icon(Icons.route_outlined),
              selectedIcon: Icon(Icons.route),
              label: 'التتبع'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'طلباتي'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'حسابي'),
        ],
      ),
    );
  }
}

// ───────────────────────── الرئيسية ─────────────────────────

class HomeView extends StatefulWidget {
  const HomeView(
      {super.key,
      required this.session,
      required this.cart,
      required this.onOpenMenu,
      required this.onCart});
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
  bool showAll = false;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return ListenableBuilder(
      listenable: Listenable.merge([session, widget.cart]),
      builder: (context, _) => CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: cream,
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('التوصيل إلى',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            Text(
                session.address.isEmpty
                    ? 'أضف عنوانك من «حسابي»'
                    : session.address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, color: plum)),
          ]),
          actions: [
            const MaaNotificationButton(role: 'customer', accent: coral),
            IconButton(
                onPressed: widget.onCart,
                icon: Badge(
                    label: Text('${widget.cart.count}'),
                    isLabelVisible: widget.cart.count > 0,
                    child: const Icon(Icons.shopping_bag_outlined)))
          ],
        ),
        SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
            sliver: SliverList(
                delegate: SliverChildListDelegate([
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [coral, Color(0xFFFF8C68)]),
                    borderRadius: BorderRadius.circular(24)),
                child:
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('طعامك أقرب لك',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 5),
                  Text(
                      session.name.isEmpty
                          ? 'مذاق أفضل .. كل يوم'
                          : 'أهلًا ${session.name}',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 14),
                  Text('رقمك التعريفي: ${session.publicId}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                ]),
              ),
              const SizedBox(height: 18),
              TextField(
                  onChanged: (v) => setState(() => search = v.trim()),
                  decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'ابحث عن مطعم',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none))),
              const SizedBox(height: 20),
              const SectionTitle('المطاعم'),
              const SizedBox(height: 8),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: session.db.collection('restaurants').snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('تعذر تحميل المطاعم. تحقق من الاتصال.'));
                  }
                  if (!snap.hasData) {
                    return const Padding(
                        padding: EdgeInsets.all(30),
                        child: Center(child: CircularProgressIndicator()));
                  }
                  final gov = '${session.profile['governorate'] ?? ''}';
                  final active = snap.data!.docs.where((d) => d.data()['accountStatus'] == statusActive).toList();
                  final cuisines = <String>{for (final d in active) if ('${d.data()['cuisine'] ?? ''}'.isNotEmpty) '${d.data()['cuisine']}'}.toList();
                  final docs = active.where((d) {
                    final m = d.data();
                    final g = '${m['governorate'] ?? ''}';
                    if (gov.isNotEmpty && !showAll && g.isNotEmpty && g != gov) return false;
                    if (cuisine.isNotEmpty && m['cuisine'] != cuisine) return false;
                    return search.isEmpty || '${m['name']}'.contains(search);
                  }).toList();
                  if (docs.isEmpty) {
                    return const Padding(
                        padding: EdgeInsets.all(30),
                        child: Center(
                            child: Text('لا توجد مطاعم متاحة الآن.',
                                style: TextStyle(color: Colors.black54))));
                  }
                  return Column(children: [
                    if (cuisines.isNotEmpty)
                      SizedBox(
                          height: 46,
                          child: ListView(scrollDirection: Axis.horizontal, children: [
                            Padding(padding: const EdgeInsets.only(left: 8), child: ChoiceChip(label: const Text('الكل'), selected: cuisine.isEmpty, onSelected: (_) => setState(() => cuisine = ''))),
                            for (final c in cuisines)
                              Padding(padding: const EdgeInsets.only(left: 8), child: ChoiceChip(label: Text(c), selected: cuisine == c, onSelected: (_) => setState(() => cuisine = c))),
                          ])),
                    if (gov.isNotEmpty)
                      Align(alignment: AlignmentDirectional.centerStart, child: TextButton(onPressed: () => setState(() => showAll = !showAll), child: Text(showAll ? 'عرض مطاعم $gov فقط' : 'عرض مطاعم كل المحافظات'))),
                    ...docs.map((d) {
                    final m = d.data();
                    final open = m['accepting'] == 'مفتوح';
                    return RestaurantCard(
                        name: '${m['name']}',
                        subtitle: [
                          if ('${m['cuisine'] ?? ''}'.isNotEmpty)
                            '${m['cuisine']}',
                          if ('${m['description'] ?? ''}'.isNotEmpty)
                            '${m['description']}',
                        ].join(' • '),
                        rating: '${m['rating'] ?? '—'}',
                        time: open
                            ? '${m['prepTime'] ?? ''} • رسوم التوصيل ${maaMoney(maaNum(m['deliveryFee']))}'
                            : 'مغلق مؤقتًا',
                        open: open,
                        logo: m['logoB64'] as String?,
                        onTap: () => widget.onOpenMenu(d.id, m));
                  })]);
                },
              ),
            ]))),
      ]),
    );
  }
}

class RestaurantCard extends StatelessWidget {
  const RestaurantCard(
      {super.key,
      required this.name,
      required this.subtitle,
      required this.rating,
      required this.time,
      required this.open,
      required this.onTap,
      this.logo});
  final String? logo;
  final String name, subtitle, rating, time;
  final bool open;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.all(10),
          leading: Opacity(
              opacity: open ? 1 : .5,
              child: MaaImage(
                  b64: logo,
                  width: 60,
                  height: 60,
                  radius: 15,
                  color: open ? coral : Colors.grey)),
          title: Text(name,
              style: const TextStyle(fontWeight: FontWeight.w800, color: plum)),
          subtitle: Text(subtitle.isEmpty ? time : '$subtitle\n$time'),
          isThreeLine: subtitle.isNotEmpty,
          trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.star, color: Color(0xFFFFB547), size: 17),
                Text(rating)
              ])));
}

// ───────────────────────── القائمة ─────────────────────────

class MenuPage extends StatelessWidget {
  const MenuPage(
      {super.key,
      required this.session,
      required this.cart,
      required this.restaurantUid,
      required this.restaurant,
      required this.onOpenCart});
  final MaaSession session;
  final Cart cart;
  final String restaurantUid;
  final Map<String, dynamic> restaurant;
  final VoidCallback onOpenCart;

  Future<void> _add(
      BuildContext context, String id, Map<String, dynamic> item) async {
    if (restaurant['accepting'] != 'مفتوح') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('المطعم مغلق مؤقتًا ولا يستقبل الطلبات.')));
      return;
    }
    if (!cart.add(restaurantUid, restaurant, id, item)) {
      final replace = await showDialog<bool>(
          context: context,
          builder: (ctx) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text('بدء سلة جديدة؟'),
                content: Text(
                    'سلتك الحالية من «${cart.restaurant['name']}». هل تريد تفريغها والطلب من «${restaurant['name']}»؟'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('إلغاء')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('تفريغ وبدء جديد')),
                ],
              )));
      if (replace == true) {
        cart.clear();
        cart.add(restaurantUid, restaurant, id, item);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('${restaurant['name']}')),
      bottomNavigationBar: ListenableBuilder(
          listenable: cart,
          builder: (context, _) => cart.count == 0
              ? const SizedBox.shrink()
              : SafeArea(
                  child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: FilledButton(
                          onPressed: onOpenCart,
                          style: FilledButton.styleFrom(
                              backgroundColor: coral,
                              minimumSize: const Size.fromHeight(54)),
                          child: Text(
                              'عرض السلة (${cart.count}) • ${maaMoney(cart.subtotal)}'))))),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Row(children: [
          MaaImage(b64: restaurant['logoB64'] as String?, width: 76, height: 76, radius: 18, color: coral),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${restaurant['cuisine'] ?? ''}', style: const TextStyle(color: Colors.black54)),
            Text('${restaurant['governorate'] ?? ''} ${restaurant['area'] ?? ''}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
          ])),
        ]),
        const SizedBox(height: 14),
        Text('${restaurant['name']}',
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w900, color: plum)),
        Text(
            '${restaurant['rating'] ?? '—'} ★  •  ${restaurant['prepTime'] ?? ''}  •  رسوم التوصيل ${maaMoney(maaNum(restaurant['deliveryFee']))}'),
        const SizedBox(height: 16),
        const SectionTitle('القائمة'),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: session.db
              .collection('menuItems')
              .where('restaurantUid', isEqualTo: restaurantUid)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('تعذر تحميل القائمة.'));
            }
            if (!snap.hasData) {
              return const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: CircularProgressIndicator()));
            }
            final items =
                snap.data!.docs.where((d) => d.data()['available'] != false).toList();
            if (items.isEmpty) {
              return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: Text('لم يضف المطعم أصنافًا بعد.',
                          style: TextStyle(color: Colors.black54))));
            }
            return _MenuSections(items: items, onAdd: (d) => _add(context, d.id, d.data()));
          },
        ),
      ]));
}

class _MenuSections extends StatefulWidget {
  const _MenuSections({required this.items, required this.onAdd});
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> items;
  final void Function(QueryDocumentSnapshot<Map<String, dynamic>>) onAdd;
  @override
  State<_MenuSections> createState() => _MenuSectionsState();
}

class _MenuSectionsState extends State<_MenuSections> {
  String selected = '';
  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final d in widget.items) {
      grouped.putIfAbsent('${d.data()['category'] ?? 'عام'}', () => []).add(d);
    }
    final names = grouped.keys.toList();
    final shown = selected.isEmpty ? names : [selected];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
          height: 46,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            Padding(padding: const EdgeInsets.only(left: 8), child: ChoiceChip(label: const Text('الكل'), selected: selected.isEmpty, onSelected: (_) => setState(() => selected = ''))),
            for (final n in names) Padding(padding: const EdgeInsets.only(left: 8), child: ChoiceChip(label: Text(n), selected: selected == n, onSelected: (_) => setState(() => selected = n))),
          ])),
      for (final n in shown) ...[
        Padding(padding: const EdgeInsets.only(top: 14, bottom: 2), child: Text(n, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: plum))),
        for (final d in grouped[n]!)
          MenuItem(
              title: '${d.data()['name']}',
              subtitle: '${d.data()['description'] ?? ''}',
              price: maaMoney(maaNum(d.data()['price'])),
              image: d.data()['imageB64'] as String?,
              onAdd: () => widget.onAdd(d)),
      ],
    ]);
  }
}

class MenuItem extends StatelessWidget {
  const MenuItem(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.price,
      required this.onAdd,
      this.image});
  final String? image;
  final String title, subtitle, price;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(top: 10),
      child: ListTile(
          leading: MaaImage(b64: image, width: 62, height: 62, radius: 12, fallback: Icons.set_meal, color: coral),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(subtitle.isEmpty ? price : '$subtitle\n$price'),
          isThreeLine: subtitle.isNotEmpty,
          trailing: IconButton(
              onPressed: onAdd,
              icon: const Icon(Icons.add_circle, color: coral))));
}

// ───────────────────────── السلة وإتمام الطلب ─────────────────────────

class CartPage extends StatefulWidget {
  const CartPage(
      {super.key,
      required this.session,
      required this.cart,
      required this.onPlaced});
  final MaaSession session;
  final Cart cart;
  final VoidCallback onPlaced;
  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  late final TextEditingController address =
      TextEditingController(text: widget.session.address);
  final notes = TextEditingController();
  bool busy = false;
  String error = '';

  @override
  void dispose() {
    address.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> place() async {
    final cart = widget.cart;
    final s = widget.session;
    if (cart.lines.isEmpty || cart.restaurantUid == null) return;
    if (address.text.trim().isEmpty) {
      setState(() => error = 'أدخل عنوان التوصيل.');
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final restSnap =
          await s.db.collection('restaurants').doc(cart.restaurantUid).get();
      final rest = restSnap.data() ?? {};
      if (rest['accountStatus'] != statusActive ||
          rest['accepting'] != 'مفتوح') {
        throw Exception('المطعم لا يستقبل الطلبات الآن.');
      }
      final minOrder = maaNum(rest['minOrder']);
      if (cart.subtotal < minOrder) {
        throw Exception('الحد الأدنى للطلب ${maaMoney(minOrder)}.');
      }
      final fee = maaNum(rest['deliveryFee']);
      num? lat = s.profile['lat'] is num ? s.profile['lat'] as num : null;
      num? lng = s.profile['lng'] is num ? s.profile['lng'] as num : null;
      if (lat == null || lng == null) {
        final here = await maaCurrentPosition();
        if (here != null) {
          lat = here.lat;
          lng = here.lng;
        }
      }
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
        'region': address.text.trim(),
        'address': address.text.trim(),
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
        'itemsList': lines
            .map((l) => {
                  'id': l.itemId,
                  'name': l.name,
                  'qty': l.qty,
                  'price': l.price
                })
            .toList(),
        'notes': notes.text.trim(),
        'cancelReason': '',
        'coordinates': (lat != null && lng != null) ? [lat, lng] : null,
        'history': '${maaClock()} — تم إنشاء الطلب',
        'createdAt': FieldValue.serverTimestamp(),
      });
      cart.clear();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('تم إرسال طلبك $id للمطعم.')));
        widget.onPlaced();
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('السلة')),
      body: ListenableBuilder(
          listenable: widget.cart,
          builder: (context, _) {
            final cart = widget.cart;
            if (cart.lines.isEmpty) {
              return const Center(
                  child: Text('سلتك فارغة. اختر مطعمًا وأضف وجبتك.'));
            }
            final fee = maaNum(cart.restaurant['deliveryFee']);
            return ListView(padding: const EdgeInsets.all(18), children: [
              Text('الطلب من ${cart.restaurant['name']}',
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w900, color: plum)),
              const SizedBox(height: 8),
              ...cart.lines.values.map((l) => Card(
                  color: Colors.white,
                  elevation: 0,
                  child: ListTile(
                    title: Text(l.name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(maaMoney(l.price * l.qty)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          onPressed: () => cart.change(l.itemId, -1),
                          icon: const Icon(Icons.remove_circle_outline)),
                      Text('${l.qty}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                          onPressed: () => cart.change(l.itemId, 1),
                          icon: const Icon(Icons.add_circle, color: coral)),
                    ]),
                  ))),
              const SizedBox(height: 10),
              TextField(
                  controller: address,
                  decoration: const InputDecoration(
                      labelText: 'عنوان التوصيل',
                      prefixIcon: Icon(Icons.location_on_outlined))),
              const SizedBox(height: 10),
              TextField(
                  controller: notes,
                  decoration: const InputDecoration(
                      labelText: 'ملاحظات للمطعم (اختياري)',
                      prefixIcon: Icon(Icons.edit_note))),
              const SizedBox(height: 14),
              _totalRow('المجموع', maaMoney(cart.subtotal)),
              _totalRow('رسوم التوصيل', maaMoney(fee)),
              const Divider(),
              _totalRow('الإجمالي', maaMoney(cart.subtotal + fee), bold: true),
              const SizedBox(height: 6),
              const Text('الدفع: نقدًا عند الاستلام',
                  style: TextStyle(color: Colors.black54)),
              if (error.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(error,
                        style: const TextStyle(color: Color(0xFFC62828)))),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: busy ? null : place,
                  style: FilledButton.styleFrom(
                      backgroundColor: coral,
                      minimumSize: const Size.fromHeight(54)),
                  child: busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: Colors.white))
                      : const Text('تأكيد الطلب')),
            ]);
          }));

  Widget _totalRow(String label, String value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style: TextStyle(
                fontWeight: bold ? FontWeight.w900 : FontWeight.normal)),
        Text(value,
            style: TextStyle(
                fontWeight: bold ? FontWeight.w900 : FontWeight.normal,
                color: plum)),
      ]));
}

// ───────────────────────── التتبع ─────────────────────────

Stream<List<Map<String, dynamic>>> customerOrders(MaaSession s) => s.db
    .collection('orders')
    .where('customerUid', isEqualTo: s.uid)
    .snapshots()
    .map((q) => maaSortedOrders(q.docs.map((d) => d.data())));

class TrackingView extends StatelessWidget {
  const TrackingView({super.key, required this.session});
  final MaaSession session;

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('تتبع الطلب')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: customerOrders(session),
          builder: (context, snap) {
            if (snap.hasError) {
              return const Center(child: Text('تعذر تحميل الطلبات.'));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final active = snap.data!
                .where((o) => activeOrderStatuses.contains(o['status']))
                .toList();
            if (active.isEmpty) {
              return const Center(
                  child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Text(
                          'لا يوجد طلب نشط حاليًا.\nاطلب وجبتك من الرئيسية لتتابعها هنا.',
                          textAlign: TextAlign.center,
                          style: TextStyle(height: 1.7))));
            }
            return ListView(
                padding: const EdgeInsets.all(20),
                children: active
                    .map((o) => _TrackedOrder(session: session, order: o))
                    .toList());
          }));
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

// ───────────────────────── طلباتي ─────────────────────────

class OrdersView extends StatelessWidget {
  const OrdersView({super.key, required this.session});
  final MaaSession session;

  Future<void> _cancel(BuildContext context, Map<String, dynamic> o) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('إلغاء الطلب؟'),
              content:
                  Text('سيُلغى الطلب ${o['order']} قبل أن يبدأ المطعم تحضيره.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('رجوع')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('إلغاء الطلب')),
              ],
            )));
    if (ok != true) return;
    try {
      await session.db.collection('orders').doc('${o['id']}').update({
        'status': orderCancelled,
        'updated': maaNow(),
        'cancelReason': 'ألغاه العميل قبل بدء التحضير',
        'history': maaAppendHistory(o['history'], 'ألغى العميل الطلب'),
      });
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تعذر الإلغاء؛ ربما بدأ المطعم التحضير.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('طلباتي')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: customerOrders(session),
          builder: (context, snap) {
            if (snap.hasError) {
              return const Center(child: Text('تعذر تحميل الطلبات.'));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.data!.isEmpty) {
              return const Center(child: Text('لم تطلب شيئًا بعد.'));
            }
            return ListView(
                padding: const EdgeInsets.all(18),
                children: snap.data!
                    .map((o) => Card(
                        color: Colors.white,
                        elevation: 0,
                        child: ListTile(
                            leading: const CircleAvatar(
                                backgroundColor: cream,
                                child: Icon(Icons.receipt_long, color: coral)),
                            title: Text('${o['restaurant']}  •  ${o['order']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text('${o['status']}\n${o['items']}'),
                            isThreeLine: true,
                            trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(maaMoney(maaNum(o['total'])),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: plum)),
                                  InkWell(onTap: () => maaFileComplaint(context, session, o), child: const Padding(padding: EdgeInsets.only(top: 4), child: Text('شكوى', style: TextStyle(color: Colors.black54, fontSize: 12)))),
                                  if (o['status'] == orderNew)
                                    InkWell(
                                        onTap: () => _cancel(context, o),
                                        child: const Padding(
                                            padding: EdgeInsets.only(top: 4),
                                            child: Text('إلغاء',
                                                style: TextStyle(
                                                    color: Color(0xFFC62828),
                                                    fontSize: 12)))),
                                ]))))
                    .toList());
          }));
}

// ───────────────────────── حسابي ─────────────────────────

class AccountView extends StatelessWidget {
  const AccountView({super.key, required this.session});
  final MaaSession session;

  Future<void> _edit(BuildContext context) async {
    final name = TextEditingController(text: session.name);
    final phone = TextEditingController(text: session.phone);
    final address = TextEditingController(text: session.address);
    final area = TextEditingController(text: '${session.profile['area'] ?? ''}');
    String governorate = '${session.profile['governorate'] ?? ''}';
    double? lat, lng;
    await showDialog<void>(
        context: context,
        builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: StatefulBuilder(
              builder: (ctx, setLocal) => AlertDialog(
                title: const Text('بياناتي وعنواني'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'الاسم')),
                  TextField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'الهاتف')),
                  DropdownButtonFormField<String>(
                      initialValue: governorate.isEmpty ? null : governorate,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'المحافظة'),
                      items: [for (final g in maaGovernorates) DropdownMenuItem(value: g, child: Text(g))],
                      onChanged: (v) => setLocal(() => governorate = v ?? '')),
                  TextField(controller: area, decoration: const InputDecoration(labelText: 'المنطقة')),
                  TextField(
                      controller: address,
                      decoration:
                          const InputDecoration(labelText: 'عنوان التوصيل')),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                      onPressed: () async {
                        final here = await maaCurrentPosition();
                        if (here != null) {
                          setLocal(() {
                            lat = here.lat;
                            lng = here.lng;
                          });
                        }
                      },
                      icon: const Icon(Icons.my_location),
                      label: Text(lat == null
                          ? 'استخدام موقعي الحالي'
                          : 'تم تحديد الموقع ✓')),
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('إلغاء')),
                  FilledButton(
                      onPressed: () async {
                        final patch = <String, dynamic>{
                          'name': name.text.trim(),
                          'phone': phone.text.trim(),
                          'address': address.text.trim(),
                          'governorate': governorate,
                          'area': area.text.trim(),
                          if (lat != null) 'lat': lat,
                          if (lng != null) 'lng': lng,
                        };
                        try {
                          await session.profileRef.update(patch);
                        } catch (_) {}
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('حفظ')),
                ],
              ),
            )));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: session,
      builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('حسابي')),
          body: ListView(padding: const EdgeInsets.all(20), children: [
            const CircleAvatar(
                radius: 36,
                backgroundColor: mint,
                child: Icon(Icons.person, color: plum, size: 40)),
            const SizedBox(height: 10),
            Center(
                child: Text(session.name,
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.bold))),
            Center(
                child: Text('الرقم التعريفي: ${session.publicId}',
                    style: const TextStyle(color: Colors.black54))),
            Center(
                child: Text(session.user?.email ?? '',
                    style:
                        const TextStyle(color: Colors.black54, fontSize: 12))),
            const SizedBox(height: 18),
            AccountTile(
                icon: Icons.location_on_outlined,
                label: session.address.isEmpty
                    ? 'عنواني (غير محدد)'
                    : session.address,
                onTap: () => _edit(context)),
            AccountTile(
                icon: Icons.edit_outlined,
                label: 'تعديل بياناتي',
                onTap: () => _edit(context)),
            AccountTile(
                icon: Icons.support_agent,
                label: 'المساعدة والدعم',
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) =>
                            MaaSupportPage(session: session, accent: coral)))),
            AccountTile(
                icon: Icons.logout,
                label: 'تسجيل الخروج',
                onTap: session.signOut),
          ])));
}

class AccountTile extends StatelessWidget {
  const AccountTile(
      {super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
      color: Colors.white,
      elevation: 0,
      child: ListTile(
          onTap: onTap,
          leading: Icon(icon, color: plum),
          title: Text(label),
          trailing: const Icon(Icons.chevron_left)));
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Text(title,
      style: const TextStyle(
          fontSize: 19, fontWeight: FontWeight.w900, color: plum));
}
