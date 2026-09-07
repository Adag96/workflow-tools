// Offscreen document for playing sounds via Audio elements (more reliable than Web Audio API)

let volume = 0.7;

chrome.runtime.onMessage.addListener((msg) => {
  if (msg.action === 'playSound') {
    playFile(msg.file || 'focus-complete.wav', msg.volume);
  } else if (msg.action === 'setVolume') {
    volume = msg.volume;
  }
});

function playFile(filename, vol) {
  const v = vol !== undefined ? vol : volume;
  const audio = new Audio(chrome.runtime.getURL(`sounds/${filename}`));
  audio.volume = Math.max(0, Math.min(1, v));
  audio.play().catch(e => console.error('Audio play failed:', e));
}
