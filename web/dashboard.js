// Autorización
const AUTH_HEADERS = {
  uid: localStorage.getItem('uid') || '',
  token: localStorage.getItem('token') || ''
};

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

let raceChart;
function renderRaceChart(stats) {
  const labels = stats.map(r => r.race);
  const data   = stats.map(r => r.count);

  if (raceChart) {
    raceChart.data.labels = labels;
    raceChart.data.datasets[0].data = data;
    raceChart.update();
  } else {
    const ctx = document.getElementById('raceChart').getContext('2d');
    raceChart = new Chart(ctx, {
      type: 'doughnut',
      data: { labels, datasets: [{ data, backgroundColor: ['#e84118','#00a8ff','#9c88ff','#44bd32','#fbc531'] }] },
      options: {
        plugins: {
          legend: { position: 'right', labels: { boxWidth: 12, color: '#e0e0e0' } }
        }
      }
    });
  }
}

async function updateStats() {
  const [usersResp, onlineResp, timeResp, razaResp] = await Promise.all([
    fetchJSON('/admin/users'),
    fetchJSON('/admin/connected_users'),
    fetchJSON('/admin/server_time'),
    fetchJSON('/admin/raza_stats'),
  ]);

  const users = Array.isArray(usersResp?.users) ? usersResp.users : [];
  const online = Array.isArray(onlineResp?.users) ? onlineResp.users : [];

  // Hora servidor
  const timeEl = document.getElementById('clock');
  timeEl.textContent = timeResp?.server_time
    ? new Date(timeResp.server_time).toLocaleTimeString()
    : '--:--:--';

  // Tarjetas
  document.getElementById('total-users').textContent  = users.length;
  document.getElementById('online-users').textContent = online.length;

  // Top raza
  const rawRaza = Array.isArray(razaResp?.data) ? razaResp.data : [];
  if (rawRaza.length) {
    const top = rawRaza.reduce((a,b) => b.count > a.count ? b : a, rawRaza[0]);
    document.getElementById('top-race').textContent = `${top.race} (${top.count})`;
  }

  // Tabla usuarios
  const tbody = document.getElementById('user-table');
  tbody.innerHTML = users.map(u => {
    const isOnline = u.online===true || online.some(o=>o.uid===u.uid);
    return `
      <tr class="${isOnline?'online':'offline'}">
        <td>${u.uid}</td>
        <td>${u.username}</td>
        <td>${u.elo}</td>
        <td>${u.race}</td>
        <td>${u.guild||''}</td>
        <td><span class="${isOnline?'status-online':'status-offline'}">
          ${isOnline?'Online':'Offline'}
        </span></td>
      </tr>`;
  }).join('');

  renderRaceChart(rawRaza);
}

document.addEventListener('DOMContentLoaded', () => {
  // Toggle sidebar
  document.querySelectorAll('.toggle-btn').forEach(btn =>
    btn.addEventListener('click', () =>
      document.body.classList.toggle('sidebar-collapsed')
    )
  );

  // Reloj local
  setInterval(() => {
    const now = new Date();
    document.getElementById('clock').textContent = now.toLocaleTimeString();
  }, 1000);

  // Botón de reinicio (opcional)
  document.getElementById('btn-restart')?.addEventListener('click', async () => {
    if (!confirm('¿Reiniciar el servidor?')) return;
    const resp = await fetch('/admin/restart', { method:'POST', headers: AUTH_HEADERS });
    alert(resp.ok ? 'Servidor reiniciado.' : 'Error reiniciando.');
  });

 // ——— Chat Global via WS ———
const chatLogEl   = document.getElementById('chat-log');
const chatInput   = document.getElementById('chat-input');
const chatSendBtn = document.getElementById('chat-send-btn');

// 1) Determinar protocolo/host/puerto
const wsProto  = location.protocol === 'https:' ? 'wss' : 'ws';
const hostName = location.hostname;     // ej. "51.81.23.58"
const chatPort = 808;                   // donde corre tu chat_server.dart
const wsChat   = new WebSocket(`${wsProto}://${hostName}:${chatPort}`);

// 2) Al abrir, limpio log y envío INIT
wsChat.addEventListener('open', () => {
  chatLogEl.textContent = '';
  chatSendBtn.disabled = false;

  wsChat.send(JSON.stringify({
    type:     'init',
    uid:      'dashboard',    // o el UID que quieras
    username: 'Dashboard'
  }));
});

// 3) Al recibir mensaje, muestro sólo los de tipo 'message'
wsChat.addEventListener('message', ev => {
  const msg = JSON.parse(ev.data);
  if (msg.type === 'message') {
    const ts = new Date(msg.timestamp).toLocaleTimeString();
    chatLogEl.textContent += `[${ts}] <${msg.username}>: ${msg.message}\n`;
    chatLogEl.scrollTop = chatLogEl.scrollHeight;
  }
});

// 4) Errores / cierre
wsChat.addEventListener('error', () => {
  chatLogEl.textContent += '\n― error conexión chat ―';
  chatSendBtn.disabled = true;
});
wsChat.addEventListener('close', () => {
  chatLogEl.textContent += '\n― conexión chat cerrada ―';
  chatSendBtn.disabled = true;
});

// 5) Función para enviar mensaje por WS
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

// 6) Eventos de UI
chatSendBtn.addEventListener('click', sendChatMessage);
chatInput.addEventListener('keydown', e => {
  if (e.key === 'Enter') {
    e.preventDefault();
    sendChatMessage();
  }
});

  // ——— Log de Servidor via WS ———
const logPre = document.getElementById('server-log');
// Elige ws o wss según estés en HTTP o HTTPS
const wsProtocol = location.protocol === 'https:' ? 'wss' : 'ws';
// Si tu Shelf corre en el mismo host/puerto que el HTML:
const wsUrl = `${wsProtocol}://${location.host}/ws/log`;
// Si corre en otro puerto, por ejemplo 8081, usar:
// const wsUrl = `${wsProtocol}://${location.hostname}:8081/ws/log`;

const wsLog = new WebSocket(wsUrl);

wsLog.addEventListener('open', () => {
  logPre.textContent = '';  // limpia el mensaje inicial
});

wsLog.addEventListener('message', (evt) => {
  logPre.textContent += evt.data + '\n';
  logPre.scrollTop = logPre.scrollHeight;
});

wsLog.addEventListener('error', (err) => {
  console.error('Error WS log:', err);
  logPre.textContent += '\n― error de conexión al log ―';
});

wsLog.addEventListener('close', () => {
  logPre.textContent += '\n― conexión de log cerrada ―';
});

  // Carga inicial de estadísticas
  updateStats();
  setInterval(updateStats, 10000);
});
