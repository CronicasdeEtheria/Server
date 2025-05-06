class BuildingData {
  final String id;
  final int baseTime;
  final int baseCostWood;
  final int baseCostStone;
  final int baseCostFood;
  final int maxLevel;

  const BuildingData({
    required this.id,
    required this.baseTime,
    required this.baseCostWood,
    required this.baseCostStone,
    required this.baseCostFood,
    this.maxLevel = 35,
  });
}

const buildingCatalog = <String, BuildingData>{
  'townhall': BuildingData(
    id: 'townhall',
    baseTime: 120,
    baseCostWood: 120,
    baseCostStone: 120,
    baseCostFood: 120,
  ),
  'warehouse': BuildingData(
    id: 'warehouse',
    baseTime: 120,
    baseCostWood: 60,
    baseCostStone: 30,
    baseCostFood: 20,
  ),
  'barracks': BuildingData(
    id: 'barracks',
    baseTime: 120,
    baseCostWood: 100,
    baseCostStone: 50,
    baseCostFood: 75,
  ),
  'lumbermill': BuildingData(
    id: 'lumbermill',
    baseTime: 90,
    baseCostWood: 80,
    baseCostStone: 40,
    baseCostFood: 60,
  ),
  'stonemine': BuildingData(
    id: 'stonemine',
    baseTime: 90,
    baseCostWood: 80,
    baseCostStone: 40,
    baseCostFood: 60,
  ),
  'farm': BuildingData(
    id: 'farm',
    baseTime: 60,
    baseCostWood: 60,
    baseCostStone: 30,
    baseCostFood: 50,
  ),
  'coliseo': BuildingData(
    id: 'coliseo',
    baseTime: 60,
    baseCostWood: 60,
    baseCostStone: 30,
    baseCostFood: 50,
  ),
};
