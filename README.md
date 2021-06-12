# Experimental Cronet Dart bindings

This package binds to Cronet's [native API](https://chromium.googlesource.com/chromium/src/+/master/components/cronet/native/test_instructions.md) to expose them in Dart.

This is a [GSoC 2021 project](https://summerofcode.withgoogle.com/projects/#4757095741652992).



## Usage

1. Add this to `pubspec.yaml`

```pubspec
dependencies:
  cronet:
    git:
      url: https://github.com/google/cronet.dart.git

```

2. Run this from the `root` of your project

Desktop Platforms

```bash
pub get
pub run cronet <platform>
```
Supported platforms: `linux64` and `windows64`

3. Import

```dart
import 'package:cronet/cronet.dart';
```

**Internet connection is required to download cronet binaries**


## Example

```dart
  final client = HttpClient();
  client
      .getUrl(Uri.parse('http://info.cern.ch/'))
      .then((HttpClientRequest request) {
    return request.close();
  }).then((HttpClientResponse response) {
    response.transform(utf8.decoder).listen((contents) {
      print(contents);
    },
      onDone: () => print(
        'Done!'));
  });
```

### Alternate API

```dart
  final client = HttpClient();
  client
      .getUrl(Uri.parse('http://info.cern.ch/'))
      .then((HttpClientRequest request) {
    request.registerCallbacks((data, bytesRead, responseCode, next) {
      print(utf8.decoder.convert(data));
      print('Status: $responseCode');
      next();
    },
        onSuccess: (responseCode) =>
            print('Done with status: $responseCode')).catchError(
        (e) => print(e));
  });
```


## Run Example

```bash
cd example_dart
pub run cronet <platform>
dart run
```

replace `<platform>` with `linux64` or `windows64`

**Wrapper & Cronet binaries build guide**: [BUILD.md](lib/src/native/wrapper/BUILD.md)

