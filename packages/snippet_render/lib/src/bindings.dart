// ignore_for_file: non_constant_identifier_names

import 'dart:ffi';

@Native<Pointer<Char> Function(Pointer<Char>, Int32)>()
external Pointer<Char> sr_check(Pointer<Char> source, int lang);

@Native<
  Pointer<Void> Function(Int64, Pointer<Char>, Int32, Uint32, Uint32, Uint32)
>()
external Pointer<Void> sr_create(
  int engine,
  Pointer<Char> source,
  int lang,
  int width,
  int height,
  int fps,
);

@Native<Int64 Function(Pointer<Void>)>()
external int sr_texture_id(Pointer<Void> surface);

@Native<Pointer<Char> Function(Pointer<Void>)>()
external Pointer<Char> sr_error(Pointer<Void> surface);

@Native<Void Function(Pointer<Void>, Pointer<Char>, Int32)>()
external void sr_set_shader(
  Pointer<Void> surface,
  Pointer<Char> source,
  int lang,
);

@Native<Void Function(Pointer<Void>, Uint32, Uint32)>()
external void sr_resize(Pointer<Void> surface, int width, int height);

@Native<Void Function(Pointer<Void>, Bool)>()
external void sr_set_paused(Pointer<Void> surface, bool paused);

@Native<Void Function(Pointer<Void>, Uint32)>()
external void sr_set_fps(Pointer<Void> surface, int fps);

@Native<Void Function(Pointer<Void>)>()
external void sr_destroy(Pointer<Void> surface);

@Native<Void Function(Pointer<Char>)>()
external void sr_free_string(Pointer<Char> p);
