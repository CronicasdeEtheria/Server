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
  const chatLogEl = document.getElementById('chat-log');
  const wsChat = new WebSocket(`wss://${location.host}/ws/chat`);
  wsChat.onopen = () => chatLogEl.textContent = '';
  wsChat.onmessage = ev => {
    const { user, message, ts } = JSON.parse(ev.data);
    chatLogEl.textContent += `[${new Date(ts).toLocaleTimeString()}] <${user}>: ${message}\n`;
    chatLogEl.scrollTop = chatLogEl.scrollHeight;
  };
  wsChat.onerror = err => console.error('WS chat error', err);

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
