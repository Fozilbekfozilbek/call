import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/api_config.dart';

/// Thin wrapper around the Socket.IO client so screens don't touch the
/// raw socket API directly.
class SocketService {
  IO.Socket? _socket;

  void connectAsAdmin() {
    _connect();
    _socket?.emit('identify', {'role': 'admin'});
  }

  void connectAsWorker(int workerId) {
    _connect();
    _socket?.emit('identify', {'role': 'worker', 'userId': workerId});
  }

  void _connect() {
    _socket ??= IO.io(
      ApiConfig.socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );
    if (_socket?.connected != true) {
      _socket?.connect();
    }
  }

  /// Fired when a worker marks a number as called — admin screens listen here.
  void onNumberCalled(void Function(Map<String, dynamic> data) handler) {
    _socket?.on('numberCalled', (data) => handler(Map<String, dynamic>.from(data)));
  }

  /// Fired when a worker collects a payment from a customer — admin
  /// screens listen here to keep their stats live.
  void onPaymentCollected(void Function(Map<String, dynamic> data) handler) {
    _socket?.on('paymentCollected', (data) => handler(Map<String, dynamic>.from(data)));
  }

  /// Fired when the admin uploads new numbers — worker screens listen here.
  void onNumbersUploaded(void Function(Map<String, dynamic> data) handler) {
    _socket?.on('numbersUploaded', (data) => handler(Map<String, dynamic>.from(data)));
  }

  void dispose() {
    _socket?.dispose();
    _socket = null;
  }
}
