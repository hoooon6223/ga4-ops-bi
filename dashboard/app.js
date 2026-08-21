const numberFmt = new Intl.NumberFormat("en-US");
const compactFmt = new Intl.NumberFormat("en-US", {
  notation: "compact",
  maximumFractionDigits: 1,
});

const state = {
  month: "2021-01",
  channel: "All",
  device: "All",
  userType: "All",
};

const money = (value) => `$${compactFmt.format(value || 0)}`;
const fixedMoney = (value) => `$${Number(value || 0).toFixed(2)}`;
const pct = (value) => `${((value || 0) * 100).toFixed(2)}%`;
const pp = (value) => `${value >= 0 ? "+" : ""}${((value || 0) * 100).toFixed(2)}pp`;
const mom = (value) => `${value >= 0 ? "+" : ""}${((value || 0) * 100).toFixed(1)}%`;

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

function previousMonth(month) {
  const months = ["2020-11", "2020-12", "2021-01"];
  return months[months.indexOf(month) - 1] || null;
}

function hasSegmentFilter() {
  return state.channel !== "All" || state.device !== "All" || state.userType !== "All";
}

function fillSelect(id, values, selected) {
  const select = document.querySelector(id);
  select.innerHTML = values
    .map((value) => `<option value="${value}" ${value === selected ? "selected" : ""}>${value}</option>`)
    .join("");
}

function filteredSegmentRows(rows, month = state.month) {
  return rows.filter((row) => {
    return (
      monthKey(row.date) === month &&
      (state.channel === "All" || row.channel_group === state.channel) &&
      (state.device === "All" || row.device_category === state.device) &&
      (state.userType === "All" || row.user_type === state.userType)
    );
  });
}

function aggregateRows(rows, month) {
  const total = rows.reduce(
    (acc, row) => {
      acc.sessions += Number(row.sessions || 0);
      acc.users += Number(row.users || 0);
      acc.purchasers += Number(row.purchasers || 0);
      acc.purchase_sessions += Number(row.purchase_sessions || 0);
      acc.orders += Number(row.orders || 0);
      acc.revenue += Number(row.revenue || 0);
      return acc;
    },
    {
      month,
      sessions: 0,
      users: 0,
      purchasers: 0,
      purchase_sessions: 0,
      orders: 0,
      revenue: 0,
    },
  );

  return {
    ...total,
    session_cvr: total.sessions ? total.purchase_sessions / total.sessions : 0,
    user_cvr: total.users ? total.purchasers / total.users : 0,
    aov: total.orders ? total.revenue / total.orders : 0,
    revenue_per_session: total.sessions ? total.revenue / total.sessions : 0,
  };
}

function dailySeriesFromSegments(rows) {
  const grouped = new Map();
  for (const row of rows) {
    const item = grouped.get(row.date) ?? {
      date: row.date,
      sessions: 0,
      purchase_sessions: 0,
      orders: 0,
      revenue: 0,
    };
    item.sessions += Number(row.sessions || 0);
    item.purchase_sessions += Number(row.purchase_sessions || 0);
    item.orders += Number(row.orders || 0);
    item.revenue += Number(row.revenue || 0);
    grouped.set(row.date, item);
  }

  return [...grouped.values()]
    .sort((a, b) => String(a.date).localeCompare(String(b.date)))
    .map((row) => ({
      ...row,
      session_cvr: row.sessions ? row.purchase_sessions / row.sessions : 0,
      aov: row.orders ? row.revenue / row.orders : 0,
      revenue_per_session: row.sessions ? row.revenue / row.sessions : 0,
    }));
}

function metricContext(monthly, segmentRows) {
  const prevMonth = previousMonth(state.month);

  if (!hasSegmentFilter()) {
    return {
      current: monthly.find((row) => row.month === state.month),
      previous: monthly.find((row) => row.month === prevMonth),
      exact: true,
    };
  }

  return {
    current: aggregateRows(filteredSegmentRows(segmentRows, state.month), state.month),
    previous: prevMonth ? aggregateRows(filteredSegmentRows(segmentRows, prevMonth), prevMonth) : null,
    exact: false,
  };
}

function renderKpis(current, previous) {
  const cards = [
    ["Revenue", money(current.revenue), previous && mom((current.revenue - previous.revenue) / previous.revenue)],
    ["Sessions", compactFmt.format(current.sessions), previous && mom((current.sessions - previous.sessions) / previous.sessions)],
    ["Session CVR", pct(current.session_cvr), previous && pp(current.session_cvr - previous.session_cvr)],
    ["AOV", fixedMoney(current.aov), previous && mom((current.aov - previous.aov) / previous.aov)],
    [
      "Revenue / Session",
      fixedMoney(current.revenue_per_session),
      previous &&
        mom((current.revenue_per_session - previous.revenue_per_session) / previous.revenue_per_session),
    ],
  ];

  document.querySelector("#kpi-grid").innerHTML = cards
    .map(
      ([label, value, delta]) => `
        <article class="metric-card">
          <span>${label}</span>
          <strong>${value}</strong>
          <em class="${delta ? "" : "neutral"}">${delta ? `${delta} MoM` : "No benchmark"}</em>
        </article>
      `,
    )
    .join("");
}

function renderLineChart(target, rows, metric, options = {}) {
  const width = 640;
  const height = options.height ?? 220;
  const pad = { top: 16, right: 18, bottom: 30, left: 42 };
  const safeRows = rows.length ? rows : [{ date: state.month, [metric]: 0 }];
  const values = safeRows.map((row) => Number(row[metric] || 0));
  const min = Math.min(0, ...values) * 0.96;
  const max = Math.max(0.001, ...values) * 1.08;
  const xStep = safeRows.length > 1 ? (width - pad.left - pad.right) / (safeRows.length - 1) : 0;
  const y = (value) =>
    pad.top + ((max - value) / (max - min)) * (height - pad.top - pad.bottom);
  const x = (index) => pad.left + index * xStep;
  const points = safeRows.map((row, index) => `${x(index)},${y(row[metric] || 0)}`).join(" ");
  const fillPoints = `${pad.left},${height - pad.bottom} ${points} ${
    width - pad.right
  },${height - pad.bottom}`;
  const ticks = safeRows.filter((row, index) => index === 0 || row.date.endsWith("-15") || index === safeRows.length - 1);

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
      ${ticks.map((row) => {
        const index = safeRows.indexOf(row);
        return `<text class="axis" x="${x(index)}" y="${height - 8}" text-anchor="middle">${row.date}</text>`;
      }).join("")}
      <text class="axis" x="${pad.left}" y="12">${options.formatMax ? options.formatMax(max) : compactFmt.format(max)}</text>
    </svg>
  `;
}

function renderDecomposition(current, previous) {
  if (!previous) {
    document.querySelector("#decomp-bars").innerHTML = `<p class="empty-state">선택 월 이전 데이터가 없어 MoM 비교를 생략합니다.</p>`;
    return;
  }

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

function renderSegments(segmentRows) {
  const prevMonth = previousMonth(state.month);
  const compareMonths = prevMonth ? [prevMonth, state.month] : [state.month];
  const monthRows = segmentRows.filter((row) => compareMonths.includes(monthKey(row.date)));
  const grouped = new Map();

  for (const row of monthRows) {
    if (state.channel !== "All" && row.channel_group !== state.channel) continue;
    if (state.device !== "All" && row.device_category !== state.device) continue;
    if (state.userType !== "All" && row.user_type !== state.userType) continue;

    const key = `${row.channel_group}||${row.device_category}||${row.user_type}`;
    const item = grouped.get(key) ?? {
      channel: row.channel_group,
      device: row.device_category,
      userType: row.user_type,
      previous: 0,
      current: 0,
    };
    if (monthKey(row.date) === state.month) item.current += row.revenue;
    if (monthKey(row.date) === prevMonth) item.previous += row.revenue;
    grouped.set(key, item);
  }

  const segments = [...grouped.values()]
    .map((row) => ({
      ...row,
      loss: row.current - row.previous,
      change: row.previous ? (row.current - row.previous) / row.previous : 0,
    }))
    .filter((row) => row.current > 0 || row.previous > 0)
    .sort((a, b) => a.loss - b.loss)
    .slice(0, 6);

  document.querySelector("#segment-table").innerHTML = segments.length
    ? segments
        .map(
          (row) => `
        <button class="segment-row" data-channel="${row.channel}" data-device="${row.device}" data-user="${row.userType}" type="button">
          <div>
            <span class="segment-name">${row.channel}</span>
            <span class="segment-sub">${row.device} · ${row.userType}</span>
          </div>
          <b>${money(row.current)}</b>
          <em>${prevMonth ? mom(row.change) : "current"}</em>
        </button>
      `,
        )
        .join("")
    : `<p class="empty-state">선택 조건에 해당하는 세그먼트가 없습니다.</p>`;

  document.querySelectorAll(".segment-row").forEach((button) => {
    button.addEventListener("click", () => {
      state.channel = button.dataset.channel;
      state.device = button.dataset.device;
      state.userType = button.dataset.user;
      render(globalData);
    });
  });
}

function renderContext(exact) {
  const filters = [
    `Month ${state.month}`,
    state.channel === "All" ? "All channels" : state.channel,
    state.device === "All" ? "All devices" : state.device,
    state.userType === "All" ? "All users" : state.userType,
  ];
  document.querySelector("#context-label").textContent = `${filters.join(" · ")} · ${
    exact ? "exact monthly KPI" : "segment-filtered daily grain"
  }`;
}

function render(data) {
  const { dailyKpi, monthly, segmentRows } = data;
  const { current, previous, exact } = metricContext(monthly, segmentRows);
  const dayRows = hasSegmentFilter()
    ? dailySeriesFromSegments(filteredSegmentRows(segmentRows))
    : dailyKpi.filter((row) => monthKey(row.date) === state.month);

  renderKpis(current, previous);
  renderLineChart("#revenue-chart", dayRows, "revenue", { formatMax: money });
  renderLineChart("#cvr-chart", dayRows, "session_cvr", {
    height: 178,
    formatMax: pct,
  });
  renderDecomposition(current, previous);
  renderSegments(segmentRows);
  renderContext(exact);

  document.querySelector("#month-filter").value = state.month;
  document.querySelector("#channel-filter").value = state.channel;
  document.querySelector("#device-filter").value = state.device;
  document.querySelector("#user-filter").value = state.userType;
}

function bindFilters(data) {
  fillSelect("#month-filter", data.monthly.map((row) => row.month), state.month);
  fillSelect("#channel-filter", ["All", ...new Set(data.segmentRows.map((row) => row.channel_group))].sort(), state.channel);
  fillSelect("#device-filter", ["All", ...new Set(data.segmentRows.map((row) => row.device_category))].sort(), state.device);
  fillSelect("#user-filter", ["All", ...new Set(data.segmentRows.map((row) => row.user_type))].sort(), state.userType);

  [
    ["#month-filter", "month"],
    ["#channel-filter", "channel"],
    ["#device-filter", "device"],
    ["#user-filter", "userType"],
  ].forEach(([selector, key]) => {
    document.querySelector(selector).addEventListener("change", (event) => {
      state[key] = event.target.value;
      render(data);
    });
  });

  document.querySelector("#reset-filters").addEventListener("click", () => {
    state.month = "2021-01";
    state.channel = "All";
    state.device = "All";
    state.userType = "All";
    render(data);
  });
}

let globalData;

async function init() {
  globalData = {
    dailyKpi: await loadCsv("../data/daily_kpi_mart.csv"),
    monthly: await loadCsv("../data/monthly_kpi_mart.csv"),
    segmentRows: await loadCsv("../data/daily_segment_mart.csv"),
  };

  bindFilters(globalData);
  render(globalData);
}

init().catch((error) => {
  document.body.innerHTML = `<pre>${error.stack}</pre>`;
});
