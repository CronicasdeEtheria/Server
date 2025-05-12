// ---------------------------------------------
// dashboard.js
// ---------------------------------------------

// Si tienes auth, rellena estos valores antes de arrancar:
// localStorage.setItem('uid','TU_UID');
// localStorage.setItem('token','TU_TOKEN');
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
    raceChart.data.labels   = labels;
    raceChart.data.datasets[0].data = data;
    raceChart.update();
  } else {
    const ctx = document.getElementById('raceChart').getContext('2d');
    raceChart = new Chart(ctx, {
      type: 'doughnut',
      data: {
        labels,
        datasets: [{
          data,
          backgroundColor: ['#e84118','#00a8ff','#9c88ff','#44bd32','#fbc531']
        }]
      },
      options: {
        plugins: {
          legend: { position: 'right', labels: { boxWidth: 12 } }
        }
      }
    });
  }
}

async function updateStats() {
  // 1) Disparamos las 4 peticiones en paralelo
  const [usersResp, onlineResp, timeResp, razaResp] = await Promise.all([
    fetchJSON('/admin/users'),
    fetchJSON('/admin/connected_users'),
    fetchJSON('/admin/server_time'),
    fetchJSON('/admin/raza_stats'),     // <— aquí la corrección
  ]);

  // 2) Extraer arrays reales
  const users = Array.isArray(usersResp?.users) ? usersResp.users : [];
  const online = Array.isArray(onlineResp?.users) ? onlineResp.users : [];

  // 3) Hora
  const timeEl = document.getElementById('server-time');
  if (timeResp?.server_time) {
    timeEl.textContent = new Date(timeResp.server_time).toLocaleString();
  } else {
    timeEl.textContent = '—';
  }

  // 4) Actualizar tarjetas
  document.getElementById('total-users').textContent  = users.length;
  document.getElementById('online-users').textContent = online.length;

  // 5) Raza más común
  //    tu endpoint devuelve { success: true, data: [...] }
  const rawRaza = Array.isArray(razaResp?.data) ? razaResp.data : [];
  if (rawRaza.length) {
    // reducir para encontrar el mayor
    const top = rawRaza.reduce((prev, cur) =>
      cur.count > prev.count ? cur : prev
    , rawRaza[0]);
    document.getElementById('top-race').textContent =
      `${top.race} (${top.count})`;
  } else {
    document.getElementById('top-race').textContent = '—';
  }

  // 6) Tabla de usuarios
  const tbody = document.getElementById('user-table');
  tbody.innerHTML = users.map(u => {
    // si tu JSON ya trae u.online, lo usamos; si no, fallback a buscar en online[]
    const isOnline = u.online === true || online.some(o => o.uid === u.uid);
    return `
      <tr class="${isOnline ? 'online':'offline'}">
        <td>${u.uid}</td>
        <td>${u.username}</td>
        <td>${u.email}</td>
        <td>${u.elo}</td>
        <td>${u.race}</td>
        <td>${u.guild||''}</td>
        <td>
          <span class="${isOnline?'status-online':'status-offline'}">
            ${isOnline?'Online':'Offline'}
          </span>
        </td>
      </tr>
    `;
  }).join('');

  // 7) Finalmente, renderizamos el doughnut
  renderRaceChart(rawRaza);
}
// —————— Controles de servidor ——————
async function fetchServerLog() {
  const log = await fetchJSON('/admin/log');
  document.getElementById('server-log').textContent =
    Array.isArray(log?.lines) ? log.lines.join('\n') : 'Error cargando log.';
}
document.getElementById('btn-refresh-log')
  .addEventListener('click', fetchServerLog);
fetchServerLog(); // carga inicial

document.getElementById('btn-restart')
  .addEventListener('click', async () => {
    if (!confirm('¿Reiniciar el servidor?')) return;
    const resp = await fetch('/admin/restart', {
      method: 'POST', headers: AUTH_HEADERS
    });
    alert(resp.ok ? 'Servidor reiniciado.' : 'Error reiniciando.');
});

// —————— Chat global via WebSocket ——————
const chatLogEl = document.getElementById('chat-log');
const ws = new WebSocket(`wss://${location.host}/ws/chat`);
ws.onmessage = ev => {
  const { user, message, ts } = JSON.parse(ev.data);
  const line = `[${new Date(ts).toLocaleTimeString()}] <${user}>: ${message}`;
  chatLogEl.textContent += line + '\n';
  chatLogEl.scrollTop = chatLogEl.scrollHeight;
};
ws.onopen = () => chatLogEl.textContent = 'Conectado al chat.\n';
ws.onerror = () => chatLogEl.textContent += 'Error en WebSocket.\n';

document.getElementById('btn-broadcast')
  .addEventListener('click', async () => {
    const msg = document.getElementById('broadcast-input').value.trim();
    if (!msg) return;
    await fetch('/admin/broadcast', {
      method: 'POST',
      headers: {...AUTH_HEADERS, 'Content-Type':'application/json'},
      body: JSON.stringify({ message: msg })
    });
    document.getElementById('broadcast-input').value = '';
  });

// Primera carga y refresco cada 10 segundos
updateStats();
setInterval(updateStats, 10000);
