"""
OpenStack Dashboard Backend — app.py
VM Backend : 192.168.56.104
Exécute les commandes microstack.openstack via subprocess
"""
from flask import Flask, jsonify, request
from flask_cors import CORS
import subprocess
import json
import os

app = Flask(__name__)
CORS(app, origins=["*"])

OS_CMD = "sudo microstack.openstack"

def run_os(args: list, input_data=None) -> dict:
    """Exécute une commande openstack et retourne le résultat JSON."""
    cmd = OS_CMD.split() + args + ["-f", "json"]
    try:
        result = subprocess.run(
            cmd,
            capture_output=True, text=True, timeout=30,
            input=input_data
        )
        if result.returncode == 0 and result.stdout.strip():
            return {"ok": True, "data": json.loads(result.stdout)}
        elif result.returncode == 0:
            return {"ok": True, "data": []}
        else:
            return {"ok": False, "error": result.stderr.strip() or "Erreur inconnue"}
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "Timeout — commande trop longue"}
    except json.JSONDecodeError:
        return {"ok": True, "data": result.stdout.strip()}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def run_os_raw(args: list) -> dict:
    """Exécute sans -f json (pour les commandes qui ne supportent pas)."""
    cmd = OS_CMD.split() + args
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            return {"ok": True, "data": result.stdout.strip()}
        return {"ok": False, "error": result.stderr.strip()}
    except Exception as e:
        return {"ok": False, "error": str(e)}

# ─── Santé ────────────────────────────────────────────────────────────────────
@app.route("/health")
def health():
    return jsonify({"status": "ok", "backend": "192.168.56.104"})

# ─── Dashboard — Vue globale ──────────────────────────────────────────────────
@app.route("/api/overview")
def overview():
    hypervisor = run_os(["hypervisor", "stats", "show"])
    projects   = run_os(["project", "list"])
    users      = run_os(["user", "list"])
    images     = run_os(["image", "list"])
    networks   = run_os(["network", "list"])
    instances  = run_os(["server", "list", "--all-projects"])
    fips       = run_os(["floating", "ip", "list"])
    return jsonify({
        "hypervisor": hypervisor.get("data"),
        "projects_count":  len(projects.get("data", [])),
        "users_count":     len(users.get("data", [])),
        "images_count":    len(images.get("data", [])),
        "networks_count":  len(networks.get("data", [])),
        "instances_count": len(instances.get("data", [])),
        "fips_count":      len(fips.get("data", [])),
    })

# ─── Projets ──────────────────────────────────────────────────────────────────
@app.route("/api/projects", methods=["GET"])
def list_projects():
    return jsonify(run_os(["project", "list", "--long"]))

@app.route("/api/projects", methods=["POST"])
def create_project():
    d = request.json or {}
    name = d.get("name", "")
    desc = d.get("description", "nouveau-projet")
    if not name:
        return jsonify({"ok": False, "error": "name requis"}), 400
    return jsonify(run_os(["project", "create", "--domain", "default",
                            "--description", desc.replace(" ", "-"), name]))

@app.route("/api/projects/<pid>", methods=["DELETE"])
def delete_project(pid):
    return jsonify(run_os_raw(["project", "delete", pid]))

# ─── Utilisateurs ─────────────────────────────────────────────────────────────
@app.route("/api/users", methods=["GET"])
def list_users():
    return jsonify(run_os(["user", "list", "--long"]))

@app.route("/api/users", methods=["POST"])
def create_user():
    d = request.json or {}
    name = d.get("name", "")
    password = d.get("password", "ChangeMe@2026!")
    project = d.get("project", "admin")
    if not name:
        return jsonify({"ok": False, "error": "name requis"}), 400
    return jsonify(run_os(["user", "create", "--domain", "default",
                            "--password", password, "--project", project,
                            "--enable", name]))

@app.route("/api/users/<uid>", methods=["DELETE"])
def delete_user(uid):
    return jsonify(run_os_raw(["user", "delete", uid]))

# ─── Hyperviseur ──────────────────────────────────────────────────────────────
@app.route("/api/hypervisors")
def list_hypervisors():
    stats = run_os(["hypervisor", "stats", "show"])
    detail = run_os(["hypervisor", "list", "--long"])
    return jsonify({"stats": stats.get("data"), "list": detail.get("data", [])})

# ─── Quotas ───────────────────────────────────────────────────────────────────
@app.route("/api/quotas/<project>", methods=["GET"])
def get_quotas(project):
    return jsonify(run_os(["quota", "show", project]))

@app.route("/api/quotas/<project>", methods=["PUT"])
def set_quotas(project):
    d = request.json or {}
    args = ["quota", "set"]
    for key, val in d.items():
        args += [f"--{key}", str(val)]
    args.append(project)
    return jsonify(run_os_raw(args))

# ─── Réseaux ──────────────────────────────────────────────────────────────────
@app.route("/api/networks", methods=["GET"])
def list_networks():
    return jsonify(run_os(["network", "list", "--long"]))

@app.route("/api/networks", methods=["POST"])
def create_network():
    d = request.json or {}
    name = d.get("name", "")
    if not name:
        return jsonify({"ok": False, "error": "name requis"}), 400
    args = ["network", "create", name]
    if d.get("external"):
        args += ["--external"]
    else:
        args += ["--internal"]
    return jsonify(run_os(args))

@app.route("/api/networks/<nid>", methods=["DELETE"])
def delete_network(nid):
    return jsonify(run_os_raw(["network", "delete", nid]))

# ─── Sous-réseaux ─────────────────────────────────────────────────────────────
@app.route("/api/subnets", methods=["GET"])
def list_subnets():
    return jsonify(run_os(["subnet", "list", "--long"]))

@app.route("/api/subnets", methods=["POST"])
def create_subnet():
    d = request.json or {}
    name    = d.get("name", "")
    network = d.get("network", "")
    cidr    = d.get("cidr", "192.168.100.0/24")
    if not name or not network:
        return jsonify({"ok": False, "error": "name et network requis"}), 400
    args = ["subnet", "create", name,
            "--network", network, "--subnet-range", cidr,
            "--dns-nameserver", "8.8.8.8"]
    return jsonify(run_os(args))

@app.route("/api/subnets/<sid>", methods=["DELETE"])
def delete_subnet(sid):
    return jsonify(run_os_raw(["subnet", "delete", sid]))

# ─── Instances (Serveurs) ──────────────────────────────────────────────────────
@app.route("/api/instances", methods=["GET"])
def list_instances():
    return jsonify(run_os(["server", "list", "--all-projects", "--long"]))

@app.route("/api/instances", methods=["POST"])
def create_instance():
    d = request.json or {}
    name   = d.get("name", "")
    image  = d.get("image", "ubuntu-22.04")
    flavor = d.get("flavor", "m1.small")
    if not name:
        return jsonify({"ok": False, "error": "name requis"}), 400
    args = ["server", "create", name, "--flavor", flavor, "--image", image]
    if d.get("network"):
        args += ["--network", d["network"]]
    if d.get("key_name"):
        args += ["--key-name", d["key_name"]]
    if d.get("security_group"):
        args += ["--security-group", d["security_group"]]
    return jsonify(run_os(args))

@app.route("/api/instances/<iid>", methods=["DELETE"])
def delete_instance(iid):
    return jsonify(run_os_raw(["server", "delete", iid, "--wait"]))

@app.route("/api/instances/<iid>/start", methods=["POST"])
def start_instance(iid):
    return jsonify(run_os_raw(["server", "start", iid]))

@app.route("/api/instances/<iid>/stop", methods=["POST"])
def stop_instance(iid):
    return jsonify(run_os_raw(["server", "stop", iid]))

@app.route("/api/instances/<iid>/reboot", methods=["POST"])
def reboot_instance(iid):
    return jsonify(run_os_raw(["server", "reboot", iid]))

# ─── Ports ────────────────────────────────────────────────────────────────────
@app.route("/api/ports", methods=["GET"])
def list_ports():
    return jsonify(run_os(["port", "list", "--long"]))

@app.route("/api/ports/<pid>", methods=["DELETE"])
def delete_port(pid):
    return jsonify(run_os_raw(["port", "delete", pid]))

# ─── Routeurs ─────────────────────────────────────────────────────────────────
@app.route("/api/routers", methods=["GET"])
def list_routers():
    return jsonify(run_os(["router", "list", "--long"]))

@app.route("/api/routers", methods=["POST"])
def create_router():
    d = request.json or {}
    name = d.get("name", "")
    if not name:
        return jsonify({"ok": False, "error": "name requis"}), 400
    args = ["router", "create", name]
    if d.get("external_gateway"):
        args += ["--external-gateway", d["external_gateway"]]
    return jsonify(run_os(args))

@app.route("/api/routers/<rid>", methods=["DELETE"])
def delete_router(rid):
    return jsonify(run_os_raw(["router", "delete", rid]))

# ─── Floating IPs ─────────────────────────────────────────────────────────────
@app.route("/api/floating-ips", methods=["GET"])
def list_fips():
    return jsonify(run_os(["floating", "ip", "list", "--long"]))

@app.route("/api/floating-ips", methods=["POST"])
def create_fip():
    d = request.json or {}
    network = d.get("network", "external")
    return jsonify(run_os(["floating", "ip", "create", network]))

@app.route("/api/floating-ips/<fid>", methods=["DELETE"])
def delete_fip(fid):
    return jsonify(run_os_raw(["floating", "ip", "delete", fid]))

@app.route("/api/floating-ips/associate", methods=["POST"])
def associate_fip():
    d = request.json or {}
    server = d.get("server", "")
    fip    = d.get("floating_ip", "")
    if not server or not fip:
        return jsonify({"ok": False, "error": "server et floating_ip requis"}), 400
    return jsonify(run_os_raw(["server", "add", "floating", "ip", server, fip]))

# ─── Images ───────────────────────────────────────────────────────────────────
@app.route("/api/images", methods=["GET"])
def list_images():
    return jsonify(run_os(["image", "list", "--long"]))

@app.route("/api/images/<iid>", methods=["DELETE"])
def delete_image(iid):
    return jsonify(run_os_raw(["image", "delete", iid]))

# ─── Flavors ──────────────────────────────────────────────────────────────────
@app.route("/api/flavors", methods=["GET"])
def list_flavors():
    return jsonify(run_os(["flavor", "list", "--long"]))

@app.route("/api/flavors", methods=["POST"])
def create_flavor():
    d = request.json or {}
    name  = d.get("name", "")
    vcpus = d.get("vcpus", 1)
    ram   = d.get("ram", 2048)
    disk  = d.get("disk", 20)
    if not name:
        return jsonify({"ok": False, "error": "name requis"}), 400
    return jsonify(run_os(["flavor", "create", name,
                            "--vcpus", str(vcpus),
                            "--ram",   str(ram),
                            "--disk",  str(disk)]))

@app.route("/api/flavors/<fid>", methods=["DELETE"])
def delete_flavor(fid):
    return jsonify(run_os_raw(["flavor", "delete", fid]))

# ─── Security Groups ──────────────────────────────────────────────────────────
@app.route("/api/security-groups", methods=["GET"])
def list_sgs():
    return jsonify(run_os(["security", "group", "list", "--long"]))

@app.route("/api/security-groups", methods=["POST"])
def create_sg():
    d = request.json or {}
    name = d.get("name", "")
    desc = d.get("description", "security-group")
    if not name:
        return jsonify({"ok": False, "error": "name requis"}), 400
    return jsonify(run_os(["security", "group", "create", name,
                            "--description", desc.replace(" ", "-")]))

@app.route("/api/security-groups/<sgid>", methods=["DELETE"])
def delete_sg(sgid):
    return jsonify(run_os_raw(["security", "group", "delete", sgid]))

# ─── Keypairs ─────────────────────────────────────────────────────────────────
@app.route("/api/keypairs", methods=["GET"])
def list_keypairs():
    return jsonify(run_os(["keypair", "list", "--long"]))

@app.route("/api/keypairs/<kid>", methods=["DELETE"])
def delete_keypair(kid):
    return jsonify(run_os_raw(["keypair", "delete", kid]))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
