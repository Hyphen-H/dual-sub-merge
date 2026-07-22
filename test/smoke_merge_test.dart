import "dart:io";
import "package:dual_sub_merge/models/merge_options.dart";
import "package:dual_sub_merge/services/merge_service.dart";
import "package:flutter_test/flutter_test.dart";
import "package:path/path.dart" as p;

void main() {
  final dir = Directory(
    r"C:\Users\27936\AppData\Local\Temp\opencode\dual-sub-merge-smoke",
  );

  test("smoke merge young justice sample", () async {
    final svc = MergeService(options: MergeOptions());
    final r = await svc.run(dir);
    expect(r.successCount, 1);
    final out = File(p.join(dir.path, "Young.Justice.S02E01.chs+eng.ass"));
    expect(out.existsSync(), isTrue);
    final text = await out.readAsString();
    expect(text.contains("中下HDRipad"), isTrue);
    expect(text.contains("英上HDRipad"), isTrue);
    expect(text, isNot(contains("under\nSavage")));
  }, skip: dir.existsSync() ? false : "local smoke fixture not present");
}
