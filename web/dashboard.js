// ——— Chat Global via WebSocket ———
const chatLogEl   = document.getElementById('chat-log');
const chatInput   = document.getElementById('chat-input');
const chatSendBtn = document.getElementById('chat-send-btn');

// Determinar protocolo y host/puerto
const wsProto = location.protocol === 'https:' ? 'wss' : 'ws';
const chatHost = location.hostname;  // mismo host
const chatPort = 808;                // el puerto donde corre chat_server.dart
const wsChat   = new WebSocket(`${wsProto}://${chatHost}:${chatPort}`);

// 1) Al abrir, limpio el log y envío el INIT
wsChat.addEventListener('open', () => {
  chatLogEl.textContent = '';
  chatSendBtn.disabled = false;

  wsChat.send(JSON.stringify({
    type:     'init',
    uid:      'dashboard',    // puedes cambiarlo si tienes otro UID
    username: 'Dashboard'     // idem para el nombre
  }));
});

// 2) Cada mensaje entrante
wsChat.addEventListener('message', ev => {
  const msg = JSON.parse(ev.data);
  if (msg.type === 'message') {
    const ts = new Date(msg.timestamp).toLocaleTimeString();
    chatLogEl.textContent += `[${ts}] <${msg.username}>: ${msg.message}\n`;
    chatLogEl.scrollTop = chatLogEl.scrollHeight;
  }
});

// 3) Errores y cierre
wsChat.addEventListener('error', err => {
  console.error('WS chat error', err);
  chatLogEl.textContent += '\n― error conexión chat ―';
  chatSendBtn.disabled = true;
});
wsChat.addEventListener('close', () => {
  chatLogEl.textContent += '\n― conexión chat cerrada ―';
  chatSendBtn.disabled = true;
});

// 4) Función para enviar un mensaje
function sendChatMessage() {
  const text = chatInput.value.trim();
  if (!text || wsChat.readyState !== WebSocket.OPEN) return;

  wsChat.send(JSON.stringify({
    type:     'message',
    uid:      'dashboard',
    username: 'Dashboard',
    message:  text
  }));

  chatInput.value = '';
  chatInput.focus();
}

// 5) Eventos de UI
chatSendBtn.addEventListener('click', sendChatMessage);
chatInput.addEventListener('keydown', e => {
  if (e.key === 'Enter') {
    e.preventDefault();
    sendChatMessage();
  }
});
