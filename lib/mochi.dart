import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'agent_character.dart';

export 'agent_character.dart';

final agentCharacters = ValueNotifier<Map<String, String>>(const {});

String? agentCharacterFor(String agentId) => agentCharacters.value[agentId];

/// Mirrors the daemon's `default_agent_character` (FNV-1a over the id, 01 and
/// 14 reserved) so an agent looks the same before its row has loaded.
String defaultAgentCharacter(String agentId) {
  switch (agentId) {
    case 'lead':
      return '14';
    case 'snippet':
    case '':
      return '01';
  }
  var h = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final b in _utf8(agentId)) {
    h = ((h ^ BigInt.from(b)) * prime) & mask;
  }
  final pool = [
    for (var n = 1; n <= 36; n++)
      if (n != 1 && n != 14) n
  ];
  final n = pool[(h % BigInt.from(pool.length)).toInt()];
  return n.toString().padLeft(2, '0');
}

List<int> _utf8(String s) => const Utf8Codec().encode(s);

/// Session id -> the agent working there, kept from the last session list so
/// surfaces without the list (notifications) still show the right character.
final Map<String, String> sessionAgents = {};

/// The character an agent shows: its stored pick, else the daemon's default.
String characterForAgent(String agentId) =>
    agentCharacterFor(agentId) ?? defaultAgentCharacter(agentId);

/// The agent's character colour, for tinting its chat; null until the roster loads.
Color? agentTintFor(String agentId) =>
    CharacterRoster.current?.character(characterForAgent(agentId))?.color;

void rememberAgentCharacters(Iterable<(String, String?)> agents) {
  final next = <String, String>{};
  for (final (id, character) in agents) {
    final trimmed = character?.trim();
    if (trimmed != null && trimmed.isNotEmpty) next[id] = trimmed;
  }
  if (!mapEquals(next, agentCharacters.value)) agentCharacters.value = next;
}

void setRememberedAgentCharacter(String id, String? character) {
  final next = Map<String, String>.of(agentCharacters.value);
  final trimmed = character?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    next.remove(id);
  } else {
    next[id] = trimmed;
  }
  agentCharacters.value = next;
}

/// Avatar size for a list row: about two thirds of the row height, so the
/// mark reads as part of the row rather than a speck in it.
double rowAvatarSize(double rowHeight, {double min = 14, double max = 44}) =>
    (rowHeight * 0.66).roundToDouble().clamp(min, max).toDouble();

/// An agent's character, kept in step with the remembered picks.
class AgentMochi extends StatelessWidget {
  const AgentMochi(this.agentId,
      {super.key,
      this.size = 18,
      this.state = AgentCharacterState.idle,
      this.badge});

  final String agentId;
  final double size;
  final AgentCharacterState state;
  final String? badge;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: agentCharacters,
        builder: (_, __, ___) => AgentCharacter(
          characterForAgent(agentId),
          size: size,
          state: state,
          staggerKey: agentId,
          badge: badge,
        ),
      );
}
