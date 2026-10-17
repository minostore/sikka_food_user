import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:maa_messaging/maa_messaging.dart';

import 'firebase_options.dart';
import 'open_street_map.dart';

const coral = Color(0xFFFF6B4A);
const plum = Color(0xFF4A1E3D);
const cream = Color(0xFFFFF8F1);
const mint = Color(0xFFA7E3C1);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var firebaseReady = false;
  final options = maaFirebaseOptions();
  if (options != null) {
    try {
      await Firebase.initializeApp(options: options);
      firebaseReady = true;
      await MaaMessaging.initialize('customer', accent: coral);
    } catch (error) {
      debugPrint('Firebase is not configured yet: $error');
    }
  }
  runApp(MaaCustomerApp(firebaseReady: firebaseReady));
}

class MaaCustomerApp extends StatelessWidget {
  const MaaCustomerApp({super.key, required this.firebaseReady});
  final bool firebaseReady;

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
        home: MaaUpdateGate(
            role: 'customer',
            accent: coral,
            enabled: firebaseReady,
            child: const Directionality(
                textDirection: TextDirection.rtl, child: CustomerShell())),
      );
}

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});
  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int tab = 0;
  int cartCount = 0;
  bool ordered = false;

  void showMenu() => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => MenuPage(onAdd: () {
                setState(() => cartCount++);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('أُضيف الطبق إلى سلتك')));
              })));

  void showCart() => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => CartPage(
                count: cartCount,
                onPlaceOrder: () {
                  setState(() {
                    ordered = true;
                    cartCount = 0;
                    tab = 1;
                  });
                  Navigator.pop(context);
                },
              )));

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeView(onOpenMenu: showMenu, onCart: showCart, cartCount: cartCount),
      TrackingView(ordered: ordered),
      const OrdersView(),
      const AccountView(),
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

class HomeView extends StatelessWidget {
  const HomeView(
      {super.key,
      required this.onOpenMenu,
      required this.onCart,
      required this.cartCount});
  final VoidCallback onOpenMenu;
  final VoidCallback onCart;
  final int cartCount;

  @override
  Widget build(BuildContext context) => CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: cream,
          title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('التوصيل إلى',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
                Text('شارع عباس العقاد، مدينة نصر، القاهرة',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: plum)),
              ]),
          actions: [
            const MaaNotificationButton(role: 'customer', accent: coral),
            IconButton(
                onPressed: onCart,
                icon: Badge(
                    label: Text('$cartCount'),
                    isLabelVisible: cartCount > 0,
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
                child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('طعامك أقرب لك',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 25,
                              fontWeight: FontWeight.w900)),
                      SizedBox(height: 5),
                      Text('مذاق أفضل .. كل يوم',
                          style: TextStyle(color: Colors.white, fontSize: 16)),
                      SizedBox(height: 18),
                      Text('وجبات تحبها، توصيل سريع، وتجربة سهلة.',
                          style: TextStyle(color: Colors.white)),
                    ]),
              ),
              const SizedBox(height: 18),
              TextField(
                  decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'ابحث عن مطعم أو وجبة',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none))),
              const SizedBox(height: 20),
              const SectionTitle('التصنيفات'),
              const SizedBox(height: 10),
              SizedBox(
                  height: 76,
                  child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: const [
                        CategoryChip(icon: Icons.lunch_dining, label: 'برجر'),
                        CategoryChip(icon: Icons.local_pizza, label: 'بيتزا'),
                        CategoryChip(icon: Icons.rice_bowl, label: 'وجبات'),
                        CategoryChip(icon: Icons.local_cafe, label: 'مشروبات'),
                        CategoryChip(
                            icon: Icons.favorite, label: 'الأكثر طلبًا'),
                      ])),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const SectionTitle('مطاعم قريبة'),
                TextButton(onPressed: onOpenMenu, child: const Text('عرض الكل'))
              ]),
              RestaurantCard(
                  name: 'بيت الشاورما',
                  subtitle: 'مشويات • وجبات عربية',
                  rating: '4.8',
                  time: '25–35 دقيقة',
                  icon: Icons.restaurant,
                  onTap: onOpenMenu),
              RestaurantCard(
                  name: 'مذاق المدينة',
                  subtitle: 'أطباق طازجة • صحي',
                  rating: '4.6',
                  time: '20–30 دقيقة',
                  icon: Icons.ramen_dining,
                  onTap: onOpenMenu),
              const SizedBox(height: 14),
              FilledButton.icon(
                  onPressed: onOpenMenu,
                  icon: const Icon(Icons.restaurant_menu),
                  label: const Text('تصفح قائمة الطعام'),
                  style: FilledButton.styleFrom(
                      backgroundColor: plum,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)))),
            ]))),
      ]);
}

class CategoryChip extends StatelessWidget {
  const CategoryChip({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
      width: 76,
      margin: const EdgeInsetsDirectional.only(end: 9),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: coral),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: plum))
      ]));
}

class RestaurantCard extends StatelessWidget {
  const RestaurantCard(
      {super.key,
      required this.name,
      required this.subtitle,
      required this.rating,
      required this.time,
      required this.icon,
      required this.onTap});
  final String name, subtitle, rating, time;
  final IconData icon;
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
          leading: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                  color: coral.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(15)),
              child: Icon(icon, color: coral, size: 30)),
          title: Text(name,
              style: const TextStyle(fontWeight: FontWeight.w800, color: plum)),
          subtitle: Text('$subtitle\n$time'),
          isThreeLine: true,
          trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.star, color: Color(0xFFFFB547), size: 17),
                Text(rating)
              ])));
}

class MenuPage extends StatelessWidget {
  const MenuPage({super.key, required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('مطاعم قريبة')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Container(
            height: 145,
            decoration: BoxDecoration(
                color: plum, borderRadius: BorderRadius.circular(22)),
            child: const Center(
                child: Icon(Icons.rice_bowl, size: 76, color: Colors.white))),
        const SizedBox(height: 15),
        const Text('بيت الشاورما',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w900, color: plum)),
        const Text('4.8 ★  •  25–35 دقيقة  •  رسوم التوصيل 8 ج.م'),
        const SizedBox(height: 18),
        const SectionTitle('الأكثر طلبًا'),
        MenuItem(
            title: 'كباب لحم',
            subtitle: 'مشوي طازج مع الأرز والسلطة',
            price: '32 ج.م',
            icon: Icons.set_meal,
            onAdd: onAdd),
        MenuItem(
            title: 'مشاوي مشكلة',
            subtitle: 'اختيار الشيف مع صوص خاص',
            price: '46 ج.م',
            icon: Icons.dinner_dining,
            onAdd: onAdd),
        MenuItem(
            title: 'سلطة عربية',
            subtitle: 'خضار طازجة يوميًا',
            price: '16 ج.م',
            icon: Icons.eco,
            onAdd: onAdd),
      ]));
}

class MenuItem extends StatelessWidget {
  const MenuItem(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.price,
      required this.icon,
      required this.onAdd});
  final String title, subtitle, price;
  final IconData icon;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(top: 10),
      child: ListTile(
          leading: Icon(icon, color: coral, size: 34),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('$subtitle\n$price'),
          isThreeLine: true,
          trailing: IconButton(
              onPressed: onAdd,
              icon: const Icon(Icons.add_circle, color: coral))));
}

class CartPage extends StatelessWidget {
  const CartPage({super.key, required this.count, required this.onPlaceOrder});
  final int count;
  final VoidCallback onPlaceOrder;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('السلة')),
      body: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
                count == 0
                    ? 'سلتك جاهزة لوجبتك القادمة'
                    : 'عدد الأطباق: $count',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: plum)),
            const SizedBox(height: 12),
            const Text('يتم احتساب رسوم التوصيل عند تأكيد الطلب.'),
            const Spacer(),
            FilledButton(
                onPressed: count == 0 ? null : onPlaceOrder,
                style: FilledButton.styleFrom(
                    backgroundColor: coral,
                    minimumSize: const Size.fromHeight(54)),
                child: const Text('تأكيد الطلب')),
          ])));
}

class TrackingView extends StatelessWidget {
  const TrackingView({super.key, required this.ordered});
  final bool ordered;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('تتبع الطلب')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const OpenStreetMapPreview(height: 235),
        const SizedBox(height: 18),
        Text(ordered ? 'طلبك قيد التجهيز' : 'رحلتك القادمة تبدأ من هنا',
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w900, color: plum)),
        const SizedBox(height: 6),
        const Text(
            'خريطة تجريبية لمركز القاهرة — موقعك الحي سيُضاف بعد تفعيل إذن الموقع.'),
        const SizedBox(height: 14),
        const StepLine(label: 'تم استلام الطلب', done: true),
        const StepLine(label: 'في قيد التحضير', done: false),
        const StepLine(label: 'السائق في الطريق', done: false),
        const StepLine(label: 'تم التسليم', done: false),
      ]));
}

class StepLine extends StatelessWidget {
  const StepLine({super.key, required this.label, required this.done});
  final String label;
  final bool done;
  @override
  Widget build(BuildContext context) => ListTile(
      leading: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
          color: done ? const Color(0xFF35A879) : Colors.black26),
      title: Text(label));
}

class OrdersView extends StatelessWidget {
  const OrdersView({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('طلباتي')),
      body: ListView(padding: const EdgeInsets.all(18), children: const [
        OrderCard(
            number: '1024',
            restaurant: 'بيت الشاورما',
            status: 'قيد التحضير',
            amount: '68 ج.م'),
        OrderCard(
            number: '1023',
            restaurant: 'مذاق المدينة',
            status: 'تم التوصيل',
            amount: '42 ج.م'),
      ]));
}

class OrderCard extends StatelessWidget {
  const OrderCard(
      {super.key,
      required this.number,
      required this.restaurant,
      required this.status,
      required this.amount});
  final String number, restaurant, status, amount;
  @override
  Widget build(BuildContext context) => Card(
      color: Colors.white,
      elevation: 0,
      child: ListTile(
          leading: const CircleAvatar(
              backgroundColor: cream,
              child: Icon(Icons.receipt_long, color: coral)),
          title: Text('$restaurant  •  #$number',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(status),
          trailing: Text(amount,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, color: plum))));
}

class AccountView extends StatelessWidget {
  const AccountView({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('حسابي')),
      body: ListView(padding: const EdgeInsets.all(20), children: const [
        CircleAvatar(
            radius: 36,
            backgroundColor: mint,
            child: Icon(Icons.person, color: plum, size: 40)),
        SizedBox(height: 10),
        Center(
            child: Text('أحمد محمد',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
        SizedBox(height: 18),
        AccountTile(
            icon: Icons.location_on_outlined, label: 'عناويني المحفوظة'),
        AccountTile(icon: Icons.payment, label: 'طرق الدفع'),
        AccountTile(icon: Icons.favorite_border, label: 'المفضلة'),
        AccountTile(icon: Icons.support_agent, label: 'المساعدة والدعم'),
        AccountTile(icon: Icons.settings_outlined, label: 'الإعدادات')
      ]));
}

class AccountTile extends StatelessWidget {
  const AccountTile({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Card(
      color: Colors.white,
      elevation: 0,
      child: ListTile(
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
