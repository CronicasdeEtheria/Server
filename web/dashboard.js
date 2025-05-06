// Cabeceras de autenticación
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
async function updateRaceChart() {
  const stats = await fetchJSON('/admin/raza_stats');
  if (!stats) return;
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
      data: {
        labels,
        datasets: [{ data, backgroundColor: ['#e84118','#00a8ff','#9c88ff','#44bd32','#fbc531'] }]
      },
      options: { plugins: { legend: { position: 'right', labels: { boxWidth: 12 } } } }
    });
  }
}

async function updateStats() {
  const [users, online, time] = await Promise.all([
    fetchJSON('/admin/users'),
    fetchJSON('/admin/connected_users'),
    fetchJSON('/admin/server_time')
  ]);
  if (!users || !online || !time) return;

  document.getElementById('total-users').textContent  = users.length;
  document.getElementById('online-users').textContent = online.length;
  document.getElementById('server-time').textContent  =
    new Date(time.server_time).toLocaleString();

  const tbody = document.getElementById('user-table');
  tbody.innerHTML = online.map(u => `
    <tr>
      <td>${u.uid}</td>
      <td>${u.username}</td>
      <td>${u.email}</td>
      <td>${u.elo}</td>
      <td>${u.race}</td>
      <td>${u.guild || ''}</td>
    </tr>
  `).join('');

  await updateRaceChart();
}

// Primera carga y refresco cada 10s
updateStats();
setInterval(updateStats, 10000);
