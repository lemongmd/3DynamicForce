// Рендер песни BeepBox (JSON) в два WAV: вступление и петлю (для бесшовного повтора).
// Петля берётся со второго прохода: в её начале уже звучит хвост реверберации конца петли.
// Usage: node render_bb.mjs <beepbox esm index.js> song.json intro.wav loop.wav
import fs from "fs";
import { pathToFileURL } from "url";
const [, , libPath, songPath, introOut, loopOut] = process.argv;
const { Song, Synth } = await import(pathToFileURL(libPath).href);

const RATE = 44100;
const song = new Song();
song.fromJsonObject(JSON.parse(fs.readFileSync(songPath, "utf8")));
const synth = new Synth(song);
synth.samplesPerSecond = RATE;
synth.warmUpSynthesizer(song);
const perBar = synth.getSamplesPerBar();
const introLen = Math.round(perBar * song.loopStart);
const loopLen = Math.round(perBar * song.loopLength);
const total = introLen + loopLen * 2;
const L = new Float32Array(total), R = new Float32Array(total);
synth.synthesize(L, R, total, true);
console.log(`такт ${perBar} сэмплов, вступление ${(introLen / RATE).toFixed(3)} с, петля ${(loopLen / RATE).toFixed(3)} с`);

function wav(path, from, len) {
  const buf = Buffer.alloc(44 + len * 4);
  buf.write("RIFF", 0); buf.writeUInt32LE(36 + len * 4, 4); buf.write("WAVE", 8);
  buf.write("fmt ", 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22);
  buf.writeUInt32LE(RATE, 24); buf.writeUInt32LE(RATE * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34);
  buf.write("data", 36); buf.writeUInt32LE(len * 4, 40);
  let peak = 0;
  for (let i = 0; i < len; i++) {
    const l = Math.max(-1, Math.min(1, L[from + i])), r = Math.max(-1, Math.min(1, R[from + i]));
    peak = Math.max(peak, Math.abs(l), Math.abs(r));
    buf.writeInt16LE(Math.round(l * 32767), 44 + i * 4);
    buf.writeInt16LE(Math.round(r * 32767), 46 + i * 4);
  }
  fs.writeFileSync(path, buf);
  console.log(path, `пик ${(20 * Math.log10(peak)).toFixed(1)} дБ`);
}
wav(introOut, 0, introLen);
wav(loopOut, introLen + loopLen, loopLen);
