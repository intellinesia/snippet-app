import 'package:flutter/material.dart';

import 'theme.dart';
import 'phosphor_icons.dart';

const _orange = Color(0xFFD97757);
const _blue = Color(0xFF8AB4F8);
const _yellow = Color(0xFFE9C46A);
const _green = Color(0xFF9ED8B5);
const _purple = Color(0xFFD7A6E8);
const _red = Color(0xFFE5867A);
const _amber = Color(0xFFE5B44A);
const _teal = Color(0xFF7CC7C9);
const _grey = Color(0xFF8C857A);

String _ext(String name) {
  final l = name.toLowerCase();
  final i = l.lastIndexOf('.');
  return i <= 0 ? '' : l.substring(i + 1);
}

(IconData, Color)? _byName(String lower) {
  if (lower == '.env' || lower.startsWith('.env.')) {
    return (PhIcons.file, _amber);
  }
  if (lower.startsWith('license') ||
      lower.startsWith('licence') ||
      lower == 'copying') {
    return (PhIcons.file, _amber);
  }
  if (lower.startsWith('readme')) return (PhIcons.fileText, _blue);
  if (lower.startsWith('changelog')) return (PhIcons.file, _blue);
  if (lower == 'dockerfile' ||
      lower.startsWith('dockerfile.') ||
      lower.startsWith('docker-compose') ||
      lower.startsWith('compose.')) {
    return (PhIcons.file, _blue);
  }
  if (lower == 'makefile' ||
      lower == 'justfile' ||
      lower == 'procfile' ||
      lower == 'rakefile') {
    return (PhIcons.terminalWindow, _orange);
  }
  if (lower.startsWith('.git')) return (PhIcons.gitDiff, _orange);
  if (const {
    'package.json',
    'cargo.toml',
    'pubspec.yaml',
    'pyproject.toml',
    'go.mod',
    'gemfile',
    'composer.json',
    'build.gradle',
    'build.gradle.kts',
    'pom.xml',
    'requirements.txt',
    'setup.py',
    'deno.json',
    'bun.lockb',
  }.contains(lower)) {
    return (PhIcons.file, _green);
  }
  if (lower.endsWith('.lock') ||
      lower.endsWith('-lock.json') ||
      lower.endsWith('-lock.yaml') ||
      lower == 'go.sum') {
    return (PhIcons.file, _grey);
  }
  if (lower.startsWith('tsconfig') ||
      lower.startsWith('jsconfig') ||
      lower.contains('.config.') ||
      lower.startsWith('.eslintrc') ||
      lower.startsWith('.prettierrc') ||
      lower == '.editorconfig' ||
      lower.startsWith('.babelrc') ||
      lower == 'analysis_options.yaml' ||
      lower.startsWith('.npmrc') ||
      lower.startsWith('.nvmrc')) {
    return (PhIcons.file, _teal);
  }
  return null;
}

(IconData, Color) fileIconFor(String name) {
  final lower = name.split('/').last.toLowerCase();
  final named = _byName(lower);
  if (named != null) return named;
  return switch (_ext(lower)) {
    'rs' => (PhIcons.fileCode, _orange),
    'swift' || 'kt' || 'kts' || 'java' || 'scala' => (
        PhIcons.fileCode,
        _orange
      ),
    'dart' || 'go' || 'py' || 'pyi' => (PhIcons.fileCode, _blue),
    'c' || 'h' || 'cc' || 'cpp' || 'hpp' || 'cs' || 'm' || 'mm' => (
        PhIcons.fileCode,
        _blue
      ),
    'ts' || 'tsx' || 'mts' || 'cts' => (PhIcons.fileCode, _blue),
    'js' || 'jsx' || 'mjs' || 'cjs' => (PhIcons.fileCode, _yellow),
    'rb' || 'erb' || 'ex' || 'exs' || 'erl' || 'clj' => (
        PhIcons.fileCode,
        _red
      ),
    'php' || 'lua' || 'zig' || 'nim' || 'jl' || 'r' || 'hs' || 'ml' => (
        PhIcons.fileCode,
        _purple
      ),
    'vue' || 'svelte' || 'astro' => (PhIcons.fileCode, _green),
    'html' || 'htm' || 'xml' || 'xhtml' => (PhIcons.fileCode, _orange),
    'css' || 'scss' || 'sass' || 'less' || 'styl' => (
        PhIcons.fileCode,
        _purple
      ),
    'sql' || 'prisma' || 'graphql' || 'gql' || 'proto' => (
        PhIcons.fileCode,
        _teal
      ),
    'json' || 'jsonc' || 'json5' || 'jsonl' || 'ndjson' => (
        PhIcons.code,
        _yellow
      ),
    'yaml' ||
    'yml' ||
    'toml' ||
    'ini' ||
    'cfg' ||
    'conf' ||
    'properties' ||
    'plist' ||
    'env' =>
      (PhIcons.file, _green),
    'md' || 'mdx' || 'markdown' || 'rst' || 'adoc' || 'org' || 'tex' => (
        PhIcons.fileText,
        _blue
      ),
    'txt' || 'rtf' => (PhIcons.fileText, _grey),
    'log' => (PhIcons.file, _grey),
    'pdf' => (PhIcons.fileText, _red),
    'doc' || 'docx' || 'odt' || 'pages' => (PhIcons.fileText, _blue),
    'csv' || 'tsv' || 'xls' || 'xlsx' || 'ods' || 'numbers' || 'parquet' => (
        PhIcons.table,
        _green
      ),
    'ppt' || 'pptx' || 'odp' => (PhIcons.filmStrip, _orange),
    'ipynb' => (PhIcons.chartLine, _orange),
    'png' ||
    'jpg' ||
    'jpeg' ||
    'gif' ||
    'webp' ||
    'bmp' ||
    'ico' ||
    'avif' ||
    'heic' ||
    'tif' ||
    'tiff' ||
    'psd' =>
      (PhIcons.image, _purple),
    'svg' => (PhIcons.image, _yellow),
    'fig' || 'sketch' || 'xd' => (PhIcons.image, _red),
    'mp4' || 'mov' || 'webm' || 'mkv' || 'avi' || 'm4v' => (
        PhIcons.filmStrip,
        _red
      ),
    'mp3' || 'wav' || 'm4a' || 'flac' || 'ogg' || 'aac' || 'aiff' => (
        PhIcons.musicNote,
        _purple
      ),
    'zip' ||
    'tar' ||
    'gz' ||
    'tgz' ||
    'bz2' ||
    'xz' ||
    'zst' ||
    '7z' ||
    'rar' ||
    'jar' ||
    'war' =>
      (PhIcons.file, _amber),
    'apk' || 'aab' || 'ipa' || 'dmg' || 'pkg' || 'deb' || 'rpm' || 'msi' => (
        PhIcons.file,
        _amber
      ),
    'sh' || 'bash' || 'zsh' || 'fish' || 'ps1' || 'bat' || 'cmd' || 'nu' => (
        PhIcons.terminalWindow,
        _green
      ),
    'ttf' || 'otf' || 'woff' || 'woff2' || 'eot' => (
        PhIcons.fileText,
        _red
      ),
    'pem' || 'crt' || 'cer' || 'p12' || 'pfx' || 'pub' || 'gpg' || 'asc' => (
        PhIcons.file,
        _amber
      ),
    'diff' || 'patch' => (PhIcons.gitDiff, _orange),
    'db' || 'sqlite' || 'sqlite3' || 'wal' => (PhIcons.database, _teal),
    'glb' || 'gltf' || 'obj' || 'fbx' || 'stl' || 'blend' || 'usdz' => (
        PhIcons.file,
        _purple
      ),
    'wasm' || 'so' || 'dylib' || 'dll' || 'exe' || 'bin' || 'o' || 'a' => (
        PhIcons.file,
        _grey
      ),
    'lock' => (PhIcons.file, _grey),
    'csr' || 'sig' => (PhIcons.file, _amber),
    _ => (PhIcons.file, _grey),
  };
}

(IconData, Color) folderIconFor(String name, {bool open = false}) {
  final l = name.toLowerCase();
  return switch (l) {
    '.git' => (PhIcons.gitBranch, _orange),
    '.github' || '.gitlab' || '.circleci' => (PhIcons.gitBranch, _grey),
    'src' ||
    'lib' ||
    'app' ||
    'source' ||
    'packages' ||
    'pkg' ||
    'internal' ||
    'cmd' ||
    'crates' ||
    'components' ||
    'modules' =>
      (PhIcons.folder, _blue),
    'test' ||
    'tests' ||
    '__tests__' ||
    'spec' ||
    'specs' ||
    'e2e' ||
    'integration_test' ||
    'testdata' ||
    'fixtures' =>
      (PhIcons.folder, _green),
    'docs' || 'doc' || 'documentation' || 'wiki' || 'notes' => (
        PhIcons.folder,
        _blue
      ),
    'node_modules' ||
    'vendor' ||
    'third_party' ||
    '.venv' ||
    'venv' ||
    '.dart_tool' ||
    'pods' =>
      (PhIcons.folder, _grey),
    'build' ||
    'dist' ||
    'out' ||
    'target' ||
    '.next' ||
    '.nuxt' ||
    '.output' ||
    'release' ||
    'bin' ||
    'obj' =>
      (PhIcons.folder, _grey),
    'config' ||
    '.config' ||
    '.vscode' ||
    '.idea' ||
    'settings' ||
    '.claude' ||
    '.cursor' =>
      (PhIcons.folder, _teal),
    'scripts' || 'tools' || 'hack' || 'ci' || '.husky' => (
        PhIcons.folder,
        _green
      ),
    'assets' ||
    'public' ||
    'static' ||
    'images' ||
    'img' ||
    'icons' ||
    'media' ||
    'fonts' ||
    'res' ||
    'resources' =>
      (PhIcons.folderStar, _purple),
    'secrets' || 'keys' || '.ssh' || 'certs' => (PhIcons.folder, _amber),
    'tmp' || 'temp' || 'cache' || '.cache' || 'logs' => (
        PhIcons.folder,
        _grey
      ),
    'android' || 'ios' || 'macos' || 'linux' || 'windows' || 'web' => (
        PhIcons.folder,
        _green
      ),
    'migrations' || 'db' || 'data' || 'database' => (
        PhIcons.folder,
        _teal
      ),
    'examples' || 'samples' || 'demo' || 'templates' => (
        PhIcons.kanban,
        _yellow
      ),
    _ => (open ? PhIcons.folderOpen : PhIcons.folder, _grey),
  };
}

/// Short label and colour for source files, drawn as a badge so each language
/// reads at a glance without shipping any icon assets.
(String, Color)? fileBadgeFor(String name) {
  final lower = name.split('/').last.toLowerCase();
  if (_byName(lower) != null) return null;
  return switch (_ext(lower)) {
    'rs' => ('RS', _orange),
    'go' => ('GO', _teal),
    'py' || 'pyi' => ('PY', _blue),
    'js' || 'mjs' || 'cjs' => ('JS', _yellow),
    'jsx' => ('JSX', _yellow),
    'ts' || 'mts' || 'cts' => ('TS', _blue),
    'tsx' => ('TSX', _blue),
    'dart' => ('DT', Color(0xFF54C5F8)),
    'kt' || 'kts' => ('KT', _purple),
    'swift' => ('SW', _orange),
    'java' => ('JV', _red),
    'scala' => ('SC', _red),
    'c' => ('C', _blue),
    'h' || 'hpp' => ('H', _purple),
    'cc' || 'cpp' || 'cxx' => ('C++', _blue),
    'cs' => ('C#', _green),
    'm' || 'mm' => ('OC', _blue),
    'rb' || 'erb' => ('RB', _red),
    'php' => ('PHP', _purple),
    'lua' => ('LU', _blue),
    'zig' => ('ZG', _amber),
    'nim' => ('NM', _yellow),
    'ex' || 'exs' => ('EX', _purple),
    'erl' => ('ER', _red),
    'clj' => ('CJ', _green),
    'hs' => ('HS', _purple),
    'ml' => ('ML', _orange),
    'jl' => ('JL', _purple),
    'r' => ('R', _blue),
    'sh' || 'bash' || 'zsh' || 'fish' => ('SH', _green),
    'ps1' => ('PS', _blue),
    'sql' => ('SQL', _teal),
    'prisma' => ('PR', _teal),
    'graphql' || 'gql' => ('GQ', _red),
    'proto' => ('PB', _teal),
    'html' || 'htm' => ('<>', _orange),
    'xml' => ('XML', _orange),
    'css' => ('CSS', _blue),
    'scss' || 'sass' => ('SC', _red),
    'less' => ('LS', _blue),
    'vue' => ('VUE', _green),
    'svelte' => ('SV', _orange),
    'astro' => ('AS', _purple),
    'json' || 'jsonc' || 'json5' => ('{}', _yellow),
    'yaml' || 'yml' => ('YML', _red),
    'toml' => ('TML', _amber),
    'md' || 'mdx' || 'markdown' => ('MD', _blue),
    'tf' || 'hcl' => ('TF', _purple),
    'sol' => ('SOL', _grey),
    'wasm' || 'wat' => ('WA', _purple),
    _ => null,
  };
}

class FileGlyph extends StatelessWidget {
  const FileGlyph(this.name,
      {super.key, this.isDir = false, this.open = false, this.size = 14});
  final String name;
  final bool isDir;
  final bool open;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.fg3;
    if (isDir) {
      return Icon(open ? PhIcons.folderOpen : PhIcons.folder,
          size: size, color: color);
    }
    return Icon(fileIconFor(name).$1, size: size, color: color);
  }
}
