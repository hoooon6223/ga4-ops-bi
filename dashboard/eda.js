const fmt = new Intl.NumberFormat("en-US");
const compact = new Intl.NumberFormat("en-US", { notation: "compact", maximumFractionDigits: 1 });
const state = { month: "All", metric: "revenue", grain: "daily", selectedDate: null };
const metricMeta = {
  revenue: { label: "Revenue", format: (v) => `$${compact.format(v)}` },
  sessions: { label: "Sessions", format: (v) => compact.format(v) },
  session_cvr: { label: "Session CVR", format: (v) => `${(v * 100).toFixed(2)}%` },
  aov: { label: "AOV", format: (v) => `$${v.toFixed(2)}` },
};

function parseCsv(text) {
  const [headerLine, ...lines] = text.trim().split(/\r?\n/);
  const headers = headerLine.split(",");
  return lines.map((line) => {
    const values = line.split(",");
    return Object.fromEntries(headers.map((h, i) => {
      const raw = values[i] ?? "";
      const n = Number(raw);
      return [h, raw !== "" && Number.isFinite(n) ? n : raw];
    }));
  });
}

async function loadRows() {
  const res = await fetch("../data/daily_kpi_mart.csv");
  return parseCsv(await res.text());
}

function monthOf(date) {
  return String(date).slice(0, 7);
}

function rowsForMonth(rows) {
  return state.month === "All" ? rows : rows.filter((r) => monthOf(r.date) === state.month);
}

function weekStart(date) {
  const d = new Date(`${date}T00:00:00`);
  const day = d.getDay();
  d.setDate(d.getDate() - day);
  return d.toISOString().slice(0, 10);
}

function weeklyRows(rows) {
  const grouped = new Map();
  rows.forEach((row) => {
    const key = weekStart(row.date);
    const current = grouped.get(key) ?? {
      date: key,
      label: `${key} week`,
      sessions: 0,
      orders: 0,
      revenue: 0,
      purchase_sessions: 0,
    };
    current.sessions += row.sessions;
    current.orders += row.orders;
    current.revenue += row.revenue;
    current.purchase_sessions += row.purchase_sessions;
    grouped.set(key, current);
  });
  return [...grouped.values()].sort((a, b) => a.date.localeCompare(b.date)).map((row) => ({
    ...row,
    session_cvr: row.sessions ? row.purchase_sessions / row.sessions : 0,
    aov: row.purchase_sessions ? row.revenue / row.purchase_sessions : 0,
  }));
}

function rolling(rows, metric, window = 7) {
  return rows.map((row, i) => {
    const start = Math.max(0, i - window + 1);
    const slice = rows.slice(start, i + 1);
    return { ...row, ma: slice.reduce((s, r) => s + Number(r[metric] || 0), 0) / slice.length };
  });
}

function aggregate(rows) {
  const total = rows.reduce((a, r) => {
    a.sessions += r.sessions;
    a.orders += r.orders;
    a.revenue += r.revenue;
    a.purchase_sessions += r.purchase_sessions;
    return a;
  }, { sessions: 0, orders: 0, revenue: 0, purchase_sessions: 0 });
  return {
    ...total,
    session_cvr: total.sessions ? total.purchase_sessions / total.sessions : 0,
    aov: total.purchase_sessions ? total.revenue / total.purchase_sessions : 0,
  };
}

function renderKpis(rows) {
  const a = aggregate(rows);
  const cards = [
    ["Revenue", `$${fmt.format(Math.round(a.revenue))}`],
    ["Sessions", fmt.format(a.sessions)],
    ["Orders", fmt.format(a.orders)],
    ["Session CVR", `${(a.session_cvr * 100).toFixed(2)}%`],
    ["AOV", `$${a.aov.toFixed(2)}`],
  ];
  document.querySelector("#eda-kpis").innerHTML = cards.map(([k, v]) => `
    <article class="eda-kpi"><span>${k}</span><strong>${v}</strong></article>
  `).join("");
}

function lineChart(target, rows, metric, withAverage = true, options = {}) {
  const data = withAverage ? rolling(rows, metric, options.window ?? 7) : rows.map((row) => ({ ...row, ma: row[metric] }));
  const w = 940, h = options.height ?? 340, p = { t: 34, r: 56, b: 42, l: 64 };
  const vals = data.flatMap((r) => withAverage ? [r[metric], r.ma] : [r[metric]]);
  const max = Math.max(0.001, ...vals) * 1.1;
  const min = Math.min(0, ...vals) * 0.95;
  const x = (i) => p.l + (i * (w - p.l - p.r)) / Math.max(1, data.length - 1);
  const y = (v) => p.t + ((max - v) / (max - min)) * (h - p.t - p.b);
  const points = data.map((r, i) => `${x(i)},${y(r[metric])}`).join(" ");
  const avg = data.map((r, i) => `${x(i)},${y(r.ma)}`).join(" ");
  const ticks = data.filter((r, i) => {
    if (state.grain === "weekly") return i === 0 || i === data.length - 1 || i % 2 === 0;
    return i === 0 || r.date.endsWith("-15") || i === data.length - 1;
  });
  const yTicks = [0, 0.25, 0.5, 0.75, 1].map((ratio) => min + (max - min) * ratio);
  const last = data[data.length - 1];
  const high = data.reduce((best, row) => Number(row[metric]) > Number(best[metric]) ? row : best, data[0]);
  const low = data.reduce((best, row) => Number(row[metric]) < Number(best[metric]) ? row : best, data[0]);
  const format = metricMeta[metric].format;
  document.querySelector(target).innerHTML = `
    <svg viewBox="0 0 ${w} ${h}" role="img" aria-label="${metricMeta[metric].label} trend">
      ${yTicks.map((v) => {
        const yy = y(v);
        return `
          <line x1="${p.l}" y1="${yy}" x2="${w-p.r}" y2="${yy}" stroke="#e8ecf3" />
          <text class="axis y-axis" x="${p.l - 10}" y="${yy + 4}" text-anchor="end">${format(v)}</text>
        `;
      }).join("")}
      <polyline points="${points}" fill="none" stroke="#2f6df6" stroke-width="3.5" stroke-linejoin="round" stroke-linecap="round" />
      ${withAverage ? `<polyline points="${avg}" fill="none" stroke="#ee5b5b" stroke-width="2.5" stroke-dasharray="7 7" stroke-linejoin="round" stroke-linecap="round" />` : ""}
      ${data.map((r, i) => `<circle class="point" data-date="${r.date}" cx="${x(i)}" cy="${y(r[metric])}" r="${options.compact ? 3 : 5}" fill="#fff" stroke="#2f6df6" stroke-width="2" />`).join("")}
      ${options.compact ? "" : `
        <g class="value-label">
          <line x1="${x(data.indexOf(last))}" y1="${y(last[metric])}" x2="${x(data.indexOf(last)) + 18}" y2="${y(last[metric]) - 18}" stroke="#8b95a5" />
          <text x="${x(data.indexOf(last)) + 22}" y="${y(last[metric]) - 20}">Last ${format(last[metric])}</text>
        </g>
        <text class="extreme-label high" x="${x(data.indexOf(high))}" y="${Math.max(14, y(high[metric]) - 10)}" text-anchor="middle">Max ${format(high[metric])}</text>
        <text class="extreme-label low" x="${x(data.indexOf(low))}" y="${Math.min(h - p.b - 8, y(low[metric]) + 18)}" text-anchor="middle">Min ${format(low[metric])}</text>
      `}
      ${ticks.map((r) => `<text class="axis" x="${x(data.indexOf(r))}" y="${h-8}" text-anchor="middle">${r.date}</text>`).join("")}
    </svg>
  `;
  document.querySelectorAll(`${target} .point`).forEach((pnt) => {
    pnt.addEventListener("click", () => {
      state.selectedDate = pnt.dataset.date;
      render(globalRows);
    });
  });
}

function renderDetail(rows) {
  const row = rows.find((r) => r.date === state.selectedDate) || rows[rows.length - 1];
  state.selectedDate = row.date;
  document.querySelector("#day-detail").innerHTML = `
    <div class="selected-date">${row.date}</div>
    <dl>
      <div><dt>Revenue</dt><dd>$${fmt.format(row.revenue)}</dd></div>
      <div><dt>Sessions</dt><dd>${fmt.format(row.sessions)}</dd></div>
      <div><dt>CVR</dt><dd>${(row.session_cvr * 100).toFixed(2)}%</dd></div>
      <div><dt>AOV</dt><dd>$${row.aov.toFixed(2)}</dd></div>
    </dl>
  `;
}

function renderDrivers(rows) {
  const metrics = ["sessions", "session_cvr", "aov"];
  document.querySelector("#driver-sparklines").innerHTML = metrics.map((m) => `
    <div class="spark-card">
      <span>${metricMeta[m].label}</span>
      <div id="spark-${m}" class="spark"></div>
    </div>
  `).join("");
  metrics.forEach((m) => lineChart(`#spark-${m}`, rows, m, false, { compact: true, height: 86 }));
}

function renderWeekday(rows) {
  const names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  const grouped = names.map((name) => ({ name, sum: 0, n: 0 }));
  rows.forEach((r) => {
    const d = new Date(`${r.date}T00:00:00`).getDay();
    grouped[d].sum += r.revenue;
    grouped[d].n += 1;
  });
  const avg = grouped.map((g) => ({ ...g, avg: g.n ? g.sum / g.n : 0 }));
  const max = Math.max(...avg.map((g) => g.avg), 1);
  document.querySelector("#weekday-bars").innerHTML = avg.map((g) => `
    <div class="weekday-row">
      <span>${g.name}</span>
      <div><i style="width:${(g.avg / max) * 100}%"></i></div>
      <b>$${compact.format(g.avg)}</b>
    </div>
  `).join("");
}

function render(rows) {
  const dailyScoped = rowsForMonth(rows);
  const scoped = state.grain === "weekly" ? weeklyRows(dailyScoped) : dailyScoped;
  renderKpis(scoped);
  lineChart("#main-trend", scoped, state.metric, state.grain === "daily", {
    window: state.grain === "daily" ? 7 : 3,
  });
  renderDetail(scoped);
  renderDrivers(scoped);
  renderWeekday(dailyScoped);
  document.querySelector("#trend-caption").textContent =
    state.grain === "daily" ? "실선은 일별 지표, 점선은 7일 이동평균" : "주별 합산/재계산 지표. CVR과 AOV는 주 단위로 다시 계산";
  document.querySelector("#month-select").value = state.month;
  document.querySelectorAll(".grain-switch button").forEach((b) => b.classList.toggle("active", b.dataset.grain === state.grain));
  document.querySelectorAll(".metric-switch button").forEach((b) => b.classList.toggle("active", b.dataset.metric === state.metric));
}

function bind(rows) {
  const months = ["All", ...new Set(rows.map((r) => monthOf(r.date)))];
  document.querySelector("#month-select").innerHTML = months.map((m) => `<option>${m}</option>`).join("");
  document.querySelector("#month-select").addEventListener("change", (e) => {
    state.month = e.target.value;
    state.selectedDate = null;
    render(rows);
  });
  document.querySelector("#metric-switch").innerHTML = Object.entries(metricMeta).map(([key, meta]) => `
    <button data-metric="${key}" type="button">${meta.label}</button>
  `).join("");
  document.querySelector("#grain-switch").innerHTML = `
    <button data-grain="daily" type="button">Daily</button>
    <button data-grain="weekly" type="button">Weekly</button>
  `;
  document.querySelectorAll(".grain-switch button").forEach((button) => {
    button.addEventListener("click", () => {
      state.grain = button.dataset.grain;
      state.selectedDate = null;
      render(rows);
    });
  });
  document.querySelectorAll(".metric-switch button").forEach((button) => {
    button.addEventListener("click", () => {
      state.metric = button.dataset.metric;
      render(rows);
    });
  });
}

let globalRows = [];
loadRows().then((rows) => {
  globalRows = rows;
  bind(rows);
  render(rows);
}).catch((err) => {
  document.body.innerHTML = `<pre>${err.stack}</pre>`;
});
