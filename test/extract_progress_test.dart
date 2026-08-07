import 'package:dual_sub_merge/services/extract/extract_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the latest mkvextract percentage', () {
    expect(
      parseMkvextractFraction('Progress: 12%\rProgress: 47%\r'),
      closeTo(0.47, 0.0001),
    );
  });

  test('maps ffmpeg out time to current video progress', () {
    expect(
      parseFfmpegFraction(
        'out_time_us=25000000\nprogress=continue\n',
        const Duration(seconds: 100),
      ),
      closeTo(0.25, 0.0001),
    );
    expect(
      parseFfmpegFraction(
        'out_time_us=25000000\nprogress=end\n',
        const Duration(seconds: 100),
      ),
      1,
    );
  });
}
