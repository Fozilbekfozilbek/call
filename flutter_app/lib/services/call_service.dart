import 'dart:async';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:phone_state/phone_state.dart';

/// Handles requesting the phone permissions, placing the call, and watching
/// the device's telephony state to figure out whether the call was actually
/// answered (as opposed to declined / not picked up / busy).
///
/// Android only — iOS does not expose telephony call state to third-party
/// apps, so this whole flow is unavailable there by design.
class CallService {
  StreamSubscription<PhoneState>? _subscription;

  /// Requests CALL_PHONE + READ_PHONE_STATE permissions.
  /// Returns true if both were granted.
  Future<bool> ensurePermissions() async {
    final statuses = await [
      Permission.phone,
    ].request();
    return statuses[Permission.phone]?.isGranted ?? false;
  }

  /// Places the call and invokes [onAnswered] once the call transitions
  /// through CALL_STARTED (dialing/ringing) and then reaches CALL_ENDED
  /// having spent a meaningful amount of time OFFHOOK — our proxy for
  /// "the other side picked up".
  ///
  /// [onAnswered] is called at most once per call attempt.
  /// [onEnded] is always called when the call session finishes, whether or
  /// not it was answered, so the UI can stop any "calling..." indicator.
  Future<void> callAndTrack({
    required String number,
    required void Function() onAnswered,
    void Function()? onEnded,
  }) async {
    final granted = await ensurePermissions();
    if (!granted) {
      throw Exception('Qo\'ng\'iroq qilish uchun ruxsat berilmadi.');
    }

    DateTime? callStartedAt;
    bool answeredFired = false;

    // Cancel any previous listener before starting a new call.
    await _subscription?.cancel();

    _subscription = PhoneState.stream.listen((PhoneState event) {
      switch (event.status) {
        case PhoneStateStatus.CALL_STARTED:
          // Dialing/ringing has begun — record when, so CALL_ENDED can
          // measure how long the whole call session lasted.
          callStartedAt = DateTime.now();
          break;

        case PhoneStateStatus.CALL_ENDED:
          if (callStartedAt != null && !answeredFired) {
            final duration = DateTime.now().difference(callStartedAt!);
            // Heuristic: this package only exposes CALL_STARTED (dial/ring)
            // and CALL_ENDED (call finished) — there is no separate
            // "answered"/OFFHOOK status to key off. If the whole session
            // lasted more than ~3 seconds, treat it as answered rather than
            // a quick reject/busy/no-answer. Tune this threshold if needed.
            if (duration.inSeconds >= 3) {
              answeredFired = true;
              onAnswered();
            }
          }
          onEnded?.call();
          _subscription?.cancel();
          _subscription = null;
          break;

        default:
          // NOTHING / CALL_INCOMING — not relevant for an outgoing call
          // placed by this app.
          break;
      }
    });

    await FlutterPhoneDirectCaller.callNumber(number);
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
