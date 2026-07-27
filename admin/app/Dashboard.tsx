"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { CSSProperties, FormEvent } from "react";

type ConnectionStatus = "online" | "offline" | "pending" | "disabled";
type Device = {
  id: string;
  name: string;
  location: string;
  platform: "macos" | "windows";
  playbackUrl: string;
  fallbackSeconds: number;
  enabled: boolean;
  keyPrefix: string;
  lastSeenAt: number | null;
  reportedStatus: string;
  currentUrl: string | null;
  appVersion: string | null;
  osVersion: string | null;
  uptimeSeconds: number | null;
  lastError: string | null;
  createdAt: number;
  updatedAt: number;
  connectionStatus: ConnectionStatus;
};

type RecentEvent = {
  id: string;
  deviceId: string;
  deviceName: string;
  recordedAt: number;
  status: string;
  currentUrl: string | null;
  errorMessage: string | null;
};

type Summary = {
  total: number;
  online: number;
  offline: number;
  pending: number;
  disabled: number;
  alerts: number;
  heartbeats24h: number;
  devices: Device[];
  recentEvents: RecentEvent[];
};

type DeviceDraft = {
  name: string;
  location: string;
  platform: "macos" | "windows";
  playbackUrl: string;
  fallbackSeconds: number;
  enabled: boolean;
};

const EMPTY_DRAFT: DeviceDraft = {
  name: "",
  location: "",
  platform: "macos",
  playbackUrl: "",
  fallbackSeconds: 200,
  enabled: true,
};

const STATUS_LABELS: Record<ConnectionStatus, string> = {
  online: "在線",
  offline: "離線",
  pending: "等待連線",
  disabled: "已停用",
};

export default function Dashboard({
  administrator,
  signOutPath,
}: {
  administrator: { name: string; email: string };
  signOutPath: string;
}) {
  const [summary, setSummary] = useState<Summary | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState<"all" | ConnectionStatus>(
    "all",
  );
  const [modal, setModal] = useState<"create" | "edit" | null>(null);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [draft, setDraft] = useState<DeviceDraft>(EMPTY_DRAFT);
  const [saving, setSaving] = useState(false);
  const [generatedPackage, setGeneratedPackage] = useState<{
    device: Device;
    apiKey?: string;
  } | null>(null);
  const [lastRefresh, setLastRefresh] = useState<Date | null>(null);
  const [activeSection, setActiveSection] = useState<
    "overview" | "devices" | "activity"
  >("overview");

  const loadSummary = useCallback(async (silent = false) => {
    if (!silent) setLoading(true);
    try {
      const response = await fetch("/api/devices", { cache: "no-store" });
      const body = (await response.json()) as Summary & { error?: string };
      if (!response.ok) throw new Error(body.error || "無法取得裝置狀態");
      setSummary(body);
      setLastRefresh(new Date());
      setError("");
    } catch (loadError) {
      setError(
        loadError instanceof Error ? loadError.message : "無法取得裝置狀態",
      );
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadSummary();
    const timer = window.setInterval(() => loadSummary(true), 20_000);
    return () => window.clearInterval(timer);
  }, [loadSummary]);

  useEffect(() => {
    const section = window.location.hash.slice(1);
    if (section === "devices" || section === "activity") {
      setActiveSection(section);
    }
  }, []);

  const filteredDevices = useMemo(() => {
    const normalized = search.trim().toLowerCase();
    return (summary?.devices ?? []).filter((device) => {
      const matchesStatus =
        statusFilter === "all" || device.connectionStatus === statusFilter;
      const matchesSearch =
        !normalized ||
        [device.name, device.location, device.playbackUrl, device.platform]
          .join(" ")
          .toLowerCase()
          .includes(normalized);
      return matchesStatus && matchesSearch;
    });
  }, [search, statusFilter, summary]);

  function openCreate() {
    setDraft(EMPTY_DRAFT);
    setEditingId(null);
    setModal("create");
  }

  function openEdit(device: Device) {
    setDraft({
      name: device.name,
      location: device.location,
      platform: device.platform,
      playbackUrl: device.playbackUrl,
      fallbackSeconds: device.fallbackSeconds,
      enabled: device.enabled,
    });
    setEditingId(device.id);
    setModal("edit");
  }

  function goToSection(section: "overview" | "devices" | "activity") {
    setActiveSection(section);
    window.history.replaceState(null, "", `#${section}`);
    document.getElementById(section)?.scrollIntoView({
      behavior: "smooth",
      block: "start",
    });
  }

  async function downloadPackage(device: Device) {
    try {
      const response = await fetch(
        `/api/devices/${encodeURIComponent(device.id)}/package`,
        { cache: "no-store" },
      );
      if (!response.ok) {
        const body = (await response.json().catch(() => null)) as {
          error?: string;
        } | null;
        throw new Error(body?.error || "安裝包產生失敗");
      }
      const objectUrl = URL.createObjectURL(await response.blob());
      const link = document.createElement("a");
      link.href = objectUrl;
      link.download = packageFilename(device);
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.setTimeout(() => URL.revokeObjectURL(objectUrl), 1_000);
    } catch (downloadError) {
      setError(
        downloadError instanceof Error
          ? downloadError.message
          : "安裝包產生失敗",
      );
    }
  }

  async function saveDevice(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSaving(true);
    setError("");
    try {
      const editing = modal === "edit" && editingId;
      const response = await fetch(
        editing ? `/api/devices/${editingId}` : "/api/devices",
        {
          method: editing ? "PATCH" : "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(draft),
        },
      );
      const body = (await response.json()) as {
        device: Device;
        apiKey?: string;
        error?: string;
      };
      if (!response.ok) throw new Error(body.error || "儲存失敗");
      setModal(null);
      setGeneratedPackage({ device: body.device, apiKey: body.apiKey });
      void downloadPackage(body.device);
      await loadSummary(true);
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : "儲存失敗");
    } finally {
      setSaving(false);
    }
  }

  async function removeDevice(device: Device) {
    if (!window.confirm(`確定刪除「${device.name}」？相關使用紀錄也會刪除。`))
      return;
    try {
      const response = await fetch(`/api/devices/${device.id}`, {
        method: "DELETE",
      });
      if (!response.ok) {
        const body = (await response.json()) as { error?: string };
        throw new Error(body.error || "刪除失敗");
      }
      await loadSummary(true);
    } catch (removeError) {
      setError(
        removeError instanceof Error ? removeError.message : "刪除失敗",
      );
    }
  }

  async function rotateKey(device: Device) {
    if (
      !window.confirm(
        `確定重新產生「${device.name}」的 API 金鑰？舊金鑰會立即失效。`,
      )
    )
      return;
    try {
      const response = await fetch(`/api/devices/${device.id}/rotate-key`, {
        method: "POST",
      });
      const body = (await response.json()) as {
        device: Device;
        apiKey: string;
        error?: string;
      };
      if (!response.ok) throw new Error(body.error || "更新金鑰失敗");
      setGeneratedPackage({ device: body.device, apiKey: body.apiKey });
      void downloadPackage(body.device);
      await loadSummary(true);
    } catch (keyError) {
      setError(
        keyError instanceof Error ? keyError.message : "更新金鑰失敗",
      );
    }
  }

  const onlineRatio = summary?.total
    ? Math.round((summary.online / summary.total) * 100)
    : 0;

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <span className="brand-mark">TV</span>
          <div>
            <strong>WALL</strong>
            <small>CONTROL</small>
          </div>
        </div>

        <nav className="nav-list" aria-label="主要導覽">
          <button
            className={`nav-item ${activeSection === "overview" ? "active" : ""}`}
            type="button"
            onClick={() => goToSection("overview")}
          >
            <span className="nav-icon grid-icon" />
            營運總覽
          </button>
          <button
            className={`nav-item ${activeSection === "devices" ? "active" : ""}`}
            type="button"
            onClick={() => goToSection("devices")}
          >
            <span className="nav-icon screen-icon" />
            節點管理
            <b>{summary?.total ?? 0}</b>
          </button>
          <button
            className={`nav-item ${activeSection === "activity" ? "active" : ""}`}
            type="button"
            onClick={() => goToSection("activity")}
          >
            <span className="nav-icon pulse-icon" />
            即時動態
          </button>
        </nav>

        <div className="sidebar-status">
          <div className="service-indicator">
            <span />
            服務運作正常
          </div>
          <p>裝置每 30 秒回報一次狀態</p>
        </div>
      </aside>

      <main className="main-content">
        <header className="topbar">
          <div>
            <p className="eyebrow">TV-WALL OPERATIONS</p>
            <h1>營運總覽</h1>
          </div>
          <div className="topbar-actions">
            <button
              className="icon-button"
              type="button"
              onClick={() => loadSummary()}
              aria-label="重新整理"
              title="重新整理"
            >
              ↻
            </button>
            <div className="admin-menu">
              <span className="avatar">
                {administrator.name.slice(0, 1).toUpperCase()}
              </span>
              <div>
                <strong>{administrator.name}</strong>
                <small>系統管理員</small>
              </div>
              <form action={signOutPath} method="post">
                <button type="submit">登出</button>
              </form>
            </div>
          </div>
        </header>

        {error && (
          <div className="error-banner" role="alert">
            <span>!</span>
            {error}
            <button type="button" onClick={() => setError("")}>
              關閉
            </button>
          </div>
        )}

        <section className="stats-grid" id="overview">
          <StatCard
            label="在線節點"
            value={summary?.online ?? 0}
            detail={`共 ${summary?.total ?? 0} 台裝置`}
            tone="green"
            symbol="●"
          />
          <StatCard
            label="需要處理"
            value={summary?.alerts ?? 0}
            detail={
              summary?.alerts ? `${summary.offline} 台離線` : "所有節點正常"
            }
            tone={summary?.alerts ? "amber" : "neutral"}
            symbol="!"
          />
          <StatCard
            label="24 小時回報"
            value={summary?.heartbeats24h ?? 0}
            detail="累計心跳事件"
            tone="blue"
            symbol="↗"
          />
          <article className="stat-card availability-card">
            <div>
              <span className="stat-label">目前可用率</span>
              <strong>{onlineRatio}%</strong>
              <small>依即時連線狀態計算</small>
            </div>
            <div
              className="availability-ring"
              style={{ "--ratio": `${onlineRatio * 3.6}deg` } as CSSProperties}
            >
              <span>{onlineRatio}</span>
            </div>
          </article>
        </section>

        <section className="content-grid">
          <div className="devices-panel panel" id="devices">
            <div className="panel-header">
              <div>
                <p className="eyebrow">DEVICE FLEET</p>
                <h2>電視牆節點</h2>
              </div>
              <button className="primary-button" type="button" onClick={openCreate}>
                <span>＋</span> 新增節點
              </button>
            </div>

            <div className="management-hint">
              <span aria-hidden="true">i</span>
              <p>
                按「新增節點」建立電視牆；既有節點可直接按右側「編輯」，更多選項包含下載安裝包、更新金鑰與刪除。
              </p>
            </div>

            <div className="table-tools">
              <label className="search-box">
                <span />
                <input
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                  placeholder="搜尋名稱、地點或網址"
                  aria-label="搜尋裝置"
                />
              </label>
              <div className="filter-pills" aria-label="裝置狀態篩選">
                {(
                  [
                    ["all", "全部"],
                    ["online", "在線"],
                    ["offline", "離線"],
                    ["pending", "待連線"],
                  ] as const
                ).map(([value, label]) => (
                  <button
                    key={value}
                    type="button"
                    className={statusFilter === value ? "selected" : ""}
                    onClick={() => setStatusFilter(value)}
                  >
                    {label}
                  </button>
                ))}
              </div>
            </div>

            {loading ? (
              <div className="loading-state">
                <span className="loading-line" />
                <span className="loading-line" />
                <span className="loading-line" />
              </div>
            ) : filteredDevices.length ? (
              <div className="table-scroll">
                <table>
                  <thead>
                    <tr>
                      <th>狀態／節點</th>
                      <th>播放內容</th>
                      <th>平台</th>
                      <th>最後回報</th>
                      <th aria-label="操作" />
                    </tr>
                  </thead>
                  <tbody>
                    {filteredDevices.map((device) => (
                      <DeviceRow
                        key={device.id}
                        device={device}
                        onEdit={() => openEdit(device)}
                        onDownload={() => {
                          setGeneratedPackage({ device });
                          void downloadPackage(device);
                        }}
                        onDelete={() => removeDevice(device)}
                        onRotateKey={() => rotateKey(device)}
                      />
                    ))}
                  </tbody>
                </table>
              </div>
            ) : (
              <div className="empty-state">
                <span className="empty-screen" />
                <h3>{summary?.total ? "找不到符合條件的節點" : "尚未新增電視牆節點"}</h3>
                <p>
                  {summary?.total
                    ? "請調整搜尋文字或狀態篩選。"
                    : "新增第一個節點後，系統會自動產生設定、程式與詳細安裝說明。"}
                </p>
                {!summary?.total && (
                  <button className="secondary-button" type="button" onClick={openCreate}>
                    新增第一個節點
                  </button>
                )}
              </div>
            )}

            <div className="panel-footer">
              <span>
                顯示 {filteredDevices.length}／{summary?.total ?? 0} 台
              </span>
              <span>
                {lastRefresh
                  ? `更新於 ${lastRefresh.toLocaleTimeString("zh-TW", {
                      hour: "2-digit",
                      minute: "2-digit",
                      second: "2-digit",
                    })}`
                  : "正在連線"}
              </span>
            </div>
          </div>

          <aside className="activity-panel panel" id="activity">
            <div className="panel-header compact">
              <div>
                <p className="eyebrow">LIVE ACTIVITY</p>
                <h2>最近動態</h2>
              </div>
              <span className="live-badge">
                <i /> LIVE
              </span>
            </div>
            <div className="activity-list">
              {summary?.recentEvents.length ? (
                summary.recentEvents.map((event) => (
                  <article className="activity-item" key={event.id}>
                    <span
                      className={`activity-dot ${
                        event.errorMessage ? "error" : ""
                      }`}
                    />
                    <div>
                      <strong>{event.deviceName}</strong>
                      <p>
                        {event.errorMessage
                          ? `回報錯誤：${event.errorMessage}`
                          : event.status === "playing"
                            ? "正在播放指定內容"
                            : `狀態回報：${event.status}`}
                      </p>
                      <time>{relativeTime(event.recordedAt)}</time>
                    </div>
                  </article>
                ))
              ) : (
                <div className="activity-empty">
                  <span>⌁</span>
                  <p>等待裝置回報</p>
                  <small>完成節點安裝後，心跳事件會顯示在這裡。</small>
                </div>
              )}
            </div>
            <div className="health-legend">
              <div>
                <span className="status-dot online" />
                正常
              </div>
              <div>
                <span className="status-dot pending" />
                等待
              </div>
              <div>
                <span className="status-dot offline" />
                異常
              </div>
            </div>
          </aside>
        </section>
      </main>

      {modal && (
        <div className="modal-backdrop" role="presentation">
          <section className="modal" role="dialog" aria-modal="true" aria-labelledby="device-modal-title">
            <div className="modal-header">
              <div>
                <p className="eyebrow">DEVICE CONFIGURATION</p>
                <h2 id="device-modal-title">
                  {modal === "create" ? "新增電視牆節點" : "編輯節點"}
                </h2>
              </div>
              <button type="button" onClick={() => setModal(null)} aria-label="關閉">
                ×
              </button>
            </div>
            <form onSubmit={saveDevice}>
              <div className="form-grid">
                <label>
                  <span>節點名稱</span>
                  <input
                    required
                    value={draft.name}
                    onChange={(event) =>
                      setDraft({ ...draft, name: event.target.value })
                    }
                    placeholder="例如：一樓大廳主螢幕"
                  />
                </label>
                <label>
                  <span>安裝位置</span>
                  <input
                    value={draft.location}
                    onChange={(event) =>
                      setDraft({ ...draft, location: event.target.value })
                    }
                    placeholder="例如：台北總部 1F"
                  />
                </label>
                <label>
                  <span>作業系統</span>
                  <select
                    value={draft.platform}
                    onChange={(event) =>
                      setDraft({
                        ...draft,
                        platform: event.target.value as "macos" | "windows",
                      })
                    }
                  >
                    <option value="macos">macOS</option>
                    <option value="windows">Windows</option>
                  </select>
                </label>
                <label>
                  <span>偵測失敗備援秒數</span>
                  <input
                    type="number"
                    min="15"
                    max="86400"
                    required
                    value={draft.fallbackSeconds}
                    onChange={(event) =>
                      setDraft({
                        ...draft,
                        fallbackSeconds: Number(event.target.value),
                      })
                    }
                  />
                </label>
                <label className="full-width">
                  <span>Canva 播放網址</span>
                  <input
                    type="url"
                    required
                    value={draft.playbackUrl}
                    onChange={(event) =>
                      setDraft({ ...draft, playbackUrl: event.target.value })
                    }
                    placeholder="https://www.canva.com/design/.../watch"
                  />
                </label>
                <label className="toggle-field full-width">
                  <span>
                    <strong>啟用此節點</strong>
                    <small>停用後，節點仍可回報狀態但不應播放內容。</small>
                  </span>
                  <input
                    type="checkbox"
                    checked={draft.enabled}
                    onChange={(event) =>
                      setDraft({ ...draft, enabled: event.target.checked })
                    }
                  />
                  <i />
                </label>
              </div>
              <div className="modal-actions">
                <button
                  className="secondary-button"
                  type="button"
                  onClick={() => setModal(null)}
                >
                  取消
                </button>
                <button className="primary-button" type="submit" disabled={saving}>
                  {saving ? "正在儲存…" : modal === "create" ? "建立節點" : "儲存變更"}
                </button>
              </div>
            </form>
          </section>
        </div>
      )}

      {generatedPackage && (
        <div className="modal-backdrop" role="presentation">
          <section className="modal key-modal" role="dialog" aria-modal="true" aria-labelledby="key-modal-title">
            <div className="key-symbol">ZIP</div>
            <p className="eyebrow">INSTALLATION PACKAGE</p>
            <h2 id="key-modal-title">完整安裝包已自動產生</h2>
            <p>
              「{generatedPackage.device.name}」的下載已開始。ZIP 內含此平台所需程式、
              自動產生的設定檔與繁體中文完整安裝、驗證、更新、移除及疑難排解說明。
            </p>
            {generatedPackage.apiKey && (
              <>
                <p>
                  新產生的 API 金鑰也已寫入安裝包。若需要手動安裝，請先安全保存：
                </p>
                <div className="key-value">
                  <code>{generatedPackage.apiKey}</code>
                  <button
                    type="button"
                    onClick={() =>
                      navigator.clipboard.writeText(generatedPackage.apiKey!)
                    }
                  >
                    複製
                  </button>
                </div>
                <div className="install-command">
                  <span>
                    {generatedPackage.device.platform === "macos"
                      ? "macOS"
                      : "Windows"}{" "}
                    手動安裝指令
                  </span>
                  <code>
                    {installationCommand(
                      generatedPackage.device,
                      generatedPackage.apiKey,
                    )}
                  </code>
                  <button
                    type="button"
                    onClick={() =>
                      navigator.clipboard.writeText(
                        installationCommand(
                          generatedPackage.device,
                          generatedPackage.apiKey!,
                        ),
                      )
                    }
                  >
                    複製完整指令
                  </button>
                </div>
              </>
            )}
            <button
              className="secondary-button full-button"
              type="button"
              onClick={() => void downloadPackage(generatedPackage.device)}
            >
              再次下載完整安裝包
            </button>
            <button
              className="primary-button full-button"
              type="button"
              onClick={() => setGeneratedPackage(null)}
            >
              完成
            </button>
          </section>
        </div>
      )}
    </div>
  );
}

function StatCard({
  label,
  value,
  detail,
  tone,
  symbol,
}: {
  label: string;
  value: number;
  detail: string;
  tone: string;
  symbol: string;
}) {
  return (
    <article className={`stat-card ${tone}`}>
      <div className="stat-symbol">{symbol}</div>
      <span className="stat-label">{label}</span>
      <strong>{value}</strong>
      <small>{detail}</small>
    </article>
  );
}

function DeviceRow({
  device,
  onEdit,
  onDownload,
  onDelete,
  onRotateKey,
}: {
  device: Device;
  onEdit: () => void;
  onDownload: () => void;
  onDelete: () => void;
  onRotateKey: () => void;
}) {
  return (
    <tr>
      <td>
        <div className="device-name">
          <span className={`status-dot ${device.connectionStatus}`} />
          <div>
            <strong>{device.name}</strong>
            <small>{device.location || "尚未設定位置"}</small>
          </div>
        </div>
      </td>
      <td>
        <div className="content-cell">
          <strong>{shortUrl(device.playbackUrl)}</strong>
          <small>備援 {device.fallbackSeconds} 秒</small>
        </div>
      </td>
      <td>
        <span className={`platform-badge ${device.platform}`}>
          {device.platform === "macos" ? "macOS" : "Windows"}
        </span>
        <small className="version-text">
          {device.appVersion || device.osVersion || "尚未回報版本"}
        </small>
      </td>
      <td>
        <span className="last-seen">
          {device.lastSeenAt ? relativeTime(device.lastSeenAt) : "從未連線"}
        </span>
        <small>{STATUS_LABELS[device.connectionStatus]}</small>
      </td>
      <td>
        <div className="row-actions">
          <button className="edit-device-button" type="button" onClick={onEdit}>
            編輯
          </button>
          <details className="row-menu">
            <summary aria-label={`更多管理選項：${device.name}`}>•••</summary>
            <div>
              <button type="button" onClick={onDownload}>
                下載完整安裝包
              </button>
              <button type="button" onClick={onRotateKey}>
                更新 API 金鑰
              </button>
              <button type="button" className="danger" onClick={onDelete}>
                刪除節點
              </button>
            </div>
          </details>
        </div>
      </td>
    </tr>
  );
}

function shortUrl(value: string) {
  try {
    const url = new URL(value);
    const parts = url.pathname.split("/").filter(Boolean);
    return parts.length >= 2 ? `${url.hostname}/${parts[0]}/${parts[1]}` : url.hostname;
  } catch {
    return value;
  }
}

function installationCommand(device: Device, apiKey: string) {
  const origin =
    typeof window === "undefined" ? "https://你的管理後台網址" : window.location.origin;
  if (device.platform === "macos") {
    return `sudo ./install-for-user.sh "${device.playbackUrl}" ${device.fallbackSeconds} "${origin}" "${apiKey}"`;
  }
  return `.\\install.ps1 -Url "${device.playbackUrl}" -FallbackSeconds ${device.fallbackSeconds} -ControlUrl "${origin}" -DeviceApiKey "${apiKey}"`;
}

function packageFilename(device: Device) {
  const slug = device.name
    .normalize("NFKD")
    .replace(/[^A-Za-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48);
  return `TV-WALL-${slug || device.id.slice(0, 8)}.zip`;
}

function relativeTime(timestamp: number) {
  const seconds = Math.max(0, Math.floor(Date.now() / 1000) - timestamp);
  if (seconds < 10) return "剛剛";
  if (seconds < 60) return `${seconds} 秒前`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)} 分鐘前`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)} 小時前`;
  return `${Math.floor(seconds / 86400)} 天前`;
}
