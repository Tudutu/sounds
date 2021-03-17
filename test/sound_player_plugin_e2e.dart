import 'dart:async';

import 'package:sounds/sounds.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Can get battery level', (tester) async {
    final player = SoundPlayer.noUI();
    expect(player, isNotNull);

    var released = false;
    var finished = Completer<bool>();

    player.onStopped = ({wasUser = false}) => finished.complete(true);
    Future.delayed(Duration(seconds: 10), () => finished.complete(false));

    player.play(Track.fromFile('assets/sample.acc'));

    finished.future.then<bool>((release) => released = release);

    await finished.future;

    expect(released, true);
  });
}
