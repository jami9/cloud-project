#!/usr/bin/env python3
"""
╔══════════════════════════════════════════════════════════════════════╗
║          MIGRATE_WINDOWS.PY — Migration VMware → OpenStack          ║
║          À exécuter sur Windows (machine hôte VMware)               ║
╠══════════════════════════════════════════════════════════════════════╣
║  Ce script fait TOUT côté Windows :                                 ║
║    1. Découvre les VM VMware (scan *.vmx)                           ║
║    2. Extrait CPU / RAM / VMDK depuis chaque fichier VMX            ║
║    3. Arrête proprement la VM via vmrun                             ║
║    4. Convertit VMDK → QCOW2 avec qemu-img                         ║
║    5. Transfère le QCOW2 vers la VM OpenStack via SCP (retry x3)   ║
╠══════════════════════════════════════════════════════════════════════╣
║  PRÉREQUIS :                                                        ║
║    pip install paramiko tqdm                                        ║
║    qemu-img installé et dans le PATH Windows                        ║
║    (https://qemu.weilnetz.de/w64/)                                  ║
╠══════════════════════════════════════════════════════════════════════╣
║  USAGE :                                                            ║
║    python migrate_windows.py                   ← toutes les VMs    ║
║    python migrate_windows.py --vm Ubuntu       ← une seule VM      ║
║    python migrate_windows.py --list            ← inventaire seul   ║
║    python migrate_windows.py --dry-run         ← simulation        ║
╚══════════════════════════════════════════════════════════════════════╝
"""

# ─── Imports stdlib (pas d'install nécessaire) ────────────────────────────────
import os, re, sys, time, json, hashlib, logging, argparse, subprocess
from pathlib import Path
from datetime import datetime
from dataclasses import dataclass, field, asdict
from typing import List, Optional
from logging.handlers import RotatingFileHandler

# ─── Imports tiers (pip install paramiko tqdm) ───────────────────────────────
try:
    import paramiko
    from tqdm import tqdm
except ImportError:
    print("[ERREUR] Dépendances manquantes. Exécutez :")
    print("         pip install paramiko tqdm")
    sys.exit(1)

# ══════════════════════════════════════════════════════════════════════════════
#  ░░░  CONFIGURATION — ADAPTEZ CES VALEURS À VOTRE ENVIRONNEMENT  ░░░
# ══════════════════════════════════════════════════════════════════════════════
CFG = {
    # ── Où sont vos VMs VMware ? ──────────────────────────────────────────────
    "vm_search_paths": [
        r"C:\Users\%USERNAME%\Documents\Virtual Machines",
    
    ],

    # ── Chemin vers vmrun.exe (VMware Workstation) ────────────────────────────
    "vmrun": r"C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe",

    # ── qemu-img (doit être dans le PATH ou indiquez le chemin complet) ───────
    "qemu_img": "qemu-img",

    # ── Dossier temporaire local pour les fichiers QCOW2 ─────────────────────
    "temp_dir": r"C:\Temp\migration",

    # ── Connexion SSH vers la VM OpenStack MicroStack ─────────────────────────
    "os_host": "192.168.56.101",
    "os_user": "admin",
    "os_ssh_key": str(Path.home() / ".ssh" / "id_ed25519"),
    "os_password": "",
    "os_remote_dir": "/tmp/migration_staging",

    # ── Comportement ──────────────────────────────────────────────────────────
    "retry_attempts": 3,       # tentatives SCP en cas d'échec réseau
    "retry_delay":    30,      # secondes entre deux tentatives
    "stop_timeout":   120,     # secondes max pour arrêter une VM
    "cleanup_qcow2":  True,    # supprimer le QCOW2 local après upload
    "log_file":       "migrate_windows.log",

    # ── Keepalive SSH (évite la déconnexion pendant les conversions longues) ──
    "ssh_keepalive_interval": 30,   # envoyer un keepalive toutes les 30s
    "ssh_keepalive_count_max": 10,  # tolérer jusqu'à 10 keepalives sans réponse
}
# ══════════════════════════════════════════════════════════════════════════════


# ─────────────────────────────────────────────────────────────────────────────
#  COULEURS CONSOLE (Windows 10+ supporte ANSI)
# ─────────────────────────────────────────────────────────────────────────────
os.system("")  # activer ANSI sur Windows
R  = "\033[0;31m"   # rouge
G  = "\033[0;32m"   # vert
Y  = "\033[1;33m"   # jaune
B  = "\033[0;34m"   # bleu
C  = "\033[0;36m"   # cyan
W  = "\033[1;37m"   # blanc gras
RS = "\033[0m"      # reset

def ok(msg):    print(f"  {G}✔{RS}  {msg}")
def err(msg):   print(f"  {R}✘{RS}  {msg}")
def info(msg):  print(f"  {C}→{RS}  {msg}")
def warn(msg):  print(f"  {Y}⚠{RS}  {msg}")
def section(t): print(f"\n{W}{'═'*60}\n  {t}\n{'═'*60}{RS}")


# ─────────────────────────────────────────────────────────────────────────────
#  DATACLASS : représente une VM VMware découverte
# ─────────────────────────────────────────────────────────────────────────────
@dataclass
class VM:
    name:         str
    vmx_path:     str
    vmdk_path:    str   = ""
    num_cpus:     int   = 1
    memory_mb:    int   = 1024
    disk_gb:      float = 0.0
    guest_os:     str   = "other"
    qcow2_path:   str   = ""
    status:       str   = "pending"   # pending|converted|uploaded|error
    error:        str   = ""
    duration_s:   float = 0.0


# ─────────────────────────────────────────────────────────────────────────────
#  LOGGING
# ─────────────────────────────────────────────────────────────────────────────
def setup_log():
    log = logging.getLogger("migrate")
    log.setLevel(logging.DEBUG)
    fh = RotatingFileHandler(CFG["log_file"], maxBytes=5_000_000, backupCount=3, encoding="utf-8")
    fh.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(message)s"))
    log.addHandler(fh)
    return log

LOG = setup_log()


# ══════════════════════════════════════════════════════════════════════════════
#  ÉTAPE 1 — DÉCOUVERTE DES VM VMware
# ══════════════════════════════════════════════════════════════════════════════
def discover_vms(filter_name: str = "") -> List[VM]:
    """
    Scanne récursivement les répertoires configurés pour trouver les *.vmx.
    Extrait CPU, RAM, disque et guestOS depuis le contenu du fichier VMX.
    Retourne une liste d'objets VM.
    """
    section("ÉTAPE 1 — Découverte des VM VMware")
    vms: List[VM] = []

    for raw_path in CFG["vm_search_paths"]:
        # Développer %USERNAME% et autres variables Windows
        path = Path(os.path.expandvars(raw_path))
        if not path.exists():
            warn(f"Chemin introuvable : {path}")
            continue
        info(f"Scan : {path}")

        for vmx_file in path.rglob("*.vmx"):
            vm = _parse_vmx(vmx_file)
            if vm is None:
                continue
            # Filtre optionnel par nom
            if filter_name and filter_name.lower() not in vm.name.lower():
                continue
            vms.append(vm)
            ok(f"{vm.name}  [{vm.num_cpus} vCPU | {vm.memory_mb} MB | {vm.disk_gb:.1f} GB | {vm.guest_os}]")
            LOG.info(f"VM découverte : {vm.name} | VMX: {vm.vmx_path} | VMDK: {vm.vmdk_path}")

    if not vms:
        err("Aucune VM découverte. Vérifiez vm_search_paths dans CFG.")
    else:
        print(f"\n  {W}{len(vms)} VM(s) trouvée(s){RS}")
    return vms


def _parse_vmx(vmx_path: Path) -> Optional[VM]:
    """Parse un fichier .vmx et retourne un objet VM, ou None si invalide."""
    try:
        content = vmx_path.read_text(encoding="utf-8", errors="replace")
    except Exception as e:
        LOG.warning(f"Lecture VMX échouée : {vmx_path} — {e}")
        return None

    # Construire un dict clé→valeur (tout en minuscules)
    data = {}
    for line in content.splitlines():
        if "=" not in line or line.strip().startswith("#"):
            continue
        k, _, v = line.partition("=")
        data[k.strip().lower()] = v.strip().strip('"')

    # displayName → nom de la VM (nettoyé pour OpenStack)
    name = data.get("displayname", "") or vmx_path.parent.name
    name = re.sub(r"[^a-zA-Z0-9_\-]", "_", name)

    # CPU / RAM / OS
    try:   num_cpus  = int(data.get("numvcpus", "1"))
    except ValueError: num_cpus  = 1
    try:   memory_mb = int(data.get("memsize",  "1024"))
    except ValueError: memory_mb = 1024
    guest_os = data.get("guestos", "other")

    # Localiser le VMDK principal
    vmdk_path = _find_vmdk(vmx_path, data)
    if not vmdk_path:
        warn(f"Aucun VMDK pour {name} — VM ignorée")
        return None

    # Taille disque en Go
    disk_gb = _disk_size_gb(vmdk_path)

    return VM(
        name=name, vmx_path=str(vmx_path), vmdk_path=str(vmdk_path),
        num_cpus=num_cpus, memory_mb=memory_mb, disk_gb=disk_gb, guest_os=guest_os,
    )


def _find_vmdk(vmx_path: Path, data: dict) -> Optional[Path]:
    """Localise le VMDK principal en cherchant dans le VMX puis par scan."""
    vm_dir = vmx_path.parent
    # 1) Chercher dans le VMX : scsi0:0.filename, ide0:0.filename …
    for k, v in sorted(data.items()):
        if re.match(r"(scsi|ide|sata|nvme)\d+:\d+\.filename", k) and v.endswith(".vmdk"):
            candidate = vm_dir / v
            if not candidate.exists():
                candidate = Path(v)       # chemin absolu dans le VMX ?
            if candidate.exists():
                return candidate
    # 2) Fallback : premier *.vmdk dans le dossier (ignorer snapshots et flat)
    for f in sorted(vm_dir.glob("*.vmdk")):
        if re.search(r"[-_](s\d{3}|\d{6})", f.name, re.I):
            continue   # snapshot fragment
        if "-flat" in f.name:
            continue   # fichier de données brutes
        return f
    return None


def _disk_size_gb(vmdk: Path) -> float:
    """Estime la taille du disque en Go (somme tous les fragments)."""
    try:
        total = sum(p.stat().st_size for p in vmdk.parent.glob(f"{vmdk.stem}*.vmdk"))
        return round(total / 1024**3, 2) or round(vmdk.stat().st_size / 1024**3, 2)
    except Exception:
        return 0.0


# ══════════════════════════════════════════════════════════════════════════════
#  ÉTAPE 2 — ARRÊT DE LA VM VMware
# ══════════════════════════════════════════════════════════════════════════════
def stop_vm(vm: VM, dry_run: bool) -> bool:
    """
    Arrête la VM via vmrun.exe :
      1. Tente un arrêt logiciel (soft — attend l'OS)
      2. Si échec, force l'arrêt (hard — équivalent power off)
    Retourne True si la VM est arrêtée (ou si vmrun absent).
    """
    info(f"Arrêt de '{vm.name}'…")
    LOG.info(f"Arrêt VM : {vm.name} | VMX: {vm.vmx_path}")

    if dry_run:
        ok("[dry-run] Arrêt simulé")
        return True

    vmrun = CFG["vmrun"]
    if not Path(vmrun).exists():
        warn(f"vmrun introuvable ({vmrun}). Vérifiez que la VM est déjà arrêtée.")
        return True     # non bloquant

    # Arrêt soft
    if _run([vmrun, "stop", vm.vmx_path, "soft"], timeout=CFG["stop_timeout"]):
        ok("VM arrêtée proprement (soft)")
        return True

    # Arrêt hard
    warn("Soft échoué → tentative hard…")
    if _run([vmrun, "stop", vm.vmx_path, "hard"], timeout=30):
        ok("VM arrêtée (hard)")
        return True

    # Vérifier si déjà arrêtée
    running = _run_out([vmrun, "list"])
    if vm.vmx_path.lower() not in running.lower():
        ok("VM déjà arrêtée")
        return True

    err(f"Impossible d'arrêter '{vm.name}'")
    return False


# ══════════════════════════════════════════════════════════════════════════════
#  ÉTAPE 3 — VÉRIFICATION DES PRÉREQUIS
# ══════════════════════════════════════════════════════════════════════════════
def check_qemu_img() -> bool:
    """Vérifie que qemu-img est disponible et affiche sa version."""
    section("Vérification prérequis")
    try:
        out = _run_out([CFG["qemu_img"], "--version"])
        ok(f"qemu-img : {out.splitlines()[0]}")
        LOG.info(f"qemu-img OK : {out.splitlines()[0]}")
        return True
    except FileNotFoundError:
        err(
            "qemu-img introuvable ! Installez QEMU for Windows :\n"
            "         https://qemu.weilnetz.de/w64/\n"
            "         puis ajoutez-le au PATH."
        )
        LOG.error("qemu-img introuvable")
        return False


# ══════════════════════════════════════════════════════════════════════════════
#  ÉTAPE 4 — CONVERSION VMDK → QCOW2
# ══════════════════════════════════════════════════════════════════════════════
def convert_vmdk(vm: VM, dry_run: bool) -> bool:
    """
    Convertit le VMDK de la VM en QCOW2 via :
        qemu-img convert -f vmdk -O qcow2 -p <source> <dest>

    Vérifie l'espace disque disponible avant de lancer.
    Vérifie l'intégrité du QCOW2 avec qemu-img check après conversion.
    Met à jour vm.qcow2_path en cas de succès.
    """
    info(f"Conversion VMDK → QCOW2 pour '{vm.name}'…")
    LOG.info(f"Conversion : {vm.vmdk_path}")

    # Créer le dossier temporaire
    temp = Path(os.path.expandvars(CFG["temp_dir"]))
    temp.mkdir(parents=True, exist_ok=True)

    out_path = temp / f"{vm.name}.qcow2"

    # ── Vérification espace disque ────────────────────────────────────────────
    import shutil
    free_gb = shutil.disk_usage(temp).free / 1024**3
    need_gb = vm.disk_gb * 0.85           # QCOW2 ≈ 85% du VMDK brut
    if free_gb < need_gb + 1:
        vm.error = f"Espace insuffisant : {free_gb:.1f} GB dispo, {need_gb:.1f} GB requis"
        err(vm.error)
        return False
    info(f"Espace disque : {free_gb:.1f} GB disponibles (requis ≈ {need_gb:.1f} GB)")

    if dry_run:
        ok(f"[dry-run] Conversion simulée → {out_path}")
        vm.qcow2_path = str(out_path)
        return True

    # Supprimer un QCOW2 résiduel
    if out_path.exists():
        warn(f"QCOW2 résiduel supprimé : {out_path.name}")
        out_path.unlink()

    # ── Lancement qemu-img ────────────────────────────────────────────────────
    cmd = [CFG["qemu_img"], "convert", "-f", "vmdk", "-O", "qcow2", "-p",
           str(vm.vmdk_path), str(out_path)]
    info(f"$ {' '.join(cmd)}")

    t0 = time.time()
    try:
        proc = subprocess.Popen(cmd, stderr=subprocess.PIPE, text=True, bufsize=1)
        last_pct = -1
        for line in proc.stderr:
            # qemu-img affiche "    (XX.XX%)" sur stderr
            m = re.search(r"([\d.]+)%", line)
            if m:
                pct = float(m.group(1))
                step = int(pct) // 10
                if step != last_pct // 10:
                    print(f"\r  {C}→{RS}  Progression : {pct:5.1f}%", end="", flush=True)
                    last_pct = pct
        proc.wait()
        print()   # saut de ligne après la progression
    except Exception as e:
        vm.error = f"qemu-img exception : {e}"
        err(vm.error)
        LOG.error(vm.error)
        return False

    if proc.returncode != 0:
        vm.error = f"qemu-img retourne code {proc.returncode}"
        err(vm.error)
        LOG.error(vm.error)
        return False

    elapsed = time.time() - t0
    size_gb = out_path.stat().st_size / 1024**3
    ok(f"QCOW2 créé : {out_path.name}  ({size_gb:.2f} GB)  en {elapsed:.1f}s")
    LOG.info(f"QCOW2 OK : {out_path} ({size_gb:.2f} GB) en {elapsed:.1f}s")

    # ── Vérification intégrité ────────────────────────────────────────────────
    info("Vérification intégrité QCOW2…")
    if _run([CFG["qemu_img"], "check", str(out_path)], timeout=120):
        ok("Intégrité vérifiée")
    else:
        warn("qemu-img check a signalé des avertissements (non bloquant)")

    vm.qcow2_path = str(out_path)
    return True


# ══════════════════════════════════════════════════════════════════════════════
#  CONNEXION SSH (fonction réutilisable pour reconnexion)
# ══════════════════════════════════════════════════════════════════════════════
def ssh_connect() -> Optional[paramiko.SSHClient]:
    """Ouvre et retourne une connexion SSH vers la VM OpenStack.
    Active le keepalive pour éviter les déconnexions pendant les longues conversions.
    """
    section("Connexion SSH → OpenStack MicroStack")
    print("HOST =", CFG["os_host"])
    print("USER =", CFG["os_user"])
    print("KEY  =", CFG["os_ssh_key"])
    host = CFG["os_host"]
    user = CFG["os_user"]
    key  = os.path.expandvars(CFG["os_ssh_key"])
    pwd  = CFG["os_password"]

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        if pwd:
            client.connect(host, username=user, password=pwd, timeout=20)
        else:
            client.connect(host, username=user, key_filename=key, timeout=20)

        # ── Keepalive SSH ──────────────────────────────────────────────────────
        # Envoie un paquet keepalive toutes les N secondes pour maintenir la
        # session active pendant les longues conversions VMDK (60-90+ min).
        transport = client.get_transport()
        if transport:
            transport.set_keepalive(CFG["ssh_keepalive_interval"])

        ok(f"SSH connecté à {user}@{host} (keepalive {CFG['ssh_keepalive_interval']}s)")
        LOG.info(f"SSH connecté : {user}@{host}")
        return client
    except paramiko.AuthenticationException:
        err("Authentification SSH échouée. Vérifiez os_ssh_key / os_password dans CFG.")
    except Exception as e:
        err(f"Connexion SSH impossible : {e}")
    LOG.error(f"SSH échec : {host}")
    return None


def _ssh_is_alive(ssh: Optional[paramiko.SSHClient]) -> bool:
    """Vérifie si la session SSH est encore active."""
    if ssh is None:
        return False
    transport = ssh.get_transport()
    return transport is not None and transport.is_active()


def ssh_ensure(ssh: Optional[paramiko.SSHClient]) -> Optional[paramiko.SSHClient]:
    """Retourne la connexion SSH existante si active, sinon en ouvre une nouvelle.
    Utilisé avant chaque upload pour se prémunir contre les déconnexions
    survenant pendant les longues conversions VMDK.
    """
    if _ssh_is_alive(ssh):
        return ssh

    warn("Session SSH inactive — reconnexion en cours…")
    LOG.warning("Session SSH perdue, tentative de reconnexion")

    if ssh is not None:
        try:
            ssh.close()
        except Exception:
            pass

    # Attendre un peu avant de retenter (évite un flood si le serveur est surchargé)
    time.sleep(3)
    new_ssh = ssh_connect()
    if new_ssh is None:
        err("Reconnexion SSH échouée.")
    return new_ssh


# ══════════════════════════════════════════════════════════════════════════════
#  ÉTAPE 5 — TRANSFERT SCP VERS OPENSTACK (retry x3)
# ══════════════════════════════════════════════════════════════════════════════
def upload_qcow2(vm: VM, ssh: paramiko.SSHClient, dry_run: bool) -> bool:
    """
    Transfère le QCOW2 vers /tmp/migration_staging/ sur la VM OpenStack
    via Paramiko SFTP avec barre de progression tqdm.
    Retry automatique : jusqu'à CFG["retry_attempts"] tentatives.

    Écrit aussi un fichier JSON de métadonnées (<vm>.json) côte-à-côte
    pour que le script OpenStack puisse créer le flavor sans intervention.

    La session SSH est vérifiée (et reconnectée si nécessaire) avant chaque
    tentative, ce qui évite l'erreur 'SSH session not active' après une
    longue conversion.
    """
    qcow2 = Path(vm.qcow2_path)
    remote_dir   = CFG["os_remote_dir"]
    remote_qcow2 = f"{remote_dir}/{qcow2.name}"
    remote_meta  = f"{remote_dir}/{vm.name}.json"
    size_bytes   = qcow2.stat().st_size if qcow2.exists() else 0

    info(f"Transfert SCP de '{qcow2.name}' ({size_bytes/1024**3:.2f} GB)…")
    LOG.info(f"Upload : {qcow2} → {CFG['os_host']}:{remote_qcow2}")

    if dry_run:
        ok(f"[dry-run] Transfert simulé → {remote_qcow2}")
        return True

    # ── S'assurer que la session SSH est vivante avant de commencer ───────────
    live_ssh = ssh_ensure(ssh)
    if live_ssh is None:
        vm.error = "Impossible d'établir une session SSH pour l'upload"
        err(vm.error)
        return False

    # Mettre à jour la référence locale (utile si reconnexion)
    ssh = live_ssh

    # Créer le dossier de staging sur la VM
    _ssh_exec(ssh, f"mkdir -p {remote_dir}")

    # ── Métadonnées JSON (lues par openstack_vm.sh) ───────────────────────────
    meta = {
        "vm_name":   vm.name,
        "num_cpus":  vm.num_cpus,
        "memory_mb": vm.memory_mb,
        "disk_gb":   max(10, int(vm.disk_gb) + 1),
        "guest_os":  vm.guest_os,
        "qcow2_file": qcow2.name,
        "image_name": f"migrated-{vm.name}",
        "flavor_name": f"migrated.{vm.name}.{vm.num_cpus}vcpu.{vm.memory_mb}mb",
        "instance_name": f"migrated-{vm.name}",
    }

    try:
        sftp = ssh.open_sftp()
        import io
        sftp.putfo(io.BytesIO(json.dumps(meta, indent=2).encode()), remote_meta)
        sftp.close()
        ok(f"Métadonnées JSON envoyées : {vm.name}.json")
    except Exception as e:
        warn(f"Envoi métadonnées échoué : {e} — nouvelle tentative après reconnexion")
        LOG.warning(f"Métadonnées upload échoué : {e}")
        ssh = ssh_ensure(None)   # forcer reconnexion
        if ssh is None:
            vm.error = "Reconnexion SSH échouée pour les métadonnées"
            err(vm.error)
            return False
        sftp = ssh.open_sftp()
        import io
        sftp.putfo(io.BytesIO(json.dumps(meta, indent=2).encode()), remote_meta)
        sftp.close()
        ok(f"Métadonnées JSON envoyées (après reconnexion) : {vm.name}.json")

    # ── Transfert QCOW2 avec retry ────────────────────────────────────────────
    for attempt in range(1, CFG["retry_attempts"] + 1):
        # Vérifier / rétablir la connexion avant chaque tentative
        ssh = ssh_ensure(ssh)
        if ssh is None:
            warn(f"Tentative {attempt} : impossible de (re)connecter SSH")
            if attempt < CFG["retry_attempts"]:
                info(f"Retry dans {CFG['retry_delay']}s…")
                time.sleep(CFG["retry_delay"])
            continue

        sftp = None
        bar  = None
        try:
            sftp = ssh.open_sftp()
            info(f"Tentative {attempt}/{CFG['retry_attempts']}…")

            transferred = [0]
            bar = tqdm(total=size_bytes, unit="B", unit_scale=True,
                       desc=f"  {qcow2.name}", ncols=70, colour="cyan")

            def _progress(sent, total):
                delta = sent - transferred[0]
                transferred[0] = sent
                bar.update(delta)

            sftp.put(str(qcow2), remote_qcow2, callback=_progress)
            bar.close()
            sftp.close()

            ok(f"Transfert réussi (tentative {attempt})")
            LOG.info(f"Upload réussi : {remote_qcow2}")

            # Nettoyage local optionnel
            if CFG["cleanup_qcow2"] and qcow2.exists():
                qcow2.unlink()
                info("QCOW2 local supprimé")
            return True

        except Exception as e:
            if bar is not None:
                try: bar.close()
                except Exception: pass
            if sftp is not None:
                try: sftp.close()
                except Exception: pass

            warn(f"Tentative {attempt} échouée : {e}")
            LOG.warning(f"Upload tentative {attempt} : {e}")

            # Invalider la session pour forcer une reconnexion au prochain tour
            try: ssh.close()
            except Exception: pass
            ssh = None

            if attempt < CFG["retry_attempts"]:
                info(f"Retry dans {CFG['retry_delay']}s…")
                time.sleep(CFG["retry_delay"])

    vm.error = f"Upload échoué après {CFG['retry_attempts']} tentatives"
    err(vm.error)
    LOG.error(vm.error)
    return False


# ══════════════════════════════════════════════════════════════════════════════
#  RAPPORT JSON (pour affichage et debug)
# ══════════════════════════════════════════════════════════════════════════════
def write_report(vms: List[VM]):
    """Écrit un rapport JSON simple avec les résultats de migration."""
    report_path = Path("migration_windows_report.json")
    data = [asdict(vm) for vm in vms]
    report_path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    info(f"Rapport JSON : {report_path}")
    LOG.info(f"Rapport : {report_path}")


# ══════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ══════════════════════════════════════════════════════════════════════════════
def _run(cmd: list, timeout: int = 60) -> bool:
    """Exécute une commande et retourne True si code de retour == 0."""
    try:
        r = subprocess.run(cmd, capture_output=True, timeout=timeout)
        return r.returncode == 0
    except Exception:
        return False

def _run_out(cmd: list, timeout: int = 30) -> str:
    """Exécute une commande et retourne stdout."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.stdout
    except Exception:
        return ""

def _ssh_exec(ssh: paramiko.SSHClient, cmd: str) -> str:
    """Exécute une commande SSH et retourne stdout."""
    try:
        _, stdout, _ = ssh.exec_command(cmd, timeout=60)
        return stdout.read().decode("utf-8", errors="replace").strip()
    except Exception:
        return ""


# ══════════════════════════════════════════════════════════════════════════════
#  RÉSUMÉ FINAL CONSOLE
# ══════════════════════════════════════════════════════════════════════════════
def print_summary(vms: List[VM]):
    section("RÉSUMÉ FINAL")
    total   = len(vms)
    success = sum(1 for v in vms if v.status == "uploaded")
    errors  = sum(1 for v in vms if v.status == "error")
    print(f"  {W}Total   :{RS} {total}")
    print(f"  {G}Succès  :{RS} {success}")
    print(f"  {R}Erreurs :{RS} {errors}")
    if total:
        print(f"  {C}Taux    :{RS} {success/total*100:.0f}%")
    print()
    if errors:
        print(f"  {Y}Détail des erreurs :{RS}")
        for v in vms:
            if v.status == "error":
                print(f"    {R}✘{RS} {v.name}: {v.error}")
    print()
    print(f"  {C}→{RS}  Maintenant exécutez {W}openstack_vm.sh{RS} sur la VM MicroStack !")
    print(f"  {C}→{RS}  Les métadonnées JSON sont dans {W}{CFG['os_remote_dir']}/{RS}")
    LOG.info(f"Fin migration : {success}/{total} succès")


# ══════════════════════════════════════════════════════════════════════════════
#  POINT D'ENTRÉE PRINCIPAL
# ══════════════════════════════════════════════════════════════════════════════
def main():
    # ── Parsing des arguments CLI ─────────────────────────────────────────────
    parser = argparse.ArgumentParser(
        description="Migration VMware → OpenStack (côté Windows)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Exemples :
  python migrate_windows.py                    Migrer toutes les VMs
  python migrate_windows.py --list             Lister les VMs sans migrer
  python migrate_windows.py --vm Ubuntu-22     Migrer une VM spécifique
  python migrate_windows.py --dry-run          Simuler sans rien faire
        """
    )
    parser.add_argument("--vm",      metavar="NOM", default="",
                        help="Filtrer par nom de VM (partiel)")
    parser.add_argument("--list",    action="store_true",
                        help="Inventaire uniquement (pas de migration)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Simulation sans actions réelles")
    args = parser.parse_args()

    # ── Bannière ──────────────────────────────────────────────────────────────
    print(f"""
{W}╔══════════════════════════════════════════════════════╗
║     MIGRATION VMware Workstation → OpenStack        ║
║     Script Windows — migrate_windows.py             ║
╚══════════════════════════════════════════════════════╝{RS}
  Démarré le : {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}
  Dry-run    : {Y + 'OUI' + RS if args.dry_run else G + 'NON' + RS}
""")

    # ── Prérequis ─────────────────────────────────────────────────────────────
    if not check_qemu_img():
        sys.exit(1)

    # ── Découverte ────────────────────────────────────────────────────────────
    vms = discover_vms(filter_name=args.vm)
    if not vms:
        sys.exit(1)

    if args.list:
        print(f"\n  {G}Mode --list : inventaire terminé.{RS}")
        sys.exit(0)

    # ── Connexion SSH initiale ────────────────────────────────────────────────
    ssh = None
    if not args.dry_run:
        ssh = ssh_connect()
        if ssh is None:
            sys.exit(1)

    # ── Migration de chaque VM ────────────────────────────────────────────────
    for i, vm in enumerate(vms, 1):
        section(f"VM {i}/{len(vms)} — {vm.name}")
        t_start = time.time()

        # 1. Arrêt
        if not stop_vm(vm, args.dry_run):
            vm.status = "error"
            vm.error  = "Arrêt VM échoué"
            continue

        # 2. Conversion
        # Note : la conversion peut durer 60-90+ minutes pour les grosses VMs.
        # Le keepalive SSH maintient la session active pendant ce temps.
        if not convert_vmdk(vm, args.dry_run):
            vm.status = "error"
            continue

        # 3. Upload
        # ssh_ensure() est appelé à l'intérieur d'upload_qcow2() pour gérer
        # toute déconnexion survenue pendant la conversion.
        if not upload_qcow2(vm, ssh, args.dry_run):
            vm.status = "error"
            continue

        vm.status     = "uploaded"
        vm.duration_s = time.time() - t_start
        ok(f"'{vm.name}' prêt sur OpenStack en {vm.duration_s:.0f}s")

    # ── Nettoyage SSH ─────────────────────────────────────────────────────────
    if ssh and _ssh_is_alive(ssh):
        ssh.close()

    # ── Rapport ───────────────────────────────────────────────────────────────
    write_report(vms)
    print_summary(vms)


if __name__ == "__main__":
    main()