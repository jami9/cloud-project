from flask import Flask, jsonify, request, send_from_directory
from flask_cors import CORS
import subprocess, json, shlex

app = Flask(__name__, static_folder='dashboard')
CORS(app)

# ─── HELPERS ──────────────────────────────────────────────────────────────────
def run(cmd):
    """Execute microstack.openstack <cmd> -f json and return parsed JSON."""
    full = f"microstack.openstack {cmd} -f json"
    result = subprocess.run(full, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        err = result.stderr.strip() or result.stdout.strip()
        return {"error": err}
    out = result.stdout.strip()
    if not out:
        return []
    try:
        return json.loads(out)
    except Exception as e:
        return {"error": f"JSON parse failed: {str(e)}", "raw": out[:500]}

def run_list(args):
    """
    Execute microstack.openstack with a list of args (safe quoting via shlex).
    Use this for commands where values may contain spaces or special chars.
    Appends -f json automatically.
    """
    cmd = ["microstack.openstack"] + args + ["-f", "json"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        err = result.stderr.strip() or result.stdout.strip()
        return {"error": err}
    out = result.stdout.strip()
    if not out:
        return []
    try:
        return json.loads(out)
    except Exception as e:
        return {"error": f"JSON parse failed: {str(e)}", "raw": out[:500]}

def run_plain(args):
    """
    Execute microstack.openstack with a list of args, no -f json.
    For commands that return no structured output (role add, router add subnet…).
    """
    cmd = ["microstack.openstack"] + args
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        err = result.stderr.strip() or result.stdout.strip()
        return {"error": err}
    return {"status": "ok", "output": result.stdout.strip()}

# ─── STATIC ───────────────────────────────────────────────────────────────────
@app.route('/')
def dashboard():
    return send_from_directory('dashboard', 'index.html')

@app.route('/script.js')
def script_js():
    return send_from_directory('dashboard', 'script.js')

# ══════════════════════════════════════════════════════════════════════════════
# SERVERS
# ══════════════════════════════════════════════════════════════════════════════
@app.route('/api/servers', methods=['GET'])
def servers():
    return jsonify(run('server list'))

@app.route('/api/servers/create', methods=['POST'])
def create_server():
    d      = request.json or {}
    name   = d.get('name', '').strip()
    flavor = d.get('flavor', 'm1.tiny').strip()
    image  = d.get('image', 'cirros').strip()
    net    = d.get('network', '').strip()
    if not name:
        return jsonify({"error": "name required"}), 400
    # BUG FIX: use list form so name/flavor/image with spaces are quoted safely
    # BUG FIX: --network is required by microstack, use 'test' (default micro network)
    args = ["server", "create",
            "--flavor", flavor,
            "--image", image,
            "--network", net if net else "test",
            name]
    return jsonify(run_list(args))

@app.route('/api/servers/<srv_id>/action/<action>', methods=['POST', 'GET'])
def action_server(srv_id, action):
    if action == 'start':
        run_plain(["server", "start", srv_id])
    elif action == 'stop':
        run_plain(["server", "stop", srv_id])
    elif action == 'reboot':
        run_plain(["server", "reboot", srv_id])
    return jsonify({"status": "ok", "action": action})

@app.route('/api/servers/<srv_id>', methods=['DELETE'])
def delete_server(srv_id):
    r = run_plain(["server", "delete", srv_id])
    return jsonify(r)

@app.route('/api/servers/<srv_id>/detail', methods=['GET'])
def server_detail(srv_id):
    return jsonify(run_list(["server", "show", srv_id]))

@app.route('/api/servers/<server>/floatingip', methods=['POST'])
def attach_floatingip(server):
    d  = request.json or {}
    ip = d.get('ip', '').strip()
    if not ip:
        return jsonify({"error": "ip required"}), 400
    return jsonify(run_plain(["server", "add", "floating", "ip", server, ip]))

# ══════════════════════════════════════════════════════════════════════════════
# NETWORKS
# ══════════════════════════════════════════════════════════════════════════════
@app.route('/api/networks', methods=['GET'])
def networks():
    return jsonify(run('network list'))

@app.route('/api/networks/create', methods=['POST'])
def create_network():
    d    = request.json or {}
    name = d.get('name', '').strip()
    if not name:
        return jsonify({"error": "name required"}), 400
    # BUG FIX: use list form for safe quoting
    return jsonify(run_list(["network", "create", name]))

@app.route('/api/networks/<net_id>', methods=['DELETE'])
def delete_network(net_id):
    # BUG FIX: use run_plain + list form, return error to frontend
    r = run_plain(["network", "delete", net_id])
    return jsonify(r)

# ══════════════════════════════════════════════════════════════════════════════
# SUBNETS
# ══════════════════════════════════════════════════════════════════════════════
@app.route('/api/subnets', methods=['GET'])
def subnets():
    return jsonify(run('subnet list'))

@app.route('/api/subnets/create', methods=['POST'])
def create_subnet():
    d       = request.json or {}
    name    = d.get('name', '').strip()
    network = d.get('network', '').strip()
    cidr    = d.get('cidr', '192.168.100.0/24').strip()
    if not name or not network:
        return jsonify({"error": "name and network required"}), 400
    return jsonify(run_list(["subnet", "create",
                             "--network", network,
                             "--subnet-range", cidr,
                             name]))

@app.route('/api/subnets/<sub_id>', methods=['DELETE'])
def delete_subnet(sub_id):
    return jsonify(run_plain(["subnet", "delete", sub_id]))

# ══════════════════════════════════════════════════════════════════════════════
# ROUTERS
# ══════════════════════════════════════════════════════════════════════════════
@app.route('/api/routers', methods=['GET'])
def routers():
    return jsonify(run('router list'))

@app.route('/api/routers/create', methods=['POST'])
def create_router():
    d    = request.json or {}
    name = d.get('name', '').strip()
    if not name:
        return jsonify({"error": "name required"}), 400
    return jsonify(run_list(["router", "create", name]))

@app.route('/api/routers/<rt_id>', methods=['DELETE'])
def delete_router(rt_id):
    return jsonify(run_plain(["router", "delete", rt_id]))

@app.route('/api/routers/<router>/subnet', methods=['POST'])
def router_add_subnet(router):
    d      = request.json or {}
    subnet = d.get('subnet', '').strip()
    if not subnet:
        return jsonify({"error": "subnet required"}), 400
    return jsonify(run_plain(["router", "add", "subnet", router, subnet]))

@app.route('/api/routers/<router>/subnet', methods=['DELETE'])
def router_remove_subnet(router):
    d      = request.json or {}
    subnet = d.get('subnet', '').strip()
    if not subnet:
        return jsonify({"error": "subnet required"}), 400
    return jsonify(run_plain(["router", "remove", "subnet", router, subnet]))

# ══════════════════════════════════════════════════════════════════════════════
# FLOATING IPs
# ══════════════════════════════════════════════════════════════════════════════
@app.route('/api/floatingips', methods=['GET'])
def floatingips():
    return jsonify(run('floating ip list'))

@app.route('/api/floatingips/create', methods=['POST'])
def create_floatingip():
    d       = request.json or {}
    network = d.get('network', 'external').strip()
    return jsonify(run_list(["floating", "ip", "create", network]))

@app.route('/api/floatingips/<fip_id>', methods=['DELETE'])
def delete_floatingip(fip_id):
    return jsonify(run_plain(["floating", "ip", "delete", fip_id]))

# ══════════════════════════════════════════════════════════════════════════════
# PORTS
# ══════════════════════════════════════════════════════════════════════════════
@app.route('/api/ports', methods=['GET'])
def ports():
    return jsonify(run('port list'))

@app.route('/api/ports/<port_id>', methods=['DELETE'])
def delete_port(port_id):
    return jsonify(run_plain(["port", "delete", port_id]))

# ══════════════════════════════════════════════════════════════════════════════
# FLAVORS & IMAGES
# ══════════════════════════════════════════════════════════════════════════════
@app.route('/api/flavors', methods=['GET'])
def flavors():
    # microstack.openstack flavor list -f json
    return jsonify(run('flavor list'))

@app.route('/api/images', methods=['GET'])
def images():
    return jsonify(run('image list'))

# ══════════════════════════════════════════════════════════════════════════════
# HYPERVISOR — BUG FIX
# microstack.openstack hypervisor list  → souvent vide avec microstack
# microstack.openstack hypervisor stats show  → retourne les stats globales
# On essaie les deux et on retourne ce qui fonctionne
# ══════════════════════════════════════════════════════════════════════════════
@app.route('/api/hypervisors', methods=['GET'])
def hypervisors():
    # 1. Essayer hypervisor list
    data = run('hypervisor list')
    if isinstance(data, list) and len(data) > 0:
        return jsonify(data)

    # 2. Fallback: hypervisor stats show  (retourne un objet, pas une liste)
    stats_result = subprocess.run(
        "microstack.openstack hypervisor stats show -f json",
        shell=True, capture_output=True, text=True
    )
    if stats_result.returncode == 0 and stats_result.stdout.strip():
        try:
            stats = json.loads(stats_result.stdout.strip())
            # Normaliser en liste pour le dashboard
            return jsonify([{
                "Hypervisor Hostname": "microstack",
                "State": "up",
                "vCPUs": stats.get("count", 0),
                "vCPUs Used": stats.get("vcpus_used", 0),
                "Memory MB": stats.get("memory_mb", 0),
                "Memory MB Used": stats.get("memory_mb_used", 0),
                "Running VMs": stats.get("running_vms", 0),
                "Local GB": stats.get("local_gb", 0),
                "Local GB Used": stats.get("local_gb_used", 0),
            }])
        except Exception:
            pass

    # 3. Fallback: quota show admin pour avoir les stats de ressources
    quota_result = subprocess.run(
        "microstack.openstack quota show admin -f json",
        shell=True, capture_output=True, text=True
    )
    if quota_result.returncode == 0 and quota_result.stdout.strip():
        try:
            quota = json.loads(quota_result.stdout.strip())
            return jsonify([{
                "Hypervisor Hostname": "microstack (quota)",
                "State": "up",
                "vCPUs": quota.get("cores", 0),
                "vCPUs Used": 0,
                "Memory MB": quota.get("ram", 0),
                "Memory MB Used": 0,
                "Running VMs": quota.get("instances", 0),
                "Local GB": 0,
                "Local GB Used": 0,
            }])
        except Exception:
            pass

    return jsonify([])

# ══════════════════════════════════════════════════════════════════════════════
# PROJECTS  — BUG FIX: ordre des arguments corrigé
# Syntaxe correcte: project create --domain default [--description "..."] <nom>
# ══════════════════════════════════════════════════════════════════════════════
@app.route('/api/projects', methods=['GET'])
def list_projects():
    return jsonify(run('project list'))

@app.route('/api/projects/create', methods=['POST'])
def create_project():
    d      = request.json or {}
    name   = d.get('name', '').strip()
    domain = d.get('domain', 'default').strip()
    desc   = d.get('description', '').strip()
    if not name:
        return jsonify({"error": "name required"}), 400
    # BUG FIX: args en liste pour éviter les problèmes de quoting du shell
    # Syntaxe: project create --domain default --description "..." <nom>
    args = ["project", "create", "--domain", domain]
    if desc:
        args += ["--description", desc]
    args.append(name)
    return jsonify(run_list(args))

@app.route('/api/projects/<proj_id>', methods=['DELETE'])
def delete_project(proj_id):
    return jsonify(run_plain(["project", "delete", proj_id]))

# ══════════════════════════════════════════════════════════════════════════════
# USERS  — BUG FIX: password quoté correctement
# Syntaxe: user create --domain default --password <pwd> <nom>
# ══════════════════════════════════════════════════════════════════════════════
@app.route('/api/users', methods=['GET'])
def list_users():
    return jsonify(run('user list'))

@app.route('/api/users/create', methods=['POST'])
def create_user():
    d        = request.json or {}
    name     = d.get('name', '').strip()
    password = d.get('password', '').strip()
    domain   = d.get('domain', 'default').strip()
    email    = d.get('email', '').strip()
    if not name or not password:
        return jsonify({"error": "name and password required"}), 400
    # BUG FIX: args en liste → le mot de passe est passé tel quel sans interprétation shell
    # Syntaxe: user create --domain default --password <pwd> [--email <e>] <nom>
    args = ["user", "create", "--domain", domain, "--password", password]
    if email:
        args += ["--email", email]
    args.append(name)
    return jsonify(run_list(args))

@app.route('/api/users/<user_id>', methods=['DELETE'])
def delete_user(user_id):
    return jsonify(run_plain(["user", "delete", user_id]))

# ══════════════════════════════════════════════════════════════════════════════
# ROLES
# Syntaxe: role add --project <projet> --user <user> <role>
# ══════════════════════════════════════════════════════════════════════════════
@app.route('/api/roles', methods=['GET'])
def list_roles():
    return jsonify(run('role list'))

@app.route('/api/roles/assignments', methods=['GET'])
def list_assignments():
    return jsonify(run('role assignment list --names'))

@app.route('/api/roles/add', methods=['POST'])
def add_role():
    d       = request.json or {}
    project = d.get('project', '').strip()
    user    = d.get('user', '').strip()
    role    = d.get('role', 'member').strip()
    if not project or not user:
        return jsonify({"error": "project and user required"}), 400
    # Syntaxe: role add --project <p> --user <u> member
    return jsonify(run_plain(["role", "add",
                              "--project", project,
                              "--user", user,
                              role]))

@app.route('/api/roles/remove', methods=['POST'])
def remove_role():
    d       = request.json or {}
    project = d.get('project', '').strip()
    user    = d.get('user', '').strip()
    role    = d.get('role', 'member').strip()
    if not project or not user:
        return jsonify({"error": "project and user required"}), 400
    return jsonify(run_plain(["role", "remove",
                              "--project", project,
                              "--user", user,
                              role]))

# ─── RUN ──────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5005, debug=True)
