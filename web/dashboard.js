// dashboard.js

// ——— Configuración de autorización HTTP (para stats) ———
const AUTH_HEADERS = {
  uid: localStorage.getItem('uid') || '',
  token: localStorage.getItem('token') || ''
};

// Helper para peticiones JSON
async function fetchJSON(url) {
  try {
    const res = await fetch(url, { headers: AUTH_HEADERS });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return await res.json();
  } catch (err) {
    console.warn(`Error al acceder a ${url}:`, err);
    return null;
  }
}

// ——— Estadísticas y gráfico de razas ———
// (idéntico al que ya tenías)
let raceChart;
function renderRaceChart(stats) { /* ... */ }
async function updateStats() { /* ... */ }

// ——— DOM Ready ———
document.addEventListener('DOMContentLoaded', () => {
  // Sidebar toggle, reloj, reinicio, log, etc...
  // …

  // ——— CHAT GLOBAL via WebSocket ———
  const chatLogEl   = document.getElementById('chat-log');
  const chatInput   = document.getElementById('chat-input');
  const chatSendBtn = document.getElementById('chat-send-btn');

  // Ajusta al host/puerto donde levantas chat_server.dart
  const wsProto = location.protocol === 'https:' ? 'wss' : 'ws';
  const chatHost = location.hostname;      // mismo host
  const chatPort = 8085;                   // ¡ojo, tu chat_server escucha en 8085!
  const wsChatUrl = `${wsProto}://${chatHost}:${chatPort}`;

  const wsChat = new WebSocket(wsChatUrl);

  // 1) Al abrir, hago el 'init' para que mi servidor registre el socket
  wsChat.addEventListener('open', () => {
    chatLogEl.textContent = '';            // limpio el <pre>
    chatSendBtn.disabled = false;          // habilito el input
    // ENVÍA init con uid y username
    wsChat.send(JSON.stringify({
      type: 'init',
      uid: localStorage.getItem('uid'),
      username: localStorage.getItem('username')  // o donde guardes tu nombre
    }));
  });

  // 2) Muestro cada mensaje entrante
  wsChat.addEventListener('message', ev => {
    const msg = JSON.parse(ev.data);
    if (msg.type === 'message') {
      const ts = new Date(msg.timestamp || msg.ts).toLocaleTimeString();
      chatLogEl.textContent += `[${ts}] <${msg.username}>: ${msg.message}\n`;
      chatLogEl.scrollTop = chatLogEl.scrollHeight;
    }
  });

  // 3) Errores / cierre
  wsChat.addEventListener('error', () => {
    chatLogEl.textContent += '\n― error de conexión chat ―';
    chatSendBtn.disabled = true;
  });
  wsChat.addEventListener('close', () => {
    chatLogEl.textContent += '\n― conexión chat cerrada ―';
    chatSendBtn.disabled = true;
  });

  // 4) Enviar mensaje por WS en vez de HTTP
  async function sendChatMessage() {
    const message = chatInput.value.trim();
    if (!message || wsChat.readyState !== WebSocket.OPEN) return;

    // Construyo el payload igual que tu servidor espera
    const payload = {
      type: 'message',
      uid: localStorage.getItem('uid'),
      username: localStorage.getItem('username'),
      message
    };
    wsChat.send(JSON.stringify(payload));
    chatInput.value = '';
    chatInput.focus();
  }

  // Eventos UI
  chatSendBtn.addEventListener('click', sendChatMessage);
  chatInput.addEventListener('keydown', e => {
    if (e.key === 'Enter') {
      e.preventDefault();
      sendChatMessage();
    }
  });

  // ——— Carga inicial de stats ———
  updateStats();
  setInterval(updateStats, 10000);
});
