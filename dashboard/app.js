const numberFmt = new Intl.NumberFormat("en-US");
const compactFmt = new Intl.NumberFormat("en-US", {
  notation: "compact",
  maximumFractionDigits: 1,
});

const money = (value) => `$${compactFmt.format(value)}`;
const fixedMoney = (value) => `$${Number(value).toFixed(2)}`;
const pct = (value) => `${(value * 100).toFixed(2)}%`;
const pp = (value) => `${value >= 0 ? "+" : ""}${(value * 100).toFixed(2)}pp`;
const mom = (value) => `${value >= 0 ? "+" : ""}${(value * 100).toFixed(1)}%`;

function parseCsv(text) {
  const [headerLine, ...lines] = text.trim().split(/\r?\n/);
  const headers = headerLine.split(",");
  return lines.map((line) => {
    const values = line.split(",");
    return Object.fromEntries(
      headers.map((header, index) => {
        const raw = values[index] ?? "";
        const numeric = Number(raw);
        return [header, raw !== "" && Number.isFinite(numeric) ? numeric : raw];
      }),
    );
  });
}

async function loadCsv(path) {
  const response = await fetch(path);
  if (!response.ok) throw new Error(`Unable to load ${path}`);
  return parseCsv(await response.text());
}

function monthKey(date) {
  return String(date).slice(0, 7);
}

function renderKpis(current, previous) {
  const cards = [
    {
      label: "Revenue",
      value: money(current.revenue),
      delta: mom((current.revenue - previous.revenue) / previous.revenue),
    },
    {
      label: "Sessions",
      value: compactFmt.format(current.sessions),
      delta: mom((current.sessions - previous.sessions) / previous.sessions),
    },
    {
      label: "Session CVR",
      value: pct(current.session_cvr),
      delta: pp(current.session_cvr - previous.session_cvr),
    },
    {
      label: "AOV",
      value: fixedMoney(current.aov),
      delta: mom((current.aov - previous.aov) / previous.aov),
    },
    {
      label: "Revenue / Session",
      value: fixedMoney(current.revenue_per_session),
      delta: mom(
        (current.revenue_per_session - previous.revenue_per_session) /
          previous.revenue_per_session,
      ),
    },
  ];

  document.querySelector("#kpi-grid").innerHTML = cards
    .map(
      (card) => `
        <article class="metric-card">
          <span>${card.label}</span>
          <strong>${card.value}</strong>
          <em>${card.delta} MoM</em>
        </article>
      `,
    )
    .join("");
}

function renderLineChart(target, rows, metric, options = {}) {
  const width = 640;
  const height = options.height ?? 220;
  const pad = { top: 16, right: 18, bottom: 30, left: 42 };
  const values = rows.map((row) => Number(row[metric]));
  const min = Math.min(0, ...values) * 0.96;
  const max = Math.max(...values) * 1.08;
  const xStep = (width - pad.left - pad.right) / (rows.length - 1);
  const y = (value) =>
    pad.top + ((max - value) / (max - min)) * (height - pad.top - pad.bottom);
  const x = (index) => pad.left + index * xStep;
  const points = rows.map((row, index) => `${x(index)},${y(row[metric])}`).join(" ");
  const fillPoints = `${pad.left},${height - pad.bottom} ${points} ${
    width - pad.right
  },${height - pad.bottom}`;
  const monthTicks = rows.filter((row) => row.date.endsWith("-01"));

  document.querySelector(target).innerHTML = `
    <svg viewBox="0 0 ${width} ${height}" role="img" aria-label="${metric} trend chart">
      <defs>
        <linearGradient id="${metric}-area" x1="0" x2="0" y1="0" y2="1">
          <stop offset="0%" stop-color="#2f6df6" stop-opacity="0.22" />
          <stop offset="100%" stop-color="#2f6df6" stop-opacity="0.02" />
        </linearGradient>
      </defs>
      ${[0.25, 0.5, 0.75].map((ratio) => {
        const yy = pad.top + (height - pad.top - pad.bottom) * ratio;
        return `<line x1="${pad.left}" y1="${yy}" x2="${width - pad.right}" y2="${yy}" stroke="#edf1f7" />`;
      }).join("")}
      <polygon points="${fillPoints}" fill="url(#${metric}-area)" />
      <polyline points="${points}" fill="none" stroke="#2f6df6" stroke-width="4" stroke-linecap="round" stroke-linejoin="round" />
      ${monthTicks.map((row) => {
        const index = rows.indexOf(row);
        return `<text class="axis" x="${x(index)}" y="${height - 8}" text-anchor="middle">${monthKey(row.date)}</text>`;
      }).join("")}
      <text class="axis" x="${pad.left}" y="12">${options.formatMax ? options.formatMax(max) : compactFmt.format(max)}</text>
    </svg>
  `;
}

function renderDecomposition(current, previous) {
  const rows = [
    ["Revenue", (current.revenue - previous.revenue) / previous.revenue],
    ["Sessions", (current.sessions - previous.sessions) / previous.sessions],
    ["Session CVR", current.session_cvr - previous.session_cvr, "pp"],
    ["AOV", (current.aov - previous.aov) / previous.aov],
    [
      "Revenue / Session",
      (current.revenue_per_session - previous.revenue_per_session) /
        previous.revenue_per_session,
    ],
  ];

  document.querySelector("#decomp-bars").innerHTML = rows
    .map(([label, value, mode]) => {
      const width = Math.max(8, Math.min(100, Math.abs(value) * (mode === "pp" ? 90 : 130)));
      return `
        <div class="bar-row">
          <span>${label}</span>
          <div class="bar-track">
            <div class="bar-fill ${value < 0 ? "negative" : ""}" style="width:${width}%"></div>
          </div>
          <b class="bar-value">${mode === "pp" ? pp(value) : mom(value)}</b>
        </div>
      `;
    })
    .join("");
}

function renderSegments(rows) {
  const monthRows = rows.filter((row) => ["2020-12", "2021-01"].includes(monthKey(row.date)));
  const grouped = new Map();

  for (const row of monthRows) {
    const key = `${row.channel_group}||${row.device_category}||${row.user_type}`;
    const current = grouped.get(key) ?? {
      channel: row.channel_group,
      device: row.device_category,
      userType: row.user_type,
      dec: 0,
      jan: 0,
      decSessions: 0,
      janSessions: 0,
    };
    if (monthKey(row.date) === "2020-12") {
      current.dec += row.revenue;
      current.decSessions += row.sessions;
    } else {
      current.jan += row.revenue;
      current.janSessions += row.sessions;
    }
    grouped.set(key, current);
  }

  const segments = [...grouped.values()]
    .map((row) => ({
      ...row,
      loss: row.jan - row.dec,
      change: row.dec ? (row.jan - row.dec) / row.dec : 0,
    }))
    .filter((row) => row.dec >= 500)
    .sort((a, b) => a.loss - b.loss)
    .slice(0, 6);

  document.querySelector("#segment-table").innerHTML = segments
    .map(
      (row) => `
      <div class="segment-row">
        <div>
          <span class="segment-name">${row.channel}</span>
          <span class="segment-sub">${row.device} · ${row.userType}</span>
        </div>
        <b>${money(row.jan)}</b>
        <em>${mom(row.change)}</em>
      </div>
    `,
    )
    .join("");
}

async function init() {
  const [dailyKpi, monthly, segmentRows] = await Promise.all([
    loadCsv("../data/daily_kpi_mart.csv"),
    loadCsv("../data/monthly_kpi_mart.csv"),
    loadCsv("../data/daily_segment_mart.csv"),
  ]);
  const previous = monthly.find((row) => row.month === "2020-12");
  const current = monthly.find((row) => row.month === "2021-01");

  renderKpis(current, previous);
  renderLineChart("#revenue-chart", dailyKpi, "revenue", {
    formatMax: money,
  });
  renderLineChart("#cvr-chart", dailyKpi, "session_cvr", {
    height: 178,
    formatMax: pct,
  });
  renderDecomposition(current, previous);
  renderSegments(segmentRows);
}

init().catch((error) => {
  document.body.innerHTML = `<pre>${error.stack}</pre>`;
});
