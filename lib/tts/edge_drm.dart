import 'dart:typed_data';

/// The `Sec-MS-GEC` token Microsoft's readaloud endpoint demands, version 2.
///
/// Version 1 was a plain SHA-256 of the time and the client token. Microsoft
/// now answers that with HTTP 403 on both the WebSocket and the voice list, so
/// Edge stopped working in the app while the service itself was fine. Version 2
/// is `<CS64>-<SHA256>`, where the SHA-256 is a deliberately non-standard
/// variant and CS64 is a checksum over the same bytes.
///
/// This is a line-by-line port of `src/edge_tts/drm.py` in rany2/edge-tts
/// (7.3.1), which is the source of truth: the constants below are copied from
/// it and must not be "tidied". Dart ints are 64-bit and wrap, so every
/// 32x32-bit product keeps its correct low 32 bits and is masked after.
const edgeSecMsGecVersionPrefix = '2-';

const _winEpoch = 11644473600;
const _mask = 0xFFFFFFFF;

const _sha256Initial = <int>[
  0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
  0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
];
const _sha256State = <int>[
  0xFD9FBEA2, 0x91243CE7, 0xBE499094, 0xCD2E1E0A,
  0x6C006F49, 0x04BD35AB, 0xFEB0A7E4, 0x03EFFBD2,
];
const _sha256Schedule = <int>[
  0xEB24BF9E, 0x1558691F, 0xA0C09EE2, 0x0CFA32BA, 0xA622EE8C, 0xD1DD9491,
  0xC0DD25A0, 0xF9E70AB6, 0xF0C31573, 0x7058CE4E, 0x7188E606, 0x00E5AB33,
  0xD258B060, 0x72766564,
];
const _roundConstants = <int>[
  0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1,
  0x923F82A4, 0xAB1C5ED5, 0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3,
  0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174, 0xE49B69C1, 0xEFBE4786,
  0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
  0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147,
  0x06CA6351, 0x14292967, 0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
  0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85, 0xA2BFE8A1, 0xA81A664B,
  0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
  0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A,
  0x5B9CCA4F, 0x682E6FF3, 0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208,
  0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
];
const _adjustment = 0xC9DC06A7;
const _sigma0Adjustment = 0x059C0B80;
const _sigma1Adjustment = 0x000B92C0;

/// The first block resumes at round 14 with this one constant swapped.
final _blockConstants = <int>[
  ..._roundConstants.sublist(0, 14),
  _adjustment,
  ..._roundConstants.sublist(15),
];

const _cs64Coefficients = <List<int>>[
  [0xE82E91B1, 0xB32700D0], [0x44DE24C6, 0x88DFF51D],
  [0x3BEB65BC, 0x29514038], [0xC89C5933, 0xB328CBDF],
  [0x8D1EC211, 0xD405B4D5], [0x314EF5D5, 0x26E55F3C],
  [0xE92491B1, 0x607801C6], [0xF0A5B9D5, 0x82B2C1FB],
  [0x06064CF3, 0xFA51A3DA], [0xDA79FA60, 0x207CC464],
  [0xBED20560, 0x3C3C74F3], [0x89F9C9F8, 0xD2D14B61],
  [0x35FA38C6, 0xBB04A2C1], [0xCB49E3C6, 0xC5626167],
];
const _cs64Factor = 0x82893933;
const _cs64Adjustment0 = 0xF2F90B1A;
const _cs64Adjustment1 = 0x0B1A0000;

int _rol16(int v) {
  v &= _mask;
  return ((v << 16) | (v >> 16)) & _mask;
}

int _rotr(int v, int n) => ((v >> n) | (v << (32 - n))) & _mask;

int _sigma0(int v) =>
    ((v >> 7) ^ (v << 25) ^ (v >> 18) ^ (v << 14) ^ (v >> 3)) & _mask;

int _sigma1(int v) =>
    ((v >> 17) ^ (v << 15) ^ (v >> 19) ^ (v << 13) ^ (v >> 10)) & _mask;

/// Little-endian 32-bit words, zero-padded to a multiple of 4 bytes and then
/// to an even number of words.
List<int> _wordsLe4Even(Uint8List data) {
  final padded = Uint8List((data.length + 3) ~/ 4 * 4)..setAll(0, data);
  final view = ByteData.sublistView(padded);
  final words = <int>[
    for (var i = 0; i < padded.length; i += 4) view.getUint32(i, Endian.little),
  ];
  if (words.length.isOdd) words.add(0);
  return words;
}

/// Standard SHA-256 rounds from [firstRound] to 63, over the given state.
List<int> _sha256Rounds(List<int> state, List<int> words, int firstRound) {
  final k = firstRound == 14 ? _blockConstants : _roundConstants;
  var a = state[0], b = state[1], c = state[2], d = state[3];
  var e = state[4], f = state[5], g = state[6], h = state[7];
  for (var i = firstRound; i < 64; i++) {
    final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
    final ch = g ^ (e & (f ^ g));
    final t1 = h + s1 + ch + k[i] + words[i];
    final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
    final maj = (a & b) | (c & (a | b));
    final t2 = s0 + maj;
    h = g;
    g = f;
    f = e;
    e = (d + t1) & _mask;
    d = c;
    c = b;
    b = a;
    a = (t1 + t2) & _mask;
  }
  return [a, b, c, d, e, f, g, h];
}

/// Extends [words] in place up to 64 entries, starting at index [first].
void _expandSchedule(List<int> words, int first) {
  for (var i = first; i < 64; i++) {
    final x = words[i - 2], y = words[i - 15];
    final s1 = (x >> 17) ^ (x << 15) ^ (x >> 19) ^ (x << 13) ^ (x >> 10);
    final s0 = (y >> 7) ^ (y << 25) ^ (y >> 18) ^ (y << 14) ^ (y >> 3);
    words.add((s1 + words[i - 7] + s0 + words[i - 16]) & _mask);
  }
}

int _beInt(Uint8List b, int start, int end) {
  var v = 0;
  for (var i = start; i < end; i++) {
    v = (v << 8) | b[i];
  }
  return v;
}

/// State after the first seven bytes, which the digest handles on their own.
List<int> _sha256Init(Uint8List first7) {
  final words = <int>[...List.filled(14, 0), _beInt(first7, 0, 3), _beInt(first7, 3, 7)];
  for (var index = 16; index < 30; index++) {
    var value = _sha256Schedule[index - 16];
    if (index - 2 >= 14) {
      value += index == 16
          ? (_sigma1(words[index - 2]) ^ _sigma1Adjustment)
          : _sigma1(words[index - 2]);
    }
    if (index - 7 >= 14) value += words[index - 7];
    if (index - 15 >= 14) {
      value += index == 29
          ? (_sigma0(words[index - 15]) ^ _sigma0Adjustment)
          : _sigma0(words[index - 15]);
    }
    words.add(value & _mask);
  }
  words.add((_sigma1(words[28]) +
          words[23] +
          _sigma0(words[15]) +
          words[14] +
          _adjustment -
          _roundConstants[14]) &
      _mask);
  _expandSchedule(words, 31);
  final working = _sha256Rounds(_sha256State, words, 14);
  return [for (var i = 0; i < 8; i++) (_sha256Initial[i] + working[i]) & _mask];
}

Uint8List _sha256Digest(Uint8List data) {
  if (data.length < 7) {
    throw ArgumentError('Token salt must contain at least seven bytes');
  }
  final length = 57 + data.length;
  final padLen = (55 - length) % 64; // Dart's % is never negative here
  final padded = BytesBuilder()
    ..add(data.sublist(7))
    ..addByte(0x80)
    ..add(Uint8List(padLen));
  final tail = ByteData(8)..setUint64(0, length * 8, Endian.big);
  padded.add(tail.buffer.asUint8List());
  final bytes = padded.takeBytes();

  var state = _sha256Init(Uint8List.sublistView(data, 0, 7));
  final view = ByteData.sublistView(bytes);
  for (var offset = 0; offset < bytes.length; offset += 64) {
    final words = <int>[
      for (var i = 0; i < 16; i++) view.getUint32(offset + i * 4, Endian.big),
    ];
    _expandSchedule(words, 16);
    final working = _sha256Rounds(state, words, 0);
    state = [for (var i = 0; i < 8; i++) (state[i] + working[i]) & _mask];
  }
  final out = ByteData(32);
  for (var i = 0; i < 8; i++) {
    out.setUint32(i * 4, state[i], Endian.big);
  }
  return out.buffer.asUint8List();
}

/// The two 32-bit CS64 words for [data], keyed by the first 8 digest bytes.
(int, int) _cs64Digest(Uint8List data, Uint8List digest) {
  final dv = ByteData.sublistView(digest);
  final keyA = dv.getUint32(0, Endian.little) | 1;
  final keyB = dv.getUint32(4, Endian.little) | 1;
  final factors = [(keyA * _cs64Factor) & _mask, (keyB * _cs64Factor) & _mask];

  final terms = <int>[
    for (var i = 0; i < _cs64Coefficients.length; i++)
      (_cs64Coefficients[i][0] * factors[i % 2]) & _mask,
  ];
  final offsets = <int>[for (final c in _cs64Coefficients) c[1]];

  final prefixed = Uint8List(data.length + 1)..setAll(1, data);
  final words = _wordsLe4Even(prefixed);
  for (var index = 0; index < words.length; index++) {
    final word = words[index];
    var term = word * (index.isEven ? keyA : keyB);
    var offset = _rol16(word) * (index.isEven ? 0xEF0569FB : 0xC31713DB);
    if (index == 0) {
      term += _cs64Adjustment0 * factors[0];
      offset += _cs64Adjustment1;
    }
    terms.add(term & _mask);
    offsets.add(offset & _mask);
  }

  var swapAcc = 0, swapLast = 0, state = 0, acc = 0;
  for (var i = 0; i < terms.length; i += 2) {
    final x = terms[i], y = terms[i + 1];
    var t = _rol16((offsets[i] + x) & _mask);
    var q = (t * 0x76F50F34) & _mask;
    swapAcc += (_rol16(q) * 0xC3EFEA97 + q) & _mask;
    t = _rol16((offsets[i + 1] + y) & _mask);
    q = (t * 0x1881CE3C) & _mask;
    swapLast = (_rol16(q) * 0x35BD1EC9 + q) & _mask;
    swapAcc = (swapAcc + swapLast) & _mask;

    state = (state * keyA + x) & _mask;
    state = (_rol16(state) * 0xCF98B111) & _mask;
    state = (_rol16(state) * 0x87085B9F) & _mask;
    state = (_rol16(state) * 0x12CEB96D) & _mask;
    state = (_rol16(state) * 0x257E1D83) & _mask;
    acc += state;
    t = (state * keyB + y) & _mask;
    t = (_rol16(t) * 0xA27416F5) & _mask;
    t = (_rol16(t) * 0xD38396FF) & _mask;
    state = (_rol16((_rol16(t) * 0x7C932B89) & _mask) * 0xBFA49F69) & _mask;
    acc = (acc + state) & _mask;
  }
  return (swapLast ^ state, swapAcc ^ acc);
}

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

/// `Sec-MS-GEC` for the given Unix time in seconds (already skew-corrected).
///
/// The time is shifted to the Windows file-time epoch, rounded down to five
/// minutes and expressed in 100 ns ticks, then hashed together with the
/// trusted client token.
String generateSecMsGec(double unixSeconds, String trustedClientToken) {
  var ticks = unixSeconds + _winEpoch;
  ticks -= ticks % 300;
  ticks *= 10000000;
  final data = Uint8List.fromList(
      '${ticks.toStringAsFixed(0)}$trustedClientToken'.codeUnits);

  final digest = _sha256Digest(data);
  final (a, b) = _cs64Digest(data, digest);
  final cs64 = ByteData(8)
    ..setUint32(0, a, Endian.little)
    ..setUint32(4, b, Endian.little);
  return '${_hex(cs64.buffer.asUint8List())}-${_hex(digest)}';
}
