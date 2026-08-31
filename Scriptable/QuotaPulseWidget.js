// Variables used by Scriptable.
// icon-color: green; icon-glyph: heartbeat;

const CONFIG_KEY = "QuotaPulse.Scriptable.Config.v1"
const CACHE_FILE = "QuotaPulseWidget-cache-v1.json"
const GREEN = new Color("#29A657")
const RED = new Color("#D64545")
const ORANGE = new Color("#E57A2A")
const isChinese = (Device.locale() || "").toLowerCase().startsWith("zh")

await main()

async function main() {
  if (!config.runsInWidget) {
    await runInApp()
    Script.complete()
    return
  }

  const payload = loadConfig()
  if (!payload) {
    const widget = setupWidget()
    widget.refreshAfterDate = new Date(Date.now() + 15 * 60 * 1000)
    Script.setWidget(widget)
    Script.complete()
    return
  }

  const result = await refreshWithCache(payload)
  saveConfig(payload)
  const widget = buildWidget(payload, result.snapshots)
  widget.refreshAfterDate = new Date(
    Date.now() + clamp(payload.refreshMinutes || 15, 5, 1440) * 60 * 1000
  )
  Script.setWidget(widget)
  Script.complete()
}

async function runInApp() {
  const hasConfig = Keychain.contains(CONFIG_KEY)
  const menu = new Alert()
  menu.title = "QuotaPulse Widget"
  menu.message = hasConfig
    ? t("配置已保存在 Scriptable Keychain。", "Configuration is stored in Scriptable Keychain.")
    : t("首次使用请导入 QuotaPulse 导出的 Scriptable JSON。", "Import the Scriptable JSON exported by QuotaPulse.")
  menu.addAction(t("导入或更新配置", "Import or Update Configuration"))
  if (hasConfig) menu.addAction(t("刷新并预览", "Refresh and Preview"))
  if (hasConfig) menu.addDestructiveAction(t("清除 Scriptable 配置", "Clear Scriptable Configuration"))
  menu.addCancelAction(t("取消", "Cancel"))
  const choice = await menu.presentSheet()
  if (choice < 0) return
  if (choice === 0) {
    await importConfiguration()
    return
  }
  if (hasConfig && choice === 1) {
    const payload = loadConfig()
    const result = await refreshWithCache(payload)
    saveConfig(payload)
    await buildWidget(payload, result.snapshots).presentMedium()
    return
  }
  if (hasConfig && choice === 2) {
    Keychain.remove(CONFIG_KEY)
    const fm = FileManager.local()
    const cachePath = fm.joinPath(fm.documentsDirectory(), CACHE_FILE)
    if (fm.fileExists(cachePath)) fm.remove(cachePath)
    await showMessage(t("已清除", "Cleared"), t("Scriptable 中的配置和缓存已删除。", "Scriptable configuration and cache were removed."))
  }
}

async function importConfiguration() {
  let paths
  try {
    paths = await DocumentPicker.openFile()
  } catch (error) {
    return
  }
  const path = Array.isArray(paths) ? paths[0] : paths
  if (!path) return
  try {
    const raw = await readSelectedFile(path)
    const payload = JSON.parse(raw)
    validateConfig(payload)
    saveConfig(payload)
    await showMessage(
      t("导入完成", "Import Complete"),
      t(
        `已将 ${payload.accounts.length} 个账号保存到 Scriptable Keychain。请删除导出的 JSON 文件。`,
        `${payload.accounts.length} accounts were stored in Scriptable Keychain. Delete the exported JSON file.`
      )
    )
  } catch (error) {
    await showMessage(t("导入失败", "Import Failed"), String(error.message || error))
  }
}

async function readSelectedFile(path) {
  const managers = [FileManager.local(), FileManager.iCloud()]
  for (const fm of managers) {
    try {
      if (fm.isFileStoredIniCloud(path) && !fm.isFileDownloaded(path)) {
        await fm.downloadFileFromiCloud(path)
      }
      const value = fm.readString(path)
      if (value) return value
    } catch (_) {}
  }
  throw new Error(t("无法读取所选 JSON 文件", "Unable to read the selected JSON file"))
}

function validateConfig(payload) {
  if (!payload || payload.format !== "quotapulse-scriptable" || payload.version !== 1) {
    throw new Error(t("不是受支持的 QuotaPulse Scriptable 配置", "Unsupported QuotaPulse Scriptable configuration"))
  }
  if (!Array.isArray(payload.accounts) || payload.accounts.length === 0) {
    throw new Error(t("配置中没有账号", "No accounts were found in the configuration"))
  }
  for (const account of payload.accounts) {
    if (!account.id || !account.provider || !account.credential || !account.credential.accessToken) {
      throw new Error(t(`账号 ${account.label || "--"} 的凭据不完整`, `Credentials are incomplete for ${account.label || "--"}`))
    }
  }
}

function loadConfig() {
  if (!Keychain.contains(CONFIG_KEY)) return null
  try {
    const payload = JSON.parse(Keychain.get(CONFIG_KEY))
    validateConfig(payload)
    return payload
  } catch (_) {
    return null
  }
}

function saveConfig(payload) {
  Keychain.set(CONFIG_KEY, JSON.stringify(payload))
}

async function refreshWithCache(payload) {
  const cache = loadCache()
  const snapshots = []
  const accounts = filteredAccounts(payload.accounts).slice(0, widgetAccountLimit())
  for (const account of accounts) {
    try {
      const snapshot = await refreshAccount(account)
      cache[account.id] = snapshot
      snapshots.push(snapshot)
    } catch (error) {
      const cached = cache[account.id]
      if (cached) {
        snapshots.push({ ...cached, stale: true, error: String(error.message || error) })
      } else {
        snapshots.push({
          accountID: account.id,
          provider: account.provider,
          label: account.label,
          kind: "error",
          error: String(error.message || error),
          fetchedAt: new Date().toISOString()
        })
      }
    }
  }
  saveCache(cache)
  return { snapshots }
}

function filteredAccounts(accounts) {
  const parameter = String(args.widgetParameter || "").trim().toLowerCase()
  if (!parameter) return accounts
  const values = accounts.filter(account =>
    String(account.provider).toLowerCase() === parameter ||
    String(account.label).toLowerCase().includes(parameter) ||
    String(account.id).toLowerCase() === parameter
  )
  return values.length ? values : accounts
}

function widgetAccountLimit() {
  const family = config.widgetFamily || "medium"
  return family === "small" ? 1 : family === "large" ? 6 : 3
}

function loadCache() {
  const fm = FileManager.local()
  const path = fm.joinPath(fm.documentsDirectory(), CACHE_FILE)
  if (!fm.fileExists(path)) return {}
  try { return JSON.parse(fm.readString(path)) } catch (_) { return {} }
}

function saveCache(cache) {
  const fm = FileManager.local()
  const path = fm.joinPath(fm.documentsDirectory(), CACHE_FILE)
  fm.writeString(path, JSON.stringify(cache))
}

async function refreshAccount(account) {
  switch (account.provider) {
    case "codex": return await refreshCodex(account)
    case "claude": return await refreshClaude(account)
    case "kimi": return await refreshKimi(account)
    case "deepseek": return await refreshDeepSeek(account)
    case "minimax": return await refreshMiniMax(account)
    case "glm": return await refreshGLM(account)
    case "copilot": return await refreshCopilot(account)
    default: throw new Error(`Unsupported provider: ${account.provider}`)
  }
}

async function refreshCodex(account) {
  const c = account.credential
  if (c.authenticationMode === "apiKey") {
    const base = apiV1Base(c.baseURL, "https://api.openai.com")
    const json = await requestJSON(`${base}/models`, {
      headers: bearerHeaders(c.accessToken)
    })
    return metricSnapshot(account, `${(json.data || []).length} models`)
  }
  const call = async () => {
    const current = account.credential
    const headers = bearerHeaders(current.accessToken)
    headers["User-Agent"] = "codex-cli"
    headers["openai-beta"] = "codex-1"
    if (current.accountID) headers["chatgpt-account-id"] = current.accountID
    return await requestJSON("https://chatgpt.com/backend-api/wham/usage", { headers })
  }
  let json
  try { json = await call() } catch (error) {
    if (error.status !== 401 || !account.credential.refreshToken) throw error
    account.credential = await refreshCodexToken(account.credential)
    json = await call()
  }
  const windows = []
  const rate = json.rate_limit || {}
  for (const [key, value] of Object.entries(rate)) {
    if (!key.endsWith("_window") || value.used_percent == null) continue
    windows.push({
      label: durationLabel(Number(value.limit_window_seconds || 0)),
      remaining: clamp(100 - Number(value.used_percent), 0, 100),
      resetAt: resetDate(value)
    })
  }
  if (!windows.length) throw new Error("Codex quota windows missing")
  return quotaSnapshot(account, windows)
}

async function refreshCodexToken(c) {
  const json = await requestJSON("https://auth.openai.com/oauth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: formBody({
      grant_type: "refresh_token",
      refresh_token: c.refreshToken,
      client_id: c.clientID || "app_EMoamEEZ73f0CkXaXp7hrann"
    })
  })
  return { ...c, accessToken: json.access_token, refreshToken: json.refresh_token || c.refreshToken }
}

async function refreshClaude(account) {
  const c = account.credential
  if (c.authenticationMode === "apiKey") {
    const base = apiV1Base(c.baseURL, "https://api.anthropic.com")
    const json = await requestJSON(`${base}/models`, {
      headers: { "x-api-key": c.accessToken, "anthropic-version": "2023-06-01" }
    })
    return metricSnapshot(account, `${(json.data || []).length} models`)
  }
  const call = async () => await requestJSON("https://api.anthropic.com/api/oauth/usage", {
    headers: {
      Authorization: `Bearer ${account.credential.accessToken}`,
      "anthropic-beta": "oauth-2025-04-20",
      "User-Agent": "claude-cli"
    }
  })
  let json
  try { json = await call() } catch (error) {
    if (error.status !== 401 || !account.credential.refreshToken) throw error
    account.credential = await refreshClaudeToken(account.credential)
    json = await call()
  }
  const windows = []
  if (json.five_hour) windows.push({ label: "5h", remaining: clamp(100 - Number(json.five_hour.utilization || 0), 0, 100), resetAt: json.five_hour.resets_at })
  if (json.seven_day) windows.push({ label: "7d", remaining: clamp(100 - Number(json.seven_day.utilization || 0), 0, 100), resetAt: json.seven_day.resets_at })
  if (!windows.length) throw new Error("Claude quota windows missing")
  return quotaSnapshot(account, windows)
}

async function refreshClaudeToken(c) {
  const json = await requestJSON("https://platform.claude.com/v1/oauth/token", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      grant_type: "refresh_token",
      refresh_token: c.refreshToken,
      client_id: c.clientID || "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    })
  })
  return { ...c, accessToken: json.access_token, refreshToken: json.refresh_token || c.refreshToken }
}

async function refreshKimi(account) {
  const c = account.credential
  if (c.authenticationMode === "apiKey") {
    const base = apiV1Base(c.baseURL, "https://api.moonshot.cn")
    const json = await requestJSON(`${base}/users/me/balance`, { headers: bearerHeaders(c.accessToken) })
    const data = json.data || {}
    return balanceSnapshot(account, "¥", Number(data.available_balance || data.availableBalance || 0))
  }
  const call = async () => await requestJSON("https://api.kimi.com/coding/v1/usages", {
    headers: { ...bearerHeaders(account.credential.accessToken), ...(account.credential.deviceHeaders || {}) }
  })
  let json
  try { json = await call() } catch (error) {
    if (![401, 403].includes(error.status) || !account.credential.refreshToken) throw error
    account.credential = await refreshKimiToken(account.credential)
    json = await call()
  }
  const windows = []
  for (const entry of json.limits || []) {
    const detail = entry.detail || entry
    const limit = Number(detail.limit || 0)
    if (!limit) continue
    const used = detail.used != null ? Number(detail.used) : limit - Number(detail.remaining || limit)
    windows.push({ label: kimiWindowLabel(entry.window || entry), remaining: clamp((limit - used) / limit * 100, 0, 100), resetAt: resetDate(detail) })
  }
  if (!windows.length && json.usage) {
    const limit = Number(json.usage.limit || 0)
    const used = Number(json.usage.used || 0)
    if (limit) windows.push({ label: "7d", remaining: clamp((limit - used) / limit * 100, 0, 100), resetAt: resetDate(json.usage) })
  }
  if (!windows.length) throw new Error("Kimi quota windows missing")
  return quotaSnapshot(account, windows)
}

async function refreshKimiToken(c) {
  const json = await requestJSON("https://auth.kimi.com/api/oauth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", ...(c.deviceHeaders || {}) },
    body: formBody({ client_id: c.clientID || "17e5f671-d194-4dfb-9706-5516cb48c098", grant_type: "refresh_token", refresh_token: c.refreshToken })
  })
  return { ...c, accessToken: json.access_token, refreshToken: json.refresh_token || c.refreshToken }
}

async function refreshDeepSeek(account) {
  const c = account.credential
  const base = normalizedBase(c.baseURL, "https://api.deepseek.com")
  const json = await requestJSON(`${base}/user/balance`, { headers: bearerHeaders(c.accessToken) })
  const infos = json.balance_infos || []
  const selected = infos.find(x => x.currency === "CNY") || infos.find(x => x.currency === "USD") || infos[0]
  if (!selected) throw new Error("DeepSeek balance missing")
  return balanceSnapshot(account, selected.currency === "CNY" ? "¥" : selected.currency === "USD" ? "$" : `${selected.currency} `, Number(selected.total_balance || 0))
}

async function refreshMiniMax(account) {
  const c = account.credential
  const base = normalizedBase(c.baseURL, "https://api.minimax.io")
  const json = await requestJSON(`${base}/v1/api/openplatform/coding_plan/remains`, { headers: bearerHeaders(c.accessToken) })
  const data = json.data || json
  const total = numberFrom(data, ["totalUsage", "total_usage", "limit"])
  const used = numberFrom(data, ["currentUsage", "current_usage", "used"])
  if (total > 0 && used != null) return quotaSnapshot(account, [{ label: "Plan", remaining: clamp((total - used) / total * 100, 0, 100) }])
  return metricSnapshot(account, "Connected")
}

async function refreshGLM(account) {
  const c = account.credential
  const base = normalizedBase(c.baseURL, "https://open.bigmodel.cn")
  let lastError
  for (const endpoint of [`${base}/api/monitor/usage/quota/limit`, `${base}/api/paas/v4/usage/quota`]) {
    try {
      const json = await requestJSON(endpoint, { headers: bearerHeaders(c.accessToken) })
      const data = json.data || json.result || json
      const percentage = numberFrom(data, ["remainingPercent", "remaining_percent", "percentage"])
      if (percentage != null) return quotaSnapshot(account, [{ label: "Plan", remaining: clamp(percentage, 0, 100) }])
      const remaining = numberFrom(data, ["remaining", "balance", "quota"])
      if (remaining != null) return metricSnapshot(account, String(remaining))
    } catch (error) { lastError = error }
  }
  throw lastError || new Error("GLM quota unavailable")
}

async function refreshCopilot(account) {
  const c = account.credential
  const base = normalizedBase(c.baseURL, "https://api.github.com")
  const json = await requestJSON(`${base}/copilot_internal/user`, {
    headers: { Authorization: `token ${c.accessToken}`, "User-Agent": "QuotaPulseScriptable" }
  })
  const windows = []
  for (const [key, value] of Object.entries(json.quota_snapshots || {})) {
    let remaining = value.percent_remaining
    if (remaining == null && Number(value.entitlement || 0) > 0) remaining = Number(value.remaining || 0) / Number(value.entitlement) * 100
    if (remaining != null) windows.push({ label: key.replace(/_/g, " "), remaining: clamp(Number(remaining), 0, 100) })
  }
  if (!windows.length) throw new Error("Copilot quota missing")
  return quotaSnapshot(account, windows)
}

async function requestJSON(url, options = {}) {
  const request = new Request(url)
  request.method = options.method || "GET"
  request.headers = { Accept: "application/json", ...(options.headers || {}) }
  request.timeoutInterval = 20
  if (options.body != null) request.body = options.body
  let text
  try { text = await request.loadString() } catch (error) {
    const status = request.response ? request.response.statusCode : 0
    throw new HTTPError(status, `${status || "Network"}: ${error.message || error}`)
  }
  const status = request.response ? request.response.statusCode : 0
  if (status < 200 || status >= 300) throw new HTTPError(status, `HTTP ${status}: ${text.slice(0, 240)}`)
  try { return JSON.parse(text) } catch (_) { throw new HTTPError(status, "Invalid JSON response") }
}

class HTTPError extends Error {
  constructor(status, message) { super(message); this.status = status }
}

function quotaSnapshot(account, windows) {
  return { accountID: account.id, provider: account.provider, label: account.label, kind: "quota", windows, fetchedAt: new Date().toISOString() }
}

function balanceSnapshot(account, symbol, value) {
  return { accountID: account.id, provider: account.provider, label: account.label, kind: "balance", symbol, value, fetchedAt: new Date().toISOString() }
}

function metricSnapshot(account, value) {
  return { accountID: account.id, provider: account.provider, label: account.label, kind: "metric", value, fetchedAt: new Date().toISOString() }
}

function buildWidget(payload, snapshots) {
  const widget = new ListWidget()
  widget.backgroundColor = Color.dynamic(new Color("#F0F1F2"), new Color("#0B0D0E"))
  widget.setPadding(12, 12, 12, 12)
  widget.url = "quotapulse://accounts"

  const header = widget.addStack()
  header.centerAlignContent()
  const title = header.addText("QuotaPulse")
  title.font = Font.boldSystemFont(14)
  title.textColor = Color.dynamic(new Color("#14171F"), Color.white())
  header.addSpacer()
  const live = header.addText("● LIVE")
  live.font = Font.boldSystemFont(9)
  live.textColor = GREEN
  widget.addSpacer(8)

  const family = config.widgetFamily || "medium"
  const limit = family === "small" ? 1 : family === "large" ? 6 : 3
  if (!snapshots.length) {
    const empty = widget.addText(t("没有可显示账号", "No accounts to display"))
    empty.font = Font.systemFont(11)
    empty.textColor = Color.gray()
    return widget
  }
  for (const snapshot of snapshots.slice(0, limit)) {
    addAccountCard(widget, snapshot, family)
    widget.addSpacer(6)
  }
  return widget
}

function addAccountCard(widget, snapshot, family) {
  const card = widget.addStack()
  card.layoutVertically()
  card.backgroundColor = Color.dynamic(Color.white(), new Color("#17191A"))
  card.cornerRadius = 10
  card.setPadding(7, 9, 7, 9)
  const top = card.addStack()
  top.centerAlignContent()
  const dot = top.addText("●")
  dot.font = Font.systemFont(8)
  dot.textColor = providerColor(snapshot.provider)
  top.addSpacer(5)
  const name = top.addText(snapshot.label || snapshot.provider)
  name.font = Font.semiboldSystemFont(11)
  name.lineLimit = 1
  top.addSpacer()
  const summary = top.addText(snapshotSummary(snapshot))
  summary.font = Font.boldSystemFont(12)
  summary.textColor = snapshot.kind === "error" ? RED : snapshot.kind === "quota" ? GREEN : providerColor(snapshot.provider)
  if (snapshot.stale) {
    top.addSpacer(5)
    const stale = top.addText(t("缓存", "Cached"))
    stale.font = Font.systemFont(8)
    stale.textColor = ORANGE
  }

  if (snapshot.kind === "quota" && snapshot.windows && family !== "small") {
    for (const window of snapshot.windows.slice(0, 2)) {
      card.addSpacer(4)
      const row = card.addStack()
      const label = row.addText(window.label)
      label.font = Font.systemFont(8)
      label.textColor = Color.gray()
      row.addSpacer()
      const percent = row.addText(`${Math.round(window.remaining)}%`)
      percent.font = Font.boldSystemFont(9)
      percent.textColor = GREEN
      card.addSpacer(2)
      const image = card.addImage(progressImage(window.remaining / 100, family === "large" ? 220 : 130, 4))
      image.imageSize = new Size(family === "large" ? 220 : 130, 4)
    }
  }
  if (snapshot.error && snapshot.kind === "error") {
    card.addSpacer(3)
    const error = card.addText(String(snapshot.error))
    error.font = Font.systemFont(7)
    error.textColor = RED
    error.lineLimit = 1
  }
}

function setupWidget() {
  const widget = new ListWidget()
  widget.backgroundColor = Color.dynamic(new Color("#F0F1F2"), new Color("#0B0D0E"))
  widget.setPadding(14, 14, 14, 14)
  const title = widget.addText("QuotaPulse")
  title.font = Font.boldSystemFont(15)
  title.textColor = GREEN
  widget.addSpacer(8)
  const text = widget.addText(t("请在 Scriptable App 中运行脚本并导入配置", "Run this script in the Scriptable app and import configuration"))
  text.font = Font.systemFont(11)
  text.textColor = Color.gray()
  return widget
}

function progressImage(ratio, width, height) {
  const draw = new DrawContext()
  draw.size = new Size(width, height)
  draw.opaque = false
  draw.respectScreenScale = true
  fillCapsule(draw, 0, width, height, Color.dynamic(new Color("#E5E7EA"), new Color("#303235")))
  fillCapsule(draw, 0, Math.max(height, width * clamp(ratio, 0, 1)), height, GREEN)
  return draw.getImage()
}

function fillCapsule(draw, x, width, height, color) {
  const safeWidth = Math.max(height, width)
  draw.setFillColor(color)
  if (safeWidth > height) {
    draw.fillRect(new Rect(x + height / 2, 0, safeWidth - height, height))
  }
  draw.fillEllipse(new Rect(x, 0, height, height))
  draw.fillEllipse(new Rect(x + safeWidth - height, 0, height, height))
}

function snapshotSummary(snapshot) {
  if (snapshot.kind === "balance") return `${snapshot.symbol || ""}${Number(snapshot.value || 0).toFixed(2)}`
  if (snapshot.kind === "quota") {
    const values = (snapshot.windows || []).map(x => Number(x.remaining))
    return values.length ? `${Math.round(Math.min(...values))}%` : "--"
  }
  if (snapshot.kind === "metric") return String(snapshot.value || "--")
  return "Error"
}

function providerColor(provider) {
  const colors = {
    codex: "#ED571A", claude: "#F51A47", kimi: "#29A657",
    deepseek: "#14948C", minimax: "#F5991A", glm: "#3D7DE0", copilot: "#8A59C7"
  }
  return new Color(colors[provider] || "#29A657")
}

function bearerHeaders(token) { return { Authorization: `Bearer ${token}`, Accept: "application/json" } }
function normalizedBase(value, fallback) { return String(value || fallback).replace(/\/+$/, "") }
function apiV1Base(value, fallback) { const base = normalizedBase(value, fallback); return base.toLowerCase().endsWith("/v1") ? base : `${base}/v1` }
function formBody(values) { return Object.entries(values).map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join("&") }
function clamp(value, low, high) { return Math.min(high, Math.max(low, Number(value))) }
function numberFrom(value, keys) { for (const key of keys) if (value[key] != null && !Number.isNaN(Number(value[key]))) return Number(value[key]); return null }
function resetDate(value) {
  for (const key of ["reset_at", "resetAt", "reset_time", "resetTime"]) if (value[key] != null) return value[key]
  for (const key of ["reset_after_seconds", "resetIn", "reset_in", "ttl"]) if (value[key] != null) return new Date(Date.now() + Number(value[key]) * 1000).toISOString()
  return null
}
function durationLabel(seconds) { if (seconds > 0 && seconds <= 21600) return `${Math.max(1, Math.round(seconds / 3600))}h`; if (seconds >= 518400 && seconds <= 691200) return "7d"; if (seconds > 21600) return `${Math.max(1, Math.round(seconds / 86400))}d`; return "Quota" }
function kimiWindowLabel(window) { const duration = Number(window.duration || 0); const unit = String(window.timeUnit || window.time_unit || "").toUpperCase(); const seconds = unit.includes("DAY") ? duration * 86400 : unit.includes("HOUR") ? duration * 3600 : unit.includes("MINUTE") ? duration * 60 : duration; return durationLabel(seconds) }
function t(zh, en) { return isChinese ? zh : en }
async function showMessage(title, message) { const alert = new Alert(); alert.title = title; alert.message = message; alert.addAction("OK"); await alert.presentAlert() }
