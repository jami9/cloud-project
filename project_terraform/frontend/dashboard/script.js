const API = "http://192.168.56.110:8000/api";
function setTheme(mode) {
  if (mode === 'light') {
    document.body.classList.add('light');
    localStorage.setItem('theme', 'light');
    document.getElementById('themeToggle').innerText = '☀️ Light';
  } else {
    document.body.classList.remove('light');
    localStorage.setItem('theme', 'dark');
    document.getElementById('themeToggle').innerText = '🌙 Dark';
  }
}

function toggleTheme() {
  const isLight = document.body.classList.contains('light');
  setTheme(isLight ? 'dark' : 'light');
}

// auto-load theme
window.addEventListener('DOMContentLoaded', () => {
  const saved = localStorage.getItem('theme') || 'dark';
  setTheme(saved);
});
// ─── STATE ────────────────────────────────────────────────────────────────────
let _projects = [], _users = [];
let _ctx = { project: "", user: "" };

// ─── FLASH ────────────────────────────────────────────────────────────────────
function flash() {
  const el = document.getElementById("flash");
  el.classList.add("on");
  setTimeout(() => el.classList.remove("on"), 200);
}

// ─── TOAST ────────────────────────────────────────────────────────────────────
function toast(msg, type = "success") {
  const c = document.getElementById("toastCont");
  const t = document.createElement("div");
  t.className = `tst ${type}`;
  t.textContent = msg;
  c.appendChild(t);
  setTimeout(() => t.remove(), type === "error" ? 6000 : 3500);
}

// ─── ERROR BANNER inside panel ────────────────────────────────────────────────
function showErr(bannerId, msg) {
  const el = document.getElementById(bannerId);
  if (!el) return;
  if (msg) {
    el.textContent = "❌ " + msg;
    el.classList.add("show");
  } else {
    el.textContent = "";
    el.classList.remove("show");
  }
}

// ─── FETCH HELPER ─────────────────────────────────────────────────────────────
async function api(path, opts = {}) {
  try {
    const res = await fetch(`${API}${path}`, {
      headers: { "Content-Type": "application/json" },
      ...opts
    });
    const data = await res.json();
    if (!res.ok) {
      const msg = data?.error || `HTTP ${res.status}`;
      throw new Error(msg);
    }
    // Si la réponse contient un champ error (vient de Flask)
    if (data && data.error) throw new Error(data.error);
    return data;
  } catch (e) {
    const el = document.getElementById("connStatus");
    el.textContent = "⚠ Error"; el.style.color = "#f87171";
    // Reset après 5s
    setTimeout(() => { el.textContent = "Connected"; el.style.color = ""; }, 5000);
    throw e; // relancer pour que l'appelant puisse afficher l'erreur
  }
}

// ─── HELPERS ──────────────────────────────────────────────────────────────────
function badge(status) {
  if (!status) return '<span class="b b-d">unknown</span>';
  const s = status.toLowerCase();
  if (s === "active") return `<span class="b b-a">active</span>`;
  if (s === "shutoff" || s === "stopped") return `<span class="b b-s">${status}</span>`;
  if (s === "build" || s === "spawning") return `<span class="b b-b">${status}</span>`;
  return `<span class="b b-d">${status}</span>`;
}

function setCount(id, v) {
  const el = document.getElementById(id);
  if (!el) return;
  const prev = el.textContent;
  el.textContent = v;
  if (prev !== String(v) && prev !== "—") {
    el.classList.add("changed");
    setTimeout(() => el.classList.remove("changed"), 600);
  }
}

function setLoading(btnId, loading) {
  const btn = document.getElementById(btnId);
  if (!btn) return;
  btn.disabled = loading;
  btn.style.opacity = loading ? "0.6" : "1";
}

// ─── CONTEXT BAR ─────────────────────────────────────────────────────────────
function onCtxChange() {
  const ps = document.getElementById("ctxProject");
  const us = document.getElementById("ctxUser");
  const np = ps.value, nu = us.value;
  if (np !== _ctx.project || nu !== _ctx.user) {
    flash();
    const bar = document.getElementById("ctxBar");
    bar.classList.add("changed");
    setTimeout(() => bar.classList.remove("changed"), 800);
    _ctx.project = np; _ctx.user = nu;
    loadInfra();
  }
  const pTxt = ps.options[ps.selectedIndex]?.text || "";
  const uTxt = us.options[us.selectedIndex]?.text || "";
  const bdg  = document.getElementById("ctxBadge");
  const btxt = document.getElementById("ctxBadgeTxt");
  const label = [pTxt, uTxt].filter(x => x && !x.includes("All")).join(" / ");
  if (label) { bdg.style.display = "flex"; btxt.textContent = label; }
  else bdg.style.display = "none";
}

function populateCtxSelectors() {
  const ps = document.getElementById("ctxProject");
  const us = document.getElementById("ctxUser");
  const ap = document.getElementById("asgnProj");
  const au = document.getElementById("asgnUser");
  const curP = ps.value, curU = us.value;
  ps.innerHTML = '<option value="">— All Projects —</option>' +
    _projects.map(p => `<option value="${p.ID||p.id}" ${(p.ID||p.id)===curP?"selected":""}>${p.Name||p.name}</option>`).join("");
  us.innerHTML = '<option value="">— All Users —</option>' +
    _users.map(u => `<option value="${u.ID||u.id}" ${(u.ID||u.id)===curU?"selected":""}>${u.Name||u.name}</option>`).join("");
  ap.innerHTML = '<option value="">Select project…</option>' +
    _projects.map(p => `<option value="${p.Name||p.name}">${p.Name||p.name}</option>`).join("");
  au.innerHTML = '<option value="">Select user…</option>' +
    _users.map(u => `<option value="${u.Name||u.name}">${u.Name||u.name}</option>`).join("");
}

// ─── SERVERS ─────────────────────────────────────────────────────────────────
let srvCounts = { active: 0, shutoff: 0, other: 0 };

async function loadServers() {
  try {
    const data = await api("/servers");
    const rows = Array.isArray(data) ? data : [];
    setCount("cS", rows.length); setCount("cS2", `${rows.length} total`);
    srvCounts = { active: 0, shutoff: 0, other: 0 };
    const tbody = document.getElementById("srvBody");
    if (!rows.length) {
      tbody.innerHTML = `<tr><td colspan="5" class="empty">No servers</td></tr>`;
      updateStatusChart(); return;
    }
    tbody.innerHTML = rows.map(s => {
      const st = (s.Status||"").toLowerCase();
      if (st === "active") srvCounts.active++;
      else if (st === "shutoff") srvCounts.shutoff++;
      else srvCounts.other++;
      return `<tr>
        <td class="nm">${s.Name||"—"}</td>
        <td class="idc" title="${s.ID}">${(s.ID||"").substring(0,12)}…</td>
        <td>${badge(s.Status)}</td>
        <td style="font-size:10px;color:var(--mt)">${s.Networks||s["IP Address"]||"—"}</td>
        <td style="display:flex;gap:4px;flex-wrap:wrap">
          <button class="ba bst" onclick="actionVM('${s.ID}','start')">▶</button>
          <button class="ba bsp" onclick="actionVM('${s.ID}','stop')">⏹</button>
          <button class="ba bb" onclick="actionVM('${s.ID}','reboot')">↺</button>
          <button class="ba bd2" onclick="deleteServer('${s.ID}')">✕</button>
        </td></tr>`;
    }).join("");
    updateStatusChart();
  } catch(e) { console.error("loadServers:", e); }
}

async function actionVM(id, action) {
  try {
    await api(`/servers/${id}/action/${action}`, { method: "POST" });
    toast(`Server ${action} sent`, "info");
    setTimeout(loadServers, 1500);
  } catch(e) { toast(`Error: ${e.message}`, "error"); }
}

async function deleteServer(id) {
  if (!confirm("Delete this server?")) return;
  try {
    await api(`/servers/${id}`, { method: "DELETE" });
    toast("Server deleted"); loadServers();
  } catch(e) { toast(`Error: ${e.message}`, "error"); }
}

// BUG FIX: createServer envoie aussi le champ network
async function createServer() {
  showErr("srvCreateErr", "");
  const name    = document.getElementById("srvName").value.trim();
  const flavor  = document.getElementById("srvFlavor").value;
  const image   = document.getElementById("srvImage").value;
  const network = document.getElementById("srvNetwork").value.trim() || "test";
  if (!name) { showErr("srvCreateErr", "Server name is required"); return; }
  setLoading("btnCreateSrv", true);
  try {
    await api("/servers/create", { method: "POST", body: JSON.stringify({ name, flavor, image, network }) });
    toast(`Launching "${name}" on network "${network}"…`);
    document.getElementById("srvName").value = "";
    setTimeout(loadServers, 2500);
  } catch(e) {
    showErr("srvCreateErr", e.message);
    toast(`Create failed: ${e.message}`, "error");
  } finally { setLoading("btnCreateSrv", false); }
}

async function attachFloatingIP() {
  const server = document.getElementById("attachServer").value.trim();
  const ip     = document.getElementById("attachIP").value.trim();
  if (!server || !ip) { toast("Server and IP required", "error"); return; }
  try {
    await api(`/servers/${server}/floatingip`, { method: "POST", body: JSON.stringify({ ip }) });
    toast(`IP ${ip} attached to ${server}`);
    document.getElementById("attachServer").value = "";
    document.getElementById("attachIP").value = "";
    loadFloatingIPs();
  } catch(e) { toast(`Error: ${e.message}`, "error"); }
}

// ─── NETWORKS ────────────────────────────────────────────────────────────────
async function loadNetworks() {
  try {
    const data = await api("/networks");
    const rows = Array.isArray(data) ? data : [];
    setCount("cN", rows.length); setCount("cN2", rows.length);
    const el = document.getElementById("netList");
    if (!rows.length) { el.innerHTML = `<div class="empty">No networks</div>`; return; }
    el.innerHTML = rows.map(n => `
      <div class="li">
        <div><div class="ln">${n.Name||n.name}</div><div class="ls">${(n.ID||"").substring(0,22)}…</div></div>
        <button class="ba bd2 bic" onclick="deleteNetwork('${n.ID}')">✕</button>
      </div>`).join("");
  } catch(e) { console.error("loadNetworks:", e); }
}

// BUG FIX: createNetwork affiche l'erreur dans le panel
async function createNetwork() {
  showErr("netErr", "");
  const name = document.getElementById("netName").value.trim();
  if (!name) { showErr("netErr", "Network name is required"); return; }
  try {
    await api("/networks/create", { method: "POST", body: JSON.stringify({ name }) });
    toast(`Network "${name}" created`);
    document.getElementById("netName").value = "";
    loadNetworks();
  } catch(e) {
    showErr("netErr", e.message);
    toast(`Error: ${e.message}`, "error");
  }
}

// BUG FIX: deleteNetwork affiche l'erreur retournée par Flask
async function deleteNetwork(id) {
  try {
    await api(`/networks/${id}`, { method: "DELETE" });
    toast("Network deleted"); loadNetworks();
  } catch(e) {
    toast(`Cannot delete network: ${e.message}`, "error");
  }
}

// ─── SUBNETS ─────────────────────────────────────────────────────────────────
async function loadSubnets() {
  try {
    const data = await api("/subnets");
    const rows = Array.isArray(data) ? data : [];
    setCount("cSub", rows.length); setCount("cSub2", rows.length);
    const el = document.getElementById("subList");
    if (!rows.length) { el.innerHTML = `<div class="empty">No subnets</div>`; return; }
    el.innerHTML = rows.map(s => `
      <div class="li">
        <div><div class="ln">${s.Name||s.name}</div><div class="ls">${s.Subnet||s.cidr||""}</div></div>
        <button class="ba bd2 bic" onclick="deleteSubnet('${s.ID||s.id}')">✕</button>
      </div>`).join("");
  } catch(e) { console.error("loadSubnets:", e); }
}

async function createSubnet() {
  showErr("subErr", "");
  const name    = document.getElementById("subName").value.trim();
  const network = document.getElementById("subNet").value.trim();
  const cidr    = document.getElementById("subCIDR").value.trim() || "192.168.100.0/24";
  if (!name || !network) { showErr("subErr", "Name and network required"); return; }
  try {
    await api("/subnets/create", { method: "POST", body: JSON.stringify({ name, network, cidr }) });
    toast(`Subnet "${name}" created`);
    document.getElementById("subName").value = "";
    document.getElementById("subNet").value = "";
    document.getElementById("subCIDR").value = "";
    loadSubnets();
  } catch(e) { showErr("subErr", e.message); toast(`Error: ${e.message}`, "error"); }
}

async function deleteSubnet(id) {
  try {
    await api(`/subnets/${id}`, { method: "DELETE" });
    toast("Subnet deleted"); loadSubnets();
  } catch(e) { toast(`Error: ${e.message}`, "error"); }
}

// ─── ROUTERS ─────────────────────────────────────────────────────────────────
async function loadRouters() {
  try {
    const data = await api("/routers");
    const rows = Array.isArray(data) ? data : [];
    setCount("cR", rows.length); setCount("cR2", rows.length);
    const el = document.getElementById("rtList");
    if (!rows.length) { el.innerHTML = `<div class="empty">No routers</div>`; return; }
    el.innerHTML = rows.map(r => `
      <div class="li">
        <div><div class="ln">${r.Name||r.name}</div><div class="ls">${badge(r.Status||r.state)}</div></div>
        <button class="ba bd2 bic" onclick="deleteRouter('${r.ID||r.id}')">✕</button>
      </div>`).join("");
  } catch(e) { console.error("loadRouters:", e); }
}

async function createRouter() {
  const name = document.getElementById("rtName").value.trim();
  if (!name) { toast("Name required", "error"); return; }
  try {
    await api("/routers/create", { method: "POST", body: JSON.stringify({ name }) });
    toast(`Router "${name}" created`);
    document.getElementById("rtName").value = "";
    loadRouters();
  } catch(e) { toast(`Error: ${e.message}`, "error"); }
}

async function deleteRouter(id) {
  try {
    await api(`/routers/${id}`, { method: "DELETE" });
    toast("Router deleted"); loadRouters();
  } catch(e) { toast(`Error: ${e.message}`, "error"); }
}

async function routerAddSubnet() {
  const router = document.getElementById("rtSubRouter").value.trim();
  const subnet = document.getElementById("rtSubSub").value.trim();
  if (!router || !subnet) { toast("Router and subnet required", "error"); return; }
  try {
    await api(`/routers/${router}/subnet`, { method: "POST", body: JSON.stringify({ subnet }) });
    toast(`Subnet "${subnet}" added to "${router}"`);
  } catch(e) { toast(`Error: ${e.message}`, "error"); }
}

async function routerRemoveSubnet() {
  const router = document.getElementById("rtSubRouter").value.trim();
  const subnet = document.getElementById("rtSubSub").value.trim();
  if (!router || !subnet) { toast("Router and subnet required", "error"); return; }
  try {
    await api(`/routers/${router}/subnet`, { method: "DELETE", body: JSON.stringify({ subnet }) });
    toast(`Subnet "${subnet}" removed from "${router}"`);
  } catch(e) { toast(`Error: ${e.message}`, "error"); }
}

// ─── FLOATING IPs ────────────────────────────────────────────────────────────
async function loadFloatingIPs() {
  try {
    const data = await api("/floatingips");
    const rows = Array.isArray(data) ? data : [];
    setCount("cIP", rows.length); setCount("cIP2", rows.length);
    const el = document.getElementById("ipList");
    if (!rows.length) { el.innerHTML = `<div class="empty">No floating IPs</div>`; return; }
    el.innerHTML = rows.map(ip => `
      <div class="li">
        <div>
          <div class="ln">${ip["Floating IP Address"]||ip.floating_ip_address||ip.ip||"—"}</div>
          <div class="ls">${ip.Status||ip.status||"—"} · Fixed: ${ip["Fixed IP Address"]||ip.fixed_ip_address||"unassigned"}</div>
        </div>
        <button class="ba bd2 bic" onclick="deleteFloatingIP('${ip.ID||ip.id}')">✕</button>
      </div>`).join("");
  } catch(e) { console.error("loadFloatingIPs:", e); }
}

async function createFloatingIP() {
  try {
    await api("/floatingips/create", { method: "POST", body: JSON.stringify({ network: "external" }) });
    toast("Floating IP allocated");
    loadFloatingIPs();
  } catch(e) { toast(`Error: ${e.message}`, "error"); }
}

async function deleteFloatingIP(id) {
  try {
    await api(`/floatingips/${id}`, { method: "DELETE" });
    toast("Floating IP released"); loadFloatingIPs();
  } catch(e) { toast(`Error: ${e.message}`, "error"); }
}

// ─── PORTS ───────────────────────────────────────────────────────────────────
async function loadPorts() {
  try {
    const data = await api("/ports");
    const rows = Array.isArray(data) ? data : [];
    setCount("cP", rows.length); setCount("cP2", rows.length);
    const el = document.getElementById("portList");
    if (!rows.length) { el.innerHTML = `<div class="empty">No ports</div>`; return; }
    el.innerHTML = rows.slice(0,20).map(p => `
      <div class="li">
        <div>
          <div class="ln" style="font-size:10px">${p["Fixed IP Addresses"]||p.fixed_ips||p.Name||"—"}</div>
          <div class="ls">${p["MAC Address"]||p.mac_address||""}</div>
        </div>
        <div class="lact">
          <span class="b ${(p.Status||"").toLowerCase()==="active"?"b-a":"b-d"}">${p.Status||"—"}</span>
          <button class="ba bd2 bic" onclick="deletePort('${p.ID||p.id}')">✕</button>
        </div>
      </div>`).join("");
    if (rows.length > 20) el.innerHTML += `<div class="empty">+${rows.length-20} more</div>`;
  } catch(e) { console.error("loadPorts:", e); }
}

async function deletePort(id) {
  try {
    await api(`/ports/${id}`, { method: "DELETE" });
    toast("Port deleted"); loadPorts();
  } catch(e) { toast(`Error: ${e.message}`, "error"); }
}

// ─── IMAGES & FLAVORS ────────────────────────────────────────────────────────
async function loadImages() {
  try {
    const data = await api("/images");
    if (!Array.isArray(data)) return;
    setCount("cImg", data.length);
    const sel = document.getElementById("srvImage");
    if (data.length) {
      sel.innerHTML = data.map(img =>
        `<option value="${img.Name||img.name}">${img.Name||img.name}</option>`).join("");
    }
  } catch(e) { console.error("loadImages:", e); }
}

async function loadFlavors() {
  try {
    const data = await api("/flavors");
    if (!Array.isArray(data) || !data.length) return;
    const sel = document.getElementById("srvFlavor");
    sel.innerHTML = data.map(f => {
      const name = f.Name || f.name || f.id;
      const ram  = f.RAM  || f.ram  ? ` (${Math.round((f.RAM||f.ram)/1024*10)/10}GB RAM)` : "";
      return `<option value="${name}">${name}${ram}</option>`;
    }).join("");
  } catch(e) { console.error("loadFlavors:", e); }
}

// ─── HYPERVISOR — BUG FIX ────────────────────────────────────────────────────
// Le backend essaie: hypervisor list → hypervisor stats show → quota show admin
// On affiche ce qui est retourné avec des barres de ressources
async function loadHypervisors() {
  const body = document.getElementById("hypBody");
  const src  = document.getElementById("hypSource");
  try {
    const data = await api("/hypervisors");
    if (!Array.isArray(data) || !data.length) {
      body.innerHTML = `<div class="empty">Hypervisor data unavailable — check microstack permissions</div>`;
      return;
    }
    // Détecter la source (quota fallback vs vraies stats)
    const isQuota = data[0]["Hypervisor Hostname"]?.includes("quota");
    if (src) {
      src.style.display = "inline";
      src.textContent = isQuota ? "quota show" : "hypervisor stats show";
    }
    body.innerHTML = data.map(h => {
      const cu = parseInt(h["vCPUs Used"])||0;
      const ct = parseInt(h["vCPUs"])||1;
      const ru = parseInt(h["Memory MB Used"])||0;
      const rt = parseInt(h["Memory MB"])||1;
      const du = parseInt(h["Local GB Used"])||0;
      const dt = parseInt(h["Local GB"])||1;
      const cp = Math.min(100, Math.round((cu/ct)*100));
      const rp = Math.min(100, Math.round((ru/rt)*100));
      const dp = Math.min(100, Math.round((du/dt)*100));
      const vms = h["Running VMs"] !== undefined ? h["Running VMs"] : "—";
      return `
        <div style="margin-bottom:20px">
          <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px">
            <span style="color:#fff;font-weight:700;font-family:'Space Mono',monospace;font-size:12px">
              🖥 ${h["Hypervisor Hostname"]||"Hypervisor"}
            </span>
            <span class="b ${h.State==="up"?"b-a":"b-d"}">${h.State||"unknown"}</span>
          </div>
          <div class="g3" style="gap:14px">
            <div>
              <div class="rl"><span>vCPU</span><span>${cu} / ${ct} (${cp}%)</span></div>
              <div class="rt"><div class="rf" style="width:${cp}%"></div></div>
            </div>
            <div>
              <div class="rl"><span>RAM</span><span>${Math.round(ru/1024*10)/10} / ${Math.round(rt/1024*10)/10} GB (${rp}%)</span></div>
              <div class="rt"><div class="rf bl" style="width:${rp}%"></div></div>
            </div>
            <div>
              <div class="rl"><span>Disk</span><span>${du} / ${dt} GB (${dp}%)</span></div>
              <div class="rt"><div class="rf yw" style="width:${dp}%"></div></div>
            </div>
          </div>
          ${vms !== "—" ? `<div style="margin-top:8px;font-size:10px;color:var(--mt);font-family:'Space Mono',monospace">Running VMs: <span style="color:#fff">${vms}</span></div>` : ""}
        </div>`;
    }).join("");
  } catch(e) {
    body.innerHTML = `<div class="empty" style="color:var(--rd)">Error: ${e.message}</div>`;
  }
}

// ─── PROJECTS — BUG FIX ──────────────────────────────────────────────────────
async function loadProjects() {
  try {
    const data = await api("/projects");
    if (!Array.isArray(data)) return;
    _projects = data;
    setCount("cPrj", data.length); setCount("cPrj2", data.length);
    const el = document.getElementById("prjList");
    if (!data.length) { el.innerHTML = `<div class="empty">No projects</div>`; return; }
    el.innerHTML = data.map(p => `
      <div class="li">
        <div>
          <div class="ln">${p.Name||p.name}</div>
          <div class="ls" style="display:flex;gap:5px;margin-top:2px">
            <span class="${(p.Enabled||p.enabled)?"b-en":"b-dis"}">${(p.Enabled||p.enabled)?"enabled":"disabled"}</span>
            <span>${p.Domain||p.domain_id||"default"}</span>
          </div>
        </div>
        <button class="ba bd2 bic" onclick="deleteProject('${p.ID||p.id}','${(p.Name||p.name).replace(/'/g,"")}')">✕</button>
      </div>`).join("");
  } catch(e) { console.error("loadProjects:", e); }
}

// BUG FIX: error banner + loading state
async function createProject() {
  showErr("prjErr", "");
  const name   = document.getElementById("prjName").value.trim();
  const domain = document.getElementById("prjDomain").value || "default";
  const desc   = document.getElementById("prjDesc").value.trim();
  if (!name) { showErr("prjErr", "Project name is required"); return; }
  setLoading("btnCreatePrj", true);
  try {
    await api("/projects/create", { method: "POST", body: JSON.stringify({ name, domain, description: desc }) });
    toast(`Project "${name}" created`);
    document.getElementById("prjName").value = "";
    document.getElementById("prjDesc").value = "";
    await loadProjects();
    populateCtxSelectors();
  } catch(e) {
    showErr("prjErr", e.message);
    toast(`Create project failed: ${e.message}`, "error");
  } finally { setLoading("btnCreatePrj", false); }
}

async function deleteProject(id, name) {
  if (!confirm(`Delete project "${name}"?`)) return;
  try {
    await api(`/projects/${id}`, { method: "DELETE" });
    toast(`Project "${name}" deleted`);
    await loadProjects(); populateCtxSelectors();
  } catch(e) { toast(`Error: ${e.message}`, "error"); }
}

// ─── USERS — BUG FIX ─────────────────────────────────────────────────────────
async function loadUsers() {
  try {
    const data = await api("/users");
    if (!Array.isArray(data)) return;
    _users = data;
    setCount("cU", data.length); setCount("cU2", data.length);
    const el = document.getElementById("usrList");
    if (!data.length) { el.innerHTML = `<div class="empty">No users</div>`; return; }
    el.innerHTML = data.map(u => `
      <div class="li">
        <div>
          <div class="ln">${u.Name||u.name}</div>
          <div class="ls" style="display:flex;gap:5px;margin-top:2px">
            <span class="${(u.Enabled||u.enabled)?"b-en":"b-dis"}">${(u.Enabled||u.enabled)?"enabled":"disabled"}</span>
            <span>${u.Email||u.email||""}</span>
          </div>
        </div>
        <button class="ba bd2 bic" onclick="deleteUser('${u.ID||u.id}','${(u.Name||u.name).replace(/'/g,"")}')">✕</button>
      </div>`).join("");
  } catch(e) { console.error("loadUsers:", e); }
}

// BUG FIX: error banner + loading state + password bien transmis
async function createUser() {
  showErr("usrErr", "");
  const name   = document.getElementById("usrName").value.trim();
  const pwd    = document.getElementById("usrPwd").value; // ne pas trim le mot de passe !
  const domain = document.getElementById("usrDomain").value || "default";
  const email  = document.getElementById("usrEmail").value.trim();
  if (!name) { showErr("usrErr", "Username is required"); return; }
  if (!pwd)  { showErr("usrErr", "Password is required"); return; }
  setLoading("btnCreateUsr", true);
  try {
    await api("/users/create", { method: "POST", body: JSON.stringify({ name, password: pwd, domain, email }) });
    toast(`User "${name}" created`);
    document.getElementById("usrName").value = "";
    document.getElementById("usrPwd").value  = "";
    document.getElementById("usrEmail").value = "";
    await loadUsers(); populateCtxSelectors();
  } catch(e) {
    showErr("usrErr", e.message);
    toast(`Create user failed: ${e.message}`, "error");
  } finally { setLoading("btnCreateUsr", false); }
}

async function deleteUser(id, name) {
  if (!confirm(`Delete user "${name}"?`)) return;
  try {
    await api(`/users/${id}`, { method: "DELETE" });
    toast(`User "${name}" deleted`);
    await loadUsers(); populateCtxSelectors();
  } catch(e) { toast(`Error: ${e.message}`, "error"); }
}

// ─── ROLES ───────────────────────────────────────────────────────────────────
async function loadRoles() {
  try {
    const [roles, assignments] = await Promise.all([api("/roles"), api("/roles/assignments")]);
    const rEl = document.getElementById("rolesList");
    if (roles && Array.isArray(roles)) {
      rEl.innerHTML = roles.map(r => `<span class="b-r">${r.Name||r.name}</span>`).join("");
      setCount("cRl2", roles.length);
      const sel = document.getElementById("asgnRole");
      if (roles.length) sel.innerHTML = roles.map(r =>
        `<option value="${r.Name||r.name}">${r.Name||r.name}</option>`).join("");
    }
    const aEl = document.getElementById("asgnList");
    if (!assignments || !Array.isArray(assignments) || !assignments.length) {
      aEl.innerHTML = `<div class="empty">No assignments found</div>`; return;
    }
    aEl.innerHTML = assignments.map(a => {
      const role = a.Role||a.role_name||"—";
      const user = a.User||a.user_name||"—";
      const proj = a.Project||a.project_name||"—";
      return `<div class="ar"><span class="b-r">${role}</span><span style="color:var(--mt)">→</span><span style="color:#fff">${user}</span><span style="color:var(--mt)">@</span><span style="color:var(--bl)">${proj}</span></div>`;
    }).join("");
  } catch(e) { console.error("loadRoles:", e); }
}

async function addRole() {
  showErr("roleErr", "");
  const user = document.getElementById("asgnUser").value.trim();
  const proj = document.getElementById("asgnProj").value.trim();
  const role = document.getElementById("asgnRole").value.trim();
  if (!user || !proj) { showErr("roleErr", "Select user and project"); return; }
  try {
    await api("/roles/add", { method: "POST", body: JSON.stringify({ user, project: proj, role }) });
    toast(`Role "${role}" → ${user} @ ${proj}`);
    loadRoles();
  } catch(e) { showErr("roleErr", e.message); toast(`Error: ${e.message}`, "error"); }
}

async function removeRole() {
  showErr("roleErr", "");
  const user = document.getElementById("asgnUser").value.trim();
  const proj = document.getElementById("asgnProj").value.trim();
  const role = document.getElementById("asgnRole").value.trim();
  if (!user || !proj) { showErr("roleErr", "Select user and project"); return; }
  if (!confirm(`Remove "${role}" from ${user} @ ${proj}?`)) return;
  try {
    await api("/roles/remove", { method: "POST", body: JSON.stringify({ user, project: proj, role }) });
    toast("Role removed"); loadRoles();
  } catch(e) { showErr("roleErr", e.message); toast(`Error: ${e.message}`, "error"); }
}

// ─── CHARTS ──────────────────────────────────────────────────────────────────
const cpuChart = new Chart(document.getElementById("cpuChart"), {
  type: "line",
  data: { labels: [], datasets: [{ label:"CPU %", data:[], borderColor:"#f97316", backgroundColor:"rgba(249,115,22,.1)", tension:0.4, fill:true, pointRadius:2 }] },
  options: { animation:false, scales: { y:{beginAtZero:true,max:100,ticks:{color:"#71717a",font:{family:"Space Mono",size:9}},grid:{color:"rgba(255,255,255,.04)"}}, x:{ticks:{color:"#71717a",font:{family:"Space Mono",size:9}},grid:{display:false}} }, plugins:{legend:{display:false}} }
});

let statusChart = null;
function updateStatusChart() {
  const ctx = document.getElementById("statusChart");
  if (statusChart) statusChart.destroy();
  const t = srvCounts.active + srvCounts.shutoff + srvCounts.other;
  if (!t) return;
  statusChart = new Chart(ctx, {
    type: "doughnut",
    data: { labels:["Active","Shutoff","Other"], datasets:[{ data:[srvCounts.active,srvCounts.shutoff,srvCounts.other], backgroundColor:["rgba(74,222,128,.8)","rgba(248,113,113,.8)","rgba(113,113,122,.8)"], borderWidth:0 }] },
    options: { cutout:"68%", plugins:{ legend:{ position:"bottom", labels:{ color:"#71717a", font:{family:"Space Mono",size:9}, boxWidth:8 } } } }
  });
}

function tickCPU() {
  const now = new Date().toLocaleTimeString();
  cpuChart.data.labels.push(now);
  cpuChart.data.datasets[0].data.push(Math.floor(Math.random()*60+10));
  if (cpuChart.data.labels.length > 14) { cpuChart.data.labels.shift(); cpuChart.data.datasets[0].data.shift(); }
  cpuChart.update("none");
}

// ─── LOAD INFRA ──────────────────────────────────────────────────────────────
async function loadInfra() {
  await Promise.all([
    loadServers(), loadNetworks(), loadSubnets(),
    loadRouters(), loadFloatingIPs(), loadPorts(),
    loadImages(), loadFlavors(), loadHypervisors()
  ]);
}

// ─── LOAD ALL ────────────────────────────────────────────────────────────────
async function loadAll() {
  await Promise.all([loadProjects(), loadUsers()]);
  populateCtxSelectors();
  await Promise.all([loadInfra(), loadRoles()]);
}

// ─── INIT ────────────────────────────────────────────────────────────────────
loadAll();
setInterval(loadInfra, 15000);
setInterval(tickCPU, 2000);
