import 'dart:math';

import '../models/balance.dart';
import '../models/campus_time.dart';
import '../models/dining_hall.dart';
import '../models/menu.dart';
import 'dining_api.dart';

const _weekdays = {DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday, DateTime.friday};
const _weekend = {DateTime.saturday, DateTime.sunday};
const _everyDay = {..._weekdays, ..._weekend};

int _t(int hour, [int minute = 0]) => hour * 60 + minute;

ServiceHours _h(String meal, Set<int> days, int opens, int closes) =>
    ServiceHours(meal: meal, weekdays: days, opensAt: opens, closesAt: closes);

/// Standard residential dining hall schedule.
List<ServiceHours> _hallHours({int dinnerCloses = 20 * 60}) => [
      _h('Breakfast', _weekdays, _t(7), _t(10)),
      _h('Lunch', _weekdays, _t(10, 30), _t(14)),
      _h('Dinner', _weekdays, _t(16, 30), dinnerCloses),
      _h('Brunch', _weekend, _t(10), _t(13, 30)),
      _h('Dinner', _weekend, _t(16, 30), _t(19, 30)),
    ];

/// Illustrative campus venues. Names and locations reflect University Housing
/// dining at Illinois; hours and menus are sample data, not official.
final demoHalls = <DiningHall>[
  DiningHall(
    id: 'ikenberry',
    name: 'Ikenberry Dining Center',
    shortName: 'Ikenberry',
    address: '301 E Gregory Dr, Champaign, IL 61820',
    type: VenueType.diningHall,
    latitude: 40.1037,
    longitude: -88.2353,
    description: 'The largest dining center on campus, serving the Ikenberry Commons halls.',
    hours: _hallHours(dinnerCloses: _t(20, 30)),
  ),
  DiningHall(
    id: 'isr',
    name: 'Illinois Street Dining Center',
    shortName: 'ISR',
    address: '1010 W Illinois St, Urbana, IL 61801',
    type: VenueType.diningHall,
    latitude: 40.1104,
    longitude: -88.2208,
    description: 'Serving Illinois Street Residence Halls on the north side of campus.',
    hours: _hallHours(),
  ),
  DiningHall(
    id: 'par',
    name: 'Pennsylvania Avenue Dining Hall',
    shortName: 'PAR',
    address: '906 W College Ct, Urbana, IL 61801',
    type: VenueType.diningHall,
    latitude: 40.1013,
    longitude: -88.2214,
    description: 'Serving the Pennsylvania Avenue Residence Halls.',
    hours: _hallHours(),
  ),
  DiningHall(
    id: 'lar',
    name: 'Lincoln Avenue Dining Hall',
    shortName: 'LAR',
    address: '1005 S Lincoln Ave, Urbana, IL 61801',
    type: VenueType.diningHall,
    latitude: 40.1044,
    longitude: -88.2193,
    description: 'Serving Lincoln Avenue and Allen Residence Halls.',
    hours: [
      _h('Breakfast', _weekdays, _t(7), _t(10)),
      _h('Lunch', _weekdays, _t(10, 30), _t(14)),
      _h('Dinner', _weekdays, _t(16, 30), _t(19, 30)),
    ],
  ),
  DiningHall(
    id: 'field-of-greens',
    name: 'Field of Greens',
    shortName: 'Field of Greens',
    address: '1005 S Lincoln Ave, Urbana, IL 61801',
    type: VenueType.cafe,
    latitude: 40.1044,
    longitude: -88.2193,
    description: 'Plant-forward bowls, salads and soups inside LAR.',
    hours: [
      _h('Lunch', _weekdays, _t(10, 30), _t(14)),
      _h('Dinner', _weekdays, _t(16, 30), _t(19)),
    ],
  ),
  DiningHall(
    id: 'caffeinator',
    name: 'Caffeinator',
    shortName: 'Caffeinator',
    address: '301 E Gregory Dr, Champaign, IL 61820',
    type: VenueType.cafe,
    latitude: 40.1037,
    longitude: -88.2353,
    description: 'Coffee, espresso and grab-and-go inside Ikenberry Dining Center.',
    hours: [
      _h('All Day', _weekdays, _t(8), _t(23)),
      _h('All Day', _weekend, _t(12), _t(23)),
    ],
  ),
  DiningHall(
    id: 'chomps',
    name: 'Chomps',
    shortName: 'Chomps',
    address: '301 E Gregory Dr, Champaign, IL 61820',
    type: VenueType.cafe,
    latitude: 40.1037,
    longitude: -88.2353,
    description: 'Late-night bites and convenience items at Ikenberry.',
    hours: [_h('Late Night', _everyDay, _t(20), _t(24))],
  ),
];

const _vg = DietaryTag.vegan;
const _v = DietaryTag.vegetarian;
const _gf = DietaryTag.glutenFree;
const _hl = DietaryTag.halal;
const _n = DietaryTag.containsNuts;
const _d = DietaryTag.containsDairy;

MenuItem _i(String name, [Set<DietaryTag> tags = const {}]) => MenuItem(
      name: name,
      // Vegan implies vegetarian.
      tags: {...tags, if (tags.contains(_vg)) _v},
      calories: 120 + _stableHash(name) % 630,
    );

final _stationPools = <String, List<MenuItem>>{
  'Griddle': [
    _i('Buttermilk Pancakes', {_v, _d}),
    _i('Belgian Waffles', {_v, _d}),
    _i('Cinnamon French Toast', {_v, _d}),
    _i('Vegan Banana Pancakes', {_vg}),
    _i('Breakfast Burrito', {_d}),
  ],
  'Eggs & Sides': [
    _i('Scrambled Eggs', {_v, _gf, _d}),
    _i('Tofu Scramble', {_vg, _gf}),
    _i('Breakfast Potatoes', {_vg, _gf}),
    _i('Turkey Sausage Links', {_gf, _hl}),
    _i('Applewood Bacon', {_gf}),
    _i('Egg & Cheese Biscuit', {_v, _d}),
  ],
  'Oatmeal & Fruit': [
    _i('Steel-Cut Oatmeal', {_vg}),
    _i('Fresh Fruit Cup', {_vg, _gf}),
    _i('Greek Yogurt Parfait', {_v, _gf, _d, _n}),
    _i('Chia Pudding', {_vg, _gf}),
  ],
  'Grill': [
    _i('Classic Cheeseburger', {_d}),
    _i('Black Bean Burger', {_vg}),
    _i('Grilled Chicken Sandwich', {_hl}),
    _i('Crispy Chicken Tenders'),
    _i('Seasoned Fries', {_vg, _gf}),
    _i('Sweet Potato Fries', {_vg, _gf}),
  ],
  'Comfort': [
    _i('Herb-Roasted Chicken', {_gf, _hl}),
    _i('Baked Mac & Cheese', {_v, _d}),
    _i('Beef Pot Roast', {_gf}),
    _i('Homestyle Meatloaf', {_d}),
    _i('Garlic Mashed Potatoes', {_v, _gf, _d}),
    _i('Roasted Green Beans', {_vg, _gf}),
    _i('Honey Cornbread', {_v, _d}),
  ],
  'Global': [
    _i('Chicken Tikka Masala', {_gf, _hl, _d}),
    _i('Chana Masala', {_vg, _gf}),
    _i('Vegetable Fried Rice', {_vg}),
    _i('Beef Bulgogi Bowl', {_hl}),
    _i("General Tso's Tofu", {_vg}),
    _i('Pork Carnitas Tacos', {_gf}),
    _i('Vegetable Lo Mein', {_vg}),
    _i('Jasmine Rice', {_vg, _gf}),
  ],
  'Pizza & Pasta': [
    _i('Pepperoni Pizza', {_d}),
    _i('Cheese Pizza', {_v, _d}),
    _i('Margherita Flatbread', {_v, _d}),
    _i('Penne Marinara', {_vg}),
    _i('Pesto Cavatappi', {_v, _d, _n}),
    _i('Gluten-Free Veggie Pizza', {_v, _gf, _d}),
  ],
  'Salad Bar': [
    _i('Build-Your-Own Salad', {_vg, _gf}),
    _i('Quinoa Tabbouleh', {_vg}),
    _i('Caesar Salad', {_d}),
    _i('Hummus & Pita', {_vg}),
    _i('Cucumber Tomato Salad', {_vg, _gf}),
  ],
  'Desserts': [
    _i('Chocolate Chip Cookies', {_v, _d}),
    _i('Fudge Brownies', {_v, _d}),
    _i('Vegan Oatmeal Cookies', {_vg}),
    _i('Apple Crisp', {_v, _d}),
    _i('Soft-Serve Ice Cream', {_v, _gf, _d}),
    _i('Peanut Butter Bars', {_v, _d, _n}),
  ],
  'Grain Bowls': [
    _i('Mediterranean Grain Bowl', {_vg}),
    _i('Tofu Poke Bowl', {_vg, _gf}),
    _i('Falafel Wrap', {_vg}),
    _i('Roasted Veggie Burrito Bowl', {_vg, _gf}),
    _i('Peanut Noodle Salad', {_vg, _n}),
  ],
  'Soups': [
    _i('Tomato Basil Soup', {_v, _gf, _d}),
    _i('Lentil Soup', {_vg, _gf}),
    _i('Three-Bean Vegetable Chili', {_vg, _gf}),
    _i('Butternut Squash Soup', {_vg, _gf}),
  ],
  'Coffee & Espresso': [
    _i('Drip Coffee', {_vg, _gf}),
    _i('Caffè Latte', {_v, _gf, _d}),
    _i('Cold Brew', {_vg, _gf}),
    _i('Chai Latte', {_v, _d}),
    _i('Oat Milk Mocha', {_vg}),
  ],
  'Bakery': [
    _i('Blueberry Muffin', {_v, _d}),
    _i('Everything Bagel & Cream Cheese', {_v, _d}),
    _i('Butter Croissant', {_v, _d}),
    _i('Vegan Banana Bread', {_vg}),
  ],
  'Grab & Go': [
    _i('Turkey Club Sandwich', {_d}),
    _i('Hummus Veggie Wrap', {_vg}),
    _i('Chicken Caesar Wrap', {_d}),
    _i('Fruit & Cheese Box', {_v, _gf, _d, _n}),
  ],
  'Late Night': [
    _i('Mozzarella Sticks', {_v, _d}),
    _i('Chicken Quesadilla', {_d}),
    _i('Loaded Nachos', {_v, _gf, _d}),
    _i('Cheese Pizza Slice', {_v, _d}),
    _i('Spicy Chicken Sandwich'),
    _i('Vegan Chili Cheese Fries', {_vg, _gf}),
  ],
};

List<String> _stationsFor(DiningHall hall, String meal) {
  switch (hall.id) {
    case 'field-of-greens':
      return ['Grain Bowls', 'Soups', 'Salad Bar'];
    case 'caffeinator':
      return ['Coffee & Espresso', 'Bakery', 'Grab & Go'];
    case 'chomps':
      return ['Late Night'];
  }
  if (meal == 'Breakfast') return ['Griddle', 'Eggs & Sides', 'Oatmeal & Fruit'];
  final stations = ['Grill', 'Comfort', 'Global', 'Pizza & Pasta', 'Salad Bar', 'Desserts'];
  if (meal == 'Brunch') stations.insertAll(0, ['Griddle', 'Eggs & Sides']);
  // Smaller halls run fewer stations.
  if (hall.id == 'lar' || hall.id == 'par') stations.remove('Pizza & Pasta');
  return stations;
}

/// FNV-1a; unlike [String.hashCode] it's stable across runs and platforms.
int _stableHash(String input) {
  var hash = 0x811c9dc5;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

/// Builds the sample menu for a venue on a day. Pure and deterministic.
DailyMenu buildDemoMenu(DiningHall hall, DateTime day) {
  final meals = <Meal>[];
  final seen = <String>{};
  for (final hours in hall.hoursOn(day)) {
    if (!seen.add(hours.meal)) continue;
    final random = Random(_stableHash('${hall.id}|${dateKey(day)}|${hours.meal}'));
    final stations = [
      for (final name in _stationsFor(hall, hours.meal))
        Station(
          name: name,
          items: (List.of(_stationPools[name]!)..shuffle(random))
              .take(min(_stationPools[name]!.length, 3 + random.nextInt(2)))
              .toList(),
        ),
    ];
    meals.add(Meal(name: hours.meal, stations: stations));
  }
  return DailyMenu(hallId: hall.id, date: dateKey(day), meals: meals);
}

/// Offline-capable sample backend used when no API is configured.
///
/// [offline] lets you simulate losing signal to see the cached experience.
class DemoDiningApi implements DiningApi, BalanceApi {
  DemoDiningApi({
    this.latency = const Duration(milliseconds: 450),
    DateTime Function()? now,
  }) : _now = now ?? CampusTime.now;

  final Duration latency;
  final DateTime Function() _now;
  bool offline = false;

  Future<void> _simulateNetwork() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (offline) throw const DiningApiException('No internet connection (simulated)');
  }

  @override
  Future<List<DiningHall>> fetchHalls() async {
    await _simulateNetwork();
    return demoHalls;
  }

  @override
  Future<DailyMenu> fetchMenu(String hallId, DateTime day) async {
    await _simulateNetwork();
    final hall = demoHalls.where((h) => h.id == hallId).firstOrNull;
    if (hall == null) throw DiningApiException('Unknown dining location "$hallId"');
    return buildDemoMenu(hall, day);
  }

  @override
  Future<MealPlanBalance> fetchBalance() async {
    await _simulateNetwork();
    return demoBalanceFor(_now());
  }
}

/// A plausible balance that drains over the semester, so the demo feels live.
MealPlanBalance demoBalanceFor(DateTime now) {
  final springTerm = now.month < 6;
  final start = springTerm ? DateTime(now.year, 1, 20) : DateTime(now.year, 8, 25);
  final end = springTerm ? DateTime(now.year, 5, 15) : DateTime(now.year, 12, 20);
  final total = end.difference(start).inDays;
  final elapsed = now.difference(start).inDays.clamp(0, total);
  final used = elapsed / total;

  const swipesTotal = 240;
  const dollarsTotal = 300.0;
  // Students tend to spend Dining Dollars a little faster than swipes.
  final swipesLeft = (swipesTotal * (1 - used * 0.92)).round();
  final dollarsLeft = ((dollarsTotal * (1 - used * 0.97)) * 100).roundToDouble() / 100;

  return MealPlanBalance(
    planName: 'Classic Plan',
    mealSwipesRemaining: swipesLeft.clamp(0, swipesTotal),
    mealSwipesTotal: swipesTotal,
    diningDollars: dollarsLeft.clamp(0, dollarsTotal),
    diningDollarsTotal: dollarsTotal,
    transactions: demoTransactionsFor(now),
  );
}

/// About two meals and a café stop a day over the past two weeks.
List<BalanceTransaction> demoTransactionsFor(DateTime now) {
  const halls = ['ISR', 'Ikenberry', 'PAR', 'LAR'];
  const prices = [3.49, 4.29, 4.99, 5.99, 6.49];
  final all = <BalanceTransaction>[];
  for (var daysAgo = 0; daysAgo < 14; daysAgo++) {
    final day = DateTime(now.year, now.month, now.day - daysAgo);
    final seed = _stableHash('${day.month}-${day.day}');
    BalanceTransaction meal(int hour, int minute) => BalanceTransaction(
          kind: TransactionKind.mealSwipe,
          time: day.add(Duration(hours: hour, minutes: minute)),
          location: halls[(seed + hour) % halls.length],
          description: 'Meal',
        );
    all.addAll([
      meal(12, seed % 40),
      if (seed % 3 != 0) meal(18, seed % 50),
      BalanceTransaction(
        kind: TransactionKind.diningDollars,
        time: day.add(Duration(hours: 9, minutes: seed % 55)),
        location: 'Terrabyte',
        description: 'Purchase',
        amount: -prices[seed % prices.length],
      ),
    ]);
  }
  return [
    for (final t in all..sort((a, b) => b.time.compareTo(a.time)))
      if (!t.time.isAfter(now)) t,
  ];
}
