import 'dart:math';
import 'package:guildserver/catalog/unit_catalog.dart';



typedef Army = Map<String, int>;

class SimResult {
  final bool attackerWon;
  final Army survivorsAttacker;
  final Army survivorsDefender;
  final int goldReward;

  const SimResult(
    this.attackerWon,
    this.survivorsAttacker,
    this.survivorsDefender,
    this.goldReward,
  );
}

final _rng = Random();

SimResult simulateBattle(Army atkArmy, Army defArmy) {
double atkPwr = _power(atkArmy, (u) => u.atk.toDouble());
double defPwr = _power(defArmy, (u) => u.def.toDouble());
double hpAtk = _power(atkArmy, (u) => u.hp.toDouble());
double hpDef = _power(defArmy, (u) => u.hp.toDouble());


  double remAtk = hpAtk;
  double remDef = hpDef;

  for (int round = 0; round < 10 && remAtk > 0 && remDef > 0; round++) {
    final atkDmg = atkPwr * (0.8 + _rng.nextDouble() * 0.4);
    final defDmg = defPwr * (0.8 + _rng.nextDouble() * 0.4);
    remDef -= max(0, atkDmg - defPwr * 0.3);
    remAtk -= max(0, defDmg - atkPwr * 0.2);
    atkPwr *= 0.95;
    defPwr *= 0.95;
  }

  final survivedAtk = _scaleArmy(atkArmy, hpAtk, remAtk);
  final survivedDef = _scaleArmy(defArmy, hpDef, remDef);
  final attackerWon = remAtk >= remDef;
  final reward = ((hpAtk + hpDef) * 0.001).floor().clamp(10, 1000);

  return SimResult(attackerWon, survivedAtk, survivedDef, reward);
}

double _power(Army army, double Function(UnitData) statSelector) {
  double total = 0.0;
  for (final entry in army.entries) {
    final unit = unitCatalog[entry.key];
    if (unit != null) {
      total += entry.value * statSelector(unit);
    }
  }
  return total;
}


Map<String, int> _scaleArmy(Army army, double totalHp, double remainingHp) {
  final ratio = totalHp <= 0 ? 0.0 : (remainingHp / totalHp).clamp(0.0, 1.0);
  return army.map((k, v) => MapEntry(k, (v * ratio).floor()));
}
