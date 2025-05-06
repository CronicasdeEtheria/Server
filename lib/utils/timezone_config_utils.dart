import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

late tz.Location serverTimezone;

void configureTimezone(String timezoneName) {
  tz.initializeTimeZones();
  serverTimezone = tz.getLocation(timezoneName);
  tz.setLocalLocation(serverTimezone);
}
