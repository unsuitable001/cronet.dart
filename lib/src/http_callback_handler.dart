// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'http_client_request.dart';

/// Deserializes the message sent by cronet and it's wrapper.
class _CallbackRequestMessage {
  final String method;
  final Uint8List data;

  /// Constructs [method] and [data] from [message].
  factory _CallbackRequestMessage.fromCppMessage(List<dynamic> message) {
    return _CallbackRequestMessage._(
        message[0] as String, message[1] as Uint8List);
  }

  _CallbackRequestMessage._(this.method, this.data);

  @override
  String toString() => 'CppRequest(method: $method)';
}

/// Handles every kind of callbacks that are invoked by messages and
/// data that are sent by [NativePort] from native cronet library.
class _CallbackHandler {
  final ReceivePort receivePort;
  final Cronet cronet;
  final Pointer<Void> executor;

  // These are a part of HttpClientRequest Public API.
  bool followRedirects = true;
  int maxRedirects = 5;

  /// Stream controller to allow consumption of data like [HttpClientResponse].
  final _controller = StreamController<List<int>>();

  /// Registers the [NativePort] to the cronet side.
  _CallbackHandler(this.cronet, this.executor, this.receivePort);

  /// [Stream] controller for [HttpClientResponse]
  Stream<List<int>> get stream {
    return _controller.stream;
  }

  // Clean up tasks for a request.
  //
  // We need to call this then whenever we are done with the request.
  void cleanUpRequest(
      Pointer<Cronet_UrlRequest> reqPtr, Function cleanUpClient) {
    receivePort.close();
    cronet.removeRequest(reqPtr);
    cleanUpClient();
  }

  /// Checks status of an URL response.
  int statusChecker(Pointer<Cronet_UrlResponseInfo> respInfoPtr, int lBound,
      int uBound, Function callback) {
    final respCode =
        cronet.Cronet_UrlResponseInfo_http_status_code_get(respInfoPtr);
    if (!(respCode >= lBound && respCode <= uBound)) {
      // If NOT in range.
      callback();
      final exception = HttpException(
          cronet.Cronet_UrlResponseInfo_http_status_text_get(respInfoPtr)
              .cast<Utf8>()
              .toDartString());
      _controller.addError(exception);
      _controller.close();
    }
    return respCode;
  }

  /// This listens to the messages sent by native cronet library.
  ///
  /// This also invokes the appropriate callbacks that are registered,
  /// according to the network events sent from cronet side.
  void listen(Pointer<Cronet_UrlRequest> reqPtr, Function cleanUpClient) {
    // Registers the listener on the receivePort.
    //
    // The message parameter contains both the name of the event and
    // the data associated with it.
    receivePort.listen((dynamic message) {
      final reqMessage =
          _CallbackRequestMessage.fromCppMessage(message as List);
      Int64List args;
      args = reqMessage.data.buffer.asInt64List();

      switch (reqMessage.method) {
        case 'OnRedirectReceived':
          {
            log('New Location: ${Pointer.fromAddress(args[0]).cast<Utf8>().toDartString()}');
            statusChecker(
                Pointer.fromAddress(args[1]).cast<Cronet_UrlResponseInfo>(),
                300,
                399,
                () => cleanUpRequest(reqPtr,
                    cleanUpClient)); // If NOT a 3XX status code, throw Exception.
            if (followRedirects && maxRedirects > 0) {
              final res = cronet.Cronet_UrlRequest_FollowRedirect(reqPtr);
              if (res != Cronet_RESULT.Cronet_RESULT_SUCCESS) {
                cleanUpRequest(reqPtr, cleanUpClient);
                throw UrlRequestException(res);
              }
              maxRedirects--;
            } else {
              cronet.Cronet_UrlRequest_Cancel(reqPtr);
            }
          }
          break;

        // When server has sent the initial response.
        case 'OnResponseStarted':
          {
            // If NOT a 1XX or 2XX status code, throw Exception.
            statusChecker(
                Pointer.fromAddress(args[0]).cast<Cronet_UrlResponseInfo>(),
                100,
                299,
                () => cleanUpRequest(reqPtr, cleanUpClient));
            log('Response started');
          }
          break;
        // Read a chunk of data.
        //
        // This is where we actually read the response from the server. Data gets added
        // to the stream here. ReadDataCallback is invoked here with data received and no
        // of bytes read.
        case 'OnReadCompleted':
          {
            final request = Pointer<Cronet_UrlRequest>.fromAddress(args[0]);
            final info = Pointer<Cronet_UrlResponseInfo>.fromAddress(args[1]);
            final buffer = Pointer<Cronet_Buffer>.fromAddress(args[2]);
            final bytesRead = args[3];

            log('Recieved: $bytesRead');
            // If NOT a 1XX or 2XX status code, throw Exception.
            statusChecker(
                info, 100, 299, () => cleanUpRequest(reqPtr, cleanUpClient));
            final data = cronet.Cronet_Buffer_GetData(buffer)
                .cast<Uint8>()
                .asTypedList(bytesRead);
            _controller.sink.add(data.toList(growable: false));
            final res = cronet.Cronet_UrlRequest_Read(request, buffer);
            if (res != Cronet_RESULT.Cronet_RESULT_SUCCESS) {
              cleanUpRequest(reqPtr, cleanUpClient);
              _controller.addError(UrlRequestException(res));
              _controller.close();
            }
          }
          break;
        // In case of network error, we will shut everything down after this.
        case 'OnFailed':
          {
            final error =
                Pointer.fromAddress(args[0]).cast<Utf8>().toDartString();
            cleanUpRequest(reqPtr, cleanUpClient);
            _controller.addError(HttpException(error));
            _controller.close();
            cronet.Cronet_UrlRequest_Destroy(reqPtr);
          }
          break;
        // when the request is cancelled, we will shut everything down after this.
        case 'OnCanceled':
          {
            cleanUpRequest(reqPtr, cleanUpClient);
            _controller.close();
            cronet.Cronet_UrlRequest_Destroy(reqPtr);
          }
          break;
        // When the request is succesfully done, we will shut everything down after this.
        case 'OnSucceeded':
          {
            cleanUpRequest(reqPtr, cleanUpClient);
            _controller.close();
            cronet.Cronet_UrlRequest_Destroy(reqPtr);
          }
          break;
        default:
          {
            break;
          }
      }
    }, onError: (Object error) {
      log(error.toString());
    });
  }
}
