// ─── Configuration ────────────────────────────────────────────────────────────
const API = "http://192.168.56.110:8000";  // Kong Gateway
// const API = "http://192.168.56.104:5001"; // Backend direct (fallback)

// ─── État global ──────────────────────────────────────────────────────────────
let currentSection = "overview";
let darkMode = true;
let refreshTimer = null;

// ─── Utilitaires ──────────────────────────────────────────────────────────────
async function apiFetch(path, method = "GET", body = null) {
  const opts = { method, headers: { "Content-Type": "application/json" } };
  if (body) opts.body = JSON.stringify(body);
  try {
    const r = await fetch(API + path, opts);
    return await r.json();
  } catch (e) {
    return { ok: false, error: e.message };
  }
}

function toast(msg, type = "success") {
  const t = document.createElement("div");
  t.className = `toast toast-${type}`;
  t.textContent = msg;
  document.getElementById("toast-container").appendChild(t);
  setTimeout(() => t.classList.add("show"), 10);
  setTimeout(() => { t.classList.remove("show"); setTimeout(() => t.remove(), 400); }, 3500);
}

function loading(id) {
  const el = document.getElementById(id);
  if (el) el.innerHTML = `<div class="loader"><div class="spin"></div><span>Chargement...</span></div>`;
}

function badge(status) {
  const s = (status || "").toUpperCase();
  const map = { ACTIVE: "badge-active", ERROR: "badge-error", BUILD: "badge-build",
                SHUTOFF: "badge-off", DOWN: "badge-off", UP: "badge-active" };
  return `<span class="badge ${map[s] || "badge-neutral"}">${s || "—"}</span>`;
}

function confirm_action(msg) {
  return window.confirm(msg);
}

// ─── Navigation ───────────────────────────────────────────────────────────────
function nav(section) {
  currentSection = section;
  document.querySelectorAll(".nav-item").forEach(n => {
    n.classList.toggle("active", n.dataset.section === section);
  });
  document.querySelectorAll(".section").forEach(s => {
    s.classList.toggle("active", s.id === section);
  });
  loadSection(section);
}

function loadSection(s) {
  const fn = {
    overview:        loadOverview,
    projects:        loadProjects,
    users:           loadUsers,
    hypervisors:     loadHypervisors,
    quotas:          loadQuotas,
    networks:        loadNetworks,
    subnets:         loadSubnets,
    instances:       loadInstances,
    ports:           loadPorts,
    routers:         loadRouters,
    "floating-ips":  loadFips,
    images:          loadImages,
    flavors:         loadFlavors,
    "security-groups": loadSGs,
    keypairs:        loadKeypairs,
  };
  if (fn[s]) fn[s]();
}

// ─── Thème ────────────────────────────────────────────────────────────────────
function toggleTheme() {
  darkMode = !darkMode;
  document.documentElement.setAttribute("data-theme", darkMode ? "dark" : "light");
  document.getElementById("theme-btn").textContent = darkMode ? "☀ Clair" : "☾ Sombre";
}

// ─── Vue globale ──────────────────────────────────────────────────────────────
async function loadOverview() {
  loading("overview-cards");
  const r = await apiFetch("/api/overview");
  if (!r) return;
  const h = r.hypervisor || {};
  const cards = [
    { icon: "⬡", label: "vCPUs",       val: `${h.vcpus_used || 0} / ${h.vcpus || 0}`,          color: "orange" },
    { icon: "▣", label: "RAM",         val: `${Math.round((h.memory_mb_used||0)/1024)}/${Math.round((h.memory_mb||0)/1024)} GB`, color: "blue" },
    { icon: "◉", label: "VMs actives", val: h.running_vms || 0,                                   color: "green" },
    { icon: "◈", label: "Projets",     val: r.projects_count  || 0,                              color: "purple" },
    { icon: "◎", label: "Utilisateurs",val: r.users_count     || 0,                              color: "teal" },
    { icon: "⬡", label: "Réseaux",     val: r.networks_count  || 0,                              color: "orange" },
    { icon: "▦", label: "Images",      val: r.images_count    || 0,                              color: "pink" },
    { icon: "◆", label: "Floating IPs",val: r.fips_count      || 0,                              color: "yellow" },
    { icon: "◉", label: "Disque libre",val: `${h.free_disk_gb || 0} GB`,                         color: "green" },
  ];
  document.getElementById("overview-cards").innerHTML = cards.map(c => `
    <div class="card card-${c.color}">
      <div class="card-icon">${c.icon}</div>
      <div class="card-val">${c.val}</div>
      <div class="card-label">${c.label}</div>
    </div>`).join("");
}

// ─── Projets ──────────────────────────────────────────────────────────────────
async function loadProjects() {
  loading("projects-table");
  const r = await apiFetch("/api/projects");
  const rows = (r.data || []).map(p => `
    <tr>
      <td class="mono">${p.ID || p.id || "—"}</td>
      <td><strong>${p.Name || p.name || "—"}</strong></td>
      <td>${p.Description || p.description || "—"}</td>
      <td>${badge(p.Enabled !== false ? "ACTIVE" : "DOWN")}</td>
      <td>
        <button class="btn btn-danger btn-sm" onclick="deleteProject('${p.ID || p.id}','${p.Name || p.name}')">
          ✕ Supprimer
        </button>
      </td>
    </tr>`).join("");
  document.getElementById("projects-table").innerHTML = tableWrap(
    ["ID", "Nom", "Description", "Statut", "Actions"], rows
  );
}

async function createProject() {
  const name = prompt("Nom du projet:");
  if (!name) return;
  const desc = prompt("Description:", "nouveau-projet") || "nouveau-projet";
  const r = await apiFetch("/api/projects", "POST", { name, description: desc });
  r.ok ? toast("Projet créé") : toast(r.error, "error");
  loadProjects();
}

async function deleteProject(id, name) {
  if (!confirm_action(`Supprimer le projet "${name}" ?`)) return;
  const r = await apiFetch(`/api/projects/${id}`, "DELETE");
  r.ok ? toast("Projet supprimé") : toast(r.error, "error");
  loadProjects();
}

// ─── Utilisateurs ─────────────────────────────────────────────────────────────
async function loadUsers() {
  loading("users-table");
  const r = await apiFetch("/api/users");
  const rows = (r.data || []).map(u => `
    <tr>
      <td class="mono">${u.ID || u.id || "—"}</td>
      <td><strong>${u.Name || u.name || "—"}</strong></td>
      <td>${u.Email || u.email || "—"}</td>
      <td>${badge(u.Enabled !== false ? "ACTIVE" : "DOWN")}</td>
      <td>
        <button class="btn btn-danger btn-sm" onclick="deleteUser('${u.ID || u.id}','${u.Name || u.name}')">
          ✕ Supprimer
        </button>
      </td>
    </tr>`).join("");
  document.getElementById("users-table").innerHTML = tableWrap(
    ["ID", "Nom", "Email", "Statut", "Actions"], rows
  );
}

async function createUser() {
  const name = prompt("Nom d'utilisateur:");
  if (!name) return;
  const password = prompt("Mot de passe:", "ChangeMe@2026!") || "ChangeMe@2026!";
  const project  = prompt("Projet:", "admin") || "admin";
  const r = await apiFetch("/api/users", "POST", { name, password, project });
  r.ok ? toast("Utilisateur créé") : toast(r.error, "error");
  loadUsers();
}

async function deleteUser(id, name) {
  if (!confirm_action(`Supprimer l'utilisateur "${name}" ?`)) return;
  const r = await apiFetch(`/api/users/${id}`, "DELETE");
  r.ok ? toast("Utilisateur supprimé") : toast(r.error, "error");
  loadUsers();
}

// ─── Hyperviseurs ─────────────────────────────────────────────────────────────
async function loadHypervisors() {
  loading("hypervisors-content");
  const r = await apiFetch("/api/hypervisors");
  const s = r.stats || {};
  const pct = s.vcpus ? Math.round((s.vcpus_used / s.vcpus) * 100) : 0;
  const ramPct = s.memory_mb ? Math.round((s.memory_mb_used / s.memory_mb) * 100) : 0;
  const diskPct = s.local_gb ? Math.round((s.local_gb_used / s.local_gb) * 100) : 0;
  document.getElementById("hypervisors-content").innerHTML = `
    <div class="hypervisor-grid">
      <div class="hyp-stat">
        <div class="hyp-label">vCPUs</div>
        <div class="hyp-bar"><div class="hyp-fill" style="width:${pct}%"></div></div>
        <div class="hyp-val">${s.vcpus_used || 0} / ${s.vcpus || 0} (${pct}%)</div>
      </div>
      <div class="hyp-stat">
        <div class="hyp-label">RAM</div>
        <div class="hyp-bar"><div class="hyp-fill" style="width:${ramPct}%"></div></div>
        <div class="hyp-val">${Math.round((s.memory_mb_used||0)/1024)} / ${Math.round((s.memory_mb||0)/1024)} GB (${ramPct}%)</div>
      </div>
      <div class="hyp-stat">
        <div class="hyp-label">Disque</div>
        <div class="hyp-bar"><div class="hyp-fill" style="width:${diskPct}%"></div></div>
        <div class="hyp-val">${s.local_gb_used || 0} / ${s.local_gb || 0} GB (${diskPct}%)</div>
      </div>
      <div class="hyp-stat">
        <div class="hyp-label">VMs actives</div>
        <div class="hyp-val-big">${s.running_vms || 0}</div>
      </div>
      <div class="hyp-stat">
        <div class="hyp-label">Charge actuelle</div>
        <div class="hyp-val-big">${s.current_workload || 0}</div>
      </div>
      <div class="hyp-stat">
        <div class="hyp-label">Disque libre min.</div>
        <div class="hyp-val-big">${s.disk_available_least || 0} GB</div>
      </div>
    </div>`;
}

// ─── Quotas ───────────────────────────────────────────────────────────────────
async function loadQuotas() {
  loading("quotas-content");
  const r = await apiFetch("/api/quotas/admin");
  const d = r.data || {};
  const fields = ["cores","ram","instances","floating-ips","networks",
                  "ports","routers","subnets","secgroups","volumes"];
  const rows = fields.map(f => {
    const val = d[f] !== undefined ? d[f] : d[f.replace("-","_")] || "—";
    return `<tr><td>${f}</td><td class="quota-val">${val === -1 ? "∞ illimité" : val}</td>
      <td><button class="btn btn-sm btn-outline" onclick="editQuota('${f}','${val}')">✎ Modifier</button></td></tr>`;
  }).join("");
  document.getElementById("quotas-content").innerHTML = tableWrap(
    ["Ressource", "Limite", "Action"], rows
  );
}

async function editQuota(field, current) {
  const val = prompt(`Nouvelle valeur pour ${field} (actuel: ${current}):`, current);
  if (val === null) return;
  const r = await apiFetch("/api/quotas/admin", "PUT", { [field]: parseInt(val) });
  r.ok ? toast("Quota modifié") : toast(r.error, "error");
  loadQuotas();
}

// ─── Réseaux ──────────────────────────────────────────────────────────────────
async function loadNetworks() {
  loading("networks-table");
  const r = await apiFetch("/api/networks");
  const rows = (r.data || []).map(n => `
    <tr>
      <td class="mono">${(n.ID || n.id || "").slice(0,12)}...</td>
      <td><strong>${n.Name || n.name || "—"}</strong></td>
      <td>${badge(n["Router Type"] || (n.external ? "EXTERNAL" : "INTERNAL"))}</td>
      <td>${n.Subnets || n.subnets || "—"}</td>
      <td>${badge(n["Admin State"] === "UP" ? "ACTIVE" : "DOWN")}</td>
      <td>
        <button class="btn btn-danger btn-sm" onclick="deleteNetwork('${n.ID || n.id}','${n.Name || n.name}')">✕</button>
      </td>
    </tr>`).join("");
  document.getElementById("networks-table").innerHTML = tableWrap(
    ["ID", "Nom", "Type", "Subnets", "État", "Actions"], rows
  );
}

async function createNetwork() {
  const name = prompt("Nom du réseau:");
  if (!name) return;
  const ext = confirm("Réseau externe ?");
  const r = await apiFetch("/api/networks", "POST", { name, external: ext });
  r.ok ? toast("Réseau créé") : toast(r.error, "error");
  loadNetworks();
}

async function deleteNetwork(id, name) {
  if (!confirm_action(`Supprimer le réseau "${name}" ?`)) return;
  const r = await apiFetch(`/api/networks/${id}`, "DELETE");
  r.ok ? toast("Réseau supprimé") : toast(r.error, "error");
  loadNetworks();
}

// ─── Subnets ──────────────────────────────────────────────────────────────────
async function loadSubnets() {
  loading("subnets-table");
  const r = await apiFetch("/api/subnets");
  const rows = (r.data || []).map(s => `
    <tr>
      <td class="mono">${(s.ID || s.id || "").slice(0,12)}...</td>
      <td><strong>${s.Name || s.name || "—"}</strong></td>
      <td class="mono">${s.Subnet || s.cidr || "—"}</td>
      <td>${s.Network || s.network_id || "—"}</td>
      <td>${s["IP Version"] || s.ip_version || "4"}</td>
      <td>
        <button class="btn btn-danger btn-sm" onclick="deleteSubnet('${s.ID || s.id}','${s.Name || s.name}')">✕</button>
      </td>
    </tr>`).join("");
  document.getElementById("subnets-table").innerHTML = tableWrap(
    ["ID", "Nom", "CIDR", "Réseau", "IP Ver.", "Actions"], rows
  );
}

async function createSubnet() {
  const name    = prompt("Nom du subnet:");
  if (!name) return;
  const network = prompt("Réseau parent (nom ou ID):");
  if (!network) return;
  const cidr    = prompt("CIDR:", "192.168.100.0/24") || "192.168.100.0/24";
  const r = await apiFetch("/api/subnets", "POST", { name, network, cidr });
  r.ok ? toast("Subnet créé") : toast(r.error, "error");
  loadSubnets();
}

async function deleteSubnet(id, name) {
  if (!confirm_action(`Supprimer le subnet "${name}" ?`)) return;
  const r = await apiFetch(`/api/subnets/${id}`, "DELETE");
  r.ok ? toast("Subnet supprimé") : toast(r.error, "error");
  loadSubnets();
}

// ─── Instances ────────────────────────────────────────────────────────────────
async function loadInstances() {
  loading("instances-table");
  const r = await apiFetch("/api/instances");
  const rows = (r.data || []).map(i => `
    <tr>
      <td class="mono">${(i.ID || i.id || "").slice(0,12)}...</td>
      <td><strong>${i.Name || i.name || "—"}</strong></td>
      <td>${badge(i.Status || i.status)}</td>
      <td class="mono">${i.Networks || i.networks || "—"}</td>
      <td>${i.Image || i.image || "—"}</td>
      <td>${i.Flavor || i.flavor || "—"}</td>
      <td class="actions-cell">
        <button class="btn btn-sm btn-green"  onclick="instanceAction('${i.ID || i.id}','start')">▶</button>
        <button class="btn btn-sm btn-orange" onclick="instanceAction('${i.ID || i.id}','stop')">■</button>
        <button class="btn btn-sm btn-blue"   onclick="instanceAction('${i.ID || i.id}','reboot')">↺</button>
        <button class="btn btn-sm btn-danger" onclick="deleteInstance('${i.ID || i.id}','${i.Name || i.name}')">✕</button>
      </td>
    </tr>`).join("");
  document.getElementById("instances-table").innerHTML = tableWrap(
    ["ID", "Nom", "Statut", "IP", "Image", "Flavor", "Actions"], rows
  );
}

async function createInstance() {
  const name   = prompt("Nom de l'instance:");
  if (!name) return;
  const image  = prompt("Image:", "ubuntu-22.04") || "ubuntu-22.04";
  const flavor = prompt("Flavor:", "m1.small") || "m1.small";
  const r = await apiFetch("/api/instances", "POST", { name, image, flavor });
  r.ok ? toast("Instance créée") : toast(r.error, "error");
  loadInstances();
}

async function instanceAction(id, action) {
  const r = await apiFetch(`/api/instances/${id}/${action}`, "POST");
  r.ok ? toast(`Action ${action} effectuée`) : toast(r.error, "error");
  setTimeout(loadInstances, 2000);
}

async function deleteInstance(id, name) {
  if (!confirm_action(`Supprimer l'instance "${name}" ?`)) return;
  const r = await apiFetch(`/api/instances/${id}`, "DELETE");
  r.ok ? toast("Instance supprimée") : toast(r.error, "error");
  loadInstances();
}

// ─── Ports ────────────────────────────────────────────────────────────────────
async function loadPorts() {
  loading("ports-table");
  const r = await apiFetch("/api/ports");
  const rows = (r.data || []).map(p => `
    <tr>
      <td class="mono">${(p.ID || p.id || "").slice(0,12)}...</td>
      <td>${p.Name || p.name || "—"}</td>
      <td>${badge(p.Status || p.status)}</td>
      <td class="mono">${p["Fixed IP Addresses"] || p.fixed_ips || "—"}</td>
      <td class="mono">${p["MAC Address"] || p.mac_address || "—"}</td>
      <td>
        <button class="btn btn-danger btn-sm" onclick="deletePort('${p.ID || p.id}')">✕</button>
      </td>
    </tr>`).join("");
  document.getElementById("ports-table").innerHTML = tableWrap(
    ["ID", "Nom", "Statut", "IP fixe", "MAC", "Actions"], rows
  );
}

async function deletePort(id) {
  if (!confirm_action("Supprimer ce port ?")) return;
  const r = await apiFetch(`/api/ports/${id}`, "DELETE");
  r.ok ? toast("Port supprimé") : toast(r.error, "error");
  loadPorts();
}

// ─── Routeurs ─────────────────────────────────────────────────────────────────
async function loadRouters() {
  loading("routers-table");
  const r = await apiFetch("/api/routers");
  const rows = (r.data || []).map(rt => `
    <tr>
      <td class="mono">${(rt.ID || rt.id || "").slice(0,12)}...</td>
      <td><strong>${rt.Name || rt.name || "—"}</strong></td>
      <td>${badge(rt.Status || rt.status)}</td>
      <td>${rt["External Network"] || rt.external_gateway_info || "—"}</td>
      <td>
        <button class="btn btn-danger btn-sm" onclick="deleteRouter('${rt.ID || rt.id}','${rt.Name || rt.name}')">✕</button>
      </td>
    </tr>`).join("");
  document.getElementById("routers-table").innerHTML = tableWrap(
    ["ID", "Nom", "Statut", "Gateway externe", "Actions"], rows
  );
}

async function createRouter() {
  const name = prompt("Nom du routeur:");
  if (!name) return;
  const gw = prompt("Gateway externe (laisser vide si aucun):", "external") || "";
  const r = await apiFetch("/api/routers", "POST", { name, external_gateway: gw });
  r.ok ? toast("Routeur créé") : toast(r.error, "error");
  loadRouters();
}

async function deleteRouter(id, name) {
  if (!confirm_action(`Supprimer le routeur "${name}" ?`)) return;
  const r = await apiFetch(`/api/routers/${id}`, "DELETE");
  r.ok ? toast("Routeur supprimé") : toast(r.error, "error");
  loadRouters();
}

// ─── Floating IPs ─────────────────────────────────────────────────────────────
async function loadFips() {
  loading("fips-table");
  const r = await apiFetch("/api/floating-ips");
  const rows = (r.data || []).map(f => `
    <tr>
      <td class="mono">${(f.ID || f.id || "").slice(0,12)}...</td>
      <td class="mono"><strong>${f["Floating IP Address"] || f.floating_ip_address || "—"}</strong></td>
      <td class="mono">${f["Fixed IP Address"] || f.fixed_ip_address || "—"}</td>
      <td>${badge(f.Status || f.status)}</td>
      <td>${f["Floating Network"] || f.floating_network_id || "—"}</td>
      <td>
        <button class="btn btn-danger btn-sm" onclick="deleteFip('${f.ID || f.id}','${f["Floating IP Address"] || f.floating_ip_address}')">✕</button>
      </td>
    </tr>`).join("");
  document.getElementById("fips-table").innerHTML = tableWrap(
    ["ID", "IP Flottante", "IP Fixe", "Statut", "Réseau", "Actions"], rows
  );
}

async function createFip() {
  const network = prompt("Réseau source:", "external") || "external";
  const r = await apiFetch("/api/floating-ips", "POST", { network });
  r.ok ? toast("Floating IP allouée") : toast(r.error, "error");
  loadFips();
}

async function deleteFip(id, ip) {
  if (!confirm_action(`Libérer la Floating IP "${ip}" ?`)) return;
  const r = await apiFetch(`/api/floating-ips/${id}`, "DELETE");
  r.ok ? toast("Floating IP libérée") : toast(r.error, "error");
  loadFips();
}

// ─── Images ───────────────────────────────────────────────────────────────────
async function loadImages() {
  loading("images-table");
  const r = await apiFetch("/api/images");
  const rows = (r.data || []).map(i => `
    <tr>
      <td class="mono">${(i.ID || i.id || "").slice(0,12)}...</td>
      <td><strong>${i.Name || i.name || "—"}</strong></td>
      <td>${badge(i.Status || i.status)}</td>
      <td>${i["Disk Format"] || i.disk_format || "—"}</td>
      <td>${i.Size ? (Math.round(i.Size/1e6)/1000).toFixed(2)+" GB" : "—"}</td>
      <td>${i.Visibility || i.visibility || "—"}</td>
      <td>
        <button class="btn btn-danger btn-sm" onclick="deleteImage('${i.ID || i.id}','${i.Name || i.name}')">✕</button>
      </td>
    </tr>`).join("");
  document.getElementById("images-table").innerHTML = tableWrap(
    ["ID", "Nom", "Statut", "Format", "Taille", "Visibilité", "Actions"], rows
  );
}

async function deleteImage(id, name) {
  if (!confirm_action(`Supprimer l'image "${name}" ?`)) return;
  const r = await apiFetch(`/api/images/${id}`, "DELETE");
  r.ok ? toast("Image supprimée") : toast(r.error, "error");
  loadImages();
}

// ─── Flavors ──────────────────────────────────────────────────────────────────
async function loadFlavors() {
  loading("flavors-table");
  const r = await apiFetch("/api/flavors");
  const rows = (r.data || []).map(f => `
    <tr>
      <td>${f.ID || f.id || "—"}</td>
      <td><strong>${f.Name || f.name || "—"}</strong></td>
      <td>${f.VCPUs || f.vcpus || "—"}</td>
      <td>${f.RAM ? Math.round(f.RAM/1024)+" GB" : "—"}</td>
      <td>${f.Disk || f.disk || "—"} GB</td>
      <td>
        <button class="btn btn-danger btn-sm" onclick="deleteFlavor('${f.ID || f.id}','${f.Name || f.name}')">✕</button>
      </td>
    </tr>`).join("");
  document.getElementById("flavors-table").innerHTML = tableWrap(
    ["ID", "Nom", "vCPUs", "RAM", "Disque", "Actions"], rows
  );
}

async function createFlavor() {
  const name  = prompt("Nom du flavor:");
  if (!name) return;
  const vcpus = parseInt(prompt("vCPUs:", "1")) || 1;
  const ram   = parseInt(prompt("RAM (MB):", "2048")) || 2048;
  const disk  = parseInt(prompt("Disque (GB):", "20")) || 20;
  const r = await apiFetch("/api/flavors", "POST", { name, vcpus, ram, disk });
  r.ok ? toast("Flavor créé") : toast(r.error, "error");
  loadFlavors();
}

async function deleteFlavor(id, name) {
  if (!confirm_action(`Supprimer le flavor "${name}" ?`)) return;
  const r = await apiFetch(`/api/flavors/${id}`, "DELETE");
  r.ok ? toast("Flavor supprimé") : toast(r.error, "error");
  loadFlavors();
}

// ─── Security Groups ──────────────────────────────────────────────────────────
async function loadSGs() {
  loading("sgs-table");
  const r = await apiFetch("/api/security-groups");
  const rows = (r.data || []).map(s => `
    <tr>
      <td class="mono">${(s.ID || s.id || "").slice(0,12)}...</td>
      <td><strong>${s.Name || s.name || "—"}</strong></td>
      <td>${s.Description || s.description || "—"}</td>
      <td>
        <button class="btn btn-danger btn-sm" onclick="deleteSG('${s.ID || s.id}','${s.Name || s.name}')">✕</button>
      </td>
    </tr>`).join("");
  document.getElementById("sgs-table").innerHTML = tableWrap(
    ["ID", "Nom", "Description", "Actions"], rows
  );
}

async function createSG() {
  const name = prompt("Nom du security group:");
  if (!name) return;
  const desc = prompt("Description:", "security-group") || "security-group";
  const r = await apiFetch("/api/security-groups", "POST", { name, description: desc });
  r.ok ? toast("Security group créé") : toast(r.error, "error");
  loadSGs();
}

async function deleteSG(id, name) {
  if (!confirm_action(`Supprimer le security group "${name}" ?`)) return;
  const r = await apiFetch(`/api/security-groups/${id}`, "DELETE");
  r.ok ? toast("Security group supprimé") : toast(r.error, "error");
  loadSGs();
}

// ─── Keypairs ─────────────────────────────────────────────────────────────────
async function loadKeypairs() {
  loading("keypairs-table");
  const r = await apiFetch("/api/keypairs");
  const rows = (r.data || []).map(k => `
    <tr>
      <td><strong>${k.Name || k.name || "—"}</strong></td>
      <td class="mono">${k.Fingerprint || k.fingerprint || "—"}</td>
      <td>${k.Type || k.type || "ssh"}</td>
      <td>
        <button class="btn btn-danger btn-sm" onclick="deleteKeypair('${k.Name || k.name}')">✕</button>
      </td>
    </tr>`).join("");
  document.getElementById("keypairs-table").innerHTML = tableWrap(
    ["Nom", "Empreinte", "Type", "Actions"], rows
  );
}

async function deleteKeypair(name) {
  if (!confirm_action(`Supprimer la keypair "${name}" ?`)) return;
  const r = await apiFetch(`/api/keypairs/${name}`, "DELETE");
  r.ok ? toast("Keypair supprimée") : toast(r.error, "error");
  loadKeypairs();
}

// ─── Tableau HTML helper ───────────────────────────────────────────────────────
function tableWrap(headers, rows) {
  if (!rows) return `<div class="empty-state">Aucune donnée disponible</div>`;
  return `<table class="data-table">
    <thead><tr>${headers.map(h => `<th>${h}</th>`).join("")}</tr></thead>
    <tbody>${rows || `<tr><td colspan="${headers.length}" class="empty">Aucune entrée</td></tr>`}</tbody>
  </table>`;
}

// ─── Refresh automatique ──────────────────────────────────────────────────────
function startAutoRefresh() {
  if (refreshTimer) clearInterval(refreshTimer);
  refreshTimer = setInterval(() => loadSection(currentSection), 30000);
}

// ─── Init ─────────────────────────────────────────────────────────────────────
document.addEventListener("DOMContentLoaded", () => {
  document.documentElement.setAttribute("data-theme", "dark");
  nav("overview");
  startAutoRefresh();
});
