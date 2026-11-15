import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

const _supported = {OS.android, OS.linux, OS.macOS};

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets ||
        !_supported.contains(input.config.code.targetOS)) {
      return;
    }
    await const RustBuilder(
      assetName: 'src/bindings.dart',
      cratePath: 'rust',
    ).run(input: input, output: output);
  });
}
