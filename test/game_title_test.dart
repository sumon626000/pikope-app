import 'package:billiard_poker/data/app_game.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every backend game key has a title (history screen)', () {
    expect(AppGameInfo.titleOf('eight'), '8-BALL');
    expect(AppGameInfo.titleOf('poker'), 'BILLIARD POKER');
    expect(AppGameInfo.titleOf('ludo2'), 'LUDO');
    expect(AppGameInfo.titleOf('ludo4'), 'LUDO (4 PLAYERS)');
    expect(AppGameInfo.titleOf('carrom'), 'CARROM');
    expect(AppGameInfo.titleOf('mystery'), 'MYSTERY');
  });
}
